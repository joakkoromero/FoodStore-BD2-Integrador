Source: complementos/migracion_fnbc/reproducir.py
Full source SHA256: 9d3756f21e75dbd78a471cb4b534b47076c4afb1d97878461495636e55d70454
Total source lines: 1480
Covered inclusive range: 1-740
SOURCE_BEGIN
#!/usr/bin/env python3
"""Controlled FNBC laboratory. Importing this module opens no connections."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import queue
import re
import subprocess
import sys
import threading
import time


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TARGET = "foodstore_tpi_migracion_nov10"
SCHEMA = "tpi_migracion"
INJECTED_STATE = "P7501"
INITIAL = [(501, 30, 801), (502, 30, 801), (503, 31, 802)]
CURRENT = [(501, 30, 803), (501, 31, 801),
           (502, 31, 801), (503, 31, 802)]
COLUMNS = "lote_id, deposito_id, responsable_control_id"
SOURCE_TABLES = ("categoria", "producto", "usuario", "pedido",
                 "detalle_pedido")
REQUIRED_DOMAIN_TABLES = ("lote", "deposito",
                          "control_lote_almacen_original")
SOURCE_FILES = ("preparar.sql", "migrar.sql", "revertir.sql",
                "reproducir.py", "README.md", "preparar_proveniencia.py")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
HEX32 = re.compile(r"^[0-9a-f]{32}$")
SAFE_NAME = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]*$")


class LaboratoryError(RuntimeError):
    pass


def require(condition, label):
    if not condition:
        raise LaboratoryError(label)


def utc_now():
    return datetime.now(timezone.utc)


def iso(value):
    return value.isoformat().replace("+00:00", "Z")


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"),
                      ensure_ascii=True).encode("ascii")


def digest_bytes(value):
    return hashlib.sha256(value).hexdigest()


def digest_file(path):
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def fixture_hash(rows):
    ordered = sorted(rows)
    return digest_bytes(
        ";".join(",".join(str(v) for v in row) for row in ordered)
        .encode("utf-8")
    )


def read_json(path):
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream)


def inside_root(path):
    return path.resolve().is_relative_to(ROOT)


def private_file(path, label):
    resolved = path.resolve(strict=True)
    require(resolved.is_file(), label + "_not_file")
    require(not inside_root(resolved), label + "_must_be_outside_repository")
    return resolved


def repo_path(name):
    require(isinstance(name, str) and name, "invalid_repository_path")
    candidate = Path(name)
    require(not candidate.is_absolute(), "absolute_repository_path")
    resolved = (ROOT / candidate).resolve(strict=True)
    require(resolved.is_relative_to(ROOT), "repository_path_escape")
    require(resolved.is_file(), "repository_path_not_file")
    return resolved


def git(*arguments):
    completed = subprocess.run(
        ["git", "-C", str(ROOT), *arguments],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        check=False, timeout=30,
    )
    require(completed.returncode == 0, "git_verification_failed")
    return completed.stdout


def relative(path):
    return path.resolve().relative_to(ROOT).as_posix()


def parse_time(value):
    require(isinstance(value, str), "backup_time_not_string")
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    require(parsed.tzinfo is not None and parsed.utcoffset() is not None,
            "backup_time_without_timezone")
    return parsed.astimezone(timezone.utc)


def verify_backup(args, started):
    manifest_path = private_file(args.backup_manifest, "backup_manifest")
    manifest = read_json(manifest_path)
    require(isinstance(manifest, dict), "backup_manifest_not_object")
    required = {
        "status", "database", "file", "size", "sha256",
        "startUtc", "endUtc", "baseline",
    }
    require(required <= manifest.keys(), "backup_required_field_missing")
    require(manifest["status"] == "SUCCESS", "backup_not_successful")
    require(manifest["database"] == args.source_database,
            "backup_database_mismatch")

    filename = manifest["file"]
    require(isinstance(filename, str) and SAFE_NAME.fullmatch(filename)
            and filename not in {".", ".."}
            and "/" not in filename and "\\" not in filename
            and ":" not in filename,
            "unsafe_backup_basename")
    # U6 writes manifests in logs/ and dumps in sibling backups/. The
    # basename and digest remain authoritative; no private file is rewritten.
    candidates = [manifest_path.parent / filename,
                  manifest_path.parent.parent / "backups" / filename]
    existing = [candidate.resolve(strict=True) for candidate in candidates
                if candidate.is_file()]
    require(len(existing) == 1, "backup_dump_missing_or_ambiguous")
    dump = existing[0]
    require(dump.name == filename, "backup_basename_mismatch")
    private_file(dump, "backup_dump")
    require(type(manifest["size"]) is int and manifest["size"] > 0,
            "invalid_backup_size")
    require(isinstance(manifest["sha256"], str)
            and HEX64.fullmatch(manifest["sha256"]),
            "invalid_backup_hash")
    require(dump.stat().st_size == manifest["size"], "backup_size_mismatch")
    require(digest_file(dump) == manifest["sha256"], "backup_hash_mismatch")
    with dump.open("rb") as stream:
        require(stream.read(5) == b"PGDMP", "backup_not_custom_format")

    start = parse_time(manifest["startUtc"])
    end = parse_time(manifest["endUtc"])
    require(start <= end < started, "backup_time_order_invalid")
    baseline = manifest["baseline"]
    require(isinstance(baseline, dict)
            and isinstance(baseline.get("counts"), dict)
            and bool(baseline["counts"])
            and isinstance(baseline.get("fingerprints"), dict)
            and bool(baseline["fingerprints"]),
            "backup_baseline_missing")
    for count in baseline["counts"].values():
        require(type(count) is int and count >= 0, "backup_count_invalid")
    for fingerprint in baseline["fingerprints"].values():
        require(isinstance(fingerprint, str)
                and bool(HEX32.fullmatch(fingerprint.lower())),
                "backup_baseline_fingerprint_invalid")

    return {
        "backup_manifest_success": True,
        "backup_sha256": manifest["sha256"],
        "backup_bytes": manifest["size"],
        "backup_manifest_sha256": digest_file(manifest_path),
        "backup_start_utc": iso(start),
        "backup_end_utc": iso(end),
        "custom_format_magic_verified": True,
        "baseline_recipe_not_assumed_equal": True,
        "baseline_fingerprint_algorithm": "MD5 (U6, distinct from dump SHA256)",
        "private_layout": "manifest logs/; dump same directory or sibling backups/",
    }


def verify_provenance(path, source_hashes):
    """Validate real wrapper artifacts plus a separate, explicit Codex coverage map.

    Raw Build/Plan metadata are immutable. This does not insert invented fields
    or claim that a technical decision is a human review.
    """
    index = read_json(path.resolve(strict=True))
    require(isinstance(index, dict), "provenance_not_object")
    code_commit = git("rev-parse", "HEAD").decode("ascii").strip()
    require(index.get("code_commit_before_execution") == code_commit,
            "code_commit_mismatch")
    spec_commit = index.get("kiro_spec_commit")
    require(isinstance(spec_commit, str)
            and re.fullmatch(r"[0-9a-f]{40}", spec_commit),
            "invalid_spec_commit")
    require(spec_commit != code_commit, "spec_commit_must_precede_code")
    git("merge-base", "--is-ancestor", spec_commit, code_commit)

    def committed_records(records, commit):
        result = {}
        for record in records:
            require(isinstance(record, dict)
                    and set(record) == {"path", "sha256"},
                    "invalid_provenance_record")
            original = repo_path(record["path"])
            name = relative(original)
            require(name not in result, "duplicate_provenance_path")
            actual = digest_file(original)
            require(record["sha256"] == actual, "provenance_hash_mismatch")
            require(digest_bytes(git("show", f"{commit}:{name}")) == actual,
                    "committed_original_mismatch")
            result[name] = actual
        return result

    specs = index.get("kiro_specs")
    notes = index.get("codex_prebuild_notes")
    require(isinstance(specs, list) and len(specs) == 3,
            "three_original_specs_required")
    require(isinstance(notes, list) and len(notes) == 3,
            "three_codex_prebuild_inputs_required")
    spec_hashes = committed_records(specs, spec_commit)
    note_hashes = committed_records(notes, spec_commit)
    for name, expected in source_hashes.items():
        require(digest_bytes(git("show", f"{code_commit}:{name}")) == expected,
                "executed_source_not_committed")
    client = repo_path("unidad5/tools/libpq_client.py")
    client_hash = digest_file(client)
    for commit in (spec_commit, code_commit):
        require(digest_bytes(git("show", f"{commit}:{relative(client)}"))
                == client_hash, "client_not_committed_unchanged")

    coverage_record = index.get("plan_coverage")
    require(isinstance(coverage_record, dict), "plan_coverage_record_missing")
    committed_records([coverage_record], code_commit)
    coverage = read_json(repo_path(coverage_record["path"]))
    require(coverage.get("reviewed_sources_sha256") == source_hashes,
            "plan_does_not_cover_executed_sources")
    require(index.get("technical_decision_codex") == "allow_execution",
            "technical_review_did_not_allow_execution")
    require(index.get("human_review_claimed") is False,
            "automated_provenance_must_not_claim_human_review")

    review_hashes = {}
    for review_kind in ("build", "plan"):
        bundle = index.get(review_kind)
        require(isinstance(bundle, dict)
                and set(bundle) == {"prompt", "answer", "metadata"},
                "review_bundle_missing")
        verified = committed_records(list(bundle.values()), code_commit)
        metadata = read_json(repo_path(bundle["metadata"]["path"]))
        require(metadata.get("status") == "completed"
                and metadata.get("agent") == review_kind
                and metadata.get("pure") is True
                and metadata.get("permission_config") == {"permission": "deny"}
                and metadata.get("tool_event_count") == 0
                and metadata.get("error_event_count") == 0
                and metadata.get("unparsed_line_count") == 0
                and metadata.get("returncode") == 0
                and metadata.get("sql_executed") is False,
                "review_not_real_pure_zero_tools")
        require(metadata.get("kiro_specification_commit") == spec_commit,
                "review_spec_commit_mismatch")
        frozen = metadata.get("kiro_specs_frozen_before_call", [])
        require({record.get("path"): record.get("sha256") for record in frozen}
                == spec_hashes, "review_frozen_specs_mismatch")
        require(metadata.get("prompt_sha256") == bundle["prompt"]["sha256"]
                and metadata.get("answer_sha256") == bundle["answer"]["sha256"],
                "review_prompt_answer_link_mismatch")
        attached = {}
        for item in metadata.get("attachments", []):
            snapshot = repo_path(item["repository_path"])
            require(digest_file(snapshot) == item.get("sha256"),
                    "review_attachment_hash_mismatch")
            require(digest_bytes(git("show", f"{code_commit}:{relative(snapshot)}"))
                    == item.get("sha256"), "review_snapshot_not_committed")
            attached[item.get("source_path_at_consultation")] = item.get("sha256")
        for name, expected in (spec_hashes | note_hashes).items():
            require(attached.get(name) == expected,
                    "review_spec_or_note_not_attached")
        if review_kind == "plan":
            chunks = coverage.get("chunks", [])
            for name, expected in source_hashes.items():
                if attached.get(name) == expected:
                    continue
                pieces = sorted((item for item in chunks
                                 if item.get("source_path") == name),
                                key=lambda item: item["start_line"])
                require(bool(pieces), "review_source_missing")
                original_lines = repo_path(name).read_text(
                    encoding="utf-8").splitlines(keepends=True)
                next_line = 1
                for piece in pieces:
                    require(piece["source_sha256"] == expected
                            and piece["start_line"] == next_line,
                            "review_chunk_gap_or_source_mismatch")
                    part = repo_path(piece["path"])
                    require(attached.get(piece["path"]) == piece["sha256"]
                            and digest_file(part) == piece["sha256"],
                            "review_chunk_not_attached_exactly")
                    body = part.read_text(encoding="utf-8").split(
                        "SOURCE_BEGIN\n", 1)[1].rsplit("\nSOURCE_END", 1)[0]
                    expected_body = "".join(original_lines[
                        piece["start_line"] - 1:piece["end_line"]]).rstrip("\n")
                    require(body == expected_body, "review_chunk_content_mismatch")
                    next_line = piece["end_line"] + 1
                require(next_line == len(original_lines) + 1,
                        "review_chunk_does_not_reach_final_line")
        review_hashes[review_kind] = verified

    return {
        "kiro_spec_commit": spec_commit,
        "kiro_specs_sha256": spec_hashes,
        "codex_prebuild_notes_sha256": note_hashes,
        "build_prompt_answer_metadata_hashes": review_hashes["build"],
        "plan_prompt_answer_metadata_hashes": review_hashes["plan"],
        "executed_source_files_sha256": source_hashes,
        "code_commit_before_execution": code_commit,
        "libpq_client_sha256": client_hash,
        "plan_coverage_sha256": coverage_record["sha256"],
        "tool_events_zero": True,
        "review_automated_not_human": True,
        "human_review_claimed": False,
        "provenance_index_sha256": digest_file(path),
    }


def load_client():
    path = ROOT / "unidad5" / "tools" / "libpq_client.py"
    spec = importlib.util.spec_from_file_location("fnbc_existing_libpq", path)
    require(spec is not None and spec.loader is not None,
            "libpq_client_unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def quote_identifier(value):
    return '"' + value.replace('"', '""') + '"'


def scalar(connection, sql, params=None):
    rows = connection.execute(sql, params).rows
    require(len(rows) == 1 and len(rows[0]) == 1, "scalar_shape_invalid")
    return rows[0][0]


def relation_rows(connection, name):
    require(re.fullmatch(r"[a-z_]+", name), "unsafe_relation_name")
    rows = connection.execute(
        f"SELECT {COLUMNS} FROM tpi_migracion.{name} "
        f"ORDER BY {COLUMNS}"
    ).rows
    return [tuple(int(value) for value in row) for row in rows]


def relation_hash(connection, name):
    return scalar(
        connection,
        "SELECT tpi_migracion.fn_relation_hash($1::regclass)",
        [f"tpi_migracion.{name}"],
    )


def kind(connection, name):
    return scalar(
        connection,
        "SELECT (SELECT c.relkind::text "
        "FROM pg_catalog.pg_class c "
        "JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname='tpi_migracion' AND c.relname=$1)",
        [name],
    )


def lifecycle(connection):
    return scalar(
        connection,
        "SELECT active::text FROM tpi_migracion._migration_guard WHERE id=1",
    )


def difference(connection, first, second):
    for name in (first, second):
        require(re.fullmatch(r"[a-z_]+", name), "unsafe_difference_relation")
    return int(scalar(
        connection,
        "SELECT count(*) FROM ("
        f"(SELECT {COLUMNS} FROM tpi_migracion.{first} EXCEPT ALL "
        f"SELECT {COLUMNS} FROM tpi_migracion.{second}) UNION ALL "
        f"(SELECT {COLUMNS} FROM tpi_migracion.{second} EXCEPT ALL "
        f"SELECT {COLUMNS} FROM tpi_migracion.{first})"
        ") AS differences",
    ))


def catalog(connection):
    rows = connection.execute(
        "SELECT c.relname, c.relkind::text "
        "FROM pg_catalog.pg_class c "
        "JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname='tpi_migracion' ORDER BY c.relname"
    ).rows
    functions = connection.execute(
        "SELECT p.proname, pg_catalog.pg_get_functiondef(p.oid) "
        "FROM pg_catalog.pg_proc p "
        "JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace "
        "WHERE n.nspname='tpi_migracion' ORDER BY p.proname"
    ).rows
    triggers = connection.execute(
        "SELECT c.relname,t.tgname,pg_catalog.pg_get_triggerdef(t.oid) "
        "FROM pg_catalog.pg_trigger t "
        "JOIN pg_catalog.pg_class c ON c.oid=t.tgrelid "
        "JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname='tpi_migracion' AND NOT t.tgisinternal "
        "ORDER BY c.relname,t.tgname"
    ).rows
    constraints = connection.execute(
        "SELECT c.relname,k.contype::text,k.convalidated::text,"
        "pg_catalog.pg_get_constraintdef(k.oid) "
        "FROM pg_catalog.pg_constraint k "
        "JOIN pg_catalog.pg_class c ON c.oid=k.conrelid "
        "JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname='tpi_migracion' "
        "ORDER BY c.relname,k.conname"
    ).rows
    data = {
        "relations": rows,
        "functions": functions,
        "triggers": triggers,
        "constraints": constraints,
    }
    require(not any(row[1] == "S" for row in rows), "sequence_created")
    return data


def key_catalog(connection):
    rows = connection.execute(
        "SELECT c.relname,k.contype::text,"
        "ARRAY(SELECT a.attname FROM unnest(k.conkey) WITH ORDINALITY "
        "AS x(attnum,ord) JOIN pg_catalog.pg_attribute a "
        "ON a.attrelid=k.conrelid AND a.attnum=x.attnum ORDER BY x.ord)::text,"
        "COALESCE(rn.nspname || '.' || rc.relname,''),"
        "k.convalidated::text "
        "FROM pg_catalog.pg_constraint k "
        "JOIN pg_catalog.pg_class c ON c.oid=k.conrelid "
        "JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace "
        "LEFT JOIN pg_catalog.pg_class rc ON rc.oid=k.confrelid "
        "LEFT JOIN pg_catalog.pg_namespace rn ON rn.oid=rc.relnamespace "
        "WHERE n.nspname='tpi_migracion' "
        "AND c.relname IN ('responsable_deposito','lote_responsable') "
        "AND k.contype IN ('p','f') ORDER BY 1,2,3,4"
    ).rows
    expected = {
        ("responsable_deposito", "p", "{responsable_control_id}", "", "true"),
        ("responsable_deposito", "f", "{responsable_control_id}",
         "public.usuario", "true"),
        ("responsable_deposito", "f", "{deposito_id}",
         "public.deposito", "true"),
        ("lote_responsable", "p", "{lote_id,responsable_control_id}",
         "", "true"),
        ("lote_responsable", "f", "{lote_id}", "public.lote", "true"),
        ("lote_responsable", "f", "{responsable_control_id}",
         "tpi_migracion.responsable_deposito", "true"),
    }
    require(set(tuple(row) for row in rows) == expected,
            "normalized_key_catalog_mismatch")
    return rows


def public_fingerprints(connection):
    inventory = connection.execute(
        "SELECT c.relname,c.relkind::text,"
        "COALESCE((SELECT string_agg(a.attname || ':' || "
        "pg_catalog.format_type(a.atttypid,a.atttypmod) || ':' || "
        "a.attnotnull::text, ';' ORDER BY a.attnum) "
        "FROM pg_catalog.pg_attribute a WHERE a.attrelid=c.oid "
        "AND a.attnum>0 AND NOT a.attisdropped),'') "
        "FROM pg_catalog.pg_class c "
        "JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname='public' AND c.relkind IN ('r','p','m') "
        "ORDER BY c.relname"
    ).rows
    names = {row[0] for row in inventory}
    require(set(SOURCE_TABLES + REQUIRED_DOMAIN_TABLES) <= names,
            "required_public_relation_missing")
    all_fingerprints = {}
    for table, _, _ in inventory:
        qualified = "public." + quote_identifier(table)
        # Only aggregate counts and digests leave PostgreSQL.
        row = connection.execute(
            "SELECT count(*)::text,pg_catalog.encode(pg_catalog.sha256("
            "pg_catalog.convert_to(COALESCE(string_agg(h, ';' ORDER BY h),"
            "''),'UTF8')),'hex') FROM ("
            "SELECT pg_catalog.encode(pg_catalog.sha256("
            "pg_catalog.convert_to(to_jsonb(t)::text,'UTF8')),'hex') AS h "
            f"FROM {qualified} AS t) AS hashed"
        ).rows[0]
        all_fingerprints[table] = {"count": int(row[0]), "sha256": row[1]}
    result = {
        "public." + table: all_fingerprints[table]
        for table in SOURCE_TABLES
    }
    remaining = {
        name: value for name, value in all_fingerprints.items()
        if name not in SOURCE_TABLES
    }
    result["public.remaining_tables_and_catalog"] = {
        "count": sum(value["count"] for value in remaining.values()),
        "sha256": digest_bytes(canonical({
            "remaining": remaining,
            "inventory": inventory,
        })),
    }
    require(len(result) == 6,
            "five_primary_public_fingerprints_plus_extensions_required")
    return result


class Runner:
    def __init__(self, args, client, evidence, started, scripts):
        self.args = args
        self.client = client
        self.evidence = evidence
        self.started = started
        self.scripts = scripts
        self.before_copy = None
        self.before_source = None
        self.checkpoint_hash = fixture_hash(INITIAL)
        self.current_hash = fixture_hash(CURRENT)

    def connect(self, database=TARGET, suffix="main"):
        connection = self.client.Connection(
            user=self.args.user,
            host=self.args.host,
            port=self.args.port,
            dbname=database,
            application_name="fnbc_" + suffix,
            secret_file=str(self.args.secret_file),
        )
        try:
            require(scalar(connection, "SELECT current_database()") == database,
                    "connection_database_mismatch")
            connection.execute("SET statement_timeout='15s'")
            connection.execute("SET lock_timeout='12s'")
            connection.execute("SET idle_in_transaction_session_timeout='20s'")
            connection.execute("SET search_path=pg_catalog")
            return connection
        except BaseException:
            connection.close()
            raise

    @contextmanager
    def transaction(self, readonly=False, database=TARGET, suffix="main"):
        connection = self.connect(database, suffix)
        try:
            connection.execute(
                "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY"
                if readonly else "BEGIN ISOLATION LEVEL READ COMMITTED"
            )
            yield connection
            connection.execute("COMMIT" if not readonly else "ROLLBACK")
        except BaseException:
            try:
                connection.execute("ROLLBACK")
            finally:
                connection.close()
            raise
        else:
            connection.close()

    def backup(self, phase):
        verified = verify_backup(self.args, self.started)
        previous = self.evidence["scope"]["backup_checks"]
        if previous:
            require(verified == previous[0]["verification"],
                    "backup_changed_during_laboratory")
        previous.append({"phase": phase, "verification": verified})

    def observe_scope(self, phase, initial=False):
        with self.transaction(True, TARGET, "copy_fingerprints") as connection:
            copy = public_fingerprints(connection)
        with self.transaction(
            True, self.args.source_database, "source_fingerprints"
        ) as connection:
            source = public_fingerprints(connection)
            source_rows = connection.execute(
                f"SELECT {COLUMNS} FROM public.control_lote_almacen_original "
                f"ORDER BY {COLUMNS}"
            ).rows
            require([tuple(int(v) for v in row) for row in source_rows]
                    == INITIAL, "official_source_fixture_changed")
        if initial:
            self.before_copy = copy
            self.before_source = source
            self.evidence["scope"]["public_fingerprints_before"] = copy
            self.evidence["scope"]["official_source_fingerprints_before"] = source
        else:
            require(copy == self.before_copy, "copy_public_changed")
            require(source == self.before_source, "official_source_changed")
        self.evidence["scope"]["phase_fingerprints"].append({
            "phase": phase,
            "public_fingerprints": copy,
            "official_source_fingerprints": source,
            "unchanged": True,
        })
        return copy, source

    def expected_error(self, connection, name, statements, expected):
        require(re.fullmatch(r"[a-z_]+", name), "unsafe_savepoint")
        connection.execute("SAVEPOINT " + name)
        observed = None
        try:
            try:
                for sql, params in statements:
                    connection.execute(sql, params)
            except self.client.DatabaseError as error:
                observed = error.sqlstate
            require(observed == expected, "unexpected_sqlstate_" + name)
        finally:
            connection.execute("ROLLBACK TO SAVEPOINT " + name)
            connection.execute("RELEASE SAVEPOINT " + name)
        return observed

    def check_checkpoint(self, connection):
        require(kind(connection, "control_legacy_checkpoint") == "r",
                "checkpoint_not_table")
        require(relation_rows(connection, "control_legacy_checkpoint")
                == INITIAL, "checkpoint_rows_changed")
        require(relation_hash(connection, "control_legacy_checkpoint")
                == self.checkpoint_hash, "checkpoint_hash_changed")
        require(scalar(
            connection,
            "SELECT sha256 FROM tpi_migracion.migration_manifest "
            "WHERE phase='checkpoint_initial'",
        ) == self.checkpoint_hash, "checkpoint_manifest_changed")

    def prepared(self, connection):
        require(kind(connection, "control_legacy") == "r",
                "prepared_legacy_not_table")
        require(relation_rows(connection, "control_legacy") == INITIAL,
                "prepared_legacy_rows_changed")
        require(relation_hash(connection, "control_legacy")
                == self.checkpoint_hash, "prepared_legacy_hash_changed")
        self.check_checkpoint(connection)
        for name in ("responsable_deposito", "lote_responsable",
                     "_migration_guard", "control_legacy_pre_migracion"):
            require(kind(connection, name) is None,
                    "unexpected_normalized_object")

    def normalized(self, connection, rows):
        require(kind(connection, "control_legacy") == "v",
                "normalized_legacy_not_view")
        require(kind(connection, "responsable_deposito") == "r"
                and kind(connection, "lote_responsable") == "r",
                "normalized_table_missing")
        require(relation_rows(connection, "control_legacy") == rows,
                "normalized_rows_mismatch")
        require(lifecycle(connection) == "true", "normalized_cycle_not_active")
        connection.execute("SELECT tpi_migracion.fn_validate_fd_ld_r()")
        self.check_checkpoint(connection)

    def prepare(self):
        self.backup("preparation")
        with self.transaction() as connection:
            require(scalar(
                connection, "SELECT to_regnamespace('tpi_migracion')::text"
            ) is None, "schema_initially_present")
            connection.execute(self.scripts["preparar.sql"])
            self.prepared(connection)
            before_catalog = catalog(connection)
            rejection = {}
            for operation, sql in {
                "insert": "INSERT INTO tpi_migracion.control_legacy_checkpoint "
                          "VALUES (501,30,801)",
                "update": "UPDATE tpi_migracion.control_legacy_checkpoint "
                          "SET deposito_id=deposito_id",
                "delete": "DELETE FROM tpi_migracion.control_legacy_checkpoint",
                "truncate": "TRUNCATE TABLE "
                            "tpi_migracion.control_legacy_checkpoint",
            }.items():
                rejection[operation] = self.expected_error(
                    connection, "checkpoint_" + operation,
                    [(sql, None)], "25006",
                )
            self.check_checkpoint(connection)
            for name, value in self.before_copy.items():
                connection.execute(
                    "INSERT INTO tpi_migracion.migration_manifest "
                    "(phase,row_count,sha256,details) "
                    "VALUES ($1,$2::bigint,$3,$4::jsonb)",
                    ["public_initial:" + name, str(value["count"]),
                     value["sha256"], json.dumps({"fingerprint": name})],
                )
            require(catalog(connection) == before_catalog,
                    "checkpoint_tests_changed_catalog")
        with self.transaction(True) as connection:
            self.prepared(connection)
            self.prepared_catalog = catalog(connection)
        self.evidence["preparation"] = {
            "legacy_relation_kind_table": True,
            "legacy_three_rows": True,
            "checkpoint_three_rows": True,
            "checkpoint_sha_before": self.checkpoint_hash,
            "checkpoint_write_rejection_25006": rejection,
            "no_sequences_created": True,
            "commit_succeeds": True,
        }
        self.observe_scope("preparation")

    def invalid_source(self):
        self.backup("invalid_source")
        connection = self.connect()
        try:
            connection.execute("BEGIN")
            observed = self.expected_error(
                connection, "invalid_rd",
                [
                    ("INSERT INTO tpi_migracion.control_legacy "
SOURCE_END

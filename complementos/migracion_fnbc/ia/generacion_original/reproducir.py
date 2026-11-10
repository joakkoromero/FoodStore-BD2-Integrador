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
SOURCE_TABLES = ("lote", "deposito", "usuario",
                 "control_lote_almacen_original")
SOURCE_FILES = ("preparar.sql", "migrar.sql", "revertir.sql",
                "reproducir.py", "README.md")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
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
    dump = (manifest_path.parent / filename).resolve(strict=True)
    require(dump.parent == manifest_path.parent, "backup_path_escape")
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
                and bool(HEX64.fullmatch(fingerprint.lower())),
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
    }


def verify_provenance(path, source_hashes):
    """Verify an external review index against original files and Git."""
    index = read_json(path.resolve(strict=True))
    require(isinstance(index, dict), "provenance_not_object")
    code_commit = git("rev-parse", "HEAD").decode("ascii").strip()
    require(index.get("code_commit_before_execution") == code_commit,
            "code_commit_mismatch")

    spec_commit = index.get("kiro_spec_commit")
    require(isinstance(spec_commit, str)
            and re.fullmatch(r"[0-9a-f]{40,64}", spec_commit),
            "invalid_spec_commit")
    require(spec_commit != code_commit, "spec_commit_must_precede_code")
    git("merge-base", "--is-ancestor", spec_commit, code_commit)

    specs = index.get("kiro_specs")
    notes = index.get("codex_prebuild_notes")
    require(isinstance(specs, list) and len(specs) == 3,
            "three_original_specs_required")
    require(isinstance(notes, list) and len(notes) == 2,
            "two_codex_notes_required")

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

    spec_hashes = committed_records(specs, spec_commit)
    note_hashes = committed_records(notes, spec_commit)

    for name, expected in source_hashes.items():
        require(digest_bytes(git("show", f"{code_commit}:{name}")) == expected,
                "executed_source_not_committed")

    client = repo_path("unidad5/tools/libpq_client.py")
    client_hash = digest_file(client)
    require(digest_bytes(git("show", f"{spec_commit}:{relative(client)}"))
            == client_hash, "client_changed_since_specs")
    require(digest_bytes(git("show", f"{code_commit}:{relative(client)}"))
            == client_hash, "client_not_committed_unchanged")

    review_hashes = {}
    for kind in ("build", "plan"):
        bundle = index.get(kind)
        require(isinstance(bundle, dict)
                and set(bundle) == {"prompt", "answer", "metadata"},
                "review_bundle_missing")
        verified = committed_records(list(bundle.values()), code_commit)
        metadata = read_json(repo_path(bundle["metadata"]["path"]))
        require(isinstance(metadata, dict)
                and metadata.get("mode") == "pure"
                and metadata.get("permission") == "deny"
                and metadata.get("tool_events") == []
                and metadata.get("review_automated_not_human") is True,
                "review_not_pure_automated_zero_tools")
        require(metadata.get("kiro_specs_sha256") == spec_hashes,
                "review_spec_inputs_mismatch")
        require(metadata.get("codex_prebuild_notes_sha256") == note_hashes,
                "review_note_inputs_mismatch")
        require(metadata.get("prompt_sha256")
                == bundle["prompt"]["sha256"]
                and metadata.get("answer_sha256")
                == bundle["answer"]["sha256"],
                "review_prompt_answer_link_mismatch")
        if kind == "plan":
            require(metadata.get("reviewed_sources_sha256") == source_hashes,
                    "plan_does_not_cover_executed_sources")
            require(metadata.get("decision") == "allow_execution",
                    "plan_did_not_allow_execution")
        review_hashes[kind] = verified

    return {
        "kiro_spec_commit": spec_commit,
        "kiro_specs_sha256": spec_hashes,
        "codex_prebuild_notes_sha256": note_hashes,
        "build_prompt_answer_metadata_hashes": review_hashes["build"],
        "plan_prompt_answer_metadata_hashes": review_hashes["plan"],
        "executed_source_files_sha256": source_hashes,
        "code_commit_before_execution": code_commit,
        "libpq_client_sha256": client_hash,
        "tool_events_zero": True,
        "review_automated_not_human": True,
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
    require(set(SOURCE_TABLES) <= names, "required_public_relation_missing")
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
    require(len(result) == 5, "five_public_fingerprints_required")
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
                     "VALUES (501,31,801)", None),
                    ("SELECT tpi_migracion.fn_check_fd_rd()", None),
                ], "23514",
            )
            connection.execute("ROLLBACK")
        finally:
            connection.close()
        with self.transaction(True) as connection:
            self.prepared(connection)
            require(catalog(connection) == self.prepared_catalog,
                    "negative_precheck_catalog_changed")
        self.evidence["invalid_source"] = {
            "invalid_tuple_501_31_801": [501, 31, 801],
            "observed_sqlstate_23514": observed,
            "explicit_rollback": True,
            "legacy_hash_restored": True,
            "no_partial_normalized_objects": True,
        }
        self.observe_scope("invalid_source")

    def migration(self, commit):
        phase = "migration_commit" if commit else "migration_rollback"
        self.backup(phase)
        expected_sha = self.evidence["provenance"][
            "executed_source_files_sha256"
        ][relative(HERE / "migrar.sql")]
        require(digest_file(HERE / "migrar.sql") == expected_sha,
                "migration_file_changed")
        connection = self.connect()
        completed = False
        try:
            connection.execute("BEGIN ISOLATION LEVEL READ COMMITTED")
            connection.execute(self.scripts["migrar.sql"])
            self.normalized(connection, INITIAL)
            require(difference(connection, "control_legacy",
                               "control_legacy_checkpoint") == 0,
                    "migration_bilateral_difference")
            keys = key_catalog(connection)
            if commit:
                connection.execute(
                    "INSERT INTO tpi_migracion.migration_manifest "
                    "(phase,row_count,sha256,details) "
                    "VALUES ('migration_body',0,$1,"
                    "'{\"rollback_and_commit_same_bytes\":true}'::jsonb)",
                    [expected_sha],
                )
            connection.execute("COMMIT" if commit else "ROLLBACK")
            completed = True
        finally:
            if not completed:
                try:
                    connection.execute("ROLLBACK")
                finally:
                    connection.close()
            else:
                connection.close()

        with self.transaction(True, suffix="migration_new_observer") as fresh:
            if commit:
                self.normalized(fresh, INITIAL)
                require(difference(fresh, "control_legacy",
                                   "control_legacy_checkpoint") == 0,
                        "committed_bilateral_difference")
                self.evidence[phase] = {
                    "same_migration_body_sha_as_rollback": expected_sha,
                    "bilateral_difference_count_zero": True,
                    "three_join_rows": True,
                    "legacy_relation_kind_view": True,
                    "checkpoint_hash_preserved": True,
                    "keys_and_foreign_keys_catalog": keys,
                    "commit_succeeds": True,
                }
            else:
                self.prepared(fresh)
                require(catalog(fresh) == self.prepared_catalog,
                        "rollback_catalog_not_restored")
                self.evidence[phase] = {
                    "same_migration_body_sha_as_commit": expected_sha,
                    "bilateral_difference_count_zero_inside": True,
                    "three_rows_inside": True,
                    "rollback_completed": True,
                    "new_connection_observation": True,
                    "legacy_relation_kind_table_after": True,
                    "legacy_hash_unchanged": True,
                    "normalized_objects_absent_after": True,
                    "catalog_sha256_restored": digest_bytes(
                        canonical(self.prepared_catalog)),
                }
        self.observe_scope(phase)

    def constraints(self):
        self.backup("constraints")
        connection = self.connect()
        cases = {}
        try:
            connection.execute("BEGIN")
            connection.execute("SAVEPOINT valid_master")
            connection.execute(
                "UPDATE tpi_migracion.responsable_deposito "
                "SET deposito_id=31 WHERE responsable_control_id=801"
            )
            require(relation_rows(connection, "control_legacy") == [
                (501, 31, 801), (502, 31, 801), (503, 31, 802)
            ], "valid_update_not_observed")
            connection.execute("ROLLBACK TO SAVEPOINT valid_master")
            connection.execute("RELEASE SAVEPOINT valid_master")

            negative = {
                "R_duplicate_23505": (
                    "INSERT INTO tpi_migracion.responsable_deposito "
                    "VALUES (801,31)", "23505"),
                "LR_duplicate_23505": (
                    "INSERT INTO tpi_migracion.lote_responsable "
                    "VALUES (501,801)", "23505"),
            }
            for key, (sql, state) in negative.items():
                cases[key] = self.expected_error(
                    connection, key.lower(), [(sql, None)], state,
                )

            missing_lot = int(scalar(
                connection,
                "SELECT CASE WHEN EXISTS(SELECT 1 FROM public.lote) "
                "THEN min(id)::numeric-1 ELSE -1 END FROM public.lote",
            ))
            require(-(2**63) <= missing_lot < 2**63,
                    "no_safe_missing_bigint_fixture")
            missing_responsible = int(scalar(
                connection,
                "SELECT CASE WHEN EXISTS(SELECT 1 FROM public.usuario) "
                "THEN min(id)::numeric-1 ELSE -1 END FROM public.usuario",
            ))
            require(-(2**63) <= missing_responsible < 2**63,
                    "no_safe_missing_responsible_fixture")
            fk_lot = self.expected_error(
                connection, "fk_missing_lot",
                [("INSERT INTO tpi_migracion.lote_responsable "
                  "VALUES ($1::bigint,801)", [str(missing_lot)])], "23503",
            )
            fk_responsible = self.expected_error(
                connection, "fk_missing_responsible",
                [("INSERT INTO tpi_migracion.responsable_deposito "
                  "VALUES ($1::bigint,30)", [str(missing_responsible)])],
                "23503",
            )
            cases["foreign_key_23503"] = {
                "lote": fk_lot, "responsable": fk_responsible,
            }

            connection.execute(
                "INSERT INTO tpi_migracion.responsable_deposito "
                "VALUES (803,30)"
            )
            cases["cross_LD_insert_23505"] = self.expected_error(
                connection, "cross_ld_insert",
                [("INSERT INTO tpi_migracion.lote_responsable "
                  "VALUES (501,803)", None)], "23505",
            )
            connection.execute(
                "INSERT INTO tpi_migracion.lote_responsable VALUES (503,803)"
            )
            cases["cross_LD_master_update_23505"] = self.expected_error(
                connection, "cross_ld_update",
                [("UPDATE tpi_migracion.responsable_deposito "
                  "SET deposito_id=31 WHERE responsable_control_id=803",
                  None)], "23505",
            )
            connection.execute("ROLLBACK")
        finally:
            connection.close()
        with self.transaction(True) as fresh:
            self.normalized(fresh, INITIAL)
            require(int(scalar(
                fresh,
                "SELECT count(*) FROM tpi_migracion.responsable_deposito"
            )) == 2, "constraint_fixture_rd_not_restored")
        cases["valid_master_update_accepted_then_rollback"] = True
        cases["fixture_three_rows_restored_before_concurrency"] = True
        self.evidence["constraints"] = cases
        self.observe_scope("constraints")

    def concurrency(self):
        self.backup("concurrency")
        with self.transaction() as connection:
            self.normalized(connection, INITIAL)
            connection.execute(
                "INSERT INTO tpi_migracion.responsable_deposito "
                "VALUES (803,30)"
            )

        messages = queue.Queue()
        release_a = threading.Event()
        allow_commit = threading.Event()
        threads = []

        def writer_a():
            connection = None
            try:
                connection = self.connect(suffix="writer_A")
                connection.execute("BEGIN ISOLATION LEVEL READ COMMITTED")
                pid = int(scalar(connection, "SELECT pg_backend_pid()"))
                connection.execute(
                    "INSERT INTO tpi_migracion.lote_responsable "
                    "VALUES (503,801)"
                )
                messages.put(("A_ready", pid))
                require(release_a.wait(15), "writer_a_release_timeout")
                if allow_commit.is_set():
                    connection.execute("COMMIT")
                    messages.put(("A_committed", True))
                else:
                    connection.execute("ROLLBACK")
                    messages.put(("A_aborted", True))
            except BaseException as error:
                messages.put(("A_failure", {
                    "type": type(error).__name__,
                    "sqlstate": getattr(error, "sqlstate", None),
                }))
            finally:
                if connection is not None:
                    try:
                        connection.execute("ROLLBACK")
                    except self.client.DatabaseError:
                        pass
                    connection.close()

        def writer_b():
            connection = None
            try:
                connection = self.connect(suffix="writer_B")
                connection.execute("BEGIN ISOLATION LEVEL READ COMMITTED")
                pid = int(scalar(connection, "SELECT pg_backend_pid()"))
                messages.put(("B_ready", pid))
                observed = None
                try:
                    connection.execute(
                        "INSERT INTO tpi_migracion.lote_responsable "
                        "VALUES (503,803)"
                    )
                except self.client.DatabaseError as error:
                    observed = error.sqlstate
                connection.execute("ROLLBACK")
                require(observed == "23505", "writer_b_unexpected_sqlstate")
                messages.put(("B_rejected", observed))
            except BaseException as error:
                messages.put(("B_failure", {
                    "type": type(error).__name__,
                    "sqlstate": getattr(error, "sqlstate", None),
                }))
            finally:
                if connection is not None:
                    try:
                        connection.execute("ROLLBACK")
                    except self.client.DatabaseError:
                        pass
                    connection.close()

        def receive(expected):
            try:
                event, value = messages.get(timeout=18)
            except queue.Empty:
                raise LaboratoryError("writer_message_timeout") from None
            require(event == expected, "unexpected_writer_event_" + event)
            return value

        observations = []
        try:
            a = threading.Thread(target=writer_a, name="fnbc_A", daemon=True)
            threads.append(a)
            a.start()
            a_pid = receive("A_ready")
            b = threading.Thread(target=writer_b, name="fnbc_B", daemon=True)
            threads.append(b)
            b.start()
            b_pid = receive("B_ready")
            require(a_pid != b_pid, "writers_share_backend")

            monitor = self.connect(suffix="lock_monitor")
            try:
                monitor_pid = int(scalar(monitor, "SELECT pg_backend_pid()"))
                require(monitor_pid not in {a_pid, b_pid},
                        "monitor_shares_backend")
                deadline = time.monotonic() + 8
                blocked = False
                while time.monotonic() < deadline:
                    row = monitor.execute(
                        "SELECT wait_event_type,state,"
                        "($2::integer=ANY(pg_catalog.pg_blocking_pids(pid)))"
                        "::text,pg_catalog.clock_timestamp()::text "
                        "FROM pg_catalog.pg_stat_activity "
                        "WHERE pid=$1::integer",
                        [str(b_pid), str(a_pid)],
                    ).rows
                    if row:
                        wait, state, blocked_by_a, observed_at = row[0]
                        if wait == "Lock" and blocked_by_a == "true":
                            observations.append({
                                "observed_at": observed_at,
                                "A_pid": a_pid,
                                "B_pid": b_pid,
                                "monitor_pid": monitor_pid,
                                "wait_event_type": wait,
                                "state": state,
                                "A_in_blocking_pids": True,
                            })
                            blocked = True
                            break
                    # Poll pacing is not used as evidence of blocking.
                    threading.Event().wait(0.025)
                require(blocked, "blocking_not_observed")
                allow_commit.set()
                release_a.set()
            finally:
                monitor.close()

            results = {}
            for _ in range(2):
                try:
                    event, value = messages.get(timeout=18)
                except queue.Empty:
                    raise LaboratoryError("writer_completion_timeout") from None
                require(event in {"A_committed", "B_rejected"},
                        "writer_failed_" + event)
                require(event not in results, "duplicate_writer_result")
                results[event] = value
            require(results == {"A_committed": True, "B_rejected": "23505"},
                    "concurrency_results_invalid")
        finally:
            release_a.set()
            for thread in threads:
                thread.join(timeout=22)
            require(not any(thread.is_alive() for thread in threads),
                    "writer_did_not_terminate")

        with self.transaction() as connection:
            connection.execute("SELECT tpi_migracion.fn_validate_fd_ld_r()")
            require(int(scalar(
                connection,
                "SELECT count(*) FROM tpi_migracion.lote_responsable "
                "WHERE lote_id=503 AND responsable_control_id=801",
            )) == 1, "writer_a_row_missing")
            require(int(scalar(
                connection,
                "SELECT count(*) FROM tpi_migracion.lote_responsable "
                "WHERE lote_id=503 AND responsable_control_id=803",
            )) == 0, "writer_b_row_persisted")
            connection.execute(
                "DELETE FROM tpi_migracion.lote_responsable "
                "WHERE lote_id=503 AND responsable_control_id=801"
            )
            connection.execute(
                "DELETE FROM tpi_migracion.responsable_deposito "
                "WHERE responsable_control_id=803"
            )
        with self.transaction(True) as fresh:
            self.normalized(fresh, INITIAL)
            require(int(scalar(
                fresh,
                "SELECT count(*) FROM tpi_migracion.responsable_deposito",
            )) == 2, "concurrency_rd_cleanup_failed")
        self.evidence["concurrency"] = {
            "different_connection_pids": True,
            "writer_A_open_transaction": True,
            "writer_B_waiting_Lock": True,
            "A_pid_in_pg_blocking_pids_of_B": True,
            "A_commit_succeeds": True,
            "B_observed_sqlstate_23505": "23505",
            "cross_LD_duplicates_zero": True,
            "explicit_auxiliary_cleanup": True,
            "fixture_three_rows_restored_after_concurrency": True,
            "lock_observations": observations,
        }
        self.observe_scope("concurrency")

    def confirmed_changes(self):
        self.backup("confirmed_changes")
        with self.transaction() as connection:
            self.normalized(connection, INITIAL)
            connection.execute(
                "UPDATE tpi_migracion.responsable_deposito "
                "SET deposito_id=31 WHERE responsable_control_id=801"
            )
            connection.execute(
                "INSERT INTO tpi_migracion.responsable_deposito "
                "VALUES (803,30)"
            )
            connection.execute(
                "INSERT INTO tpi_migracion.lote_responsable VALUES (501,803)"
            )
            self.normalized(connection, CURRENT)
            require(relation_hash(connection, "control_legacy")
                    == self.current_hash, "confirmed_hash_mismatch")
            rows = [
                dict(zip(
                    ("lote_id", "deposito_id", "responsable_control_id"), row
                )) for row in CURRENT
            ]
            connection.execute(
                "INSERT INTO tpi_migracion.migration_manifest "
                "(phase,row_count,sha256,details) "
                "VALUES ('confirmed_changes',4,$1,$2::jsonb)",
                [self.current_hash, json.dumps({"rows": rows})],
            )
        with self.transaction(True) as fresh:
            self.normalized(fresh, CURRENT)
        self.evidence["confirmed_changes"] = {
            "R801_D31": True,
            "R803_D30": True,
            "L501_R803": True,
            "commit_succeeds": True,
            "join_four_rows_exact": CURRENT,
            "join_four_rows_hash": self.current_hash,
            "checkpoint_three_rows_unchanged": True,
        }
        self.observe_scope("confirmed_changes")

    def down_error(self):
        self.backup("down_injected_error")
        with self.transaction(True) as connection:
            before_catalog = catalog(connection)
            self.normalized(connection, CURRENT)
        connection = self.connect()
        observed = None
        try:
            connection.execute("BEGIN")
            connection.execute(
                "SELECT set_config('tpi_migracion.inject_down_error','on',true)"
            )
            connection.execute("SAVEPOINT injected_down")
            try:
                connection.execute(self.scripts["revertir.sql"])
            except self.client.DatabaseError as error:
                observed = error.sqlstate
            require(observed == INJECTED_STATE,
                    "down_injected_state_mismatch")
            connection.execute("ROLLBACK TO SAVEPOINT injected_down")
            connection.execute("RELEASE SAVEPOINT injected_down")
            connection.execute("ROLLBACK")
        finally:
            connection.close()
        with self.transaction(True, suffix="down_error_observer") as fresh:
            self.normalized(fresh, CURRENT)
            require(catalog(fresh) == before_catalog,
                    "injected_down_catalog_not_restored")
            for name in ("control_legacy_fnbc_archivada",
                         "control_legacy_new", "down_snapshot"):
                require(kind(fresh, name) is None,
                        "injected_down_object_persisted")
            require(relation_hash(fresh, "control_legacy") == self.current_hash,
                    "injected_down_hash_changed")
        self.evidence["down_injected_error"] = {
            "declared_injected_sqlstate": INJECTED_STATE,
            "observed_same_sqlstate": observed,
            "explicit_rollback": True,
            "new_connection_observation": True,
            "legacy_relation_kind_view_restored": True,
            "archived_view_name_absent": True,
            "reconstructed_table_name_absent": True,
            "lifecycle_active_true_restored": True,
            "normalized_four_rows_hash_unchanged": True,
            "checkpoint_hash_unchanged": True,
            "catalog_sha256_restored": digest_bytes(canonical(before_catalog)),
        }
        self.observe_scope("down_injected_error")

    def down_commit(self):
        self.backup("down_commit")
        with self.transaction() as connection:
            connection.execute(
                "SELECT set_config('tpi_migracion.inject_down_error','off',true)"
            )
            connection.execute(self.scripts["revertir.sql"])
            require(kind(connection, "control_legacy") == "r",
                    "down_legacy_not_table")
            require(kind(connection, "control_legacy_fnbc_archivada") == "v",
                    "down_archived_view_missing")
            require(relation_rows(connection, "control_legacy") == CURRENT,
                    "down_reconstructed_rows_wrong")
            require(lifecycle(connection) == "false", "down_cycle_still_active")
            require(difference(connection, "control_legacy",
                               "down_snapshot") == 0,
                    "down_snapshot_difference")
            require(difference(connection, "control_legacy",
                               "control_legacy_fnbc_archivada") == 0,
                    "down_archived_view_difference")
            self.check_checkpoint(connection)
        self.evidence["down_commit"] = {
            "tables_locked_before_join_capture": True,
            "current_join_four_rows_snapshot": CURRENT,
            "reconstructed_rows_four": True,
            "bilateral_differences_zero": True,
            "no_drop_or_cascade": True,
            "view_renamed_control_legacy_fnbc_archivada": True,
            "reconstructed_table_renamed_control_legacy": True,
            "normalized_relations_retained": True,
            "lifecycle_active_false": True,
            "commit_succeeds": True,
        }
        self.observe_scope("down_commit")

    def final(self):
        self.backup("final_archive_rejections")
        rejections = {}
        with self.transaction(suffix="final_fresh_connection") as connection:
            require(kind(connection, "control_legacy") == "r",
                    "final_legacy_not_table")
            require(relation_rows(connection, "control_legacy") == CURRENT,
                    "final_legacy_rows_wrong")
            require(relation_rows(
                connection, "control_legacy_fnbc_archivada"
            ) == CURRENT, "final_archived_view_rows_wrong")
            require(relation_rows(
                connection, "control_legacy_pre_migracion"
            ) == INITIAL, "initial_legacy_archive_changed")
            require(relation_hash(connection, "control_legacy")
                    == self.current_hash, "final_hash_wrong")
            self.check_checkpoint(connection)
            before = catalog(connection)
            statements = {
                "RD_insert_rejected_25006":
                    "INSERT INTO tpi_migracion.responsable_deposito "
                    "VALUES (803,30)",
                "RD_update_rejected_25006":
                    "UPDATE tpi_migracion.responsable_deposito "
                    "SET deposito_id=deposito_id",
                "RD_delete_rejected_25006":
                    "DELETE FROM tpi_migracion.responsable_deposito",
                "LR_insert_rejected_25006":
                    "INSERT INTO tpi_migracion.lote_responsable "
                    "VALUES (501,803)",
                "LR_update_rejected_25006":
                    "UPDATE tpi_migracion.lote_responsable SET lote_id=lote_id",
                "LR_delete_rejected_25006":
                    "DELETE FROM tpi_migracion.lote_responsable",
                "RD_LR_truncate_rejected_25006":
                    "TRUNCATE TABLE tpi_migracion.responsable_deposito, "
                    "tpi_migracion.lote_responsable",
                "LR_truncate_rejected_25006":
                    "TRUNCATE TABLE tpi_migracion.lote_responsable",
                "checkpoint_insert_rejected_25006":
                    "INSERT INTO tpi_migracion.control_legacy_checkpoint "
                    "VALUES (501,30,801)",
                "checkpoint_update_rejected_25006":
                    "UPDATE tpi_migracion.control_legacy_checkpoint "
                    "SET deposito_id=deposito_id",
                "checkpoint_delete_rejected_25006":
                    "DELETE FROM tpi_migracion.control_legacy_checkpoint",
                "checkpoint_truncate_rejected_25006":
                    "TRUNCATE TABLE tpi_migracion.control_legacy_checkpoint",
            }
            for label, sql in statements.items():
                rejections[label] = self.expected_error(
                    connection, label.lower(), [(sql, None)], "25006",
                )
                require(relation_rows(
                    connection, "control_legacy_fnbc_archivada"
                ) == CURRENT, "archive_changed_after_rejection")
                require(relation_hash(
                    connection, "control_legacy_fnbc_archivada"
                ) == self.current_hash, "archive_hash_changed_after_rejection")
                require(lifecycle(connection) == "false",
                        "archive_lifecycle_changed")
                self.check_checkpoint(connection)
            require(catalog(connection) == before,
                    "archive_tests_changed_catalog")
            for name in ("responsable_deposito", "lote_responsable",
                         "_migration_guard"):
                require(kind(connection, name) == "r",
                        "final_archive_table_missing")
            require(scalar(
                connection,
                "SELECT sha256 FROM tpi_migracion.migration_manifest "
                "WHERE phase='confirmed_changes'",
            ) == self.current_hash, "final_snapshot_manifest_changed")
        copy, source = self.observe_scope("final")
        self.evidence["scope"]["public_fingerprints_after"] = copy
        self.evidence["scope"]["official_source_fingerprints_after"] = source
        self.evidence["final"] = {
            "fresh_connection_validation": True,
            "legacy_relation_kind_table": True,
            "legacy_four_rows_exact": CURRENT,
            "legacy_hash_matches_current_join_snapshot": True,
            "archived_view_four_rows_exact": CURRENT,
            "RD_LR_retained": True,
            **rejections,
            "checkpoint_three_rows_hash_same": True,
            "public_fingerprints_unchanged": True,
            "official_source_fingerprints_unchanged": True,
            "no_personal_rows_exported": True,
            "no_human_approval_claimed": True,
            "no_sequences_created": True,
            "catalog_sha256": digest_bytes(canonical(before)),
        }

    def run(self):
        self.observe_scope("before", initial=True)
        self.prepare()
        self.invalid_source()
        self.migration(False)
        self.migration(True)
        self.constraints()
        self.concurrency()
        self.confirmed_changes()
        self.down_error()
        self.down_commit()
        self.final()


def write_evidence(path, evidence):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    with temporary.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(evidence, stream, sort_keys=True, indent=2,
                  ensure_ascii=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, path)


def arguments(argv=None):
    parser = argparse.ArgumentParser(
        description="FNBC laboratory restricted to the named working copy."
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=55605)
    parser.add_argument("--user", default="u5_bootstrap")
    parser.add_argument("--secret-file", type=Path, required=True)
    parser.add_argument("--backup-manifest", type=Path, required=True)
    parser.add_argument("--source-database", default="foodstore")
    parser.add_argument(
        "--evidence", type=Path,
        default=ROOT / "docs/evidencias_tpi/migracion_fnbc.json",
    )
    parser.add_argument(
        "--provenance", type=Path, required=True,
        help="Review index linking original Kiro/Codex and Build/Plan artifacts.",
    )
    return parser.parse_args(argv)


def main(argv=None):
    require(sys.version_info >= (3, 12), "python_312_required")
    args = arguments(argv)
    started = utc_now()
    evidence = {
        "status": "RUNNING",
        "started_utc": iso(started),
        "review_automated_not_human": True,
        "scope": {
            "database_name_exact": TARGET,
            "source_database_name": args.source_database,
            "schema": SCHEMA,
            "public_writes_allowed": False,
            "backup_checks": [],
            "phase_fingerprints": [],
        },
    }
    destination = args.evidence
    if not destination.is_absolute():
        destination = ROOT / destination
    destination = destination.resolve()
    require(destination.is_relative_to(ROOT), "evidence_must_be_in_repository")
    require(destination.suffix == ".json", "evidence_must_be_json")
    require(not destination.exists(), "evidence_already_exists")
    require(not destination.with_name(destination.name + ".tmp").exists(),
            "evidence_temporary_file_already_exists")
    require(destination.parent.resolve().is_relative_to(ROOT),
            "evidence_parent_escape")

    runner = None
    try:
        require(1 <= args.port <= 65535, "invalid_port")
        require(args.source_database != TARGET
                and bool(args.source_database), "invalid_source_database")
        args.secret_file = private_file(args.secret_file, "secret_file")
        args.backup_manifest = private_file(
            args.backup_manifest, "backup_manifest")
        require(args.secret_file != args.backup_manifest,
                "secret_and_manifest_must_differ")
        backup = verify_backup(args, started)
        evidence["scope"].update(backup)

        sources = {relative(HERE / name): digest_file(HERE / name)
                   for name in SOURCE_FILES}
        evidence["provenance"] = verify_provenance(args.provenance, sources)
        scripts = {
            name: (HERE / name).read_text(encoding="utf-8")
            for name in ("preparar.sql", "migrar.sql", "revertir.sql")
        }
        for name in scripts:
            require(digest_file(HERE / name) == sources[relative(HERE / name)],
                    "source_changed_after_review")

        # libpq connection establishment is bounded independently of SQL timeouts.
        os.environ["PGCONNECT_TIMEOUT"] = "5"
        os.environ["PGCLIENTENCODING"] = "UTF8"
        client = load_client()
        runner = Runner(args, client, evidence, started, scripts)
        with runner.transaction(True, suffix="initial_identity") as connection:
            absent = scalar(
                connection, "SELECT to_regnamespace('tpi_migracion')::text"
            ) is None
            require(absent, "destination_schema_already_exists")
            evidence["scope"]["schema_initially_absent"] = True
        runner.run()
        for name, expected in sources.items():
            require(digest_file(ROOT / name) == expected,
                    "source_changed_during_execution")
        evidence["status"] = "SUCCESS"
        evidence["completed_utc"] = iso(utc_now())
        write_evidence(destination, evidence)
        print("SUCCESS: FNBC evidence written.")
        return 0
    except Exception as error:
        evidence["status"] = "FAILED"
        evidence["completed_utc"] = iso(utc_now())
        evidence["failure"] = {"type": type(error).__name__}
        state = getattr(error, "sqlstate", None)
        if isinstance(state, str) and re.fullmatch(r"[A-Z0-9]{5}", state):
            evidence["failure"]["sqlstate"] = state
        if isinstance(error, LaboratoryError):
            # These labels are local constants, never raw server diagnostics.
            evidence["failure"]["check"] = str(error)
        if runner is not None and runner.before_copy is not None:
            try:
                runner.observe_scope("failure_observation")
            except Exception as scope_error:
                evidence["failure"]["scope_observation_failed"] = {
                    "type": type(scope_error).__name__,
                }
        write_evidence(destination, evidence)
        print("FAILED: laboratory stopped; inspect sanitized evidence.",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

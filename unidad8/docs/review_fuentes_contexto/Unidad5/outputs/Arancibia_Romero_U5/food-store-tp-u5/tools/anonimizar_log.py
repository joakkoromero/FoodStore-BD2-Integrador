# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Extract real incident sessions and sanitize an offline PostgreSQL log.

Usage: python tools/anonimizar_log.py INPUT_RAW OUTPUT_SANITIZED
Raw input must remain outside this repository and the workspace outputs folder.
The tool never invents events or prints log contents. Review the sanitized log
manually before sending it to an AI; the scan report records that requirement.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys

from libpq_client import ConfigurationError, REPOSITORY_ROOT, load_secrets


EMAIL = re.compile(r"(?i)[A-Z0-9.!#$%&*+/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}")
ENTRY_START = re.compile(r"^\d{4}-\d{2}-\d{2}[ T]")
APP_FIELD = re.compile(r"\b(?:app|application_name)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s]+))")
SESSION_FIELD = re.compile(r"\b(?:session|session_id)\s*=\s*['\"]?([A-Za-z0-9_.:-]+)")
PID_FIELD = re.compile(r"(?:\[(\d+)\]|\bpid=(\d+))")
SQL_STRING = r"'(?:''|[^'])*'"
AUTH_LITERAL = re.compile(r"(?is)(\bfn_autenticar\s*\(\s*)("+SQL_STRING+r")(\s*,\s*)("+SQL_STRING+r")")
RESET_LITERAL = re.compile(r"(?is)(\bfn_resetear_password\s*\(\s*[^,()]+,\s*)("+SQL_STRING+r")")
PASSWORD_LITERAL = re.compile(r"(?i)(\bPASSWORD\s+)("+SQL_STRING+r")")
BCRYPT = re.compile(r"\$2[aby]\$[0-9]{2}\$[^\s'\",;()]*")
SCRAM = re.compile(r"(?i)SCRAM-SHA-256\$[A-Za-z0-9/+=:$.]+")
PERSON_FIELD = re.compile(r"(?i)\b(nombre|apellido|full_name|person_name|display_name)\s*=\s*('(?:''|[^'])*'|\"[^\"]*\"|[^\s,;]+)")
PHONE_FIELD = re.compile(r"(?i)\b(telefono|phone|telephone)\s*=\s*('(?:''|[^'])*'|\"[^\"]*\"|[^\s,;]+)")


@dataclass
class Entry:
    text: str
    application: str | None = None
    session: str | None = None
    pid: str | None = None


def _alias_email(value: str) -> str:
    if value.lower().endswith(("@anon.invalid", "@example.invalid")):
        return value
    suffix = hashlib.sha256(value.casefold().encode("utf-8")).hexdigest()[:12]
    return "cuenta_"+suffix+"@anon.invalid"


def _person_token(value: str) -> str:
    suffix = hashlib.sha256(value.encode("utf-8")).hexdigest()[:10]
    return "PERSONA_"+suffix


def _metadata(line: str) -> Entry:
    if line.lstrip().startswith("{"):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            obj = None
        if isinstance(obj, dict):
            session = obj.get("session_id")
            pid = obj.get("pid")
            return Entry(line, obj.get("application_name"),
                         str(session) if session is not None else None,
                         str(pid) if pid is not None else None)
    app_match = APP_FIELD.search(line)
    session_match = SESSION_FIELD.search(line)
    pid_match = PID_FIELD.search(line)
    app = next((v for v in app_match.groups() if v is not None), None) if app_match else None
    pid = next((v for v in pid_match.groups() if v is not None), None) if pid_match else None
    return Entry(line, app, session_match.group(1) if session_match else None, pid)


def parse_entries(text: str) -> list[Entry]:
    """Keep multiline SQL/context lines attached to their actual log entry."""
    entries: list[Entry] = []
    for line in text.splitlines(keepends=True):
        if ENTRY_START.match(line) or line.lstrip().startswith("{"):
            entries.append(_metadata(line))
        elif entries:
            entries[-1].text += line
        else:
            entries.append(Entry(line))
    return entries


def extract_sessions(entries: list[Entry], application: str,
                     explicit_sessions: list[str]) -> tuple[str, dict]:
    matched = [e for e in entries if e.application and e.application.startswith(application)]
    sessions = {e.session for e in matched if e.session}
    sessions.update(explicit_sessions)
    # A backend PID is only a fallback for formats lacking session IDs. We
    # expose that weaker correlation in the report, rather than hiding it.
    fallback_pids = {e.pid for e in matched if not e.session and e.pid}
    if not sessions and not fallback_pids:
        raise ConfigurationError("No incident session matches the requested application or session IDs")
    selected = [e for e in entries if
                (e.session is not None and e.session in sessions)
                or (e.session is None and e.pid is not None and e.pid in fallback_pids)]
    if not selected:
        raise ConfigurationError("Requested session IDs do not occur in the raw log")
    # Preserve source order and every selected entry, including failed queries.
    return "".join(e.text for e in selected), {
        "application_prefix": application,
        "selected_entries": len(selected),
        "selected_sessions": sorted(sessions),
        "fallback_pid_correlation": bool(fallback_pids),
        "matched_application_entries": len(matched),
    }


def secret_inventory(data: dict) -> list[str]:
    """Collect private password/token values, including the role mapping.

    Identity/configuration fields are handled separately, so role names and
    event labels retain their investigative meaning in the sanitized log.
    """
    collected: set[str] = set()
    sensitive = re.compile(r"(?i)(password|passwd|passphrase|secret|token|credential|\bpwd\b)")
    role_keys = {"app_web", "admin_datos", "u5_bootstrap", "u5_admin", "tp_admin", "postgres"}

    def visit(value, path: tuple[str, ...]) -> None:
        if isinstance(value, dict):
            for key, nested in value.items():
                visit(nested, path+(str(key),))
        elif isinstance(value, list):
            for index, nested in enumerate(value):
                visit(nested, path+(str(index),))
        elif isinstance(value, str) and value:
            is_role_value = len(path) >= 2 and path[-2] in {"roles", "passwords", "db_passwords"}
            is_named_secret = any(sensitive.search(part) for part in path)
            is_flat_role = len(path) == 1 and path[0] in role_keys
            if is_role_value or is_named_secret or is_flat_role:
                if len(value) < 4:
                    raise ConfigurationError("A runtime secret is too short for reliable offline substring scanning")
                collected.add(value)

    visit(data, ())
    if not collected:
        raise ConfigurationError("Private runtime file contains no recognizable secret inventory")
    return sorted(collected, key=len, reverse=True)


def sanitize(text: str, secrets: list[str], private_redactions: dict[str, str]) -> tuple[str, dict]:
    counts: dict[str, int] = {}
    original_emails = EMAIL.findall(text)
    counts["auth_quoted_passwords"] = len(AUTH_LITERAL.findall(text))
    counts["reset_quoted_passwords"] = len(RESET_LITERAL.findall(text))
    counts["password_utility_literals"] = len(PASSWORD_LITERAL.findall(text))
    counts["known_secret_occurrences"] = sum(text.count(secret) for secret in secrets)

    def auth_replacement(match):
        account = match.group(2)[1:-1].replace("''", "'")
        account = _alias_email(account) if "@" in account else _person_token(account)
        return match.group(1)+"'"+account+"'"+match.group(3)+"'[CREDENTIAL_REDACTED]'"

    text = AUTH_LITERAL.sub(auth_replacement, text)
    text = RESET_LITERAL.sub(lambda m: m.group(1)+"'[CREDENTIAL_REDACTED]'", text)
    text = PASSWORD_LITERAL.sub(lambda m: m.group(1)+"'[CREDENTIAL_REDACTED]'", text)
    for secret in secrets:
        text = text.replace(secret, "[SECRET_REDACTED]")
    counts["bcrypt_hashes"] = len(BCRYPT.findall(text))
    counts["scram_verifiers"] = len(SCRAM.findall(text))
    text = BCRYPT.sub("[CREDENTIAL_HASH_REDACTED]", text)
    text = SCRAM.sub("[CREDENTIAL_HASH_REDACTED]", text)
    text = EMAIL.sub(lambda m: _alias_email(m.group()), text)
    counts["email_occurrences"] = len(original_emails)
    counts["email_occurrences_changed"] = sum(_alias_email(value) != value for value in original_emails)
    counts["person_fields"] = len(PERSON_FIELD.findall(text))
    text = PERSON_FIELD.sub(lambda m: m.group(1)+"='"+_person_token(m.group(2))+"'", text)
    counts["phone_fields"] = len(PHONE_FIELD.findall(text))
    text = PHONE_FIELD.sub(lambda m: m.group(1)+"='[PHONE_REDACTED]'", text)
    text, counts["database_labels"] = re.subn(
        r"(?i)\bfoodstore_(?:u[0-9]+|tp[0-9]+)(?:_[A-Za-z0-9]+)*\b", "foodstore_lab", text)
    text, counts["windows_user_paths"] = re.subn(
        r"(?i)([A-Z]:[\\/]+Users[\\/]+)[^\\/\r\n'\"]+", lambda m: m.group(1)+"USR_LOCAL", text)
    text, counts["unix_user_paths"] = re.subn(
        r"(/(?:home|Users)/)[^/\s'\"]+", lambda m: m.group(1)+"USR_LOCAL", text)
    counts["private_literal_replacements"] = 0
    for original, replacement in sorted(private_redactions.items(), key=lambda item: len(item[0]), reverse=True):
        if not original or not isinstance(replacement, str):
            raise ConfigurationError("Private redactions must map nonempty text to synthetic text")
        counts["private_literal_replacements"] += text.count(original)
        text = text.replace(original, replacement)

    # Final checks do not disclose which secret matched, or its value.
    if any(secret in text for secret in secrets):
        raise ConfigurationError("Sanitized output still contains a known runtime secret")
    if BCRYPT.search(text) or SCRAM.search(text):
        raise ConfigurationError("Sanitized output still contains a credential hash")
    remaining_emails = EMAIL.findall(text)
    if any(not value.lower().endswith(("@anon.invalid", "@example.invalid")) for value in remaining_emails):
        raise ConfigurationError("Sanitized output still contains a non-synthetic email")
    quoted_auth = AUTH_LITERAL.findall(text)
    quoted_reset = RESET_LITERAL.findall(text)
    if any("CREDENTIAL_REDACTED" not in m[-1] for m in quoted_auth+quoted_reset):
        raise ConfigurationError("A quoted authentication credential still requires review")
    return text, {
        "replacement_counts": counts,
        "secret_scan_passed": True,
        "credential_hash_scan_passed": True,
        "email_scan_passed": True,
        "raw_selected_contained_known_secrets": counts["known_secret_occurrences"] > 0,
        "raw_selected_contained_quoted_credentials": bool(
            counts["auth_quoted_passwords"]+counts["reset_quoted_passwords"]+counts["password_utility_literals"]),
        "manual_review_required": True,
        "manual_review_scope": [
            "Check names or identifying text outside recognized field formats",
            "Verify session selection covers the entire executed sequence",
            "Confirm event order, outcomes, role names, timestamps and loopback topology were preserved",
        ],
        "limitations": "Deterministic substitutions reduce disclosure; they do not establish irreversible anonymization or prove the original log was untampered.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_raw", type=Path)
    parser.add_argument("output_sanitized", type=Path)
    parser.add_argument("--application", default="u5_incident")
    parser.add_argument("--session", action="append", default=[], help="Also include this actual source session ID")
    parser.add_argument("--secrets", type=Path, help="Private file; otherwise U5_SECRET_FILE/default workspace private file")
    parser.add_argument("--redactions-file", type=Path, help="Optional private JSON literal-to-synthetic mapping for manual findings")
    parser.add_argument("--report", type=Path, help="Default: output filename followed by .scan.json")
    args = parser.parse_args()
    raw = args.input_raw.resolve()
    output = args.output_sanitized.resolve()
    if raw == output or raw.is_relative_to(REPOSITORY_ROOT):
        raise ConfigurationError("Keep raw input outside the repository and separate from sanitized output")
    for ancestor in REPOSITORY_ROOT.parents:
        if ancestor.name.casefold() == "outputs" and raw.is_relative_to(ancestor):
            raise ConfigurationError("Raw logs must not be stored inside the workspace outputs directory")
    raw_bytes = raw.read_bytes()
    raw_text = raw_bytes.decode("utf-8-sig")
    selected, selection = extract_sessions(parse_entries(raw_text), args.application, args.session)
    inventory = secret_inventory(load_secrets(args.secrets))
    redactions = {}
    if args.redactions_file:
        redaction_path = args.redactions_file.resolve()
        if redaction_path.is_relative_to(REPOSITORY_ROOT):
            raise ConfigurationError("The private redaction mapping must stay outside the repository")
        redactions = json.loads(redaction_path.read_text(encoding="utf-8-sig"))
        if not isinstance(redactions, dict) or not all(isinstance(k, str) for k in redactions):
            raise ConfigurationError("Private redactions must be a JSON object")
    sanitized, scan = sanitize(selected, inventory, redactions)
    report = {
        **selection, **scan,
        "source_file_sha256": hashlib.sha256(raw_bytes).hexdigest(),
        "selected_raw_sha256": hashlib.sha256(selected.encode("utf-8")).hexdigest(),
        "sanitized_sha256": hashlib.sha256(sanitized.encode("utf-8")).hexdigest(),
        "events_invented": False,
        "retained": "Source ordering, timestamps/time zone, PID/session correlation, service roles and loopback addresses",
    }
    report_path = args.report.resolve() if args.report else output.with_name(output.name+".scan.json")
    if report_path == raw or report_path == output:
        raise ConfigurationError("The scan report needs its own output path")
    output.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    # Preserve the exact UTF-8 bytes hashed above, including LF/CRLF source
    # endings. Text mode would translate newlines again on Windows.
    output.write_bytes(sanitized.encode("utf-8"))
    written_sha256 = hashlib.sha256(output.read_bytes()).hexdigest()
    if written_sha256 != report["sanitized_sha256"]:
        raise ConfigurationError("The sanitized file bytes do not match the recorded SHA-256")
    report["sanitized_file_sha256_verified"] = True
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    # Counts and hashes only: neither input contents nor private mappings.
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ConfigurationError, OSError, UnicodeError, json.JSONDecodeError) as error:
        # OSError path details are not needed in a shareable diagnostic.
        message = str(error) if isinstance(error, ConfigurationError) else "Unable to read or write the local log inputs/outputs"
        print(json.dumps({"status": "failed", "reason": message}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(2)

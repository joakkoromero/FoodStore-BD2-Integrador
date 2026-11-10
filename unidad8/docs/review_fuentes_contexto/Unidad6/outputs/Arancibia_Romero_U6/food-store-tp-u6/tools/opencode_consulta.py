# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Run an actual, tool-denied OpenCode consultation and retain its provenance.

Only supply material already sanitized for disclosure. The complete event stream
and diagnostic output are stored outside this repository; the repository receives
the exact prompt, answer text, and non-secret run metadata. This program does not
execute generated SQL and does not represent technical review as human approval.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


REPOSITORY = Path(__file__).resolve().parents[1]
TASK_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_EXECUTABLE = Path(
    r"C:\Users\ASPIRE LITE 16\AppData\Roaming\npm\node_modules\opencode-ai\bin\opencode.exe"
)
DEFAULT_MODEL = "openai/gpt-6.1-sol"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def parse_events(raw: str) -> tuple[list[dict], list[str]]:
    events, unparsable = [], []
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            unparsable.append(line)
        else:
            if isinstance(event, dict):
                events.append(event)
            else:
                unparsable.append(line)
    return events, unparsable


def extract_answer(events: list[dict]) -> str:
    chunks = []
    for event in events:
        if event.get("type") != "text":
            continue
        part = event.get("part", {})
        text = part.get("text") if isinstance(part, dict) else None
        if isinstance(text, str) and text.strip():
            chunks.append(text)
    return "\n\n".join(chunks).strip()


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True,
                        help="Artifact label, for example d or a_revision")
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--file", dest="attachments", type=Path,
                        action="append", default=[],
                        help="Previously sanitized context attachment; repeatable")
    parser.add_argument("--executable", type=Path, default=DEFAULT_EXECUTABLE)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--working-dir", type=Path,
                        default=TASK_ROOT / "work/unidad6/opencode")
    parser.add_argument("--output-dir", type=Path,
                        default=REPOSITORY / "docs/ia")
    parser.add_argument("--private-dir", type=Path,
                        default=TASK_ROOT / "work/unidad6/private/opencode")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--retry-failed", action="store_true",
                        help="Retry an unsuccessful consultation, preserving its metadata privately")
    return parser.parse_args()


def main() -> int:
    args = arguments()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", args.prefix):
        raise SystemExit("Invalid artifact prefix")
    if is_within(args.private_dir, REPOSITORY):
        raise SystemExit("Raw events must be stored outside the deliverable repository")
    if not args.executable.is_file() or not args.prompt_file.is_file():
        raise SystemExit("Missing executable or prompt file")
    for attachment in args.attachments:
        if not attachment.is_file():
            raise SystemExit("A sanitized attachment does not exist")
    if args.timeout < 1:
        raise SystemExit("Timeout must be positive")

    prompt = args.prompt_file.read_text(encoding="utf-8")
    if not prompt.strip():
        raise SystemExit("Empty prompt")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.private_dir.mkdir(parents=True, exist_ok=True)
    args.working_dir.mkdir(parents=True, exist_ok=True)
    prompt_output = args.output_dir / f"{args.prefix}_prompt.txt"
    answer_output = args.output_dir / f"{args.prefix}_respuesta.md"
    metadata_output = args.output_dir / f"{args.prefix}_metadatos.json"
    prior_attempts = []
    if any(path.exists() for path in (answer_output, metadata_output)):
        if not args.retry_failed or answer_output.exists() or not metadata_output.exists():
            raise SystemExit("Answer/metadata already exist; use a new prefix for a new consultation")
        previous = json.loads(metadata_output.read_text(encoding="utf-8"))
        if previous.get("status") != "failed":
            raise SystemExit("A completed consultation cannot be retried under the same prefix")
        prior_attempts = previous.get("prior_failed_attempts", []) + [{
            key: previous.get(key) for key in (
                "started_at_utc", "finished_at_utc", "returncode", "timed_out",
                "event_count", "error_event_count", "raw_jsonl_sha256", "status"
            )
        }]
        failed_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        (args.private_dir / f"{args.prefix}_{failed_id}_previous_metadata.json").write_text(
            json.dumps(previous, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    if prompt_output.resolve() != args.prompt_file.resolve():
        prompt_output.write_text(prompt, encoding="utf-8")

    # Feed immutable byte-for-byte snapshots, so later SQL corrections cannot
    # replace the evidence of what the assistant actually received.
    snapshots = []
    if args.attachments:
        attachment_dir = args.output_dir / f"{args.prefix}_adjuntos"
        attachment_dir.mkdir(parents=True, exist_ok=True)
        for index, original in enumerate(args.attachments, 1):
            snapshot = attachment_dir / f"{index:02d}_{original.name}"
            source = original.read_bytes()
            if snapshot.exists() and snapshot.read_bytes() != source:
                raise SystemExit("An existing attachment snapshot differs; use a new consultation prefix")
            if not snapshot.exists():
                snapshot.write_bytes(source)
            snapshots.append((original, snapshot))

    environment = os.environ.copy()
    environment["OPENCODE_CONFIG_CONTENT"] = json.dumps({"permission": "deny"})
    version = subprocess.run(
        [str(args.executable), "--version"], env=environment,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        shell=False, timeout=30, check=False,
    )
    if version.returncode != 0:
        raise SystemExit("Unable to read installed OpenCode version")
    command = [str(args.executable), "run", prompt, "--pure", "--agent", "plan",
               "--format", "json", "--model", args.model,
               "--dir", str(args.working_dir.resolve())]
    for original, snapshot in snapshots:
        command.extend(["--file", str(snapshot.resolve())])

    started = utc_now()
    identifier = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    raw_output = args.private_dir / f"{args.prefix}_{identifier}.jsonl"
    raw_errors = args.private_dir / f"{args.prefix}_{identifier}.stderr.txt"
    timed_out = False
    try:
        completed = subprocess.run(
            command, env=environment, capture_output=True, text=True,
            encoding="utf-8", errors="replace", shell=False,
            timeout=args.timeout, check=False,
        )
        stdout, stderr, returncode = (
            completed.stdout, completed.stderr, completed.returncode
        )
    except subprocess.TimeoutExpired as error:
        timed_out = True
        stdout = error.stdout or ""
        stderr = error.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        returncode = None
    raw_output.write_text(stdout, encoding="utf-8")
    raw_errors.write_text(stderr, encoding="utf-8")
    events, invalid = parse_events(stdout)
    answer = extract_answer(events)
    errors = [event for event in events if event.get("type") == "error"]
    tool_events = [event for event in events
                   if event.get("type") in {"tool_use", "tool"}]
    successful = returncode == 0 and bool(answer) and not errors and not timed_out
    if answer:
        answer_output.write_text(answer + "\n", encoding="utf-8")
    attachments = []
    for original, snapshot in snapshots:
        item = {"name": original.name, "sha256": sha256(snapshot)}
        if is_within(snapshot, REPOSITORY):
            item["repository_path"] = snapshot.resolve().relative_to(REPOSITORY).as_posix()
        if is_within(original, REPOSITORY):
            item["source_path_at_consultation"] = original.resolve().relative_to(REPOSITORY).as_posix()
        attachments.append(item)
    metadata = {
        "tool": "OpenCode",
        "installed_version": version.stdout.strip(),
        "requested_model": args.model,
        "agent": "plan", "pure": True,
        "permission_config": {"permission": "deny"},
        "started_at_utc": started, "finished_at_utc": utc_now(),
        "prompt_sha256": sha256(prompt_output),
        "attachments": attachments,
        "returncode": returncode, "timed_out": timed_out,
        "event_count": len(events), "unparsed_line_count": len(invalid),
        "error_event_count": len(errors), "tool_event_count": len(tool_events),
        "answer_sha256": sha256(answer_output) if answer_output.exists() else None,
        "raw_jsonl_sha256": sha256(raw_output),
        "raw_event_storage": "Private work directory outside deliverable repository",
        "status": "completed" if successful else "failed",
        "prior_failed_attempts": prior_attempts,
        "sql_executed": False,
        "human_validation": "Pending; this consultation does not establish human approval",
    }
    metadata_output.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # Never print raw output, errors, authentication material, or environment.
    print(json.dumps({"prefix": args.prefix, "status": metadata["status"],
                      "model": args.model, "event_count": len(events),
                      "answer_characters": len(answer)}, ensure_ascii=False))
    return 0 if successful else 1


if __name__ == "__main__":
    sys.exit(main())

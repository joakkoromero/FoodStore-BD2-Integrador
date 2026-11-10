# Fuentes saneadas para revisión estática: Unidad5

No ejecutar estas copias. Los literales personales/de carga se sustituyeron por placeholders; las comprobaciones en motor usarán las fuentes originales locales. Señalar archivo/línea y distinguir errores confirmables de hipótesis.

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\opencode_consulta.py

SHA256 original: 28b87af6df59f448d954d1f925988916b7d3fc7e5999d51ab1de2dc25af9cb82
SHA256 saneado: 03f941dc2934cbe99657ebce8d4eb80e67b33a94aff8067644d4254261323f56

`````py
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
                        default=TASK_ROOT / "work/unidad5/opencode")
    parser.add_argument("--output-dir", type=Path,
                        default=REPOSITORY / "docs/ia")
    parser.add_argument("--private-dir", type=Path,
                        default=TASK_ROOT / "work/unidad5/private/opencode")
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

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\preparar_laboratorio.py

SHA256 original: 01114896e1a3af4877f76b8c620569cc74070b5f7d20790b69c620170111f7b4
SHA256 saneado: 71f9879d73aa65dda5a9257ec2729742f4d06dde3299c5ea27f3c23903e1d8f0

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Preparar una instancia PostgreSQL 17 privada para Food Store Unidad 5.

Codigo generado con asistencia de Codex; no acredita uso de Kiro u OpenCode.
Solo biblioteca estandar. Importar este modulo no inicia procesos ni conexiones.
El respaldo debe permanecer fuera del repositorio. El runtime, sus claves y los
logs sin anonimizar son privados y no forman parte de la entrega Git.

Este preparador NO crea roles de aplicacion, NO escribe roles.sql y NO modifica
los permisos del esquema public. Esos pasos requieren la especificacion previa.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import subprocess
import sys
import traceback


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DATABASE = "foodstore_u5_arancibia_romero"
BOOTSTRAP_USER = "u5_bootstrap"
HOST = "127.0.0.1"


class PreparationError(RuntimeError):
    """Mensaje publico deliberadamente sanitizado."""


def hidden_process_options() -> dict:
    if os.name != "nt":
        return {}
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    return {
        "creationflags": subprocess.CREATE_NO_WINDOW,
        "startupinfo": startup,
    }


class PrivateLog:
    def __init__(self, path: Path):
        self.path = path

    def write(self, text: str) -> None:
        with self.path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            if not text.endswith("\n"):
                handle.write("\n")


def private_command(arguments: list[str], *, log: PrivateLog,
                    environment: dict | None = None,
                    timeout: int = 180) -> subprocess.CompletedProcess:
    """No imprimir salida de herramientas, consultas ni parametros privados."""
    log.write("COMANDO: " + subprocess.list2cmdline(arguments))
    try:
        result = subprocess.run(
            arguments,
            env=environment,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
            **hidden_process_options(),
        )
    except Exception:
        log.write(traceback.format_exc())
        raise PreparationError("Una herramienta local no pudo completarse") from None
    log.write("STDOUT:\n" + result.stdout)
    log.write("STDERR:\n" + result.stderr)
    log.write(f"EXITCODE: {result.returncode}\n")
    if result.returncode != 0:
        raise PreparationError("Una herramienta local devolvio un error; revisar el log privado")
    return result


def pg_binary_directory(explicit: str | None) -> Path:
    if explicit:
        selected = Path(explicit).expanduser().resolve()
    else:
        preferred = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "PostgreSQL" / "17" / "bin"
        if preferred.is_dir():
            selected = preferred.resolve()
        else:
            executable = shutil.which("pg_ctl.exe")
            if not executable:
                raise PreparationError("No se encontro PostgreSQL 17; indicar --pg-bin")
            selected = Path(executable).resolve().parent
    if not all((selected / name).is_file() for name in
               ("initdb.exe", "pg_ctl.exe", "createdb.exe", "pg_restore.exe", "psql.exe")):
        raise PreparationError("El directorio --pg-bin no contiene las herramientas requeridas")
    return selected


def current_user_sid() -> str:
    try:
        result = subprocess.run(
            ["whoami.exe", "/user", "/fo", "csv", "/nh"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=15, check=False, **hidden_process_options(),
        )
        rows = list(csv.reader(io.StringIO(result.stdout)))
        sid = next(field for row in rows for field in row
                   if re.fullmatch(r"S-\d+(?:-\d+)+", field))
        if result.returncode:
            raise ValueError("whoami")
        return sid
    except Exception:
        raise PreparationError("No se pudo identificar el usuario Windows para proteger el runtime") from None


def create_private_runtime(runtime: Path) -> PrivateLog:
    """Crear solo un directorio nuevo; no cambiar ACL de carpetas existentes."""
    if runtime.exists():
        if (runtime / "pgdata").exists():
            raise PreparationError("Ya existe pgdata; no se borra ni reutiliza un cluster")
        raise PreparationError("El runtime debe ser un directorio nuevo; no se sobrescribe su contenido")
    if not runtime.parent.is_dir():
        raise PreparationError("Debe existir el directorio padre del runtime elegido")
    sid = current_user_sid()
    runtime.mkdir(exist_ok=False)
    arguments = [
        "icacls.exe", str(runtime), "/inheritance:r", "/grant:r",
        f"*{sid}:(OI)(CI)F",
        "*S-1-5-18:(OI)(CI)F",       # SYSTEM, independiente del idioma.
        "*S-1-5-32-544:(OI)(CI)F",   # Administradores locales.
    ]
    try:
        result = subprocess.run(
            arguments, capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=20, check=False, **hidden_process_options(),
        )
    except Exception:
        raise PreparationError("No se pudo aplicar la ACL privada; no se generaron claves") from None
    if result.returncode:
        raise PreparationError("Fallo la ACL privada; no se generaron claves")
    # Solo despues de proteger la carpeta se escriben logs y material secreto.
    log = PrivateLog(runtime / "preparacion_privada.log")
    log.write("ACL runtime: usuario Windows actual, SYSTEM y Administradores locales.")
    log.write(result.stdout)
    log.write(result.stderr)
    return log


def write_new_private_file(path: Path, content: str) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)


def dump_digest(source: Path) -> str:
    digest = hashlib.sha256()
    with source.open("rb") as handle:
        if handle.read(5) != b"PGDMP":
            raise PreparationError("--source-dump debe ser un respaldo PostgreSQL en formato custom")
        handle.seek(0)
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_port(port: int) -> None:
    if not 1024 <= port <= 65535:
        raise PreparationError("El puerto debe estar entre 1024 y 65535")
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.bind((HOST, port))
    except OSError:
        raise PreparationError("El puerto local elegido no esta libre; no se toca el servidor existente") from None


def postgresql_settings(port: int) -> str:
    return f"""
# Laboratorio U5 privado: se agrega antes del primer inicio.
listen_addresses = '{HOST}'
port = {port}
cluster_name = 'foodstore_u5_desarrollo'
timezone = 'America/Argentina/Buenos_Aires'
log_timezone = 'America/Argentina/Buenos_Aires'
password_encryption = 'secreto_saneado_b8d966c6866f'
logging_collector = on
log_destination = 'stderr,jsonlog'
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_file_mode = 0600
log_line_prefix = '%m [%p] user=%u db=%d app=%a client=%r sqlstate=%e session=%c '
log_connections = on
log_disconnections = on
log_statement = 'none'
log_min_error_statement = 'panic'
log_parameter_max_length = 0
log_parameter_max_length_on_error = 0
"""


def prepare(arguments: argparse.Namespace) -> tuple[Path, Path]:
    if os.name != "nt":
        raise PreparationError("Este preparador requiere Windows y PostgreSQL 17")
    runtime = Path(arguments.runtime).expanduser().resolve()
    source = Path(arguments.source_dump).expanduser().resolve()
    if runtime.is_relative_to(REPOSITORY_ROOT):
        raise PreparationError("El runtime privado debe quedar fuera del repositorio Git")
    if source.is_relative_to(REPOSITORY_ROOT):
        raise PreparationError("El respaldo privado debe quedar fuera del repositorio Git")
    if (runtime / "pgdata").exists():
        raise PreparationError("Ya existe pgdata; no se borra ni reutiliza un cluster")
    if runtime.exists():
        raise PreparationError("El runtime debe ser un directorio nuevo; no se sobrescribe su contenido")
    if not source.is_file():
        raise PreparationError("No se encontro el respaldo privado indicado")
    pg_bin = pg_binary_directory(arguments.pg_bin)
    source_sha = dump_digest(source)
    validate_port(arguments.port)
    log = create_private_runtime(runtime)
    pgdata = runtime / "pgdata"
    secret_path = runtime / "secrets.json"
    connection_path = runtime / "connection.json"
    init_password_path = runtime / "initpw"
    server_start_attempted = False
    initialization_password_created = False
    successful = False
    try:
        version = private_command([str(pg_bin / "initdb.exe"), "--version"], log=log)
        if not re.search(r"\b17(?:\.|\s|$)", version.stdout):
            raise PreparationError("Se requiere PostgreSQL 17 para reproducir este laboratorio")

        bootstrap_password = secrets.token_urlsafe(32)
        app_password = secrets.token_urlsafe(32)
        admin_password = secrets.token_urlsafe(32)
        business_password = secrets.token_urlsafe(32)
        business_email = "laboratorio.u5." + secrets.token_hex(8) + "@example.invalid"
        private_secrets = {
            "bootstrap_user": BOOTSTRAP_USER,
            "bootstrap_password": bootstrap_password,
            "app_user": "app_web",
            "app_password": app_password,
            "admin_user": "admin_datos",
            "admin_password": admin_password,
            "business_email": business_email,
            "business_password": business_password,
            "roles": {
                BOOTSTRAP_USER: bootstrap_password,
                "app_web": app_password,
                "admin_datos": admin_password,
            },
            "app_auth": {"email": business_email, "password": business_password},
            "host": HOST,
            "port": arguments.port,
            "database": DATABASE,
        }
        write_new_private_file(secret_path, json.dumps(private_secrets, ensure_ascii=False, indent=2) + "\n")
        connection = {
            "host": HOST,
            "port": arguments.port,
            "dbname": DATABASE,
            "bootstrap_user": BOOTSTRAP_USER,
            "pg_bin": str(pg_bin),
            "pgdata": str(pgdata),
            "secret_file": str(secret_path),
            "source_dump_sha256": source_sha,
            "connection_args": ["-h", HOST, "-p", str(arguments.port), "-U", BOOTSTRAP_USER, "-d", DATABASE],
            "state": "preparacion_iniciada",
            "scope": "Cluster nuevo de desarrollo; sin roles ni cambios de permisos U5",
        }
        write_new_private_file(connection_path, json.dumps(connection, ensure_ascii=False, indent=2) + "\n")
        write_new_private_file(init_password_path, bootstrap_password + "\n")
        initialization_password_created = True
        try:
            private_command([
                str(pg_bin / "initdb.exe"), "-D", str(pgdata),
                "--username", BOOTSTRAP_USER, "-A", "scram-sha-256",
                "--pwfile", str(init_password_path), "--encoding", "UTF8", "--locale", "C",
            ], log=log)
        finally:
            # Solo se elimina ESTE archivo literal creado por esta ejecucion.
            # No se borran carpetas, pgdata ni ningun respaldo o archivo previo.
            if initialization_password_created:
                init_password_path.unlink(missing_ok=True)
                initialization_password_created = False

        with (pgdata / "postgresql.conf").open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(postgresql_settings(arguments.port))
        server_start_attempted = True
        private_command([
            str(pg_bin / "pg_ctl.exe"), "-D", str(pgdata), "-l", str(runtime / "arranque_privado.log"),
            "-w", "-t", "60", "start",
        ], log=log, timeout=90)

        # La contrasena viaja en el entorno privado del proceso, no en argv,
        # stdout, archivos SQL, Git, cadenas de conexion ni el comando impreso.
        # No heredar PGHOSTADDR/PGSERVICE/PGOPTIONS de otra instalacion: podrian
        # dirigir una herramienta a un servidor distinto pese al -h explicito.
        environment = {key: value for key, value in os.environ.items()
                       if not key.upper().startswith("PG")}
        environment.update({
            "PGHOST": HOST, "PGPORT": str(arguments.port), "PGUSER": BOOTSTRAP_USER,
            "PGPASSWORD": bootstrap_password, "PGCLIENTENCODING": "UTF8", "PGCONNECT_TIMEOUT": "10",
            "PGAPPNAME": "u5_preparar_laboratorio",
        })
        private_command([
            str(pg_bin / "createdb.exe"), "-w", "-h", HOST, "-p", str(arguments.port),
            "-U", BOOTSTRAP_USER, "--encoding", "UTF8", DATABASE,
        ], log=log, environment=environment)
        private_command([
            str(pg_bin / "pg_restore.exe"), "-w", "-h", HOST, "-p", str(arguments.port),
            "-U", BOOTSTRAP_USER, "--dbname", DATABASE, "--format=custom",
            "--no-owner", "--no-privileges", "--exit-on-error", str(source),
        ], log=log, environment=environment, timeout=900)
        connection["state"] = "respaldo_restaurado_sin_roles_u5"
        connection_path.write_text(json.dumps(connection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        successful = True
        log.write("Preparacion finalizada. No se crearon roles U5 ni se modificaron ACL de public.")
        return secret_path, connection_path
    except Exception:
        log.write(traceback.format_exc())
        raise PreparationError("La preparacion no termino; revisar preparacion_privada.log en el runtime") from None
    finally:
        if initialization_password_created:
            init_password_path.unlink(missing_ok=True)
        if not successful and server_start_attempted and (pgdata / "postmaster.pid").is_file():
            # Solo se detiene el cluster que esta ejecucion intento iniciar.
            # Su ruta resuelta debe seguir dentro del runtime nuevo y privado.
            if pgdata.resolve().is_relative_to(runtime) and pgdata.resolve() == runtime / "pgdata":
                try:
                    private_command([
                        str(pg_bin / "pg_ctl.exe"), "-D", str(pgdata), "-m", "fast", "-w", "-t", "30", "stop",
                    ], log=log, timeout=45)
                except PreparationError:
                    log.write("No se confirmo la detencion del cluster nuevo; revisar su estado localmente.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Crear un cluster PostgreSQL 17 privado y restaurar la copia de desarrollo U5. No aplicar roles."
    )
    parser.add_argument("--source-dump", required=True, help="Respaldo custom privado, fuera del repositorio; nunca se copia a Git")
    parser.add_argument(
        "--runtime", default=str(REPOSITORY_ROOT.parent / "food-store-tp-u5-runtime"),
        help="Directorio externo nuevo para datos, claves y logs privados; nunca dentro del repositorio",
    )
    parser.add_argument("--pg-bin", help="Directorio bin de PostgreSQL 17; se detecta su instalacion Windows")
    parser.add_argument("--port", type=int, default=55605, help="Puerto IPv4 local libre; predeterminado 55605")
    args = parser.parse_args(argv)
    try:
        secret_path, connection_path = prepare(args)
    except PreparationError as exc:
        print("ERROR: " + str(exc), file=sys.stderr)
        return 1
    except Exception:
        # No publicar traceback ni errores de herramientas con datos sensibles.
        print("ERROR: no se completo la preparacion; revisar el runtime privado si fue creado", file=sys.stderr)
        return 1
    print("Laboratorio privado preparado; la etapa de roles U5 todavia no fue aplicada.")
    print("SECRETS=" + str(secret_path))
    print("CONNECTION=" + str(connection_path))
    quoted_secret = str(secret_path).replace("'", "''")
    print("Siguiente comando (PowerShell): $env:U5_SECRET_FILE = '" + quoted_secret + "'")
    print("Despues, seguir el README para aplicar la especificacion y los roles aprobados.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\rotar_log.py

SHA256 original: 09820b3049598d134e859bbff46e14d2dd7287a44a81dbffb6e364af00dbfd47
SHA256 saneado: 92437126de0ac69d5e171a03ec4582719cc1649c4c763d55f38637003b91f18c

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Rotate the private server JSON log, preserving the source for capture."""
import json
import time
from libpq_client import Connection, load_secrets


def main():
    secret = load_secrets()
    with Connection(secret['bootstrap_user'], application_name='u5_rotate_log') as db:
        query = 'SELECT pg_catalog.pg_current_logfile($1::text)'
        before = db.scalar(query, ['jsonlog'])
        requested = db.scalar('SELECT pg_catalog.pg_rotate_logfile()')
        if requested != 't':
            raise RuntimeError('Server did not accept log rotation')
        for attempt in range(20):
            time.sleep(0.1)
            after = db.scalar(query, ['jsonlog'])
            if before != after:
                break
        else:
            raise RuntimeError('Rotation not observed; source may still be active')
    print(json.dumps({'previous_json_log':before,'current_json_log':after,
                      'rotation_observed':True}))


if __name__ == '__main__':
    main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\verificar_conservacion.py

SHA256 original: 43032979d45abf5f6aa1f5a512aabfab2e724f654905ffd7ae6c8980e5dfafaa
SHA256 saneado: f803e7e85b0b21a04293ce3b46882acd6bea8d86fc8fd9b016a19a895103099a

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Compare complete inherited business tables without exporting their rows."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from pathlib import Path

from libpq_client import Connection, load_secrets, REPOSITORY_ROOT

TABLES = {'categoria': 'id', 'producto': 'id', 'usuario': 'id',
          'pedido': 'id', 'detalle_pedido': 'pedido_id,producto_id'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('before', 'after'), required=True)
    parser.add_argument('--evidence-dir', type=Path,
                        help='Fresh evidence directory for an independent reproduction')
    args = parser.parse_args()
    secret = load_secrets()
    directory = args.evidence_dir or REPOSITORY_ROOT/'docs'/'evidencias'
    target = directory/('conservacion_'+args.phase+'.json')
    if target.exists():
        raise RuntimeError('Existing conservation evidence must not be overwritten')
    evidence = {'phase': args.phase, 'started_at_utc': datetime.now(timezone.utc).isoformat(),
                'method': 'count plus MD5 of ordered, complete row JSON digests; no source rows exported',
                'tables': {}}
    with Connection(secret['bootstrap_user'], application_name='u5_conservation') as db:
        db.execute('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY')
        db.execute("SET LOCAL TimeZone='America/Argentina/Buenos_Aires'")
        db.execute("SET LOCAL DateStyle='ISO,YMD'")
        for table, order in TABLES.items():
            # Table and column names are fixed above, never supplied by the user.
            row = db.execute('SELECT count(*)::text, pg_catalog.md5('
                "pg_catalog.string_agg(pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY "
                +order+')) FROM public.'+table+' AS t').rows[0]
            evidence['tables'][table] = {'rows': int(row[0]), 'ordered_complete_row_md5': row[1]}
        db.execute('COMMIT')
    if args.phase == 'after':
        before = json.loads(target.with_name('conservacion_before.json').read_text(encoding='utf-8'))
        evidence['same_as_before'] = evidence['tables'] == before['tables']
        if not evidence['same_as_before']:
            raise RuntimeError('Business content changed; stop and investigate before packaging')
    evidence['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(evidence, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'phase': args.phase, 'tables_checked': len(TABLES),
                      'same_as_before': evidence.get('same_as_before'), 'source_rows_exported': False}))


if __name__ == '__main__':
    main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\verificar_matriz.py

SHA256 original: e15a36d6151f1c11ff82efbc10ca2671f071333fff49617f3e486fae97b35272
SHA256 saneado: 9df98dd1439816f3b784359fa68c65ed99db7bb0b98dc482e674d2223c3659b0

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Compare real explicit business ACLs with the final Kiro matrix."""
import json
from datetime import datetime, timezone
from libpq_client import Connection, load_secrets, REPOSITORY_ROOT


def main():
    expected = set()
    def add(role, table, privilege, columns=None, schema='public'):
        for column in columns or ['<table>']:
            expected.add((role, schema, table, column, privilege, 'f'))
    for table in ('categoria', 'producto', 'pedido', 'detalle_pedido'):
        add('rol_app_lectura', table, 'SELECT')
    add('rol_app_lectura', 'usuario', 'SELECT', ['id','nombre','apellido','email','telefono','eliminado','created_at'])
    add('rol_app_escritura', 'pedido', 'INSERT', ['usuario_id','fecha','forma_pago'])
    add('rol_app_escritura', 'pedido', 'UPDATE', ['estado','forma_pago','eliminado'])
    add('rol_app_escritura', 'detalle_pedido', 'INSERT', ['pedido_id','producto_id','cantidad','precio_unitario'])
    add('rol_app_escritura', 'detalle_pedido', 'UPDATE', ['cantidad','precio_unitario'])
    add('rol_app_escritura', 'detalle_pedido', 'DELETE')
    add('rol_soporte', 'usuario', 'SELECT', ['id','nombre','apellido','email','telefono','eliminado'])
    add('rol_soporte', 'usuario', 'UPDATE', ['telefono'])
    for table in ('mv_facturacion_categoria_mes','mv_u4_ventas_categoria_dia'):
        add('rol_reportes', table, 'SELECT')
    add('rol_reportes', 'usuario_anon', 'SELECT', schema='datos_anon')
    add('rol_funciones', 'usuario', 'SELECT', ['id','email','contrasena','eliminado'])
    add('rol_funciones', 'usuario', 'UPDATE', ['contrasena'])
    add('rol_funciones', 'detalle_pedido', 'SELECT', ['pedido_id','subtotal'])
    add('rol_funciones', 'pedido', 'SELECT', ['id'])
    add('rol_funciones', 'pedido', 'UPDATE', ['total'])
    add('rol_funciones', 'mv_u4_ventas_categoria_dia', 'MAINTAIN')
    secret = load_secrets()
    with Connection(secret['bootstrap_user'], application_name='u5_exact_acl') as db:
        result = db.execute("""
WITH acl AS (
 SELECT c.relowner,n.nspname,c.relname,'<table>'::text AS columna,
        a.grantee,a.privilege_type,a.is_grantable
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m','S')
 UNION ALL
 SELECT c.relowner,n.nspname,c.relname,t.attname,a.grantee,a.privilege_type,a.is_grantable
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 JOIN pg_catalog.pg_attribute t ON t.attrelid=c.oid
 CROSS JOIN LATERAL pg_catalog.aclexplode(t.attacl) a
 WHERE n.nspname IN ('public','datos_anon') AND t.attnum>0 AND NOT t.attisdropped
)
SELECT CASE WHEN grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(grantee) END,
       nspname,relname,columna,privilege_type,is_grantable
FROM acl WHERE grantee<>relowner ORDER BY 1,2,3,4,5
""")
        actual = set(result.rows)
        memberships = set(db.execute("""
SELECT mbr.rolname,par.rolname,m.admin_option,m.inherit_option,m.set_option
FROM pg_catalog.pg_auth_members m
JOIN pg_catalog.pg_roles mbr ON mbr.oid=m.member
JOIN pg_catalog.pg_roles par ON par.oid=m.roleid
WHERE mbr.rolname IN ('app_web','admin_datos','rol_app_lectura','rol_app_escritura',
 'rol_soporte','rol_reportes','rol_propietario','rol_funciones')
""").rows)
        expected_memberships = {('app_web','rol_app_lectura','f','t','f'),
            ('app_web','rol_app_escritura','f','t','f'),('admin_datos','rol_soporte','f','t','f')}
    evidence = {'fecha_utc': datetime.now(timezone.utc).isoformat(),
        'expected_explicit_business_acl_entries': len(expected),
        'actual_explicit_business_acl_entries': len(actual),
        'missing': sorted(expected-actual), 'unexpected': sorted(actual-expected),
        'missing_memberships': sorted(expected_memberships-memberships),
        'unexpected_memberships': sorted(memberships-expected_memberships),
        'source': 'Final Kiro requirements/design plus documented Codex precision; actual catalog ACLs',
        'note': 'Owner implicit privileges excluded; column ACLs and table ACLs compared separately. No RLS isolation claimed.'}
    evidence['passed'] = not any(evidence[k] for k in ('missing','unexpected','missing_memberships','unexpected_memberships'))
    target = REPOSITORY_ROOT/'docs'/'evidencias'/'a_comparacion_exacta.json'
    target.parent.mkdir(exist_ok=True)
    target.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'exact_acl_matrix_passed': evidence['passed'], 'entries': len(actual),
                      'missing':len(evidence['missing']), 'unexpected':len(evidence['unexpected'])}))
    if not evidence['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

`````


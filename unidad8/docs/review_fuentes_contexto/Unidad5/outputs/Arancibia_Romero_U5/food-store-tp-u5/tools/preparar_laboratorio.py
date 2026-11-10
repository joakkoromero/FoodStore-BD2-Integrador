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

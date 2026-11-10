# tools/reproducir.py parte1/2

Líneas originales1-540 de1054. SHA256 completo11aa1e237fa05e506911e82cef9af1eb211b15ec59144689b035097d741eee3a. Ambas partes juntas contienen toda la fuente.

`````python
#!/usr/bin/env python3
"""
Reproduccion U8. No contiene credenciales ni realiza ventas.

Ejemplo, desde food-store:
python tools/reproducir.py --pg-bin "C:/Program Files/PostgreSQL/17/bin" \
    --database foodstore_u8_arancibia_romero \
    --private-dir "C:/U8-privado/ejecucion-01"

PGHOST, PGPORT, PGUSER y PGPASSWORD o PGPASSFILE se configuran externamente.
El directorio privado debe ser nuevo y estar fuera del proyecto.
No se elimina ni reemplaza una base PostgreSQL o SQLite existente.
"""

import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sqlite3
import subprocess
import sys
import uuid
from datetime import datetime, timezone


SOURCE = "foodstore"
COPY = "foodstore_u8_arancibia_romero"
CATEGORY = "U8-FERIA-Arancibia-Romero"
NAMES = {
    "muzzarella": "U8 - Muzzarella",
    "empanadas": "U8 - Empanadas",
    "fugazzeta": "U8 - Fugazzeta",
    "agua": "U8 - Agua",
}
INITIAL = {
    "U8 - Muzzarella": (900000, 10),
    "U8 - Empanadas": (120000, 4),
    "U8 - Fugazzeta": (800000, 5),
    "U8 - Agua": (150000, 20),
}
HEADER = [
    "producto_id", "nombre", "precio_centavos", "stock",
    "disponible", "eliminado", "capturado_en",
]
TABLES = ("categoria", "producto", "usuario", "pedido", "detalle_pedido")
FIXED_TIME = "2026-01-01T00:00:00Z"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def protect_private_directory(path):
    """Protect before any dump or diagnostic is written (including Windows 3.12)."""
    if os.name != "nt":
        path.chmod(0o700)
        return "POSIX mode 0700"
    identity = subprocess.run(
        ["whoami.exe", "/user", "/fo", "csv", "/nh"],
        capture_output=True, text=True, errors="replace", check=False,
    )
    require(identity.returncode == 0, "No se pudo identificar al usuario local")
    rows = list(csv.reader(identity.stdout.splitlines()))
    require(len(rows) == 1 and len(rows[0]) >= 2, "Identidad Windows no valida")
    sid = rows[0][1]
    require(re.fullmatch(r"S-[0-9-]+", sid) is not None, "SID Windows no valido")
    acl = subprocess.run(
        ["icacls.exe", str(path), "/inheritance:r", "/grant:r",
         "*" + sid + ":(OI)(CI)F", "*S-1-5-18:(OI)(CI)F",
         "*S-1-5-32-544:(OI)(CI)F"],
        capture_output=True, check=False,
    )
    require(acl.returncode == 0, "No se pudo proteger la ACL privada")
    return "Windows ACL: usuario actual, SYSTEM y Administradores; sin herencia"


def statements(text):
    """Respeta comentarios, comillas y sentencias multilinea de SQLite."""
    pending = ""
    for char in text:
        pending += char
        if char == ";" and sqlite3.complete_statement(pending):
            yield pending
            pending = ""
    # Se permite un comentario final, pero no una sentencia sin terminador.
    tail = re.sub(r"--[^\n]*", "", pending).strip()
    require(not tail, "SQL incompleto al final del archivo")


def run_local_script(connection, path, evidence, expected_errors=False):
    records = []
    evidence.append({"archivo_sql": str(path.name), "sentencias": records})
    expected_seen = []
    for sql in statements(path.read_text(encoding="utf-8")):
        marker = re.search(r"EXPECT_ERROR:\s*(SQLITE_[A-Z_]+)", sql)
        require(expected_errors or marker is None,
                "Marcador de error fuera del archivo de pruebas")
        entry = {"sql": sql.strip()}
        records.append(entry)
        try:
            cursor = connection.execute(sql)
        except sqlite3.IntegrityError as exc:
            name = getattr(exc, "sqlite_errorname", "")
            entry["error"] = {"nombre": name, "mensaje": str(exc)}
            require(marker is not None, "Error SQLite no esperado")
            require(name == marker.group(1), "Tipo de error SQLite incorrecto")
            require(connection.in_transaction,
                    "Se esperaba una transaccion abierta para ROLLBACK")
            expected_seen.append(name)
            continue

        require(marker is None, "Una sentencia que debia fallar tuvo exito")
        if cursor.description:
            columns = [column[0] for column in cursor.description]
            rows = [list(row) for row in cursor.fetchall()]
            entry["columnas"] = columns
            entry["filas"] = rows
            for row in rows:
                for column, value in zip(columns, row):
                    if column == "esperado_cero":
                        require(value == 0, "Quedaron filas despues de ROLLBACK")
                    elif column == "esperado_uno":
                        require(value == 1, "Verificacion C1 incorrecta")

    require(not connection.in_transaction, "El script dejo una transaccion abierta")
    if expected_errors:
        require(
            expected_seen == [
                "SQLITE_CONSTRAINT_CHECK",
                "SQLITE_CONSTRAINT_FOREIGNKEY",
            ],
            "No se ejecutaron los dos errores reales C7",
        )


def connect_local(path):
    connection = sqlite3.connect(path, isolation_level=None)
    connection.execute("PRAGMA foreign_keys = ON")
    require(connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1,
            "foreign_keys no esta activo")
    return connection


def import_snapshot(connection, path, local_evidence):
    with path.open("r", encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream)
        require(reader.fieldnames == HEADER, "Cabecera CSV incorrecta")
        rows = []
        names = set()
        ids = set()
        for raw in reader:
            require(None not in raw and all(v is not None for v in raw.values()),
                    "Fila CSV con columnas faltantes o sobrantes")
            for key in ("producto_id", "precio_centavos", "stock"):
                require(re.fullmatch(r"[0-9]+", raw[key]) is not None,
                        "Numero CSV invalido")
            product_id = int(raw["producto_id"])
            price = int(raw["precio_centavos"])
            stock = int(raw["stock"])
            require(0 < product_id <= 2**63 - 1, "ID fuera de rango")
            require(0 <= price <= 2**63 - 1, "Precio fuera de INTEGER64")
            require(0 <= stock <= 2**31 - 1, "Stock fuera de rango")
            require(raw["disponible"] in ("t", "f"), "Disponible no es t/f")
            require(raw["eliminado"] in ("t", "f"), "Eliminado no es t/f")
            captured = raw["capturado_en"]
            require(bool(captured), "Falta capturado_en del servidor")
            parsed = datetime.fromisoformat(captured.replace("Z", "+00:00"))
            require(parsed.tzinfo is not None, "Fecha del servidor sin zona")
            require(product_id not in ids, "ID CSV duplicado")
            require(raw["nombre"] not in names, "Nombre fixture duplicado")
            ids.add(product_id)
            names.add(raw["nombre"])
            rows.append((
                product_id, raw["nombre"], price, stock,
                int(raw["disponible"] == "t"),
                int(raw["eliminado"] == "t"), captured,
            ))

    require(names == set(INITIAL) and len(rows) == 4,
            "El CSV no contiene exactamente el fixture")
    try:
        connection.execute("BEGIN IMMEDIATE")
        # Se reemplaza la instantanea auxiliar, nunca las filas del cache.
        connection.execute("DELETE FROM snapshot_servidor")
        connection.executemany(
            """
            INSERT INTO snapshot_servidor
                (producto_id,nombre,precio_centavos,stock,
                 disponible,eliminado,capturado_en)
            VALUES (?,?,?,?,?,?,?)
            """,
            rows,
        )
        connection.execute(
            """
            INSERT INTO producto_cache
                (producto_id,nombre,precio_centavos,stock_visto,
                 disponible_visto,eliminado,capturado_en)
            SELECT producto_id,nombre,precio_centavos,stock,
                   disponible,eliminado,capturado_en
            FROM snapshot_servidor
            WHERE 1
            ON CONFLICT(producto_id) DO UPDATE SET
                nombre=excluded.nombre,
                precio_centavos=excluded.precio_centavos,
                stock_visto=excluded.stock_visto,
                disponible_visto=excluded.disponible_visto,
                eliminado=excluded.eliminado,
                capturado_en=excluded.capturado_en
            """
        )
        connection.execute("COMMIT")
    except Exception:
        if connection.in_transaction:
            connection.execute("ROLLBACK")
        raise
    local_evidence.append({
        "importacion_csv": path.name,
        "sha256": sha256_file(path),
        "filas": len(rows),
        "fecha_autoridad": "capturado_en recibido de PostgreSQL",
    })


def create_draft(connection, items):
    local_id = str(uuid.uuid4())
    request_id = str(uuid.uuid4())
    try:
        connection.execute("BEGIN IMMEDIATE")
        connection.execute(
            "INSERT INTO pedido_borrador VALUES (?,?,?,?)",
            (local_id, 1, "EFECTIVO", FIXED_TIME),
        )
        for name, quantity in items:
            matches = connection.execute(
                "SELECT producto_id,precio_centavos FROM producto_cache WHERE nombre=?",
                (name,),
            ).fetchall()
            require(len(matches) == 1, "Producto fixture ambiguo o inexistente")
            product_id, price = matches[0]
            connection.execute(
                "INSERT INTO item_borrador VALUES (?,?,?,?)",
                (local_id, product_id, quantity, price),
            )
        connection.execute(
            """
            INSERT INTO cola_sync
                (solicitud_uuid,id_local,estado,motivo,creada_en)
            VALUES (?,?,'PENDIENTE','',?)
            """,
            (request_id, local_id, FIXED_TIME),
        )
        connection.execute("COMMIT")
    except Exception:
        if connection.in_transaction:
            connection.execute("ROLLBACK")
        raise
    return local_id, request_id


def request_row(connection, request_id):
    cursor = connection.execute(
        "SELECT * FROM cola_sync WHERE solicitud_uuid=?", (request_id,)
    )
    row = cursor.fetchone()
    require(row is not None, "Solicitud inexistente")
    return dict(zip([d[0] for d in cursor.description], row))


def simulate(connection, semaforo, request_id, state, fragments, records):
    before = request_row(connection, request_id)
    scripts = []
    run_local_script(connection, semaforo, scripts)
    after = request_row(connection, request_id)
    require(after["estado"] == state, "Estado inesperado del semaforo")
    for fragment in fragments:
        require(fragment in after["motivo"], "Motivo incompleto del semaforo")
    records.append({
        "solicitud_uuid": request_id,
        "antes": before,
        "despues": after,
        "ejecucion": scripts,
        "postgresql_en_esta_funcion": False,
    })
    return after


def expect_integrity(connection, sql, parameters, expected_name, records):
    require(not connection.in_transaction, "Transaccion local previa inesperada")
    connection.execute("BEGIN IMMEDIATE")
    try:
        connection.execute(sql, parameters)
    except sqlite3.IntegrityError as exc:
        name = getattr(exc, "sqlite_errorname", "")
        records.append({
            "sql": sql,
            "parametros": list(parameters),
            "error": name,
            "mensaje": str(exc),
            "rollback_explicito": True,
        })
        require(name == expected_name, "Restriccion incorrecta")
    else:
        raise RuntimeError("Se esperaba un error de integridad")
    finally:
        if connection.in_transaction:
            connection.execute("ROLLBACK")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pg-bin", required=True, type=Path)
    parser.add_argument("--database", required=True)
    parser.add_argument("--private-dir", required=True, type=Path)
    args = parser.parse_args()

    require(sys.version_info >= (3, 12), "Se requiere Python 3.12+")
    require(sqlite3.sqlite_version_info >= (3, 37, 0),
            "Se requiere SQLite 3.37+")
    require(args.database == COPY, "Solo se admite la copia exacta autorizada")

    root = Path(__file__).resolve().parents[1]
    private = args.private_dir.resolve()
    require(not private.is_relative_to(root),
            "--private-dir debe estar fuera del proyecto")
    require(not private.exists(), "--private-dir debe ser un directorio nuevo")

    mobile = root / "movil"
    docs = root / "docs" / "evidencias"
    database_path = mobile / "foodstore_movil.db"
    final_csv = mobile / "servidor_snapshot.csv"
    json_path = docs / "reproduccion_u8.json"
    text_path = docs / "reproduccion_u8.txt"
    protected_outputs = [
        database_path, final_csv, json_path, text_path,
        docs / "snapshot_inicial.csv",
        docs / "snapshot_c2.csv",
        docs / "snapshot_c4.csv",
    ]
    require(not any(path.exists() for path in protected_outputs),
            "Hay salidas previas; no se sobrescriben. Use otra copia del proyecto")

    paths = {
        "schema": mobile / "schema_sqlite.sql",
        "tests": mobile / "pruebas_sqlite.sql",
        "semaforo": mobile / "semaforo.sql",
        "fixture": root / "postgresql" / "10_fixture_y_snapshot.sql",
        "validation": root / "postgresql" / "20_validar_no_ventas.sql",
    }
    require(all(path.is_file() for path in paths.values()),
            "Faltan scripts requeridos")

    executables = {}
    for name in ("psql", "createdb", "pg_dump"):
        suffix = ".exe" if os.name == "nt" else ""
        path = args.pg_bin.resolve() / (name + suffix)
        require(path.is_file(), "No se encontro una herramienta PostgreSQL")
        executables[name] = str(path)

    # No se heredan PGSERVICE, PGDATABASE, PGOPTIONS, PGAPPNAME,
    # PGHOSTADDR, PGTARGETSESSIONATTRS ni otras redirecciones PG.
    allowed_pg = {
        "PGHOST", "PGPORT", "PGUSER", "PGPASSWORD", "PGPASSFILE",
        "PGSSLMODE", "PGSSLROOTCERT", "PGSSLCERT", "PGSSLKEY",
        "PGSSLCRL", "PGSSLCRLDIR", "PGCHANNELBINDING",
        "PGCONNECT_TIMEOUT",
    }
    env = {
        key: value for key, value in os.environ.items()
        if not key.upper().startswith("PG") or key.upper() in allowed_pg
    }
    env["PGCLIENTENCODING"] = "UTF8"
    env.setdefault("PGCONNECT_TIMEOUT", "15")
    require(
        "PGPASSWORD" not in env or "PGPASSFILE" not in env,
        "Configure PGPASSWORD o PGPASSFILE, no ambos",
    )

    private.mkdir(parents=True, mode=0o700)
    private_protection = protect_private_directory(private)
    docs.mkdir(parents=True, exist_ok=True)
    evidence = {
        "inicio_utc": datetime.now(timezone.utc).isoformat(),
        "estado": "EN_CURSO",
        "proteccion_directorio_privado": private_protection,
        "advertencias": [
            "SIMULADO_APROBADO no es una venta.",
            "Aceptacion de precio es una accion sintetica de laboratorio, no humana.",
            "La hora local es diagnostica; no decide autoridad ni vigencia.",
            "Tras restaurar servidor se invalidan todas las caches e instantaneas "
            "y se reconcilian UUID y colas antes de reenviar.",
            "El dump y los diagnosticos privados no deben incluirse en el ZIP.",
        ],
        "scripts_sha256": {
            str(path.relative_to(root)): sha256_file(path)
            for path in paths.values()
        },
        "comandos": [],
        "local": [],
        "casos": {},
    }
    diagnostic_index = 0
    connection = None

    def command(tool, arguments, label, input_text=None):
        nonlocal diagnostic_index
        argv = [executables[tool], *arguments]
        completed = subprocess.run(
            argv, input=input_text, text=True, encoding="utf-8",
            errors="strict", stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            env=env, check=False,
        )
        diagnostic_index += 1
        # Las salidas completas quedan exclusivamente fuera del proyecto.
        # No se guardan variables de entorno ni argumentos de conexion secretos.
        (private / f"{diagnostic_index:03d}_stdout.txt").write_text(
            completed.stdout, encoding="utf-8"
        )
        (private / f"{diagnostic_index:03d}_stderr.txt").write_text(
            completed.stderr, encoding="utf-8"
        )
        evidence["comandos"].append({
            "operacion": label,
            "herramienta": tool,
            "codigo_salida": completed.returncode,
        })
        require(completed.returncode == 0,
                "Fallo una herramienta PostgreSQL; revise diagnosticos privados")
        return completed.stdout

    def pg(database, sql, label):
        return command(
            "psql",
            ["-X", "-w", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
             "--dbname", database],
            label,
            sql,
        )

    def pg_file(database, path, label):
        return pg(database, path.read_text(encoding="utf-8"), label)

    def fingerprints():
        result = {}
        for table in TABLES:
            # Se serializan filas solo dentro de PostgreSQL.
            # Al cliente vuelven conteo, bytes y una huella agregada.
            sql = f"""
            BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
            SET LOCAL TIME ZONE 'UTC';
            SET LOCAL DateStyle = 'ISO, YMD';
            WITH serializadas AS (
                SELECT row_to_json(t)::text AS contenido
                FROM public.{table} AS t
            ),
            hashes AS (
                SELECT
                    octet_length(convert_to(contenido, 'UTF8')) AS bytes,
                    encode(
                        sha256(convert_to(contenido, 'UTF8')), 'hex'
                    ) AS hash_fila
                FROM serializadas
            )
            SELECT json_build_object(
                'filas', count(*),
                'bytes', coalesce(sum(bytes), 0),
                'sha256', encode(
                    sha256(convert_to(
                        coalesce(string_agg(hash_fila, '' ORDER BY hash_fila), ''),
                        'UTF8'
                    )),
                    'hex'
                )
            )::text
            FROM hashes;
            COMMIT;
            """
            result[table] = json.loads(
                pg(SOURCE, sql, "huella agregada fuente: " + table)
            )
        return result

    def validate_copy(label):
        result = json.loads(pg_file(COPY, paths["validation"], label))
        require(result["productos_fixture"] == 4, "Fixture incompleto en copia")
        return result

    def export_snapshot(filename):
        sql = (
            "\\copy (SELECT producto_id,nombre,precio_centavos,stock,"
            "disponible,eliminado,capturado_en "
            "FROM public.v_snapshot_movil ORDER BY producto_id) "
            "TO STDOUT WITH (FORMAT CSV, HEADER true, ENCODING 'UTF8')\n"
        )
        text = pg(COPY, sql, "exportacion CSV " + filename)
        # Se valida antes de persistir o importar.
        reader = csv.reader(io.StringIO(text))
        require(next(reader, None) == HEADER, "Exportacion CSV invalida")
        require(len(list(reader)) == 4, "Exportacion no limitada al fixture")
        path = docs / filename
        with path.open("x", encoding="utf-8", newline="") as stream:
            stream.write(text)
        evidence.setdefault("snapshots", []).append({
            "archivo": str(path.relative_to(root)),
            "sha256": sha256_file(path),
            "bytes": path.stat().st_size,
            "comando": sql.strip(),
        })
        return path

    def administrative_change(kind):
        if kind == "C2":
            name = NAMES["muzzarella"]
            set_clause = "precio = precio + 100.00::numeric"
            expected = "(p.precio * 100)::bigint = 910000 AND NOT p.eliminado"
        else:
            require(kind == "C4", "Preparacion administrativa desconocida")
            name = NAMES["agua"]
            set_clause = "eliminado = true"
            expected = "p.eliminado"
        # Los nombres son constantes del programa, no entrada CLI.
        sql = f"""
        BEGIN;
        DO $admin$
        DECLARE
            afectados integer;
        BEGIN

`````

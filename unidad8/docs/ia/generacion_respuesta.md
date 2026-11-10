### FILE: movil/schema_sqlite.sql
```sql
PRAGMA foreign_keys = ON;

BEGIN;

CREATE TABLE producto_cache (
    producto_id INTEGER PRIMARY KEY CHECK (producto_id > 0),
    nombre TEXT NOT NULL CHECK (length(trim(nombre)) > 0),
    precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
    stock_visto INTEGER NOT NULL CHECK (stock_visto >= 0),
    disponible_visto INTEGER NOT NULL CHECK (disponible_visto IN (0, 1)),
    eliminado INTEGER NOT NULL CHECK (eliminado IN (0, 1)),
    capturado_en TEXT NOT NULL CHECK (length(capturado_en) > 0)
) STRICT;

CREATE TABLE pedido_borrador (
    id_local TEXT PRIMARY KEY NOT NULL CHECK (
        length(id_local) = 36
        AND substr(id_local, 9, 1) = '-'
        AND substr(id_local, 14, 1) = '-'
        AND substr(id_local, 19, 1) = '-'
        AND substr(id_local, 24, 1) = '-'
        AND length(replace(id_local, '-', '')) = 32
        AND replace(id_local, '-', '') NOT GLOB '*[^0-9a-fA-F]*'
    ),
    usuario_id_servidor INTEGER NOT NULL CHECK (usuario_id_servidor > 0),
    forma_pago TEXT NOT NULL CHECK (
        forma_pago IN ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA')
    ),
    creado_en TEXT NOT NULL CHECK (length(creado_en) > 0)
) STRICT;

CREATE TABLE item_borrador (
    id_local TEXT NOT NULL REFERENCES pedido_borrador(id_local),
    producto_id INTEGER NOT NULL REFERENCES producto_cache(producto_id),
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_centavos_visto INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),
    PRIMARY KEY (id_local, producto_id)
) STRICT;

CREATE TABLE cola_sync (
    solicitud_uuid TEXT PRIMARY KEY NOT NULL CHECK (
        length(solicitud_uuid) = 36
        AND substr(solicitud_uuid, 9, 1) = '-'
        AND substr(solicitud_uuid, 14, 1) = '-'
        AND substr(solicitud_uuid, 19, 1) = '-'
        AND substr(solicitud_uuid, 24, 1) = '-'
        AND length(replace(solicitud_uuid, '-', '')) = 32
        AND replace(solicitud_uuid, '-', '') NOT GLOB '*[^0-9a-fA-F]*'
    ),
    id_local TEXT NOT NULL REFERENCES pedido_borrador(id_local),
    estado TEXT NOT NULL CHECK (
        estado IN ('PENDIENTE', 'CONFLICTO', 'RECHAZADO', 'SIMULADO_APROBADO')
    ),
    motivo TEXT NOT NULL DEFAULT '',
    creada_en TEXT NOT NULL CHECK (length(creada_en) > 0),
    evaluado_en TEXT
) STRICT;

CREATE UNIQUE INDEX uq_cola_sync_pendiente
    ON cola_sync(id_local)
    WHERE estado = 'PENDIENTE';

-- Auxiliar no STRICT. El importador valida el CSV y normaliza t/f a 1/0.
CREATE TABLE snapshot_servidor (
    producto_id INTEGER PRIMARY KEY CHECK (producto_id > 0),
    nombre TEXT NOT NULL,
    precio_centavos INTEGER NOT NULL CHECK (
        typeof(precio_centavos) = 'integer' AND precio_centavos >= 0
    ),
    stock INTEGER NOT NULL CHECK (typeof(stock) = 'integer' AND stock >= 0),
    disponible INTEGER NOT NULL CHECK (
        typeof(disponible) = 'integer' AND disponible IN (0, 1)
    ),
    eliminado INTEGER NOT NULL CHECK (
        typeof(eliminado) = 'integer' AND eliminado IN (0, 1)
    ),
    capturado_en TEXT NOT NULL CHECK (length(capturado_en) > 0)
);

CREATE VIEW v_catalogo_disponible AS
SELECT producto_id, nombre, precio_centavos, stock_visto, capturado_en
FROM producto_cache
WHERE eliminado = 0
  AND disponible_visto = 1
  AND stock_visto > 0;

COMMIT;
```

### FILE: movil/pruebas_sqlite.sql
```sql
-- Ejecutar sentencia por sentencia, conservando la conexion.
-- Los marcadores EXPECT_ERROR corresponden a la sentencia que los contiene.
-- Despues de cada error esperado se ejecuta el ROLLBACK siguiente.
-- No ejecutar este archivo mediante executescript().

-- C1: consulta exclusivamente local, sin conexion PostgreSQL.
SELECT producto_id, nombre, precio_centavos, stock_visto, capturado_en
FROM v_catalogo_disponible
ORDER BY producto_id;

-- C1-COMMIT: encabezado, dos items y solicitud en una sola transaccion.
BEGIN;

INSERT INTO pedido_borrador
    (id_local, usuario_id_servidor, forma_pago, creado_en)
VALUES
    ('10000000-0000-4000-8000-000000000001', 1, 'EFECTIVO',
     '2026-01-01T00:00:00Z');

INSERT INTO item_borrador
    (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT '10000000-0000-4000-8000-000000000001',
       producto_id, 1, precio_centavos
FROM producto_cache
WHERE nombre IN ('U8 - Muzzarella', 'U8 - Empanadas');

INSERT INTO cola_sync
    (solicitud_uuid, id_local, estado, motivo, creada_en)
VALUES
    ('20000000-0000-4000-8000-000000000001',
     '10000000-0000-4000-8000-000000000001',
     'PENDIENTE', '', '2026-01-01T00:00:00Z');

COMMIT;

SELECT
    (SELECT count(*) FROM pedido_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000001') AS esperado_uno,
    (SELECT count(*) = 2 FROM item_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000001') AS esperado_uno,
    (SELECT count(*) FROM cola_sync
     WHERE solicitud_uuid = '20000000-0000-4000-8000-000000000001'
       AND estado = 'PENDIENTE') AS esperado_uno;

-- C1-ROLLBACK: las mismas cuatro clases de escritura quedan revertidas.
BEGIN;

INSERT INTO pedido_borrador
    (id_local, usuario_id_servidor, forma_pago, creado_en)
VALUES
    ('10000000-0000-4000-8000-000000000002', 1, 'TARJETA',
     '2026-01-01T00:00:00Z');

INSERT INTO item_borrador
    (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT '10000000-0000-4000-8000-000000000002',
       producto_id, 1, precio_centavos
FROM producto_cache
WHERE nombre IN ('U8 - Muzzarella', 'U8 - Empanadas');

INSERT INTO cola_sync
    (solicitud_uuid, id_local, estado, motivo, creada_en)
VALUES
    ('20000000-0000-4000-8000-000000000002',
     '10000000-0000-4000-8000-000000000002',
     'PENDIENTE', '', '2026-01-01T00:00:00Z');

ROLLBACK;

SELECT
    (SELECT count(*) FROM pedido_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000002') AS esperado_cero,
    (SELECT count(*) FROM item_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000002') AS esperado_cero,
    (SELECT count(*) FROM cola_sync
     WHERE id_local = '10000000-0000-4000-8000-000000000002') AS esperado_cero;

-- C7-cantidad: debe fallar CHECK; no basta con revertir solo el INSERT.
BEGIN;

INSERT INTO pedido_borrador
    (id_local, usuario_id_servidor, forma_pago, creado_en)
VALUES
    ('10000000-0000-4000-8000-000000000007', 1, 'EFECTIVO',
     '2026-01-01T00:00:00Z');

-- EXPECT_ERROR: SQLITE_CONSTRAINT_CHECK
INSERT INTO item_borrador
    (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT '10000000-0000-4000-8000-000000000007',
       producto_id, 0, precio_centavos
FROM producto_cache
WHERE nombre = 'U8 - Muzzarella';

ROLLBACK;

SELECT
    (SELECT count(*) FROM pedido_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000007') AS esperado_cero,
    (SELECT count(*) FROM item_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000007') AS esperado_cero,
    (SELECT count(*) FROM cola_sync
     WHERE id_local = '10000000-0000-4000-8000-000000000007') AS esperado_cero;

-- C7-fk: -1 no puede existir en producto_cache por su CHECK producto_id > 0.
BEGIN;

INSERT INTO pedido_borrador
    (id_local, usuario_id_servidor, forma_pago, creado_en)
VALUES
    ('10000000-0000-4000-8000-000000000008', 1, 'TRANSFERENCIA',
     '2026-01-01T00:00:00Z');

-- EXPECT_ERROR: SQLITE_CONSTRAINT_FOREIGNKEY
INSERT INTO item_borrador
    (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES
    ('10000000-0000-4000-8000-000000000008', -1, 1, 900000);

ROLLBACK;

SELECT
    (SELECT count(*) FROM pedido_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000008') AS esperado_cero,
    (SELECT count(*) FROM item_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000008') AS esperado_cero,
    (SELECT count(*) FROM cola_sync
     WHERE id_local = '10000000-0000-4000-8000-000000000008') AS esperado_cero;
```

### FILE: movil/semaforo.sql
```sql
PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

-- Solo se consultan tablas SQLite. La fecha local es diagnostica,
-- nunca determina vigencia, disponibilidad ni autoridad del snapshot.
WITH
evaluacion_item AS (
    SELECT
        i.id_local,
        i.producto_id,
        CASE
            WHEN s.producto_id IS NULL THEN
                printf('producto_id=%lld ausente de snapshot_servidor',
                       i.producto_id)
            WHEN s.eliminado = 1 THEN
                printf('producto_id=%lld dado de baja', i.producto_id)
            WHEN s.stock = 0 THEN
                printf('producto_id=%lld sin stock: solicitado=%lld disponible=0',
                       i.producto_id, i.cantidad)
            WHEN i.cantidad > s.stock THEN
                printf(
                    'producto_id=%lld stock insuficiente: solicitado=%lld disponible=%lld',
                    i.producto_id, i.cantidad, s.stock
                )
            WHEN s.disponible <> 1 THEN
                printf('producto_id=%lld no disponible en snapshot_servidor',
                       i.producto_id)
            ELSE NULL
        END AS rojo,
        CASE
            WHEN s.producto_id IS NOT NULL
             AND i.precio_centavos_visto <> s.precio_centavos THEN
                printf(
                    'producto_id=%lld precio distinto: visto=%lld servidor=%lld centavos',
                    i.producto_id,
                    i.precio_centavos_visto,
                    s.precio_centavos
                )
            ELSE NULL
        END AS amarillo
    FROM item_borrador AS i
    LEFT JOIN snapshot_servidor AS s
        ON s.producto_id = i.producto_id
),
resumen AS (
    SELECT
        b.id_local,
        count(e.producto_id) AS cantidad_items,
        count(e.rojo) AS rojos,
        count(e.amarillo) AS amarillos,
        group_concat(e.rojo, '; ') AS motivos_rojos,
        group_concat(e.amarillo, '; ') AS motivos_amarillos
    FROM pedido_borrador AS b
    LEFT JOIN evaluacion_item AS e ON e.id_local = b.id_local
    GROUP BY b.id_local
),
resultado AS (
    SELECT
        id_local,
        CASE
            WHEN cantidad_items = 0 OR rojos > 0 THEN 'RECHAZADO'
            WHEN amarillos > 0 THEN 'CONFLICTO'
            ELSE 'SIMULADO_APROBADO'
        END AS estado,
        CASE
            WHEN cantidad_items = 0 THEN 'borrador vacio'
            WHEN rojos > 0 THEN motivos_rojos
            WHEN amarillos > 0 THEN motivos_amarillos
            ELSE 'Sin conflictos en snapshot; simulacion local, no es una venta'
        END AS motivo
    FROM resumen
)
UPDATE cola_sync
SET estado = (
        SELECT r.estado FROM resultado AS r
        WHERE r.id_local = cola_sync.id_local
    ),
    motivo = (
        SELECT r.motivo FROM resultado AS r
        WHERE r.id_local = cola_sync.id_local
    ),
    evaluado_en = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE estado = 'PENDIENTE';

COMMIT;
```

### FILE: postgresql/10_fixture_y_snapshot.sql
```sql
\set ON_ERROR_STOP on

BEGIN;

DO $guard$
BEGIN
    IF current_database() <> 'foodstore_u8_arancibia_romero' THEN
        RAISE EXCEPTION
            'Destino incorrecto: se requiere foodstore_u8_arancibia_romero';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.categoria
        WHERE nombre = 'U8-FERIA-Arancibia-Romero'
    ) OR EXISTS (
        SELECT 1 FROM public.producto
        WHERE nombre IN (
            'U8 - Muzzarella', 'U8 - Empanadas',
            'U8 - Fugazzeta', 'U8 - Agua'
        )
    ) THEN
        RAISE EXCEPTION
            'Fixture o nombres ya existentes; se aborta sin modificar filas previas';
    END IF;

    IF to_regclass('public.v_snapshot_movil') IS NOT NULL THEN
        RAISE EXCEPTION
            'public.v_snapshot_movil ya existe; no se reemplaza';
    END IF;
END
$guard$;

INSERT INTO public.categoria (nombre, descripcion, eliminado)
VALUES (
    'U8-FERIA-Arancibia-Romero',
    'Fixture ficticio de laboratorio U8; no representa ventas',
    false
);

INSERT INTO public.producto
    (nombre, descripcion, precio, stock, categoria_id, eliminado)
SELECT
    f.nombre,
    'Producto ficticio del fixture U8',
    f.precio,
    f.stock,
    c.id,
    false
FROM public.categoria AS c
CROSS JOIN (
    VALUES
        ('U8 - Muzzarella', 9000.00::numeric(12,2), 10),
        ('U8 - Empanadas', 1200.00::numeric(12,2), 4),
        ('U8 - Fugazzeta', 8000.00::numeric(12,2), 5),
        ('U8 - Agua', 1500.00::numeric(12,2), 20)
) AS f(nombre, precio, stock)
WHERE c.nombre = 'U8-FERIA-Arancibia-Romero';

CREATE VIEW public.v_snapshot_movil AS
SELECT
    p.id AS producto_id,
    p.nombre,
    (p.precio * 100)::bigint AS precio_centavos,
    p.stock,
    (p.stock > 0) AS disponible,
    (p.eliminado OR c.eliminado) AS eliminado,
    now() AS capturado_en
FROM public.producto AS p
JOIN public.categoria AS c ON c.id = p.categoria_id
WHERE c.nombre = 'U8-FERIA-Arancibia-Romero'
  AND p.nombre IN (
      'U8 - Muzzarella', 'U8 - Empanadas',
      'U8 - Fugazzeta', 'U8 - Agua'
  );

DO $verify$
BEGIN
    IF (SELECT count(*) FROM public.v_snapshot_movil) <> 4 THEN
        RAISE EXCEPTION 'Se esperaban exactamente cuatro productos fixture';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.v_snapshot_movil
        WHERE precio_centavos IS NULL
           OR stock IS NULL
           OR disponible IS NULL
           OR eliminado IS NULL
    ) THEN
        RAISE EXCEPTION 'Fixture con valores nulos no exportables';
    END IF;
END
$verify$;

COMMIT;

SELECT *
FROM public.v_snapshot_movil
ORDER BY producto_id;
```

### FILE: postgresql/20_validar_no_ventas.sql
```sql
\set ON_ERROR_STOP on

BEGIN READ ONLY;

SET LOCAL TIME ZONE 'UTC';
SET LOCAL DateStyle = 'ISO, YMD';

DO $guard$
BEGIN
    IF current_database() <> 'foodstore_u8_arancibia_romero' THEN
        RAISE EXCEPTION
            'Validacion de copia: se requiere foodstore_u8_arancibia_romero';
    END IF;
END
$guard$;

-- Este archivo solo lee. El runner conserva y compara estos resultados.
-- Precio C2 y baja C4 son preparaciones administrativas en la copia.
-- No se permite que el semaforo cree pedidos ni modifique stock.
-- La huella de productos completos cambia deliberadamente por C2/C4.
-- La huella estructural sin precio/eliminado y el stock deben permanecer iguales.

WITH
fixture AS (
    SELECT
        p.id AS producto_id,
        p.nombre,
        p.precio,
        p.stock,
        p.categoria_id,
        p.eliminado,
        p.created_at,
        p.descripcion
    FROM public.producto AS p
    JOIN public.categoria AS c ON c.id = p.categoria_id
    WHERE c.nombre = 'U8-FERIA-Arancibia-Romero'
      AND p.nombre IN (
          'U8 - Muzzarella', 'U8 - Empanadas',
          'U8 - Fugazzeta', 'U8 - Agua'
      )
),
huellas AS (
    SELECT
        producto_id,
        encode(
            sha256(convert_to(row_to_json(f)::text, 'UTF8')),
            'hex'
        ) AS completa,
        encode(
            sha256(convert_to(
                json_build_array(
                    producto_id, nombre, stock, categoria_id,
                    created_at, descripcion
                )::text,
                'UTF8'
            )),
            'hex'
        ) AS estable
    FROM fixture AS f
)
SELECT json_build_object(
    'base', current_database(),
    'pedidos', (SELECT count(*) FROM public.pedido),
    'productos_fixture', (SELECT count(*) FROM fixture),
    'suma_stock', (SELECT sum(stock::bigint) FROM fixture),
    'vector_stock', (
        SELECT json_agg(
            json_build_object('producto_id', producto_id, 'stock', stock)
            ORDER BY producto_id
        )
        FROM fixture
    ),
    'estado_administrativo', (
        SELECT json_agg(
            json_build_object(
                'producto_id', producto_id,
                'precio_centavos', (precio * 100)::bigint,
                'eliminado', eliminado
            )
            ORDER BY producto_id
        )
        FROM fixture
    ),
    'huella_producto_completa', (
        SELECT encode(
            sha256(convert_to(
                coalesce(string_agg(completa, '' ORDER BY producto_id), ''),
                'UTF8'
            )),
            'hex'
        )
        FROM huellas
    ),
    'huella_producto_sin_precio_ni_baja', (
        SELECT encode(
            sha256(convert_to(
                coalesce(string_agg(estable, '' ORDER BY producto_id), ''),
                'UTF8'
            )),
            'hex'
        )
        FROM huellas
    )
)::text;

COMMIT;
```

### FILE: tools/reproducir.py
```python
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
    docs.mkdir(parents=True, exist_ok=True)
    evidence = {
        "inicio_utc": datetime.now(timezone.utc).isoformat(),
        "estado": "EN_CURSO",
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
            IF current_database() <> '{COPY}' THEN
                RAISE EXCEPTION 'Copia incorrecta';
            END IF;
            UPDATE public.producto AS p
            SET {set_clause}
            FROM public.categoria AS c
            WHERE p.categoria_id = c.id
              AND c.nombre = '{CATEGORY}'
              AND p.nombre = '{name}';
            GET DIAGNOSTICS afectados = ROW_COUNT;
            IF afectados <> 1 THEN
                RAISE EXCEPTION 'Se esperaba modificar un producto fixture';
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM public.producto p
                JOIN public.categoria c ON c.id = p.categoria_id
                WHERE c.nombre = '{CATEGORY}'
                  AND p.nombre = '{name}'
                  AND {expected}
            ) THEN
                RAISE EXCEPTION 'Preparacion administrativa incorrecta';
            END IF;
        END
        $admin$;
        COMMIT;
        """
        pg(COPY, sql, "preparacion administrativa explicita " + kind)
        evidence.setdefault("preparaciones_administrativas", []).append({
            "caso": kind,
            "sql": sql.strip(),
            "origen": "runner administrativo, nunca semaforo.sql",
        })

    def save_evidence():
        evidence["fin_utc"] = datetime.now(timezone.utc).isoformat()
        encoded = json.dumps(evidence, ensure_ascii=True, indent=2)
        json_path.write_text(encoded + "\n", encoding="utf-8")
        # El TXT conserva tambien comandos SQL, estados y motivos completos.
        text_path.write_text(
            "U8 - Evidencia real de reproduccion\n"
            "SIMULADO_APROBADO NO ES UNA VENTA\n"
            "No contiene credenciales ni filas de usuarios.\n\n"
            + encoded + "\n",
            encoding="utf-8",
        )

    try:
        versions = {}
        for tool in executables:
            output = command(tool, ["--version"], "version " + tool).strip()
            match = re.search(r"\b(\d+)\.(\d+)", output)
            require(match is not None and int(match.group(1)) == 17,
                    "Se requieren herramientas cliente PostgreSQL 17")
            versions[tool] = output
        server_version = int(pg(
            SOURCE, "SHOW server_version_num;", "version servidor"
        ).strip())
        require(server_version == 170011, "Se requiere PostgreSQL 17.11")
        versions["server_version_num"] = server_version
        versions["python"] = sys.version.split()[0]
        versions["sqlite"] = sqlite3.sqlite_version
        evidence["versiones"] = versions

        exists = pg(
            SOURCE,
            f"SELECT count(*) FROM pg_database WHERE datname = '{COPY}';",
            "verificar ausencia de destino",
        ).strip()
        require(exists == "0",
                "La base destino ya existe; se aborta sin reemplazarla")

        evidence["fuente_antes"] = fingerprints()

        command(
            "createdb",
            ["-w", "--maintenance-db", SOURCE, "--template", SOURCE, COPY],
            "crear copia nueva desde template foodstore",
        )
        evidence["copia_creada"] = COPY

        dump_path = private / "copia_antes_fixture.dump"
        command(
            "pg_dump",
            ["-w", "--format=custom", "--file", str(dump_path),
             "--dbname", COPY],
            "respaldo privado custom antes de preparar fixture",
        )
        require(dump_path.is_file() and dump_path.stat().st_size > 0,
                "Respaldo vacio o inexistente")
        evidence["respaldo_privado"] = {
            "formato": "custom",
            "bytes": dump_path.stat().st_size,
            "sha256": sha256_file(dump_path),
            "incluido_en_entregables": False,
        }

        # La copia anterior al fixture debe tener las mismas cardinalidades.
        copy_counts = {}
        for table in TABLES:
            copy_counts[table] = int(pg(
                COPY, f"SELECT count(*) FROM public.{table};",
                "conteo copia previa: " + table,
            ).strip())
            require(
                copy_counts[table] == evidence["fuente_antes"][table]["filas"],
                "La copia previa no coincide en cantidad de filas con la fuente",
            )
        evidence["conteos_copia_previa"] = copy_counts

        pg_file(COPY, paths["fixture"], "preparar fixture y vista limitada")
        baseline = validate_copy("baseline copia despues del fixture")
        evidence["copia_baseline"] = baseline
        initial_csv = export_snapshot("snapshot_inicial.csv")

        # Reserva exclusiva: sqlite3.connect no debe reutilizar otra base.
        with database_path.open("xb"):
            pass
        connection = connect_local(database_path)
        run_local_script(connection, paths["schema"], evidence["local"])

        schema_check = {
            "foreign_keys": connection.execute(
                "PRAGMA foreign_keys"
            ).fetchone()[0],
            "integrity_check": connection.execute(
                "PRAGMA integrity_check"
            ).fetchone()[0],
            "tablas": connection.execute(
                """
                SELECT name FROM sqlite_schema
                WHERE type='table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
                """
            ).fetchall(),
            "indice": connection.execute(
                "SELECT sql FROM sqlite_schema WHERE name='uq_cola_sync_pendiente'"
            ).fetchone()[0],
        }
        require(schema_check["integrity_check"] == "ok", "Esquema corrupto")
        require(len(schema_check["tablas"]) == 5, "Se esperaban cinco tablas")
        evidence["esquema"] = schema_check

        import_snapshot(connection, initial_csv, evidence["local"])
        for name, (price, stock) in INITIAL.items():
            row = connection.execute(
                """
                SELECT precio_centavos,stock_visto,eliminado
                FROM producto_cache WHERE nombre=?
                """,
                (name,),
            ).fetchone()
            require(row == (price, stock, 0), "Fixture inicial inesperado")

        # C1 y C7: se ejecutan las sentencias literales del archivo entregado.
        command_count = len(evidence["comandos"])
        run_local_script(
            connection, paths["tests"], evidence["local"], expected_errors=True
        )
        require(len(evidence["comandos"]) == command_count,
                "C1/C7 no deben invocar PostgreSQL")
        evidence["casos"]["C1_C7"] = {
            "archivo_ejecutado": "movil/pruebas_sqlite.sql",
            "comandos_postgresql_durante_prueba": 0,
            "resultado": "aserciones SQL verificadas y errores CHECK/FK reales",
        }

        # Preparar todos estos borradores con el snapshot inicial.
        c2_local, c2_request = create_draft(
            connection, [(NAMES["muzzarella"], 1)]
        )
        _, c3_request = create_draft(
            connection, [(NAMES["empanadas"], 5)]
        )
        _, c4_request = create_draft(
            connection, [(NAMES["agua"], 1)]
        )
        _, c5_request = create_draft(
            connection, [(NAMES["fugazzeta"], 1)]
        )
        _, mixed_request = create_draft(
            connection,
            [(NAMES["agua"], 1), (NAMES["muzzarella"], 1)],
        )
        _, empty_request = create_draft(connection, [])

        # Administracion PostgreSQL separada de la evaluacion SQLite.
        administrative_change("C2")
        c2_csv = export_snapshot("snapshot_c2.csv")
        administrative_change("C4")
        c4_csv = export_snapshot("snapshot_c4.csv")

        # Se conserva y prueba tambien la instantanea intermedia C2.
        import_snapshot(connection, c2_csv, evidence["local"])
        require(connection.execute(
            "SELECT precio_centavos FROM producto_cache WHERE nombre=?",
            (NAMES["muzzarella"],),
        ).fetchone()[0] == 910000, "No se importo el precio C2")
        import_snapshot(connection, c4_csv, evidence["local"])
        with final_csv.open("xb") as stream:
            stream.write(c4_csv.read_bytes())

        # Desde aqui hasta finalizar los casos no se invoca herramienta PG.
        local_phase_commands = len(evidence["comandos"])
        cases = evidence["casos"]
        for label in ("C2", "C3", "C4", "C5", "C6", "bordes"):
            cases[label] = []

        simulate(
            connection, paths["semaforo"], c3_request, "RECHAZADO",
            ["stock insuficiente", "solicitado=5", "disponible=4"], cases["C3"]
        )
        simulate(
            connection, paths["semaforo"], c4_request, "RECHAZADO",
            ["dado de baja"], cases["C4"]
        )
        water_id = connection.execute(
            "SELECT producto_id FROM producto_cache WHERE nombre=?",
            (NAMES["agua"],),
        ).fetchone()[0]
        require(connection.execute(
            "SELECT eliminado FROM producto_cache WHERE producto_id=?",
            (water_id,),
        ).fetchone()[0] == 1, "La lapida no permanece en cache")
        require(connection.execute(
            "SELECT count(*) FROM v_catalogo_disponible WHERE producto_id=?",
            (water_id,),
        ).fetchone()[0] == 0, "La vista no oculta la lapida")
        cases["C4"].append({
            "producto_id": water_id,
            "lapida_en_cache": True,
            "visible_en_catalogo": False,
        })

        simulate(
            connection, paths["semaforo"], c5_request, "SIMULADO_APROBADO",
            ["no es una venta"], cases["C5"]
        )
        c2_original = simulate(
            connection, paths["semaforo"], c2_request, "CONFLICTO",
            ["visto=900000", "servidor=910000"], cases["C2"]
        )

        # Aceptacion sintetica de laboratorio: no declara consentimiento humano.
        accepted_request = str(uuid.uuid4())
        try:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute(
                """
                UPDATE item_borrador
                SET precio_centavos_visto = (
                    SELECT s.precio_centavos FROM snapshot_servidor s
                    WHERE s.producto_id = item_borrador.producto_id
                )
                WHERE id_local = ?
                """,
                (c2_local,),
            )
            connection.execute(
                """
                INSERT INTO cola_sync
                    (solicitud_uuid,id_local,estado,motivo,creada_en)
                VALUES (?,?,'PENDIENTE','',?)
                """,
                (accepted_request, c2_local, FIXED_TIME),
            )
            connection.execute("COMMIT")
        except Exception:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            raise

        simulate(
            connection, paths["semaforo"], accepted_request,
            "SIMULADO_APROBADO", ["no es una venta"], cases["C2"]
        )
        require(request_row(connection, c2_request) == c2_original,
                "Se altero el conflicto historico C2")
        cases["C2"].append({
            "aceptacion": "sintetica de laboratorio, no aprobacion humana",
            "precio_centavos_visto": connection.execute(
                "SELECT precio_centavos_visto FROM item_borrador WHERE id_local=?",
                (c2_local,),
            ).fetchone()[0],
            "uuid_anterior": c2_request,
            "uuid_nuevo": accepted_request,
        })
        require(connection.execute(
            "SELECT count(*) FROM cola_sync WHERE id_local=?", (c2_local,)
        ).fetchone()[0] == 2, "No se conservaron dos solicitudes historicas")

        # C6-PK: el mismo UUID falla por la PRIMARY KEY real.
        expect_integrity(
            connection,
            """
            INSERT INTO cola_sync
                (solicitud_uuid,id_local,estado,motivo,creada_en)
            VALUES (?,?,'PENDIENTE','duplicado',?)
            """,
            (c2_request, c2_local, FIXED_TIME),
            "SQLITE_CONSTRAINT_PRIMARYKEY", cases["C6"],
        )
        require(request_row(connection, c2_request) == c2_original,
                "INSERT duplicado altero C2")

        # C6-semaforo: ninguna fila historica debe cambiar, ni su timestamp.
        historical_before = connection.execute(
            "SELECT * FROM cola_sync ORDER BY solicitud_uuid"
        ).fetchall()
        run_local_script(connection, paths["semaforo"], evidence["local"])
        historical_after = connection.execute(
            "SELECT * FROM cola_sync ORDER BY solicitud_uuid"
        ).fetchall()
        require(historical_before == historical_after,
                "La repeticion reevaluo filas historicas")
        cases["C6"].append({
            "reejecucion_historica_identica": True,
            "incluye_estado_motivo_y_evaluado_en": True,
        })

        # C6-historico: otro CONFLICTO del mismo borrador es legal.
        historical_request = str(uuid.uuid4())
        connection.execute(
            """
            INSERT INTO cola_sync
                (solicitud_uuid,id_local,estado,motivo,creada_en)
            VALUES (?,?,'CONFLICTO','Entrada historica sintetica C6',?)
            """,
            (historical_request, c2_local, FIXED_TIME),
        )
        require(connection.execute(
            "SELECT count(*) FROM cola_sync WHERE id_local=? AND estado='CONFLICTO'",
            (c2_local,),
        ).fetchone()[0] == 2, "Se impuso unicidad global de id_local")
        cases["C6"].append({
            "historico_adicional": request_row(connection, historical_request)
        })

        # Una segunda PENDIENTE falla por el indice parcial.
        pending_local, pending_request = create_draft(
            connection, [(NAMES["fugazzeta"], 1)]
        )
        pending_before = request_row(connection, pending_request)
        expect_integrity(
            connection,
            """
            INSERT INTO cola_sync
                (solicitud_uuid,id_local,estado,motivo,creada_en)
            VALUES (?,?,'PENDIENTE','',?)
            """,
            (str(uuid.uuid4()), pending_local, FIXED_TIME),
            "SQLITE_CONSTRAINT_UNIQUE", cases["bordes"],
        )
        require(request_row(connection, pending_request) == pending_before,
                "Se altero la primera PENDIENTE")

        simulate(
            connection, paths["semaforo"], mixed_request, "RECHAZADO",
            ["dado de baja"], cases["bordes"]
        )
        require(connection.execute(
            """
            SELECT count(*)
            FROM item_borrador i
            JOIN snapshot_servidor s ON s.producto_id=i.producto_id
            WHERE i.id_local=(SELECT id_local FROM cola_sync WHERE solicitud_uuid=?)
              AND i.precio_centavos_visto <> s.precio_centavos
            """,
            (mixed_request,),
        ).fetchone()[0] > 0, "El caso mixto no tenia amarillo")
        simulate(
            connection, paths["semaforo"], empty_request, "RECHAZADO",
            ["borrador vacio"], cases["bordes"]
        )

        # Bordes con alteracion auxiliar local y ROLLBACK: no falsifican un CSV.
        # Permiten probar las ramas no producibles con stock>0 del servidor.
        edge_cases = [
            ("ausente", "DELETE FROM snapshot_servidor WHERE producto_id=?",
             ["ausente de snapshot_servidor"]),
            ("no_disponible",
             "UPDATE snapshot_servidor SET disponible=0 WHERE producto_id=?",
             ["no disponible"]),
            ("sin_stock",
             "UPDATE snapshot_servidor SET stock=0,disponible=0 WHERE producto_id=?",
             ["sin stock"]),
            ("rojo_y_precio_mismo_item",
             "UPDATE snapshot_servidor SET stock=0,disponible=0,"
             "precio_centavos=precio_centavos+1 WHERE producto_id=?",
             ["sin stock"]),
        ]
        # Se usa SAVEPOINT para deshacer el snapshot modificado despues de evaluar.
        # semaforo.sql tiene BEGIN propio: para estos casos se prueba una copia
        # SQLite efimera, sin modificar la base final ni conectar PostgreSQL.
        for label, change_sql, fragments in edge_cases:
            probe = sqlite3.connect(":memory:", isolation_level=None)
            try:
                connection.backup(probe)
                probe.execute("PRAGMA foreign_keys=ON")
                require(probe.execute("PRAGMA foreign_keys").fetchone()[0] == 1,
                        "FK desactivada en conexion de borde")
                _, probe_request = create_draft(
                    probe, [(NAMES["fugazzeta"], 1)]
                )
                probe_id = probe.execute(
                    "SELECT producto_id FROM producto_cache WHERE nombre=?",
                    (NAMES["fugazzeta"],),
                ).fetchone()[0]
                probe.execute(change_sql, (probe_id,))
                record = {"borde": label, "base": "copia efimera en memoria",
                          "alteracion_auxiliar_local": change_sql, "resultado": []}
                simulate(
                    probe, paths["semaforo"], probe_request,
                    "RECHAZADO", fragments, record["resultado"]
                )
                cases["bordes"].append(record)
            finally:
                probe.close()

        require(len(evidence["comandos"]) == local_phase_commands,
                "La fase de semaforo invoco PostgreSQL")
        evidence["fase_semaforo"] = {
            "comandos_postgresql": 0,
            "solo_sqlite": True,
            "snapshot_final": final_csv.name,
        }

        integrity = [row[0] for row in connection.execute("PRAGMA integrity_check")]
        foreign_keys = connection.execute("PRAGMA foreign_key_check").fetchall()
        require(integrity == ["ok"], "integrity_check fallo")
        require(foreign_keys == [], "foreign_key_check encontro violaciones")
        require(connection.execute("PRAGMA foreign_keys").fetchone()[0] == 1,
                "FK desactivadas al final")
        evidence["verificacion_sqlite_final"] = {
            "integrity_check": integrity,
            "foreign_key_check": foreign_keys,
            "foreign_keys": 1,
        }

        cursor = connection.execute(
            "SELECT * FROM cola_sync ORDER BY id_local,solicitud_uuid"
        )
        columns = [d[0] for d in cursor.description]
        evidence["cola_sync_final"] = [
            dict(zip(columns, row)) for row in cursor.fetchall()
        ]
        connection.close()
        connection = None
        evidence["sqlite_final"] = {
            "archivo": str(database_path.relative_to(root)),
            "bytes": database_path.stat().st_size,
            "sha256": sha256_file(database_path),
        }

        # La conexion PostgreSQL se retoma solo para validacion administrativa.
        after = validate_copy("validacion final copia")
        evidence["copia_despues"] = after
        stable_keys = (
            "pedidos", "productos_fixture", "suma_stock", "vector_stock",
            "huella_producto_sin_precio_ni_baja",
        )
        for key in stable_keys:
            require(after[key] == baseline[key],
                    "Cambio prohibido en copia: " + key)

        initial_admin = {
            row["producto_id"]: row for row in baseline["estado_administrativo"]
        }
        final_admin = {
            row["producto_id"]: row for row in after["estado_administrativo"]
        }
        expected_admin = {key: dict(value) for key, value in initial_admin.items()}
        with final_csv.open("r", encoding="utf-8", newline="") as stream:
            exported = list(csv.DictReader(stream))
        by_name = {row["nombre"]: int(row["producto_id"]) for row in exported}
        expected_admin[by_name[NAMES["muzzarella"]]]["precio_centavos"] += 10000
        expected_admin[by_name[NAMES["agua"]]]["eliminado"] = True
        require(final_admin == expected_admin,
                "Precio o baja difiere de la preparacion administrativa prevista")

        evidence["fuente_despues"] = fingerprints()
        require(evidence["fuente_despues"] == evidence["fuente_antes"],
                "La fuente cambio: revisar concurrencia o escrituras externas")
        evidence["conservacion"] = {
            "cinco_tablas_fuente_filas_bytes_sha256_identicos": True,
            "pedidos_copia_identicos": True,
            "vector_stock_copia_identico": True,
            "cambios_administrativos_solo_C2_C4": True,
            "ventas_creadas_por_simulacion": 0,
        }
        evidence["estado"] = "COMPLETADO_CON_VERIFICACIONES"
        save_evidence()
        print("Reproduccion completada; revise docs/evidencias.")
        print("SIMULADO_APROBADO no es una venta.")
        return 0

    except Exception as exc:
        # No se publican mensajes arbitrarios de subprocess ni variables PG.
        evidence["estado"] = "FALLO"
        evidence["fallo"] = {
            "tipo": type(exc).__name__,
            "diagnostico": "Revisar diagnosticos privados y evidencia parcial.",
        }
        (private / "fallo_python.txt").write_text(
            type(exc).__name__ + ": " + str(exc) + "\n", encoding="utf-8"
        )
        if connection is not None:
            if connection.in_transaction:
                connection.execute("ROLLBACK")
            connection.close()
        save_evidence()
        print(
            "Reproduccion detenida. No se borraron bases ni salidas parciales. "
            "Revise la evidencia y el directorio privado.",
            file=sys.stderr,
        )
        return 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, OSError, ValueError) as exc:
        # Las comprobaciones previas no incluyen credenciales ni respuestas PG.
        print("No se inicio la reproduccion: " + str(exc), file=sys.stderr)
        raise SystemExit(1)
```

**Supuestos y riesgos a revisar antes de ejecutar:** no se ejecutaron herramientas ni se verificaron resultados en esta respuesta. Se necesita una ventana sin escrituras concurrentes sobre `foodstore`, permisos para clonar y respaldar, y ACL privadas para `--private-dir`, especialmente en Windows. El respaldo contiene datos de la copia completa y debe permanecer fuera del proyecto y del ZIP. Si falla una ejecución, quedan artefactos y la copia para diagnóstico; el runner no los elimina ni permite repetir sobre ellos. Los bordes adicionales usan copias SQLite efímeras en memoria; sus resultados quedan en JSON/TXT, no en la cola de la base final.

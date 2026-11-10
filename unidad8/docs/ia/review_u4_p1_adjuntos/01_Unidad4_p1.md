# Fuentes saneadas para revisión estática: Unidad4

No ejecutar estas copias. Los literales personales/de carga se sustituyeron por placeholders; las comprobaciones en motor usarán las fuentes originales locales. Señalar archivo/línea y distinguir errores confirmables de hipótesis.


Parte 1/3: archivos completos, sin cambiar sus cuerpos. Otras partes se revisan por separado.

## outputs\Arancibia_Romero_U4\00_reconstruir_base.ps1

SHA256 original: cc83d932d15a12a139db847b331cc422dc388c160463e20258b6234cf8ee47ba
SHA256 saneado: e7419dbbf67465fc9cb15e64e930fe0caea0e2fa07e5d72f4de354b44d30bca3

`````ps1
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
# Exequiel Arancibia / Joaquin Romero - continuidad de TP1 a TP5.
# Crea una base nueva; createdb falla si ya existe. No borra otras bases.
param(
    [string]$PgBin = 'C:\Program Files\PostgreSQL\17\bin',
    [string]$Servidor = '127.0.0.1',
    [int]$Puerto = 5432,
    [string]$Usuario = 'postgres'
)
$ErrorActionPreference = 'Stop'
$env:PGCLIENTENCODING = 'UTF8'
$baseU4 = 'foodstore_u4_arancibia_romero'
$archivosU4 = $PSScriptRoot
$copiaU4 = Join-Path $archivosU4 'antecedentes\respaldo_pre_tp4.dump'
$hashU4 = (Get-FileHash -LiteralPath $copiaU4 -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hashU4 -ne 'f53af18eac3da8de40114f63daaea8ccddae528db688b68e6740c8e31fc01871') {
    throw 'El respaldo no coincide con el original adjunto del TP4.'
}
& (Join-Path $PgBin 'createdb.exe') -h $Servidor -p $Puerto -U $Usuario $baseU4
if ($LASTEXITCODE -ne 0) { throw 'No se creo la base nueva; no continuar.' }
& (Join-Path $PgBin 'pg_restore.exe') -h $Servidor -p $Puerto -U $Usuario -d $baseU4 --no-owner --no-privileges --exit-on-error $copiaU4
if ($LASTEXITCODE -ne 0) { throw 'Fallo la restauracion del respaldo.' }
foreach ($nombreU4 in @('antecedentes\indices_tp4.sql', 'antecedentes\indices_tp5.sql', 'antecedentes\views_tp5.sql', '01_actividad_del_dia.sql')) {
    & (Join-Path $PgBin 'psql.exe') -X -v ON_ERROR_STOP=1 -h $Servidor -p $Puerto -U $Usuario -d $baseU4 -f (Join-Path $archivosU4 $nombreU4)
    if ($LASTEXITCODE -ne 0) { throw "Fallo el archivo $nombreU4" }
}
Write-Output 'Base heredada preparada. Ejecutar ahora los dos scripts de Unidad 4.'

`````

## outputs\Arancibia_Romero_U4\01_actividad_del_dia.sql

SHA256 original: ff0dc5d863f46d7e81d5317536ee1c1f58640a8e9e70d8bf1cf91596b2c9f03a
SHA256 saneado: 1e06df06d14125034800b922ede649a7eba11ef6a785cef3eef1e106deda3247

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Unidad 4 - Exequiel Arancibia / Joaquin Romero.
-- Continuacion de los TP1-TP5: NO se recrean tablas ni datos historicos.
-- Agrega exclusivamente actividad identificable del dia del laboratorio.
-- Ejecutar una sola vez, antes de instalar la nueva materializada U4.
\set ON_ERROR_STOP on
SET search_path = public, pg_catalog;
SET TIME ZONE 'America/Argentina/Buenos_Aires';
BEGIN;
DO $$
BEGIN
    IF current_database() <> 'foodstore_u4_arancibia_romero' THEN
        RAISE EXCEPTION 'Usar la copia foodstore_u4_arancibia_romero';
    END IF;
    IF (SELECT count(*) FROM public.pedido) <> 200000
       OR (SELECT max(id) FROM public.pedido) <> 200000
       OR (SELECT count(*) FROM public.detalle_pedido) <> 399997
       OR (SELECT count(*) FROM public.producto) <> 50000
       OR (SELECT count(*) FROM public.usuario) <> 20000 THEN
        RAISE EXCEPTION 'La base no coincide con el respaldo heredado';
    END IF;
    IF to_regclass('public.mv_u4_ventas_categoria_dia') IS NOT NULL THEN
        RAISE EXCEPTION 'La carga del dia debe preceder a la instalacion U4';
    END IF;
END $$;

-- El respaldo conserva los estados y todas las fechas historicas.
-- Cada nuevo pedido utiliza un usuario existente y nace PENDIENTE.
INSERT INTO public.pedido (usuario_id, fecha, forma_pago)
SELECT 1 + ((g - 1) % 20000),
       (CURRENT_DATE::timestamp AT TIME ZONE 'America/Argentina/Buenos_Aires')
           + (g - 1) * INTERVAL '1 second',
       'EFECTIVO'::public.forma_pago
FROM generate_series(1, 25000) g;

-- Mismo criterio de carga por lotes que en TP3/TP5: solo se pausa el
-- recalculo costoso. La validacion TP2 de detalle PENDIENTE sigue ACTIVA.
ALTER TABLE public.detalle_pedido DISABLE TRIGGER trg_recalcular_total;
INSERT INTO public.detalle_pedido
    (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, pr.id, 1, pr.precio
FROM public.pedido p
CROSS JOIN generate_series(0, 3) k
JOIN public.producto pr
    ON pr.id = 1 + ((p.id * 17 + k * 7919) % 50000)
WHERE p.id BETWEEN 200001 AND 225000;

-- subtotal permanece GENERATED: nunca se inserta ni se actualiza a mano.
UPDATE public.pedido p
SET total = t.total
FROM (
    SELECT pedido_id, SUM(subtotal) AS total
    FROM public.detalle_pedido
    WHERE pedido_id BETWEEN 200001 AND 225000
    GROUP BY pedido_id
) t
WHERE p.id = t.pedido_id;
ALTER TABLE public.detalle_pedido ENABLE TRIGGER trg_recalcular_total;

DO $$
BEGIN
    IF (SELECT count(*) FROM public.pedido) <> 225000
       OR (SELECT count(*) FROM public.detalle_pedido) <> 499997
       OR EXISTS (
            SELECT 1 FROM public.pedido p
            WHERE p.id BETWEEN 200001 AND 225000
              AND p.total <> COALESCE((SELECT SUM(d.subtotal)
                  FROM public.detalle_pedido d WHERE d.pedido_id = p.id), 0)
       ) THEN
        RAISE EXCEPTION 'Fallo de conteo o de totales en la nueva actividad';
    END IF;
END $$;
COMMIT;

-- Se conserva el objeto mensual del TP5 y su politica de instantanea.
-- Este refresco explicito incorpora la nueva carga inicial de laboratorio.
REFRESH MATERIALIZED VIEW public.mv_facturacion_categoria_mes;
ANALYZE public.pedido;
ANALYZE public.detalle_pedido;
SELECT 'pedidos_heredados' AS control, count(*) AS filas
FROM public.pedido WHERE id <= 200000
UNION ALL SELECT 'pedidos_agregados_hoy', count(*)
FROM public.pedido WHERE id BETWEEN 200001 AND 225000
UNION ALL SELECT 'detalles_heredados', count(*)
FROM public.detalle_pedido WHERE pedido_id <= 200000
UNION ALL SELECT 'detalles_agregados_hoy', count(*)
FROM public.detalle_pedido WHERE pedido_id BETWEEN 200001 AND 225000;

`````

## outputs\Arancibia_Romero_U4\antecedentes\indices_tp4.sql

SHA256 original: faa93dd80e418ec49464b76db3dcc575f8741a4bc976fcf9b5ab4f1857ed1e8b
SHA256 saneado: cba7d1d69e5e3d192a6e6de1a52f1e736fb4f1f24c2f1fff64d236c6e5910d72

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- La PK existente empieza por pedido_id. Estas consultas parten de producto,
-- por eso se agrega el camino inverso y se cubren las columnas analiticas.
CREATE INDEX idx_tp4_detalle_producto_cobertura
    ON detalle_pedido (producto_id, pedido_id)
    INCLUDE (cantidad, subtotal);

ANALYZE detalle_pedido;

`````

## outputs\Arancibia_Romero_U4\antecedentes\indices_tp5.sql

SHA256 original: 5dc9d9b749360693fe945d38f23cb93b7c8bfcfbb0f2c258e257dda2a9357ac9
SHA256 saneado: 2e7757c18ca03070662e267a13f3d3660947af4b428705d3a61a4f51248495c8

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- TP5 - Parte A: indices aceptados
-- Autores: Exequiel Arancibia y Joaquin Romero
-- PostgreSQL 16+
\set ON_ERROR_STOP on

-- Q1. Indice parcial de expresion: normaliza la fecha a la zona del negocio,
-- excluye filas irrelevantes y cubre las columnas proyectadas.
CREATE INDEX IF NOT EXISTS idx_u3_pedido_fecha_local_entregado
ON pedido ((fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'))
INCLUDE (id, usuario_id, total)
WHERE eliminado = FALSE AND estado = 'ENTREGADO';

-- Q2. Stock primero satisface filtro y orden; id estabiliza el orden.
-- Es parcial porque los productos eliminados no aparecen en el catalogo.
CREATE INDEX IF NOT EXISTS idx_u3_producto_stock_vig
ON producto (stock, id)
INCLUDE (nombre, precio)
WHERE eliminado = FALSE;

-- Q3. La PK existente comienza por pedido_id y no sirve para buscar primero
-- por producto_id. Este orden complementario evita recorrer todo el detalle.
CREATE INDEX IF NOT EXISTS idx_u3_detalle_producto_pedido
ON detalle_pedido (producto_id, pedido_id)
INCLUDE (cantidad, precio_unitario);

ANALYZE pedido;
ANALYZE producto;
ANALYZE detalle_pedido;

`````

## outputs\Arancibia_Romero_U4\antecedentes\views_tp5.sql

SHA256 original: 7c4aa415da587e7a4e6d076d151cadac5374ccb2a03153c32a45bad5738a6ccd
SHA256 saneado: 472d8dda34a43f6359a8650b53d7334b393840e877981249f8bc962d73d3fadb

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- TP5 - Partes B y C: vistas y vista materializada
-- Autores: Exequiel Arancibia y Joaquin Romero
-- PostgreSQL 16+
\set ON_ERROR_STOP on

-- Catalogo publico: solo productos y categorias vigentes.
CREATE OR REPLACE VIEW v_productos_vigentes_categoria AS
SELECT pr.id AS producto_id,
       pr.nombre AS producto_nombre,
       pr.descripcion,
       pr.precio,
       pr.stock,
       c.id AS categoria_id,
       c.nombre AS categoria_nombre
FROM producto AS pr
JOIN categoria AS c ON c.id = pr.categoria_id
WHERE pr.eliminado = FALSE AND c.eliminado = FALSE;

-- Vista segura: expone contacto, pero nunca usuario.contrasena.
CREATE OR REPLACE VIEW v_pedidos_usuario AS
SELECT p.id AS pedido_id,
       p.fecha,
       p.forma_pago,
       p.estado,
       p.total,
       u.id AS usuario_id,
       u.nombre AS usuario_nombre,
       u.apellido AS usuario_apellido,
       u.email,
       u.telefono
FROM pedido AS p
JOIN usuario AS u ON u.id = p.usuario_id
WHERE p.eliminado = FALSE AND u.eliminado = FALSE;

-- Detalle historico: conserva lineas aunque luego el producto sea dado de baja.
CREATE OR REPLACE VIEW v_detalle_pedido_producto AS
SELECT d.pedido_id,
       d.producto_id,
       pr.nombre AS producto_nombre,
       d.cantidad,
       d.precio_unitario,
       d.subtotal
FROM detalle_pedido AS d
JOIN producto AS pr ON pr.id = d.producto_id;

-- Reporte agregado costoso. DROP permite reproducir el script completo.
DROP MATERIALIZED VIEW IF EXISTS mv_facturacion_categoria_mes;
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT c.id AS categoria_id,
       c.nombre AS categoria_nombre,
       date_trunc('month', p.fecha) AS mes,
       count(DISTINCT p.id) AS cantidad_pedidos,
       sum(d.cantidad)::bigint AS unidades,
       sum(d.subtotal)::numeric(16,2) AS facturacion
FROM categoria AS c
JOIN producto AS pr ON pr.categoria_id = c.id
JOIN detalle_pedido AS d ON d.producto_id = pr.id
JOIN pedido AS p ON p.id = d.pedido_id
WHERE p.eliminado = FALSE AND p.estado <> 'CANCELADO'
GROUP BY c.id, c.nombre, date_trunc('month', p.fecha)
WITH DATA;

-- Requisito para futuros REFRESH CONCURRENTLY.
CREATE UNIQUE INDEX ux_mv_facturacion_categoria_mes
ON mv_facturacion_categoria_mes (categoria_id, mes);

ANALYZE mv_facturacion_categoria_mes;

`````

## outputs\Arancibia_Romero_U4\reproduccion\verify_fnbc.py

SHA256 original: 7351b171b790849577b5cbfd18c257b3376d06fc9fcf3fe883206b9179900b58
SHA256 saneado: 7efd63a8ad8a2edf37167c51ce25c38d8166d55fb63e737bcb138ef1438d202f

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Verificaciones independientes de la Parte 1 - Arancibia / Romero.

Solo biblioteca estandar y psql.exe. Requiere la copia restaurada del TP5
foodstore_u4_arancibia_romero en 127.0.0.1:55439 y su extension U4 aplicada.
Todas las referencias de negocio usan el esquema public heredado.
No crea ni modifica usuarios. Las pruebas de anomalias usan BEGIN/ROLLBACK;
la prueba concurrente limpia sus asignaciones y el maestro auxiliar al terminar.
"""

from __future__ import annotations

import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
import traceback


WORK = Path(__file__).resolve().parent
ROOT = WORK.parent.parent
JSON_OUTPUT = WORK / "fnbc_tests.json"
TEXT_OUTPUT = (
    WORK.parent / "evidencias" / "parte1_pruebas.txt"
    if WORK.name == "reproduccion"
    else ROOT / "outputs" / "Arancibia_Romero_U4" / "evidencias" / "parte1_pruebas.txt"
)
PSQL = os.environ.get("TP_PSQL") or shutil.which("psql.exe") or (
    r"C:\Program Files\PostgreSQL\17\bin\psql.exe"
)
BASE_CMD = [
    PSQL, "-X", "-w", "-h", "127.0.0.1", "-p", "55439",
    "-U", "tp_admin", "-d", "foodstore_u4_arancibia_romero", "-A", "-t",
    "-q",
    "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose",
    "--pset=pager=off",
]
ENV = os.environ.copy()
ENV["PGCLIENTENCODING"] = "UTF8"
ENV["PGCONNECT_TIMEOUT"] = "10"
REPORT: dict = {
    "endpoint": "127.0.0.1:55439/foodstore_u4_arancibia_romero",
    "usuario": "tp_admin",
    "motor": "PostgreSQL",
    "success": False,
    "tests": [],
}
TRANSCRIPT: list[str] = [
    "PARTE 1 - VERIFICACIONES REALES DE FNBC Y ANOMALIAS",
    "Servidor: 127.0.0.1:55439 | Base: foodstore_u4_arancibia_romero | Usuario: tp_admin",
    "Esquema heredado: public | Integrantes: Exequiel Arancibia - Joaquin Romero",
    "",
]


def run_sql(sql: str, *, app: str = "tp_fnbc_verificador") -> subprocess.CompletedProcess:
    env = ENV.copy()
    env["PGAPPNAME"] = app
    return subprocess.run(
        BASE_CMD + ["-c", sql],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=30,
        env=env,
        check=False,
    )


def require_success(result: subprocess.CompletedProcess, context: str) -> None:
    if result.returncode:
        raise AssertionError(
            f"{context}: psql termino con codigo {result.returncode}\n"
            f"{result.stdout}\n{result.stderr}"
        )


def add_result(name: str, sql: str, result: subprocess.CompletedProcess,
               **details) -> None:
    record = {
        "nombre": name,
        "ok": result.returncode == 0,
        "codigo_psql": result.returncode,
        "sql": sql.strip(),
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
        **details,
    }
    REPORT["tests"].append(record)
    TRANSCRIPT.extend([
        name.upper(),
        "SQL ejecutado:", sql.strip(),
        "Salida estandar:", result.stdout.strip() or "(vacia)",
        "Mensajes del servidor:", result.stderr.strip() or "(vacios)",
        f"Codigo de salida de psql: {result.returncode}",
        "",
    ])


def test_closures() -> None:
    attrs = frozenset("LDR")
    fds = [(frozenset("LD"), frozenset("R")),
           (frozenset("R"), frozenset("D"))]

    def closure(seed: frozenset) -> frozenset:
        current = set(seed)
        while True:
            previous = current.copy()
            for lhs, rhs in fds:
                if lhs <= current:
                    current.update(rhs)
            if current == previous:
                return frozenset(current)

    def label(values: frozenset) -> str:
        return "".join(a for a in "LDR" if a in values) or "{}"

    subsets = [
        frozenset(items)
        for size in range(4)
        for items in itertools.combinations("LDR", size)
    ]
    actual = {label(s): label(closure(s)) for s in subsets}
    expected = {"{}": "{}", "L": "L", "D": "D", "R": "DR",
                "LD": "LDR", "LR": "LDR", "DR": "DR", "LDR": "LDR"}
    assert actual == expected, (actual, expected)
    keys = [
        s for s in subsets
        if closure(s) == attrs
        and not any(t < s and closure(t) == attrs for t in subsets)
    ]
    assert set(keys) == {frozenset("LD"), frozenset("LR")}, keys
    primes = frozenset().union(*keys)
    assert primes == attrs
    assert closure(frozenset("R")) != attrs

    REPORT["matematica"] = {
        "dependencias": ["LD -> R", "R -> D"],
        "clausuras_todos_los_subconjuntos": actual,
        "claves_candidatas": [label(k) for k in keys],
        "atributos_primos": label(primes),
        "atributos_no_primos": [],
        "dependencia_violatoria_fnbc": "R -> D",
        "ok": True,
    }
    TRANSCRIPT.extend([
        "CALCULO EXHAUSTIVO DE CLAUSURAS MEDIANTE PYTHON",
        "Dependencias: LD -> R; R -> D",
        *[f"{source}+ = {target}" for source, target in actual.items()],
        "Claves candidatas completas: LD, LR",
        "Atributos primos: L, D, R; no primos: ninguno.",
        "R+ = DR no contiene L: R -> D viola FNBC.",
        "Resultado de todos los asserts matematicos: correcto.", "",
    ])


def test_anomalies() -> None:
    sql = """
BEGIN;
DO $$
DECLARE rechazo BOOLEAN := FALSE;
BEGIN
    BEGIN
        INSERT INTO public.control_lote_almacen_original
            (lote_id, deposito_id, responsable_control_id)
        VALUES (NULL, 30, 803);
    EXCEPTION WHEN not_null_violation THEN
        rechazo := TRUE;
        RAISE NOTICE 'Insercion rechazada: SQLSTATE 23502; falta un lote para registrar R803 -> D30';
    END;
    IF NOT rechazo THEN
        RAISE EXCEPTION 'La insercion sin lote debio rechazarse';
    END IF;
END $$;
ROLLBACK;
SELECT 'insercion_verificada_sin_cambios';
"""
    result = run_sql(sql)
    add_result("Anomalia de insercion", sql, result, sqlstate_esperado="23502")
    require_success(result, "Anomalia de insercion")
    assert "23502" in result.stderr

    sql = """
BEGIN;
DELETE FROM public.control_lote_almacen_original
WHERE lote_id = 503 AND deposito_id = 31 AND responsable_control_id = 802;
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM public.control_lote_almacen_original
        WHERE responsable_control_id = 802
    ) THEN
        RAISE EXCEPTION 'La prueba esperaba perder la pertenencia de R802 a D31';
    END IF;
    RAISE NOTICE 'Borrado verificado: quedan 0 filas de R802; se pierde el dato maestro R802 -> D31';
END $$;
SELECT COUNT(*) AS filas_restantes_de_r802
FROM public.control_lote_almacen_original
WHERE responsable_control_id = 802;
ROLLBACK;
"""
    result = run_sql(sql)
    add_result("Anomalia de borrado", sql, result, filas_r802_tras_borrado=0)
    require_success(result, "Anomalia de borrado")
    assert "\n0\n" in "\n" + result.stdout + "\n"

    sql = """
BEGIN;
UPDATE public.control_lote_almacen_original
SET deposito_id = 31
WHERE lote_id = 501 AND responsable_control_id = 801;
DO $$
DECLARE cantidad INTEGER;
BEGIN
    SELECT COUNT(DISTINCT deposito_id) INTO cantidad
    FROM public.control_lote_almacen_original
    WHERE responsable_control_id = 801;
    IF cantidad <> 2 THEN
        RAISE EXCEPTION 'Se esperaban 2 depositos diferentes para R801: %', cantidad;
    END IF;
    RAISE NOTICE 'Actualizacion parcial verificada: R801 aparece en D30 y D31; se viola R -> D';
END $$;
SELECT responsable_control_id, COUNT(DISTINCT deposito_id) AS depositos_distintos
FROM public.control_lote_almacen_original
WHERE responsable_control_id = 801
GROUP BY responsable_control_id;
ROLLBACK;
"""
    result = run_sql(sql)
    add_result("Anomalia de actualizacion", sql, result, depositos_distintos_r801=2)
    require_success(result, "Anomalia de actualizacion")
    assert "801|2" in result.stdout


def launch(sql: str, app: str) -> subprocess.Popen:
    env = ENV.copy()
    env["PGAPPNAME"] = app
    return subprocess.Popen(
        BASE_CMD + ["-c", f"SET application_name = '{app}';\n" + sql],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )


def launch_interactive(app: str) -> subprocess.Popen:
    """Mantener A abierta hasta que el observador confirme el bloqueo de B."""
    env = ENV.copy()
    env["PGAPPNAME"] = app
    return subprocess.Popen(
        BASE_CMD,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=env,
    )


def send_sql(process: subprocess.Popen, sql: str) -> None:
    assert process.stdin is not None
    process.stdin.write(sql.strip() + "\n")
    process.stdin.flush()


def wait_activity(app: str, condition: str, process: subprocess.Popen,
                  timeout: float = 20.0) -> list[dict]:
    deadline = time.monotonic() + timeout
    last_rows: list[dict] = []
    while time.monotonic() < deadline:
        result = run_sql(
            "SELECT COALESCE(json_agg(r),'[]'::json) FROM ("
            "SELECT pid,state,wait_event_type,wait_event,query "
            "FROM pg_stat_activity "
            f"WHERE application_name = '{app}' AND ({condition})"
            ") r;"
        )
        require_success(result, "Observacion de concurrencia")
        last_rows = json.loads(result.stdout.strip())
        if last_rows:
            return last_rows
        if process.poll() is not None:
            out, err = process.communicate()
            raise AssertionError(
                f"{app} termino antes del estado esperado: "
                f"codigo={process.returncode}, salida={out!r}, mensajes={err!r}"
            )
        time.sleep(0.03)
    raise AssertionError(
        f"No se observo el estado esperado de {app}: {condition}; "
        f"ultima observacion={last_rows}"
    )


def test_concurrency() -> None:
    prepare_sql = """
BEGIN;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM public.responsable_deposito WHERE responsable_control_id = 803)
       OR EXISTS (SELECT 1 FROM public.lote_responsable WHERE lote_id = 503 AND responsable_control_id = 801)
    THEN
        RAISE EXCEPTION 'La preparacion requiere libres las filas auxiliares de esta prueba';
    END IF;
END $$;
INSERT INTO public.responsable_deposito (responsable_control_id, deposito_id)
VALUES (803, 30);
COMMIT;
"""
    result = run_sql(prepare_sql)
    add_result("Preparacion de concurrencia", prepare_sql, result)
    require_success(result, "Preparacion de concurrencia")

    sql_a_start = """
SET application_name = 'tp_fnbc_prueba_A';
BEGIN;
INSERT INTO public.lote_responsable (lote_id, responsable_control_id)
VALUES (503, 801);
SELECT 'A_CONTROL_INSERTADO';
"""
    sql_a_finish = """
SELECT pg_sleep(2);
COMMIT;
"""
    sql_a = sql_a_start + sql_a_finish
    sql_b = """
BEGIN;
INSERT INTO public.lote_responsable (lote_id, responsable_control_id)
VALUES (503, 803);
COMMIT;
"""
    clients: list[subprocess.Popen] = []
    try:
        process_a = launch_interactive("tp_fnbc_prueba_A")
        clients.append(process_a)
        send_sql(process_a, sql_a_start)
        state_a = wait_activity(
            "tp_fnbc_prueba_A",
            "state = 'idle in transaction' AND query LIKE '%A_CONTROL_INSERTADO%'",
            process_a,
        )
        start_b = time.monotonic()
        process_b = launch(sql_b, "tp_fnbc_prueba_B")
        clients.append(process_b)
        state_b = wait_activity(
            "tp_fnbc_prueba_B", "wait_event_type = 'Lock'", process_b
        )
        # A no puede confirmar antes de observar el bloqueo real de B. Recien
        # ahora se envia la pausa de dos segundos y COMMIT por el mismo canal.
        send_sql(process_a, sql_a_finish)
        assert process_a.stdin is not None
        process_a.stdin.close()
        process_a.stdin = None
        out_a, err_a = process_a.communicate(timeout=15)
        out_b, err_b = process_b.communicate(timeout=15)
        elapsed_b = time.monotonic() - start_b

        expected_rejection = process_b.returncode != 0 and "23505" in err_b
        entry = {
            "nombre": "Concurrencia real de dos sesiones",
            "ok": process_a.returncode == 0 and expected_rejection,
            "estado_a_observado": state_a,
            "estado_b_observado": state_b,
            "espera_por_bloqueo_observada": True,
            "coordinacion": "A conserva BEGIN abierto hasta observar B esperando Lock; luego ejecuta pg_sleep(2) y COMMIT",
            "duracion_b_segundos": round(elapsed_b, 6),
            "sesion_a": {"sql": sql_a.strip(), "codigo_psql": process_a.returncode,
                         "stdout": out_a.strip(), "stderr": err_a.strip()},
            "sesion_b": {"sql": sql_b.strip(), "codigo_psql": process_b.returncode,
                         "stdout": out_b.strip(), "stderr": err_b.strip()},
            "sqlstate_esperado_b": "23505",
        }
        REPORT["tests"].append(entry)
        TRANSCRIPT.extend([
            "CONCURRENCIA REAL DE DOS SESIONES",
            "A inserta (L503,R801) y conserva BEGIN abierto por un canal stdin.",
            "B intenta insertar (L503,R803); ambos responsables pertenecen a D30.",
            "Tras observar B esperando Lock, A duerme 2 segundos y confirma.",
            f"Estado A observado antes de iniciar B: {state_a}",
            f"Estado B observado durante la espera: {state_b}",
            f"Tiempo total de B: {elapsed_b:.6f} s",
            "SQL de A:", sql_a.strip(), "Salida A:", out_a.strip(), err_a.strip(),
            f"Codigo psql A: {process_a.returncode}",
            "SQL de B:", sql_b.strip(), "Salida B:", out_b.strip(), err_b.strip(),
            f"Codigo psql B: {process_b.returncode}",
            "B debe esperar el bloqueo y terminar con SQLSTATE 23505.", "",
        ])
        assert process_a.returncode == 0, (out_a, err_a)
        assert expected_rejection, (out_b, err_b)

        verify_sql = """
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.lote_responsable
        WHERE lote_id = 503 AND responsable_control_id = 801
    ) OR EXISTS (
        SELECT 1 FROM public.lote_responsable
        WHERE lote_id = 503 AND responsable_control_id = 803
    ) THEN
        RAISE EXCEPTION 'El estado final no coincide con A confirmada y B rechazada';
    END IF;
END $$;
SELECT 'A_confirmada_B_rechazada';
"""
        verify = run_sql(verify_sql)
        add_result("Estado posterior a concurrencia", verify_sql, verify)
        require_success(verify, "Estado posterior a concurrencia")
    finally:
        for client in clients:
            if client.poll() is None:
                client.terminate()
                client.communicate(timeout=10)
        cleanup_sql = """
BEGIN;
DELETE FROM public.lote_responsable
WHERE lote_id = 503 AND responsable_control_id IN (801, 803);
DELETE FROM public.responsable_deposito WHERE responsable_control_id = 803;
COMMIT;
"""
        cleanup = run_sql(cleanup_sql)
        add_result("Limpieza de las filas de concurrencia", cleanup_sql, cleanup)
        require_success(cleanup, "Limpieza de concurrencia")


def test_final_integrity() -> None:
    sql = """
DO $$
DECLARE cantidad INTEGER;
BEGIN
    SELECT COUNT(*) INTO cantidad FROM public.control_lote_almacen;
    IF cantidad <> 3 THEN
        RAISE EXCEPTION 'La vista final deberia tener 3 filas; tiene %', cantidad;
    END IF;
    IF EXISTS (
        SELECT * FROM public.control_lote_almacen_original
        EXCEPT ALL SELECT * FROM public.control_lote_almacen
    ) OR EXISTS (
        SELECT * FROM public.control_lote_almacen
        EXCEPT ALL SELECT * FROM public.control_lote_almacen_original
    ) THEN
        RAISE EXCEPTION 'La prueba altero la equivalencia de la migracion';
    END IF;
END $$;
SELECT lote_id, deposito_id, responsable_control_id
FROM public.control_lote_almacen ORDER BY lote_id, deposito_id, responsable_control_id;
SELECT 'diferencias_bilaterales=0; filas_vista=3; originales_restaurados';
"""
    result = run_sql(sql)
    add_result("Integridad final y restauracion de las pruebas", sql, result)
    require_success(result, "Integridad final")
    assert all(line in result.stdout for line in
               ["501|30|801", "502|30|801", "503|31|802"])


def save() -> None:
    JSON_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    TEXT_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    JSON_OUTPUT.write_text(json.dumps(REPORT, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    TEXT_OUTPUT.write_text("\n".join(TRANSCRIPT) + "\n", encoding="utf-8")


def main() -> int:
    try:
        server = run_sql("SELECT version();")
        require_success(server, "Conexion con PostgreSQL")
        REPORT["version_servidor"] = server.stdout.strip()
        TRANSCRIPT.extend(["VERSION REAL DEL SERVIDOR", server.stdout.strip(), ""])
        test_closures()
        test_anomalies()
        test_concurrency()
        test_final_integrity()
        assert all(test["ok"] for test in REPORT["tests"])
        REPORT["success"] = True
        TRANSCRIPT.append("RESULTADO GLOBAL: todas las pruebas y asserts fueron satisfactorios.")
        save()
        print(f"OK: {len(REPORT['tests'])} pruebas SQL y todas las clausuras verificadas.")
        print(JSON_OUTPUT)
        print(TEXT_OUTPUT)
        return 0
    except Exception as exc:
        REPORT["error"] = str(exc)
        REPORT["traceback"] = traceback.format_exc()
        TRANSCRIPT.extend(["RESULTADO GLOBAL: FALLO", traceback.format_exc()])
        save()
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

`````


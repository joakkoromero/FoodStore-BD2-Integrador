-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Unidad 6 - Food Store. Exequiel Arancibia / Joaquin Romero.
-- Implementacion tecnica: Codex. Ejecutar con psql -X -w -A -t
-- -v ON_ERROR_STOP=1 -d foodstore[..._restore_test] -f validaciones.sql.
-- stdout: UN objeto JSON con counts, fingerprints, invalid. Sin filas ni PII.
-- La guia llama cliente a la entidad que aqui conserva public.usuario.
\set ON_ERROR_STOP on
\set QUIET 1
\pset pager off

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL TIME ZONE 'America/Argentina/Buenos_Aires';
SET LOCAL DateStyle = 'ISO, YMD';
SET LOCAL application_name = 'u6_validaciones';

DO $base_correcta$
BEGIN
    IF pg_catalog.current_database() NOT IN ('foodstore','foodstore_restore_test') THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'validaciones.sql requiere foodstore o foodstore_restore_test';
    END IF;
END
$base_correcta$;

-- Una instantanea por ejecucion evita mezclar conteos de varios instantes.
-- El orquestador debe evitar escritores entre baseline y snapshot del dump,
-- o compartir expresamente un snapshot exportado. Este archivo no lo presume.
-- Las huellas siguen U5: MD5 de la concatenacion ordenada de MD5 de cada fila
-- completa en JSON. Son checksums de conservacion, no anonimato ni firma.
-- Se fija zona/DateStyle para que timestamps tengan la misma representacion.
WITH categorias AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.categoria AS t
), productos AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.count(*) FILTER (WHERE t.precio < 0 OR t.stock < 0) AS invalidos,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.producto AS t
), usuarios AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.usuario AS t
), pedidos AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.pedido AS t
), detalles AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.count(*) FILTER (WHERE t.cantidad <= 0 OR t.precio_unitario < 0) AS invalidos,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),''
               ORDER BY t.pedido_id,t.producto_id),'')) AS huella
    FROM public.detalle_pedido AS t
)
SELECT pg_catalog.jsonb_build_object(
    'counts', pg_catalog.jsonb_build_object(
        'categoria',c.n,'producto',pr.n,'usuario',u.n,'pedido',pe.n,'detalle_pedido',d.n),
    'fingerprints', pg_catalog.jsonb_build_object(
        'categoria',c.huella,'producto',pr.huella,'usuario',u.huella,
        'pedido',pe.huella,'detalle_pedido',d.huella),
    'invalid', pg_catalog.jsonb_build_object('productos',pr.invalidos,'detalles',d.invalidos)
) AS validacion
FROM categorias AS c CROSS JOIN productos AS pr CROSS JOIN usuarios AS u
CROSS JOIN pedidos AS pe CROSS JOIN detalles AS d;

COMMIT;

-- No agregar metadata variable a este JSON: los scripts registran fecha/base
-- y comparan los cinco counts/fingerprints y los dos ceros de forma explicita.
-- precio, stock, cantidad y precio_unitario son NOT NULL en el modelo real;
-- las condiciones invalid conservan exactamente los controles de la guia.

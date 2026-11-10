-- Trabajo practico Unidad 4 - Parte 2.
-- Exequiel Arancibia y Joaquin Romero. PostgreSQL 17.
-- Base acumulativa: respaldo TP4 + indice TP4 + indices y vistas TP5.
-- Ejecutar despues de preparar la copia foodstore_u4_arancibia_romero.
-- No recrea ni vacia las tablas heredadas.
\set ON_ERROR_STOP on
SET timezone = 'America/Argentina/Buenos_Aires';
SET default_transaction_isolation = 'read committed';
-- Parametros comunes a las mediciones antes y despues del informe.
SET max_parallel_workers_per_gather = 0;
SET jit = off;

DO $$
BEGIN
    IF current_database() <> 'foodstore_u4_arancibia_romero' THEN
        RAISE EXCEPTION 'Base incorrecta: %. Usar foodstore_u4_arancibia_romero',
            current_database();
    END IF;
    IF to_regclass('public.detalle_pedido') IS NULL
       OR to_regclass('public.mv_facturacion_categoria_mes') IS NULL
       OR NOT EXISTS (
           SELECT 1 FROM pg_trigger
           WHERE tgrelid='public.detalle_pedido'::regclass
             AND tgname='trg_validar_detalle_pendiente' AND NOT tgisinternal
       ) THEN
        RAISE EXCEPTION 'Falta la base heredada acumulativa de TP2 a TP5';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid='public.pedido'::regclass AND attname='fecha'
          AND atttypid='timestamptz'::regtype AND NOT attisdropped
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_attribute
        WHERE attrelid='public.detalle_pedido'::regclass AND attname='subtotal'
          AND attgenerated='s' AND NOT attisdropped
    ) THEN
        RAISE EXCEPTION 'Se esperaba fecha TIMESTAMPTZ y subtotal generado heredados';
    END IF;
END;
$$;

-- 5.2(a): adaptacion explicita de la consulta de la guia al proyecto previo.
-- detalle_pedido no tiene eliminado: no existe baja logica de una linea;
-- toda linea persistida integra el pedido. Se conserva ped.eliminado=FALSE.
-- fecha es TIMESTAMPTZ: la igualdad con CURRENT_DATE solo incluiria medianoche.
-- El intervalo semiabierto recupera TODO el dia local; no se filtra por estado.
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
FROM public.detalle_pedido dp
JOIN public.producto pr ON pr.id=dp.producto_id
JOIN public.categoria c ON c.id=pr.categoria_id
JOIN public.pedido ped ON ped.id=dp.pedido_id
WHERE ped.fecha >= CURRENT_DATE::timestamptz
  AND ped.fecha < (CURRENT_DATE+1)::timestamptz
  AND ped.eliminado=FALSE
GROUP BY c.nombre
ORDER BY total_vendido DESC
LIMIT 5;

-- 5.2(c): instalacion atomica. Las lecturas fuente pueden continuar.
BEGIN;
LOCK TABLE public.categoria,public.producto,public.pedido,public.detalle_pedido
IN SHARE ROW EXCLUSIVE MODE;

CREATE MATERIALIZED VIEW public.mv_u4_ventas_categoria_dia AS
SELECT (ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS fecha,
       c.nombre AS categoria, SUM(dp.subtotal) AS total_vendido
FROM public.detalle_pedido dp
JOIN public.producto pr ON pr.id=dp.producto_id
JOIN public.categoria c ON c.id=pr.categoria_id
JOIN public.pedido ped ON ped.id=dp.pedido_id
WHERE ped.eliminado=FALSE
GROUP BY (ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,c.nombre;

-- Todas las fechas evitan depender de un refresco especial a medianoche.
-- El nombre, y no el ID, conserva la agrupacion solicitada por la guia.
-- En el proyecto heredado, categoria.nombre tiene ademas restriccion UNIQUE.
CREATE INDEX idx_u4_ventas_categoria_dia_top
ON public.mv_u4_ventas_categoria_dia(fecha,total_vendido DESC);

CREATE FUNCTION public.u4_serializar_ventas()
RETURNS trigger LANGUAGE plpgsql VOLATILE
SET search_path=pg_catalog AS $$
BEGIN
    -- TRUNCATE saltearia los triggers por fila heredados y dejaria pedidos
    -- confirmados sin detalle o total desactualizado. Se rechaza en las cuatro
    -- fuentes; tambien se detiene TRUNCATE ... CASCADE antes de vaciar datos.
    IF TG_OP='TRUNCATE' THEN
        RAISE EXCEPTION
            'TRUNCATE no admitido sobre %.%: preservar detalle, total y estados heredados',
            TG_TABLE_SCHEMA,TG_TABLE_NAME
            USING ERRCODE='23514';
    END IF;
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'La sincronizacion U4 requiere READ COMMITTED'
            USING ERRCODE='25001';
    END IF;
    PERFORM pg_advisory_xact_lock(204620,4);
    RETURN NULL;
END;
$$;

CREATE FUNCTION public.u4_refrescar_ventas()
RETURNS trigger LANGUAGE plpgsql VOLATILE
SET search_path=pg_catalog AS $$
BEGIN
    -- El trigger previo trg_recalcular_total actualiza pedido por cada linea.
    -- Esos UPDATE anidados no deben reconstruir la MV una vez por cada fila:
    -- el AFTER STATEMENT externo de detalle la reconstruye al finalizar.
    -- Esta excepcion se limita al camino heredado conocido detalle -> pedido.
    IF TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME='pedido'
       AND pg_trigger_depth()>1 THEN
        RAISE DEBUG 'U4_REFRESH_SKIPPED table=% depth=%',TG_TABLE_NAME,pg_trigger_depth();
        RETURN NULL;
    END IF;
    RAISE DEBUG 'U4_REFRESH_EXECUTED table=% depth=%',TG_TABLE_NAME,pg_trigger_depth();
    REFRESH MATERIALIZED VIEW public.mv_u4_ventas_categoria_dia;
    RETURN NULL;
END;
$$;

CREATE TRIGGER ventas_bloqueo
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.detalle_pedido
FOR EACH STATEMENT EXECUTE FUNCTION public.u4_serializar_ventas();
CREATE TRIGGER ventas_refresco
AFTER INSERT OR UPDATE OR DELETE ON public.detalle_pedido
FOR EACH STATEMENT EXECUTE FUNCTION public.u4_refrescar_ventas();

CREATE TRIGGER ventas_bloqueo
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.pedido
FOR EACH STATEMENT EXECUTE FUNCTION public.u4_serializar_ventas();
CREATE TRIGGER ventas_refresco
AFTER INSERT OR UPDATE OR DELETE ON public.pedido
FOR EACH STATEMENT EXECUTE FUNCTION public.u4_refrescar_ventas();

CREATE TRIGGER ventas_bloqueo
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.producto
FOR EACH STATEMENT EXECUTE FUNCTION public.u4_serializar_ventas();
CREATE TRIGGER ventas_refresco
AFTER INSERT OR UPDATE OR DELETE ON public.producto
FOR EACH STATEMENT EXECUTE FUNCTION public.u4_refrescar_ventas();

CREATE TRIGGER ventas_bloqueo
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON public.categoria
FOR EACH STATEMENT EXECUTE FUNCTION public.u4_serializar_ventas();
CREATE TRIGGER ventas_refresco
AFTER INSERT OR UPDATE OR DELETE ON public.categoria
FOR EACH STATEMENT EXECUTE FUNCTION public.u4_refrescar_ventas();
COMMIT;
ANALYZE public.mv_u4_ventas_categoria_dia;

-- 5.2(d): consulta del panel: solo el resumen, sin JOIN ni SUM.
EXPLAIN (ANALYZE, BUFFERS)
SELECT categoria,total_vendido
FROM public.mv_u4_ventas_categoria_dia
WHERE fecha=CURRENT_DATE
ORDER BY total_vendido DESC
LIMIT 5;

SELECT categoria,total_vendido
FROM public.mv_u4_ventas_categoria_dia
WHERE fecha=CURRENT_DATE
ORDER BY total_vendido DESC
LIMIT 5;
-- El proyecto conserva sus dos categorias; LIMIT 5 devuelve hasta cinco filas.

-- 5.2(e): auditoria de TODAS las fechas. Resultado esperado: cero filas.
BEGIN ISOLATION LEVEL READ COMMITTED;
DO $$ BEGIN PERFORM pg_advisory_xact_lock(204620,4); END $$;
WITH fuente AS (
    SELECT (ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date AS fecha,
           c.nombre AS categoria,SUM(dp.subtotal) AS total_vendido
    FROM public.detalle_pedido dp
    JOIN public.producto pr ON pr.id=dp.producto_id
    JOIN public.categoria c ON c.id=pr.categoria_id
    JOIN public.pedido ped ON ped.id=dp.pedido_id
    WHERE ped.eliminado=FALSE
    GROUP BY (ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date,c.nombre
), diferencias AS (
    SELECT 'fuente-mv' AS sentido,d.* FROM (
        SELECT * FROM fuente
        EXCEPT ALL
        SELECT fecha,categoria,total_vendido FROM public.mv_u4_ventas_categoria_dia
    ) d
    UNION ALL
    SELECT 'mv-fuente',d.* FROM (
        SELECT fecha,categoria,total_vendido FROM public.mv_u4_ventas_categoria_dia
        EXCEPT ALL
        SELECT * FROM fuente
    ) d
)
SELECT * FROM diferencias;
COMMIT;

-- Comprobacion adicional de la invariante heredada pedido.total.
-- Resultado esperado: cero filas. Incluye pedidos pendientes y eliminados.
WITH totales AS (
    SELECT pedido_id,SUM(subtotal) AS total FROM public.detalle_pedido GROUP BY pedido_id
)
SELECT p.id,p.total AS almacenado,COALESCE(t.total,0) AS calculado
FROM public.pedido p LEFT JOIN totales t ON t.pedido_id=p.id
WHERE p.total IS DISTINCT FROM COALESCE(t.total,0::numeric);

-- La MV mensual y las vistas TP5 se conservan. Su refresco sigue el mecanismo
-- documentado en TP5; esta implementacion mantiene solo el nuevo resumen diario.
-- Reversion: ver reversion_desnormalizacion.sql. Las fuentes y sus restricciones
-- e indices anteriores permanecen disponibles para volver al reporte con JOIN.

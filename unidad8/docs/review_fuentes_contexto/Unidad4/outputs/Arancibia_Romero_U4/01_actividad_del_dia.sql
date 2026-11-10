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

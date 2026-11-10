-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Reversion OPCIONAL de la Parte 2. No ejecutar durante la instalacion.
-- Solo retira objetos U4. Conserva fuentes, historia, reglas e indices TP1-TP5.
\set ON_ERROR_STOP on
DO $$ BEGIN
    IF current_database()<>'foodstore_u4_arancibia_romero' THEN
        RAISE EXCEPTION 'Ejecutar solo en foodstore_u4_arancibia_romero';
    END IF;
END $$;
BEGIN;
LOCK TABLE public.categoria,public.producto,public.pedido,public.detalle_pedido
IN SHARE ROW EXCLUSIVE MODE;
DROP TRIGGER IF EXISTS ventas_bloqueo ON public.detalle_pedido;
DROP TRIGGER IF EXISTS ventas_refresco ON public.detalle_pedido;
DROP TRIGGER IF EXISTS ventas_bloqueo ON public.pedido;
DROP TRIGGER IF EXISTS ventas_refresco ON public.pedido;
DROP TRIGGER IF EXISTS ventas_bloqueo ON public.producto;
DROP TRIGGER IF EXISTS ventas_refresco ON public.producto;
DROP TRIGGER IF EXISTS ventas_bloqueo ON public.categoria;
DROP TRIGGER IF EXISTS ventas_refresco ON public.categoria;
DROP FUNCTION IF EXISTS public.u4_serializar_ventas();
DROP FUNCTION IF EXISTS public.u4_refrescar_ventas();
DROP MATERIALIZED VIEW IF EXISTS public.mv_u4_ventas_categoria_dia;
COMMIT;
-- Volver a la consulta con JOIN y rango diario incluida en el script principal.

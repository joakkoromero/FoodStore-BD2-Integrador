-- Corrección Codex del hallazgo real review_tp2/H-01, comprobado en copia U8.
-- No reemplaza ni modifica las entregas anteriores ni la fuente foodstore.
\set ON_ERROR_STOP on
BEGIN;
DO $guard$
BEGIN
    IF current_database() <> 'foodstore_u8_arancibia_romero' THEN
        RAISE EXCEPTION 'Aplicar exclusivamente en la copia U8 autorizada';
    END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION public.u8_exigir_pedido_pendiente()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $function$
BEGIN
    IF NEW.estado IS DISTINCT FROM 'PENDIENTE'::public.estado_pedido THEN
        RAISE EXCEPTION 'Todo pedido debe crearse en estado PENDIENTE'
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END
$function$;

REVOKE ALL ON FUNCTION public.u8_exigir_pedido_pendiente() FROM PUBLIC;
CREATE OR REPLACE TRIGGER u8_pedido_nace_pendiente
BEFORE INSERT ON public.pedido
FOR EACH ROW EXECUTE FUNCTION public.u8_exigir_pedido_pendiente();
COMMIT;

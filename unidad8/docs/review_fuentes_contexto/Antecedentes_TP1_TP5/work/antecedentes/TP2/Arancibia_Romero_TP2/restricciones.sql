-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- TP2 - Reglas de integridad Food Store
-- Revisar con git diff y ejecutar primero dentro de BEGIN ... ROLLBACK.

CREATE OR REPLACE FUNCTION validar_estado_pedido()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF NOT (
        (OLD.estado = 'PENDIENTE' AND NEW.estado IN ('CONFIRMADO','CANCELADO')) OR
        (OLD.estado = 'CONFIRMADO' AND NEW.estado IN ('ENTREGADO','CANCELADO'))
    ) THEN
        RAISE EXCEPTION 'Transicion de pedido no permitida: % -> %', OLD.estado, NEW.estado
            USING ERRCODE = '23514';
    END IF;

    IF NEW.estado IN ('CONFIRMADO','ENTREGADO')
       AND NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.pedido_id = NEW.id)
    THEN
        RAISE EXCEPTION 'El pedido % no puede pasar a % sin detalle', NEW.id, NEW.estado
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_confirmacion ON pedido;
DROP TRIGGER IF EXISTS trg_validar_estado_pedido ON pedido;
CREATE TRIGGER trg_validar_estado_pedido
BEFORE UPDATE OF estado ON pedido
FOR EACH ROW EXECUTE FUNCTION validar_estado_pedido();

CREATE OR REPLACE FUNCTION validar_detalle_pendiente()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_estado estado_pedido;
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') THEN
        SELECT estado INTO v_estado FROM pedido WHERE id = OLD.pedido_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Pedido inexistente: %', OLD.pedido_id USING ERRCODE = '23503';
        END IF;
        IF v_estado <> 'PENDIENTE' THEN
            RAISE EXCEPTION 'El detalle del pedido % no es editable en estado %', OLD.pedido_id, v_estado
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT','UPDATE') THEN
        SELECT estado INTO v_estado FROM pedido WHERE id = NEW.pedido_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Pedido inexistente: %', NEW.pedido_id USING ERRCODE = '23503';
        END IF;
        IF v_estado <> 'PENDIENTE' THEN
            RAISE EXCEPTION 'El detalle del pedido % no es editable en estado %', NEW.pedido_id, v_estado
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validar_detalle_pendiente ON detalle_pedido;
CREATE TRIGGER trg_validar_detalle_pendiente
BEFORE INSERT OR UPDATE OR DELETE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION validar_detalle_pendiente();

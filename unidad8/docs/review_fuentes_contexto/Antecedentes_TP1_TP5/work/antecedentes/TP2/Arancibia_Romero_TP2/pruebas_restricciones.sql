-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Ejecutar en foodstore_tp2_copia despues de restricciones.sql.
BEGIN;

-- Se guarda el id generado para que la prueba no dependa de una secuencia concreta.
CREATE TEMP TABLE tp2_ctx (pedido_id BIGINT) ON COMMIT DROP;
WITH nuevo AS (
  INSERT INTO pedido (usuario_id, forma_pago) VALUES (1,'EFECTIVO') RETURNING id
)
INSERT INTO tp2_ctx SELECT id FROM nuevo;

-- Invalida: confirmar sin detalle. Debe capturarse SQLSTATE 23514.
DO $$ BEGIN
  BEGIN
    UPDATE pedido SET estado='CONFIRMADO' WHERE id=(SELECT pedido_id FROM tp2_ctx);
    RAISE EXCEPTION 'FALLO: la operacion invalida fue aceptada';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: se rechazo confirmar sin detalle';
  END;
END $$;

-- Valida: agregar detalle y confirmar.
INSERT INTO detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario)
SELECT pedido_id,1,1,1050.00 FROM tp2_ctx;
UPDATE pedido SET estado='CONFIRMADO' WHERE id=(SELECT pedido_id FROM tp2_ctx);

-- Invalida: volver a PENDIENTE.
DO $$ BEGIN
  BEGIN
    UPDATE pedido SET estado='PENDIENTE' WHERE id=(SELECT pedido_id FROM tp2_ctx);
    RAISE EXCEPTION 'FALLO: se permitio retroceder el estado';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: se rechazo CONFIRMADO -> PENDIENTE';
  END;
END $$;

-- Invalida: modificar detalle confirmado.
DO $$ BEGIN
  BEGIN
    UPDATE detalle_pedido SET cantidad=2
     WHERE pedido_id=(SELECT pedido_id FROM tp2_ctx) AND producto_id=1;
    RAISE EXCEPTION 'FALLO: se modifico un detalle confirmado';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'OK: se rechazo modificar detalle no pendiente';
  END;
END $$;

-- Valida: CONFIRMADO -> ENTREGADO.
UPDATE pedido SET estado='ENTREGADO' WHERE id=(SELECT pedido_id FROM tp2_ctx);
SELECT id,estado,total FROM pedido WHERE id=(SELECT pedido_id FROM tp2_ctx);

ROLLBACK; -- primera ejecucion segura; cambiar por COMMIT solo tras revisar.

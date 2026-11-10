-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Medicion reversible de 3.000 INSERT sobre detalle_pedido.
-- Se desactiva temporalmente el trigger de negocio para aislar el costo
-- de escritura e indices; ROLLBACK restaura tanto filas como trigger.
\set ON_ERROR_STOP on
BEGIN;
ALTER TABLE detalle_pedido DISABLE TRIGGER USER;
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, 50000, 1, pr.precio
FROM pedido AS p
JOIN producto AS pr ON pr.id = 50000
WHERE NOT EXISTS (
    SELECT 1 FROM detalle_pedido AS d
    WHERE d.pedido_id = p.id AND d.producto_id = 50000
)
LIMIT 3000;
ROLLBACK;


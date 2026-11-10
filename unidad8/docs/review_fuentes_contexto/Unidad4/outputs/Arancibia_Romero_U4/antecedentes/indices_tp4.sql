-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- La PK existente empieza por pedido_id. Estas consultas parten de producto,
-- por eso se agrega el camino inverso y se cubren las columnas analiticas.
CREATE INDEX idx_tp4_detalle_producto_cobertura
    ON detalle_pedido (producto_id, pedido_id)
    INCLUDE (cantidad, subtotal);

ANALYZE detalle_pedido;

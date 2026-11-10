-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Conserva los indices medidos en TP3 y retira solo los candidatos de TP4.
DROP INDEX IF EXISTS idx_tp4_pedido_fecha_vigente;
DROP INDEX IF EXISTS idx_tp4_detalle_pedido_cobertura;
DROP INDEX IF EXISTS idx_tp4_detalle_producto_cobertura;
DROP INDEX IF EXISTS idx_tp4_descartado_estado;
ANALYZE pedido;
ANALYZE detalle_pedido;

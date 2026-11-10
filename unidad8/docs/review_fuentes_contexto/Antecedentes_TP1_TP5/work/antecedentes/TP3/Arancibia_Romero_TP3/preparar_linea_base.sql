-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Retira solamente los indices de optimizacion para medir la linea base.
-- Las claves primarias y restricciones permanecen activas.
DROP INDEX IF EXISTS idx_producto_categoria;
DROP INDEX IF EXISTS idx_pedido_usuario_fecha;
DROP INDEX IF EXISTS idx_tp3_producto_categoria_precio;
DROP INDEX IF EXISTS idx_tp3_pedido_usuario_fecha;
DROP INDEX IF EXISTS idx_tp3_pedido_estado_fecha;
ANALYZE producto;
ANALYZE pedido;

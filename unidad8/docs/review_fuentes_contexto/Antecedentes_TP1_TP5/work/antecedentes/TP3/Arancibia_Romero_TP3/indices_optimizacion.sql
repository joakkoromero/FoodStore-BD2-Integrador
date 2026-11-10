-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Indices aceptados despues de leer y justificar cada sentencia.
-- Q1: igualdad, rango y orden; parcial porque las consultas omiten borrados.
CREATE INDEX idx_tp3_producto_categoria_precio
    ON producto (categoria_id, precio DESC, id)
    WHERE eliminado = FALSE;

-- Q2: igualdad por usuario y salida ya ordenada por fecha.
CREATE INDEX idx_tp3_pedido_usuario_fecha
    ON pedido (usuario_id, fecha DESC)
    WHERE eliminado = FALSE;

-- Q3: igualdad por estado, rango/orden por fecha y datos de salida incluidos.
CREATE INDEX idx_tp3_pedido_estado_fecha
    ON pedido (estado, fecha DESC)
    INCLUDE (usuario_id, total)
    WHERE eliminado = FALSE;

ANALYZE producto;
ANALYZE pedido;

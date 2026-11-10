-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- TP5 - Parte A: indices aceptados
-- Autores: Exequiel Arancibia y Joaquin Romero
-- PostgreSQL 16+
\set ON_ERROR_STOP on

-- Q1. Indice parcial de expresion: normaliza la fecha a la zona del negocio,
-- excluye filas irrelevantes y cubre las columnas proyectadas.
CREATE INDEX IF NOT EXISTS idx_u3_pedido_fecha_local_entregado
ON pedido ((fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'))
INCLUDE (id, usuario_id, total)
WHERE eliminado = FALSE AND estado = 'ENTREGADO';

-- Q2. Stock primero satisface filtro y orden; id estabiliza el orden.
-- Es parcial porque los productos eliminados no aparecen en el catalogo.
CREATE INDEX IF NOT EXISTS idx_u3_producto_stock_vig
ON producto (stock, id)
INCLUDE (nombre, precio)
WHERE eliminado = FALSE;

-- Q3. La PK existente comienza por pedido_id y no sirve para buscar primero
-- por producto_id. Este orden complementario evita recorrer todo el detalle.
CREATE INDEX IF NOT EXISTS idx_u3_detalle_producto_pedido
ON detalle_pedido (producto_id, pedido_id)
INCLUDE (cantidad, precio_unitario);

ANALYZE pedido;
ANALYZE producto;
ANALYZE detalle_pedido;

-- TP5 - Partes B y C: vistas y vista materializada
-- Autores: Exequiel Arancibia y Joaquin Romero
-- PostgreSQL 16+
\set ON_ERROR_STOP on

-- Catalogo publico: solo productos y categorias vigentes.
CREATE OR REPLACE VIEW v_productos_vigentes_categoria AS
SELECT pr.id AS producto_id,
       pr.nombre AS producto_nombre,
       pr.descripcion,
       pr.precio,
       pr.stock,
       c.id AS categoria_id,
       c.nombre AS categoria_nombre
FROM producto AS pr
JOIN categoria AS c ON c.id = pr.categoria_id
WHERE pr.eliminado = FALSE AND c.eliminado = FALSE;

-- Vista segura: expone contacto, pero nunca usuario.contrasena.
CREATE OR REPLACE VIEW v_pedidos_usuario AS
SELECT p.id AS pedido_id,
       p.fecha,
       p.forma_pago,
       p.estado,
       p.total,
       u.id AS usuario_id,
       u.nombre AS usuario_nombre,
       u.apellido AS usuario_apellido,
       u.email,
       u.telefono
FROM pedido AS p
JOIN usuario AS u ON u.id = p.usuario_id
WHERE p.eliminado = FALSE AND u.eliminado = FALSE;

-- Detalle historico: conserva lineas aunque luego el producto sea dado de baja.
CREATE OR REPLACE VIEW v_detalle_pedido_producto AS
SELECT d.pedido_id,
       d.producto_id,
       pr.nombre AS producto_nombre,
       d.cantidad,
       d.precio_unitario,
       d.subtotal
FROM detalle_pedido AS d
JOIN producto AS pr ON pr.id = d.producto_id;

-- Reporte agregado costoso. DROP permite reproducir el script completo.
DROP MATERIALIZED VIEW IF EXISTS mv_facturacion_categoria_mes;
CREATE MATERIALIZED VIEW mv_facturacion_categoria_mes AS
SELECT c.id AS categoria_id,
       c.nombre AS categoria_nombre,
       date_trunc('month', p.fecha) AS mes,
       count(DISTINCT p.id) AS cantidad_pedidos,
       sum(d.cantidad)::bigint AS unidades,
       sum(d.subtotal)::numeric(16,2) AS facturacion
FROM categoria AS c
JOIN producto AS pr ON pr.categoria_id = c.id
JOIN detalle_pedido AS d ON d.producto_id = pr.id
JOIN pedido AS p ON p.id = d.pedido_id
WHERE p.eliminado = FALSE AND p.estado <> 'CANCELADO'
GROUP BY c.id, c.nombre, date_trunc('month', p.fecha)
WITH DATA;

-- Requisito para futuros REFRESH CONCURRENTLY.
CREATE UNIQUE INDEX ux_mv_facturacion_categoria_mes
ON mv_facturacion_categoria_mes (categoria_id, mes);

ANALYZE mv_facturacion_categoria_mes;

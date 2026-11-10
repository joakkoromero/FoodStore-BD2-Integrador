-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Q1 - Facturacion mensual de una franja del catalogo (4 tablas).
SELECT
    c.id AS categoria_id,
    c.nombre AS categoria,
    date_trunc('month', p.fecha) AS mes,
    count(DISTINCT p.id) AS pedidos,
    sum(d.cantidad) AS unidades,
    sum(d.subtotal) AS facturacion
FROM categoria AS c
JOIN producto AS pr ON pr.categoria_id = c.id
JOIN detalle_pedido AS d ON d.producto_id = pr.id
JOIN pedido AS p ON p.id = d.pedido_id
WHERE c.id = 1
  AND c.eliminado = FALSE
  AND pr.eliminado = FALSE
  AND pr.precio BETWEEN 1500 AND 1520
  AND p.eliminado = FALSE
  AND p.estado <> 'CANCELADO'
GROUP BY c.id, c.nombre, date_trunc('month', p.fecha)
ORDER BY mes, categoria_id;

-- Q2 - Ranking de usuarios por compras de esa franja (5 tablas).
SELECT
    u.id AS usuario_id,
    u.nombre || ' ' || u.apellido AS usuario,
    count(DISTINCT p.id) AS pedidos,
    sum(d.subtotal) AS gasto_total
FROM categoria AS c
JOIN producto AS pr ON pr.categoria_id = c.id
JOIN detalle_pedido AS d ON d.producto_id = pr.id
JOIN pedido AS p ON p.id = d.pedido_id
JOIN usuario AS u ON u.id = p.usuario_id
WHERE c.id = 1
  AND c.eliminado = FALSE
  AND pr.eliminado = FALSE
  AND pr.precio BETWEEN 1500 AND 1520
  AND p.eliminado = FALSE
  AND p.estado <> 'CANCELADO'
  AND u.eliminado = FALSE
GROUP BY u.id, u.nombre, u.apellido
ORDER BY gasto_total DESC, usuario_id
LIMIT 100;

-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Carga de trabajo frecuente usada para medir los indices del TP5.
\set ON_ERROR_STOP on

-- Q1: pedidos entregados de un dia operativo, expresado en hora local.
SELECT id, usuario_id, fecha, total
FROM pedido
WHERE eliminado = FALSE
  AND estado = 'ENTREGADO'
  AND (fecha AT TIME ZONE 'America/Argentina/Buenos_Aires') >= timestamp '2025-04-15 00:00:00'
  AND (fecha AT TIME ZONE 'America/Argentina/Buenos_Aires') <  timestamp '2025-04-16 00:00:00'
ORDER BY (fecha AT TIME ZONE 'America/Argentina/Buenos_Aires');

-- Q2: reposicion de productos vigentes con stock entre 80 y 82.
SELECT id, nombre, precio, stock
FROM producto
WHERE eliminado = FALSE AND stock BETWEEN 80 AND 82
ORDER BY stock, id;

-- Q3: lineas historicas para un intervalo de productos.
SELECT producto_id, pedido_id, cantidad, precio_unitario, subtotal
FROM detalle_pedido
WHERE producto_id BETWEEN 100 AND 120
ORDER BY producto_id, pedido_id;


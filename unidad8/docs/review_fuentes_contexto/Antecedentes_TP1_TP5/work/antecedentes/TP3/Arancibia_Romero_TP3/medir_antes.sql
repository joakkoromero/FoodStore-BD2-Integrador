-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
\set ON_ERROR_STOP on
\pset pager off
\echo 'Q1 ANTES'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT TEXT)
SELECT id, nombre, precio, stock FROM producto
WHERE categoria_id = 1 AND eliminado = FALSE AND precio BETWEEN 1500 AND 3500
ORDER BY precio DESC, id LIMIT 200;

\echo 'Q2 ANTES'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT TEXT)
SELECT id, fecha, estado, forma_pago, total FROM pedido
WHERE usuario_id = 1234 AND eliminado = FALSE
ORDER BY fecha DESC LIMIT 50;

\echo 'Q3 ANTES'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT TEXT)
SELECT id, usuario_id, fecha, total FROM pedido
WHERE estado = 'ENTREGADO' AND eliminado = FALSE
  AND fecha >= timestamptz '2025-04-01 00:00:00-03'
ORDER BY fecha DESC LIMIT 200;

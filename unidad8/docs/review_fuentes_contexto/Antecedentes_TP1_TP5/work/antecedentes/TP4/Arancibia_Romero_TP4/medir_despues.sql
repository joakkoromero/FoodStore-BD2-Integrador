-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
\set ON_ERROR_STOP on
\pset pager off
\echo 'Q1 DESPUES - FACTURACION MENSUAL POR CATEGORIA'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, FORMAT TEXT)
SELECT c.id categoria_id,c.nombre categoria,date_trunc('month',p.fecha) mes,
       count(DISTINCT p.id) pedidos,sum(d.cantidad) unidades,sum(d.subtotal) facturacion
FROM categoria c JOIN producto pr ON pr.categoria_id=c.id
JOIN detalle_pedido d ON d.producto_id=pr.id
JOIN pedido p ON p.id=d.pedido_id
WHERE c.id=1 AND c.eliminado=FALSE AND pr.eliminado=FALSE
  AND pr.precio BETWEEN 1500 AND 1520
  AND p.eliminado=FALSE AND p.estado<>'CANCELADO'
GROUP BY c.id,c.nombre,date_trunc('month',p.fecha)
ORDER BY mes,categoria_id;

\echo 'Q2 DESPUES - RANKING DE USUARIOS'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, FORMAT TEXT)
SELECT u.id usuario_id,u.nombre||' '||u.apellido usuario,
       count(DISTINCT p.id) pedidos,sum(d.subtotal) gasto_total
FROM categoria c JOIN producto pr ON pr.categoria_id=c.id
JOIN detalle_pedido d ON d.producto_id=pr.id
JOIN pedido p ON p.id=d.pedido_id
JOIN usuario u ON u.id=p.usuario_id
WHERE c.id=1 AND c.eliminado=FALSE AND pr.eliminado=FALSE
  AND pr.precio BETWEEN 1500 AND 1520
  AND p.eliminado=FALSE AND p.estado<>'CANCELADO' AND u.eliminado=FALSE
GROUP BY u.id,u.nombre,u.apellido
ORDER BY gasto_total DESC,usuario_id LIMIT 100;

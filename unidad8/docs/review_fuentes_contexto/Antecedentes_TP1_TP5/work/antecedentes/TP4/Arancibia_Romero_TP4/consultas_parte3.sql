-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
\set ON_ERROR_STOP on
\pset pager off

-- PARTE 3A - RANKING CON FUNCION DE VENTANA
-- Spec: para cada categoria vigente, listar productos vigentes que aparezcan
-- en al menos un pedido vigente ENTREGADO. Mostrar categoria, producto,
-- facturacion y posicion dentro de la categoria. DENSE_RANK comparte puesto
-- ante empate de facturacion; devolver puestos 1 a 10 por categoria, con
-- salida por categoria, posicion y producto_id.

-- Version 1: agregar primero y aplicar DENSE_RANK despues.
WITH ventas AS (
    SELECT c.id categoria_id, c.nombre categoria,
           pr.id producto_id, pr.nombre producto,
           sum(d.subtotal) facturacion
    FROM categoria c
    JOIN producto pr ON pr.categoria_id=c.id
    JOIN detalle_pedido d ON d.producto_id=pr.id
    JOIN pedido p ON p.id=d.pedido_id
    WHERE c.eliminado=FALSE AND pr.eliminado=FALSE
      AND p.eliminado=FALSE AND p.estado='ENTREGADO'
    GROUP BY c.id,c.nombre,pr.id,pr.nombre
), ranking_v1 AS (
    SELECT categoria_id,categoria,producto_id,producto,facturacion,
           dense_rank() OVER (PARTITION BY categoria_id ORDER BY facturacion DESC) puesto
    FROM ventas
)
SELECT * FROM ranking_v1
WHERE puesto <= 10
ORDER BY categoria_id,puesto,producto_id;

-- Version 2: suma de ventana sobre filas de detalle, DISTINCT y ranking final.
WITH filas AS (
    SELECT c.id categoria_id,c.nombre categoria,
           pr.id producto_id,pr.nombre producto,
           sum(d.subtotal) OVER (PARTITION BY pr.id) facturacion
    FROM categoria c
    JOIN producto pr ON pr.categoria_id=c.id
    JOIN detalle_pedido d ON d.producto_id=pr.id
    JOIN pedido p ON p.id=d.pedido_id
    WHERE c.eliminado=FALSE AND pr.eliminado=FALSE
      AND p.eliminado=FALSE AND p.estado='ENTREGADO'
), ventas AS (
    SELECT DISTINCT categoria_id,categoria,producto_id,producto,facturacion FROM filas
), ranking_v2 AS (
    SELECT categoria_id,categoria,producto_id,producto,facturacion,
           dense_rank() OVER (PARTITION BY categoria_id ORDER BY facturacion DESC) puesto
    FROM ventas
)
SELECT * FROM ranking_v2
WHERE puesto <= 10
ORDER BY categoria_id,puesto,producto_id;

-- Equivalencia del ranking: ambas direcciones deben dar cero diferencias.
WITH ventas1 AS (
    SELECT c.id categoria_id,c.nombre categoria,pr.id producto_id,pr.nombre producto,
           sum(d.subtotal) facturacion
    FROM categoria c JOIN producto pr ON pr.categoria_id=c.id
    JOIN detalle_pedido d ON d.producto_id=pr.id JOIN pedido p ON p.id=d.pedido_id
    WHERE c.eliminado=FALSE AND pr.eliminado=FALSE AND p.eliminado=FALSE AND p.estado='ENTREGADO'
    GROUP BY c.id,c.nombre,pr.id,pr.nombre
), a AS (
    SELECT *,dense_rank() OVER(PARTITION BY categoria_id ORDER BY facturacion DESC) puesto FROM ventas1
), filas AS (
    SELECT c.id categoria_id,c.nombre categoria,pr.id producto_id,pr.nombre producto,
           sum(d.subtotal) OVER(PARTITION BY pr.id) facturacion
    FROM categoria c JOIN producto pr ON pr.categoria_id=c.id
    JOIN detalle_pedido d ON d.producto_id=pr.id JOIN pedido p ON p.id=d.pedido_id
    WHERE c.eliminado=FALSE AND pr.eliminado=FALSE AND p.eliminado=FALSE AND p.estado='ENTREGADO'
), ventas2 AS (
    SELECT DISTINCT categoria_id,categoria,producto_id,producto,facturacion FROM filas
), b AS (
    SELECT *,dense_rank() OVER(PARTITION BY categoria_id ORDER BY facturacion DESC) puesto FROM ventas2
)
SELECT 'A_MINUS_B' prueba,count(*) diferencias
FROM (SELECT * FROM a WHERE puesto<=10 EXCEPT SELECT * FROM b WHERE puesto<=10) x
UNION ALL
SELECT 'B_MINUS_A',count(*)
FROM (SELECT * FROM b WHERE puesto<=10 EXCEPT SELECT * FROM a WHERE puesto<=10) x;

-- PARTE 3B - SUBCONSULTA CORRELACIONADA
-- Spec: por cada usuario vigente con pedidos vigentes no cancelados, mostrar
-- id, nombre completo, cantidad de pedidos, gasto total y fecha del ultimo
-- pedido. Ordenar gasto DESC e id ASC y mostrar los primeros 20. No usar
-- SELECT * en la salida final.

-- Version 1: tres subconsultas correlacionadas, incluida EXISTS.
WITH correlacionada AS (
    SELECT u.id usuario_id,u.nombre||' '||u.apellido usuario,
           (SELECT count(*) FROM pedido p
            WHERE p.usuario_id=u.id AND p.eliminado=FALSE AND p.estado<>'CANCELADO') pedidos,
           (SELECT sum(p.total) FROM pedido p
            WHERE p.usuario_id=u.id AND p.eliminado=FALSE AND p.estado<>'CANCELADO') gasto_total,
           (SELECT max(p.fecha) FROM pedido p
            WHERE p.usuario_id=u.id AND p.eliminado=FALSE AND p.estado<>'CANCELADO') ultimo_pedido
    FROM usuario u
    WHERE u.eliminado=FALSE
      AND EXISTS (SELECT 1 FROM pedido p
                  WHERE p.usuario_id=u.id AND p.eliminado=FALSE AND p.estado<>'CANCELADO')
)
SELECT usuario_id,usuario,pedidos,gasto_total,ultimo_pedido
FROM correlacionada ORDER BY gasto_total DESC,usuario_id LIMIT 20;

-- Version 2: join y agregacion.
WITH agrupada AS (
    SELECT u.id usuario_id,u.nombre||' '||u.apellido usuario,
           count(*) pedidos,sum(p.total) gasto_total,max(p.fecha) ultimo_pedido
    FROM usuario u JOIN pedido p ON p.usuario_id=u.id
    WHERE u.eliminado=FALSE AND p.eliminado=FALSE AND p.estado<>'CANCELADO'
    GROUP BY u.id,u.nombre,u.apellido
)
SELECT usuario_id,usuario,pedidos,gasto_total,ultimo_pedido
FROM agrupada ORDER BY gasto_total DESC,usuario_id LIMIT 20;

-- Equivalencia de la subconsulta correlacionada y join + agregacion.
WITH a AS (
    SELECT u.id usuario_id,u.nombre||' '||u.apellido usuario,
           (SELECT count(*) FROM pedido p WHERE p.usuario_id=u.id AND p.eliminado=FALSE AND p.estado<>'CANCELADO') pedidos,
           (SELECT sum(p.total) FROM pedido p WHERE p.usuario_id=u.id AND p.eliminado=FALSE AND p.estado<>'CANCELADO') gasto_total,
           (SELECT max(p.fecha) FROM pedido p WHERE p.usuario_id=u.id AND p.eliminado=FALSE AND p.estado<>'CANCELADO') ultimo_pedido
    FROM usuario u WHERE u.eliminado=FALSE
      AND EXISTS (SELECT 1 FROM pedido p WHERE p.usuario_id=u.id AND p.eliminado=FALSE AND p.estado<>'CANCELADO')
), b AS (
    SELECT u.id usuario_id,u.nombre||' '||u.apellido usuario,count(*) pedidos,
           sum(p.total) gasto_total,max(p.fecha) ultimo_pedido
    FROM usuario u JOIN pedido p ON p.usuario_id=u.id
    WHERE u.eliminado=FALSE AND p.eliminado=FALSE AND p.estado<>'CANCELADO'
    GROUP BY u.id,u.nombre,u.apellido
)
SELECT 'A_MINUS_B' prueba,count(*) diferencias FROM (TABLE a EXCEPT TABLE b) x
UNION ALL
SELECT 'B_MINUS_A',count(*) FROM (TABLE b EXCEPT TABLE a) x;

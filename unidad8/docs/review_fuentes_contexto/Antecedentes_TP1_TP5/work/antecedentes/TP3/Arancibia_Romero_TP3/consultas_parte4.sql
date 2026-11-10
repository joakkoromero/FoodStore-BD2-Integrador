-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- PARTE 4A - RESUMEN
-- Spec: por cada categoria vigente, devolver nombre y cantidad de productos
-- vigentes; incluir categorias sin productos, ordenar cantidad DESC y nombre ASC.

-- Version A (generada desde la spec): LEFT JOIN + GROUP BY.
WITH resumen_a AS (
    SELECT c.nombre AS categoria, count(p.id)::bigint AS productos_vigentes
    FROM categoria AS c
    LEFT JOIN producto AS p
      ON p.categoria_id = c.id AND p.eliminado = FALSE
    WHERE c.eliminado = FALSE
    GROUP BY c.id, c.nombre
)
SELECT * FROM resumen_a ORDER BY productos_vigentes DESC, categoria ASC;

-- Version B independiente: subconsulta correlacionada.
WITH resumen_b AS (
    SELECT c.nombre AS categoria,
           (SELECT count(*) FROM producto AS p
            WHERE p.categoria_id = c.id AND p.eliminado = FALSE)::bigint
              AS productos_vigentes
    FROM categoria AS c
    WHERE c.eliminado = FALSE
)
SELECT * FROM resumen_b ORDER BY productos_vigentes DESC, categoria ASC;

-- Equivalencia formal A EXCEPT B y B EXCEPT A: debe devolver cero filas.
WITH a AS (
    SELECT c.nombre categoria, count(p.id)::bigint cantidad
    FROM categoria c LEFT JOIN producto p
      ON p.categoria_id=c.id AND p.eliminado=FALSE
    WHERE c.eliminado=FALSE GROUP BY c.id,c.nombre
), b AS (
    SELECT c.nombre categoria,
           (SELECT count(*) FROM producto p
            WHERE p.categoria_id=c.id AND p.eliminado=FALSE)::bigint cantidad
    FROM categoria c WHERE c.eliminado=FALSE
)
SELECT 'A_MINUS_B' prueba, count(*) diferencias FROM (TABLE a EXCEPT TABLE b) x
UNION ALL
SELECT 'B_MINUS_A', count(*) FROM (TABLE b EXCEPT TABLE a) x;

-- PARTE 4B - SUBCONSULTA
-- Spec: usuarios vigentes cuyo gasto en pedidos vigentes y no cancelados sea
-- superior al promedio de gasto de los usuarios con pedidos; mostrar id, nombre,
-- apellido y gasto, ordenar gasto DESC y limitar a 20.

-- Version A: agregados en CTE y subconsulta escalar para el promedio.
WITH gasto AS (
    SELECT u.id, u.nombre, u.apellido, sum(p.total)::numeric(16,2) gasto_total
    FROM usuario u JOIN pedido p ON p.usuario_id=u.id
    WHERE u.eliminado=FALSE AND p.eliminado=FALSE AND p.estado <> 'CANCELADO'
    GROUP BY u.id,u.nombre,u.apellido
), resultado_a AS (
    SELECT * FROM gasto WHERE gasto_total > (SELECT avg(gasto_total) FROM gasto)
)
SELECT * FROM resultado_a ORDER BY gasto_total DESC, id LIMIT 20;

-- Version B: ventana para calcular el promedio de los mismos grupos.
WITH gasto AS (
    SELECT u.id, u.nombre, u.apellido, sum(p.total)::numeric(16,2) gasto_total
    FROM usuario u JOIN pedido p ON p.usuario_id=u.id
    WHERE u.eliminado=FALSE AND p.eliminado=FALSE AND p.estado <> 'CANCELADO'
    GROUP BY u.id,u.nombre,u.apellido
), resultado_b AS (
    SELECT id,nombre,apellido,gasto_total
    FROM (SELECT gasto.*, avg(gasto_total) OVER () promedio FROM gasto) x
    WHERE gasto_total > promedio
)
SELECT * FROM resultado_b ORDER BY gasto_total DESC, id LIMIT 20;

-- Equivalencia sobre el conjunto completo, sin LIMIT ni orden.
WITH gasto AS (
    SELECT u.id, u.nombre, u.apellido, sum(p.total)::numeric(16,2) gasto_total
    FROM usuario u JOIN pedido p ON p.usuario_id=u.id
    WHERE u.eliminado=FALSE AND p.eliminado=FALSE AND p.estado <> 'CANCELADO'
    GROUP BY u.id,u.nombre,u.apellido
), a AS (
    SELECT id,nombre,apellido,gasto_total FROM gasto
    WHERE gasto_total > (SELECT avg(gasto_total) FROM gasto)
), b AS (
    SELECT id,nombre,apellido,gasto_total
    FROM (SELECT gasto.*, avg(gasto_total) OVER () promedio FROM gasto) x
    WHERE gasto_total > promedio
)
SELECT 'A_MINUS_B' prueba, count(*) diferencias FROM (TABLE a EXCEPT TABLE b) x
UNION ALL
SELECT 'B_MINUS_A', count(*) FROM (TABLE b EXCEPT TABLE a) x;

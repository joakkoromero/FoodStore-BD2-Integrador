-- Ejecutar sentencia por sentencia, conservando la conexion.
-- Los marcadores EXPECT_ERROR corresponden a la sentencia que los contiene.
-- Despues de cada error esperado se ejecuta el ROLLBACK siguiente.
-- No ejecutar este archivo mediante executescript().

-- C1: consulta exclusivamente local, sin conexion PostgreSQL.
SELECT producto_id, nombre, precio_centavos, stock_visto, capturado_en
FROM v_catalogo_disponible
ORDER BY producto_id;

-- C1-COMMIT: encabezado, dos items y solicitud en una sola transaccion.
BEGIN;

INSERT INTO pedido_borrador
    (id_local, usuario_id_servidor, forma_pago, creado_en)
VALUES
    ('10000000-0000-4000-8000-000000000001', 1, 'EFECTIVO',
     '2026-01-01T00:00:00Z');

INSERT INTO item_borrador
    (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT '10000000-0000-4000-8000-000000000001',
       producto_id, 1, precio_centavos
FROM producto_cache
WHERE nombre IN ('U8 - Muzzarella', 'U8 - Empanadas');

INSERT INTO cola_sync
    (solicitud_uuid, id_local, estado, motivo, creada_en)
VALUES
    ('20000000-0000-4000-8000-000000000001',
     '10000000-0000-4000-8000-000000000001',
     'PENDIENTE', '', '2026-01-01T00:00:00Z');

COMMIT;

SELECT
    (SELECT count(*) FROM pedido_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000001') AS esperado_uno,
    (SELECT count(*) = 2 FROM item_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000001') AS esperado_uno,
    (SELECT count(*) FROM cola_sync
     WHERE solicitud_uuid = '20000000-0000-4000-8000-000000000001'
       AND estado = 'PENDIENTE') AS esperado_uno;

-- C1-ROLLBACK: las mismas cuatro clases de escritura quedan revertidas.
BEGIN;

INSERT INTO pedido_borrador
    (id_local, usuario_id_servidor, forma_pago, creado_en)
VALUES
    ('10000000-0000-4000-8000-000000000002', 1, 'TARJETA',
     '2026-01-01T00:00:00Z');

INSERT INTO item_borrador
    (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT '10000000-0000-4000-8000-000000000002',
       producto_id, 1, precio_centavos
FROM producto_cache
WHERE nombre IN ('U8 - Muzzarella', 'U8 - Empanadas');

INSERT INTO cola_sync
    (solicitud_uuid, id_local, estado, motivo, creada_en)
VALUES
    ('20000000-0000-4000-8000-000000000002',
     '10000000-0000-4000-8000-000000000002',
     'PENDIENTE', '', '2026-01-01T00:00:00Z');

ROLLBACK;

SELECT
    (SELECT count(*) FROM pedido_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000002') AS esperado_cero,
    (SELECT count(*) FROM item_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000002') AS esperado_cero,
    (SELECT count(*) FROM cola_sync
     WHERE id_local = '10000000-0000-4000-8000-000000000002') AS esperado_cero;

-- C7-cantidad: debe fallar CHECK; no basta con revertir solo el INSERT.
BEGIN;

INSERT INTO pedido_borrador
    (id_local, usuario_id_servidor, forma_pago, creado_en)
VALUES
    ('10000000-0000-4000-8000-000000000007', 1, 'EFECTIVO',
     '2026-01-01T00:00:00Z');

-- EXPECT_ERROR: SQLITE_CONSTRAINT_CHECK
INSERT INTO item_borrador
    (id_local, producto_id, cantidad, precio_centavos_visto)
SELECT '10000000-0000-4000-8000-000000000007',
       producto_id, 0, precio_centavos
FROM producto_cache
WHERE nombre = 'U8 - Muzzarella';

ROLLBACK;

SELECT
    (SELECT count(*) FROM pedido_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000007') AS esperado_cero,
    (SELECT count(*) FROM item_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000007') AS esperado_cero,
    (SELECT count(*) FROM cola_sync
     WHERE id_local = '10000000-0000-4000-8000-000000000007') AS esperado_cero;

-- C7-fk: -1 no puede existir en producto_cache por su CHECK producto_id > 0.
BEGIN;

INSERT INTO pedido_borrador
    (id_local, usuario_id_servidor, forma_pago, creado_en)
VALUES
    ('10000000-0000-4000-8000-000000000008', 1, 'TRANSFERENCIA',
     '2026-01-01T00:00:00Z');

-- EXPECT_ERROR: SQLITE_CONSTRAINT_FOREIGNKEY
INSERT INTO item_borrador
    (id_local, producto_id, cantidad, precio_centavos_visto)
VALUES
    ('10000000-0000-4000-8000-000000000008', -1, 1, 900000);

ROLLBACK;

SELECT
    (SELECT count(*) FROM pedido_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000008') AS esperado_cero,
    (SELECT count(*) FROM item_borrador
     WHERE id_local = '10000000-0000-4000-8000-000000000008') AS esperado_cero,
    (SELECT count(*) FROM cola_sync
     WHERE id_local = '10000000-0000-4000-8000-000000000008') AS esperado_cero;

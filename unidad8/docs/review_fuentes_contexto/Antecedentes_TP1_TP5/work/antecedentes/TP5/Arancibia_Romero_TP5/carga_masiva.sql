-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Carga masiva deterministica heredada para reproducir el TP5
-- Autores: Exequiel Arancibia y Joaquin Romero
-- Ejecutar UNICAMENTE sobre la copia llamada foodstore_tp5_copia.
\set ON_ERROR_STOP on

DO $$
BEGIN
    IF current_database() <> 'DATO_FICTICIO_SANEADO_4313744fc826' THEN
        RAISE EXCEPTION 'DATO_FICTICIO_SANEADO_2cf6320f3975', current_database();
    END IF;
END $$;

BEGIN;

-- Completa 50.000 productos (los tres primeros provienen de data.sql).
INSERT INTO producto (nombre, descripcion, precio, stock, categoria_id)
SELECT
    'DATO_FICTICIO_SANEADO_90f120a4f31a' || gs,
    'DATO_FICTICIO_SANEADO_759a09791a08',
    (500 + (gs * 37 % 4501))::numeric(12,2),
    (gs * 13 % 201)::integer,
    CASE WHEN gs % 2 = 0 THEN 1 ELSE 2 END
FROM generate_series(4, 50000) AS gs;

-- Completa 20.000 usuarios (los tres primeros provienen de data.sql).
INSERT INTO usuario (nombre, apellido, email, contrasena, telefono)
SELECT
    'DATO_FICTICIO_SANEADO_63614ffde2d3' || gs,
    'DATO_FICTICIO_SANEADO_ac3f091ca341' || gs,
    'DATO_FICTICIO_SANEADO_9250e222c4c7' || gs || 'DATO_FICTICIO_SANEADO_9b8f410bd2f9',
    'DATO_FICTICIO_SANEADO_72bdd6a25e22' || gs,
    '0' || lpad(gs::text, 7, '0')
FROM generate_series(4, 20000) AS gs;

-- Completa 200.000 pedidos. Se crean PENDIENTES para respetar la regla
-- que impide confirmar un pedido sin detalle.
INSERT INTO pedido (usuario_id, fecha, forma_pago)
SELECT
    ((gs - 1) % 20000) + 1,
    timestamptz '2025-01-01 00:00:00-03' + (gs % 525600) * interval 'DATO_FICTICIO_SANEADO_e67b6f61f579',
    CASE gs % 3
        WHEN 0 THEN 'EFECTIVO'::forma_pago
        WHEN 1 THEN 'TARJETA'::forma_pago
        ELSE 'TRANSFERENCIA'::forma_pago
    END
FROM generate_series(6, 200000) AS gs;

-- Durante la carga por lotes se pausa el recalculo fila a fila. La integridad
-- se recompone antes del COMMIT y se verifica al final.
ALTER TABLE detalle_pedido DISABLE TRIGGER USER;

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario)
SELECT p.id, x.producto_id, x.cantidad, pr.precio
FROM pedido AS p
CROSS JOIN LATERAL (
    VALUES
      (((p.id * 17) % 50000) + 1, ((p.id % 3) + 1)::integer),
      (((p.id * 17 + 7919) % 50000) + 1, (((p.id + 1) % 3) + 1)::integer)
) AS x(producto_id, cantidad)
JOIN producto AS pr ON pr.id = x.producto_id
WHERE p.id >= 6;

UPDATE pedido AS p
SET total = t.total
FROM (
    SELECT pedido_id, SUM(subtotal) AS total
    FROM detalle_pedido
    WHERE pedido_id >= 6
    GROUP BY pedido_id
) AS t
WHERE p.id = t.pedido_id;

ALTER TABLE detalle_pedido ENABLE TRIGGER USER;

-- Estados reproducibles: 10% queda pendiente, el resto se confirma y una
-- parte se entrega en una segunda transicion valida.
UPDATE pedido
SET estado = 'CONFIRMADO'
WHERE id >= 6 AND id % 10 <> 0;

UPDATE pedido
SET estado = 'ENTREGADO'
WHERE id >= 6 AND estado = 'CONFIRMADO' AND id % 4 IN (0, 1);

COMMIT;

ANALYZE categoria;
ANALYZE producto;
ANALYZE usuario;
ANALYZE pedido;
ANALYZE detalle_pedido;

-- Controles esperados: 2 categorias, 50.000 productos, 20.000 usuarios,
-- 200.000 pedidos y 399.997 detalles (7 originales + 2 por pedido nuevo).
SELECT 'DATO_FICTICIO_SANEADO_01da6a6ca507' AS tabla, count(*) AS filas FROM categoria
UNION ALL SELECT 'DATO_FICTICIO_SANEADO_85dc0c638f09', count(*) FROM producto
UNION ALL SELECT 'DATO_FICTICIO_SANEADO_9250e222c4c7', count(*) FROM usuario
UNION ALL SELECT 'DATO_FICTICIO_SANEADO_ca012797c0da', count(*) FROM pedido
UNION ALL SELECT 'DATO_FICTICIO_SANEADO_d7e868ff9156', count(*) FROM detalle_pedido
ORDER BY tabla;

SELECT count(*) AS pedidos_con_total_incorrecto
FROM pedido AS p
WHERE p.total <> COALESCE((
    SELECT SUM(d.subtotal) FROM detalle_pedido AS d WHERE d.pedido_id = p.id
), 0);

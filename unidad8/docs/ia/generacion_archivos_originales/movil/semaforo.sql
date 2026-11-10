PRAGMA foreign_keys = ON;

BEGIN IMMEDIATE;

-- Solo se consultan tablas SQLite. La fecha local es diagnostica,
-- nunca determina vigencia, disponibilidad ni autoridad del snapshot.
WITH
evaluacion_item AS (
    SELECT
        i.id_local,
        i.producto_id,
        CASE
            WHEN s.producto_id IS NULL THEN
                printf('producto_id=%lld ausente de snapshot_servidor',
                       i.producto_id)
            WHEN s.eliminado = 1 THEN
                printf('producto_id=%lld dado de baja', i.producto_id)
            WHEN s.stock = 0 THEN
                printf('producto_id=%lld sin stock: solicitado=%lld disponible=0',
                       i.producto_id, i.cantidad)
            WHEN i.cantidad > s.stock THEN
                printf(
                    'producto_id=%lld stock insuficiente: solicitado=%lld disponible=%lld',
                    i.producto_id, i.cantidad, s.stock
                )
            WHEN s.disponible <> 1 THEN
                printf('producto_id=%lld no disponible en snapshot_servidor',
                       i.producto_id)
            ELSE NULL
        END AS rojo,
        CASE
            WHEN s.producto_id IS NOT NULL
             AND i.precio_centavos_visto <> s.precio_centavos THEN
                printf(
                    'producto_id=%lld precio distinto: visto=%lld servidor=%lld centavos',
                    i.producto_id,
                    i.precio_centavos_visto,
                    s.precio_centavos
                )
            ELSE NULL
        END AS amarillo
    FROM item_borrador AS i
    LEFT JOIN snapshot_servidor AS s
        ON s.producto_id = i.producto_id
),
resumen AS (
    SELECT
        b.id_local,
        count(e.producto_id) AS cantidad_items,
        count(e.rojo) AS rojos,
        count(e.amarillo) AS amarillos,
        group_concat(e.rojo, '; ') AS motivos_rojos,
        group_concat(e.amarillo, '; ') AS motivos_amarillos
    FROM pedido_borrador AS b
    LEFT JOIN evaluacion_item AS e ON e.id_local = b.id_local
    GROUP BY b.id_local
),
resultado AS (
    SELECT
        id_local,
        CASE
            WHEN cantidad_items = 0 OR rojos > 0 THEN 'RECHAZADO'
            WHEN amarillos > 0 THEN 'CONFLICTO'
            ELSE 'SIMULADO_APROBADO'
        END AS estado,
        CASE
            WHEN cantidad_items = 0 THEN 'borrador vacio'
            WHEN rojos > 0 THEN motivos_rojos
            WHEN amarillos > 0 THEN motivos_amarillos
            ELSE 'Sin conflictos en snapshot; simulacion local, no es una venta'
        END AS motivo
    FROM resumen
)
UPDATE cola_sync
SET estado = (
        SELECT r.estado FROM resultado AS r
        WHERE r.id_local = cola_sync.id_local
    ),
    motivo = (
        SELECT r.motivo FROM resultado AS r
        WHERE r.id_local = cola_sync.id_local
    ),
    evaluado_en = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
WHERE estado = 'PENDIENTE';

COMMIT;

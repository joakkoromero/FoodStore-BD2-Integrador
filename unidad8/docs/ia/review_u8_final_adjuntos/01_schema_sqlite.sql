PRAGMA foreign_keys = ON;

BEGIN;

CREATE TABLE producto_cache (
    producto_id INTEGER PRIMARY KEY CHECK (producto_id > 0),
    nombre TEXT NOT NULL CHECK (length(trim(nombre)) > 0),
    precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
    stock_visto INTEGER NOT NULL CHECK (stock_visto >= 0),
    disponible_visto INTEGER NOT NULL CHECK (disponible_visto IN (0, 1)),
    eliminado INTEGER NOT NULL CHECK (eliminado IN (0, 1)),
    capturado_en TEXT NOT NULL CHECK (length(capturado_en) > 0)
) STRICT;

CREATE TABLE pedido_borrador (
    id_local TEXT PRIMARY KEY NOT NULL CHECK (
        length(id_local) = 36
        AND substr(id_local, 9, 1) = '-'
        AND substr(id_local, 14, 1) = '-'
        AND substr(id_local, 19, 1) = '-'
        AND substr(id_local, 24, 1) = '-'
        AND length(replace(id_local, '-', '')) = 32
        AND replace(id_local, '-', '') NOT GLOB '*[^0-9a-fA-F]*'
    ),
    usuario_id_servidor INTEGER NOT NULL CHECK (usuario_id_servidor > 0),
    forma_pago TEXT NOT NULL CHECK (
        forma_pago IN ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA')
    ),
    creado_en TEXT NOT NULL CHECK (length(creado_en) > 0)
) STRICT;

CREATE TABLE item_borrador (
    id_local TEXT NOT NULL REFERENCES pedido_borrador(id_local),
    producto_id INTEGER NOT NULL REFERENCES producto_cache(producto_id),
    cantidad INTEGER NOT NULL CHECK (cantidad > 0),
    precio_centavos_visto INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),
    PRIMARY KEY (id_local, producto_id)
) STRICT;

CREATE TABLE cola_sync (
    solicitud_uuid TEXT PRIMARY KEY NOT NULL CHECK (
        length(solicitud_uuid) = 36
        AND substr(solicitud_uuid, 9, 1) = '-'
        AND substr(solicitud_uuid, 14, 1) = '-'
        AND substr(solicitud_uuid, 19, 1) = '-'
        AND substr(solicitud_uuid, 24, 1) = '-'
        AND length(replace(solicitud_uuid, '-', '')) = 32
        AND replace(solicitud_uuid, '-', '') NOT GLOB '*[^0-9a-fA-F]*'
    ),
    id_local TEXT NOT NULL REFERENCES pedido_borrador(id_local),
    estado TEXT NOT NULL CHECK (
        estado IN ('PENDIENTE', 'CONFLICTO', 'RECHAZADO', 'SIMULADO_APROBADO')
    ),
    motivo TEXT NOT NULL DEFAULT '',
    creada_en TEXT NOT NULL CHECK (length(creada_en) > 0),
    evaluado_en TEXT
) STRICT;

CREATE UNIQUE INDEX uq_cola_sync_pendiente
    ON cola_sync(id_local)
    WHERE estado = 'PENDIENTE';

-- Auxiliar no STRICT. El importador valida el CSV y normaliza t/f a 1/0.
CREATE TABLE snapshot_servidor (
    producto_id INTEGER PRIMARY KEY CHECK (producto_id > 0),
    nombre TEXT NOT NULL,
    precio_centavos INTEGER NOT NULL CHECK (
        typeof(precio_centavos) = 'integer' AND precio_centavos >= 0
    ),
    stock INTEGER NOT NULL CHECK (typeof(stock) = 'integer' AND stock >= 0),
    disponible INTEGER NOT NULL CHECK (
        typeof(disponible) = 'integer' AND disponible IN (0, 1)
    ),
    eliminado INTEGER NOT NULL CHECK (
        typeof(eliminado) = 'integer' AND eliminado IN (0, 1)
    ),
    capturado_en TEXT NOT NULL CHECK (length(capturado_en) > 0)
);

CREATE VIEW v_catalogo_disponible AS
SELECT producto_id, nombre, precio_centavos, stock_visto, capturado_en
FROM producto_cache
WHERE eliminado = 0
  AND disponible_visto = 1
  AND stock_visto > 0;

COMMIT;

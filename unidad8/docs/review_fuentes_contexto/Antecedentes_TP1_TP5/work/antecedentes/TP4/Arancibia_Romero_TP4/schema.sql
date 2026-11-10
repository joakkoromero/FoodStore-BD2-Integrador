-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Food Store - Esquema base reutilizado en TP4
-- Exequiel Arancibia / Joaquin Romero
-- PostgreSQL 16+
BEGIN;

DROP TABLE IF EXISTS detalle_pedido, pedido, producto, usuario, categoria CASCADE;
DROP TYPE IF EXISTS forma_pago, estado_pedido CASCADE;

CREATE TYPE forma_pago AS ENUM ('EFECTIVO', 'TARJETA', 'TRANSFERENCIA');
CREATE TYPE estado_pedido AS ENUM ('PENDIENTE', 'CONFIRMADO', 'ENTREGADO', 'CANCELADO');

CREATE TABLE categoria (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR(60)  NOT NULL UNIQUE,
    descripcion VARCHAR(255),
    eliminado   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE producto (
    id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre       VARCHAR(120) NOT NULL,
    descripcion  VARCHAR(255),
    precio       NUMERIC(12,2) NOT NULL,
    stock        INTEGER       NOT NULL DEFAULT 0,
    categoria_id BIGINT        NOT NULL
        REFERENCES categoria(id) ON DELETE RESTRICT,
    eliminado    BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at   TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT ck_producto_precio CHECK (precio >= 0),
    CONSTRAINT ck_producto_stock CHECK (stock >= 0)
);

CREATE TABLE usuario (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre      VARCHAR(60)  NOT NULL,
    apellido    VARCHAR(60)  NOT NULL,
    email       VARCHAR(120) NOT NULL UNIQUE,
    contrasena  VARCHAR(255) NOT NULL,
    telefono    VARCHAR(30),
    eliminado   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_usuario_email CHECK (
        position('@' in email) > 1 AND position('.' in split_part(email,'@',2)) > 1
    )
);

CREATE TABLE pedido (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    usuario_id  BIGINT        NOT NULL
        REFERENCES usuario(id) ON DELETE RESTRICT,
    fecha       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    forma_pago  forma_pago    NOT NULL,
    estado      estado_pedido NOT NULL DEFAULT 'PENDIENTE',
    total       NUMERIC(14,2) NOT NULL DEFAULT 0,
    eliminado   BOOLEAN       NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT ck_pedido_total CHECK (total >= 0)
);

CREATE TABLE detalle_pedido (
    pedido_id       BIGINT NOT NULL
        REFERENCES pedido(id) ON DELETE RESTRICT,
    producto_id     BIGINT NOT NULL
        REFERENCES producto(id) ON DELETE RESTRICT,
    cantidad        INTEGER       NOT NULL,
    precio_unitario NUMERIC(12,2) NOT NULL,
    subtotal        NUMERIC(14,2)
        GENERATED ALWAYS AS (cantidad * precio_unitario) STORED,
    PRIMARY KEY (pedido_id, producto_id),
    CONSTRAINT ck_detalle_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_detalle_precio CHECK (precio_unitario >= 0)
);

-- Mantiene pedido.total igual a la suma de sus lineas.
CREATE OR REPLACE FUNCTION recalcular_total_pedido()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_pedido BIGINT;
BEGIN
    v_pedido := COALESCE(NEW.pedido_id, OLD.pedido_id);
    UPDATE pedido
       SET total = COALESCE((SELECT SUM(subtotal)
                               FROM detalle_pedido
                              WHERE pedido_id = v_pedido), 0)
     WHERE id = v_pedido;
    IF TG_OP = 'UPDATE' AND OLD.pedido_id <> NEW.pedido_id THEN
        UPDATE pedido
           SET total = COALESCE((SELECT SUM(subtotal)
                                   FROM detalle_pedido
                                  WHERE pedido_id = OLD.pedido_id), 0)
         WHERE id = OLD.pedido_id;
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_recalcular_total
AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido
FOR EACH ROW EXECUTE FUNCTION recalcular_total_pedido();

-- Un pedido puede estar vacio solo mientras permanece PENDIENTE.
CREATE OR REPLACE FUNCTION validar_confirmacion_pedido()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.estado IN ('CONFIRMADO', 'ENTREGADO')
       AND NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.pedido_id = NEW.id)
    THEN
        RAISE EXCEPTION 'El pedido % no puede confirmarse sin detalle', NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validar_confirmacion
BEFORE INSERT OR UPDATE OF estado ON pedido
FOR EACH ROW EXECUTE FUNCTION validar_confirmacion_pedido();

-- Acelera el catalogo de productos por categoria.
CREATE INDEX idx_producto_categoria ON producto (categoria_id);
-- Acelera el historial cronologico de pedidos de un usuario.
CREATE INDEX idx_pedido_usuario_fecha ON pedido (usuario_id, fecha DESC);

COMMIT;

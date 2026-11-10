--
-- PostgreSQL database dump
--

\restrict NhjHRfMM2ka2gSmlONQZZgIfdqCDy5cKBvcFvgu1ecEeTiiREV9hIMB6VoduIju

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: crypto; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA crypto;


--
-- Name: datos_anon; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA datos_anon;


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA crypto;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: estado_pedido; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.estado_pedido AS ENUM (
    'PENDIENTE',
    'CONFIRMADO',
    'ENTREGADO',
    'CANCELADO'
);


--
-- Name: forma_pago; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.forma_pago AS ENUM (
    'EFECTIVO',
    'TARJETA',
    'TRANSFERENCIA'
);


--
-- Name: bloquear_control_lote(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bloquear_control_lote() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE public.guardia_control_lote
    SET turno = NOT turno
    WHERE id = 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Falta la fila de sincronización de control de lotes';
    END IF;

    RETURN NULL; -- En un trigger de sentencia se ignora el valor de retorno.
END
$$;


--
-- Name: recalcular_total_pedido(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recalcular_total_pedido() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: u4_refrescar_ventas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.u4_refrescar_ventas() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
BEGIN
    -- El trigger previo trg_recalcular_total actualiza pedido por cada linea.
    -- Esos UPDATE anidados no deben reconstruir la MV una vez por cada fila:
    -- el AFTER STATEMENT externo de detalle la reconstruye al finalizar.
    -- Esta excepcion se limita al camino heredado conocido detalle -> pedido.
    IF TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME='pedido'
       AND pg_trigger_depth()>1 THEN
        RAISE DEBUG 'U4_REFRESH_SKIPPED table=% depth=%',TG_TABLE_NAME,pg_trigger_depth();
        RETURN NULL;
    END IF;
    RAISE DEBUG 'U4_REFRESH_EXECUTED table=% depth=%',TG_TABLE_NAME,pg_trigger_depth();
    REFRESH MATERIALIZED VIEW public.mv_u4_ventas_categoria_dia;
    RETURN NULL;
END;
$$;


--
-- Name: u4_serializar_ventas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.u4_serializar_ventas() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'pg_catalog'
    AS $$
BEGIN
    -- TRUNCATE saltearia los triggers por fila heredados y dejaria pedidos
    -- confirmados sin detalle o total desactualizado. Se rechaza en las cuatro
    -- fuentes; tambien se detiene TRUNCATE ... CASCADE antes de vaciar datos.
    IF TG_OP='TRUNCATE' THEN
        RAISE EXCEPTION 'TRUNCATE no admitido sobre %.%: preservar detalle, total y estados heredados', TG_TABLE_SCHEMA,TG_TABLE_NAME
            USING ERRCODE='23514';
    END IF;
    IF current_setting('transaction_isolation') <> 'read committed' THEN
        RAISE EXCEPTION 'La sincronizacion U4 requiere READ COMMITTED'
            USING ERRCODE='25001';
    END IF;
    PERFORM pg_advisory_xact_lock(204620,4);
    RETURN NULL;
END;
$$;


--
-- Name: validar_confirmacion_pedido(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_confirmacion_pedido() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.estado IN ('CONFIRMADO', 'ENTREGADO')
       AND NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.pedido_id = NEW.id)
    THEN
        RAISE EXCEPTION 'El pedido % no puede confirmarse sin detalle', NEW.id;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: validar_detalle_pendiente(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_detalle_pendiente() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_estado estado_pedido;
BEGIN
    IF TG_OP IN ('UPDATE','DELETE') THEN
        SELECT estado INTO v_estado FROM pedido WHERE id = OLD.pedido_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Pedido inexistente: %', OLD.pedido_id USING ERRCODE = '23503';
        END IF;
        IF v_estado <> 'PENDIENTE' THEN
            RAISE EXCEPTION 'El detalle del pedido % no es editable en estado %', OLD.pedido_id, v_estado
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF TG_OP IN ('INSERT','UPDATE') THEN
        SELECT estado INTO v_estado FROM pedido WHERE id = NEW.pedido_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'Pedido inexistente: %', NEW.pedido_id USING ERRCODE = '23503';
        END IF;
        IF v_estado <> 'PENDIENTE' THEN
            RAISE EXCEPTION 'El detalle del pedido % no es editable en estado %', NEW.pedido_id, v_estado
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END;
$$;


--
-- Name: validar_estado_pedido(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.validar_estado_pedido() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.estado = OLD.estado THEN
        RETURN NEW;
    END IF;

    IF NOT (
        (OLD.estado = 'PENDIENTE' AND NEW.estado IN ('CONFIRMADO','CANCELADO')) OR
        (OLD.estado = 'CONFIRMADO' AND NEW.estado IN ('ENTREGADO','CANCELADO'))
    ) THEN
        RAISE EXCEPTION 'Transicion de pedido no permitida: % -> %', OLD.estado, NEW.estado
            USING ERRCODE = '23514';
    END IF;

    IF NEW.estado IN ('CONFIRMADO','ENTREGADO')
       AND NOT EXISTS (SELECT 1 FROM detalle_pedido d WHERE d.pedido_id = NEW.id)
    THEN
        RAISE EXCEPTION 'El pedido % no puede pasar a % sin detalle', NEW.id, NEW.estado
            USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: verificar_control_lote(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.verificar_control_lote() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF EXISTS (
        SELECT lr.lote_id, rd.deposito_id
        FROM public.lote_responsable AS lr
        JOIN public.responsable_deposito AS rd
            USING (responsable_control_id)
        GROUP BY lr.lote_id, rd.deposito_id
        HAVING COUNT(*) > 1
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23505',
            MESSAGE = 'Ya existe otro responsable para el mismo lote y depósito';
    END IF;

    RETURN NULL;
END
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: usuario_anon; Type: TABLE; Schema: datos_anon; Owner: -
--

CREATE TABLE datos_anon.usuario_anon (
    folio bigint NOT NULL,
    nombre text NOT NULL,
    apellido text NOT NULL,
    email text NOT NULL,
    mes_alta date NOT NULL,
    eliminado boolean NOT NULL,
    CONSTRAINT usuario_anon_folio_check CHECK ((folio > 0))
);


--
-- Name: categoria; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categoria (
    id bigint NOT NULL,
    nombre character varying(60) NOT NULL,
    descripcion character varying(255),
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: categoria_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.categoria ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.categoria_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: lote_responsable; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lote_responsable (
    lote_id bigint NOT NULL,
    responsable_control_id bigint NOT NULL
);


--
-- Name: responsable_deposito; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.responsable_deposito (
    responsable_control_id bigint NOT NULL,
    deposito_id bigint NOT NULL
);


--
-- Name: control_lote_almacen; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.control_lote_almacen AS
 SELECT lote_responsable.lote_id,
    responsable_deposito.deposito_id,
    lote_responsable.responsable_control_id
   FROM (public.lote_responsable
     JOIN public.responsable_deposito USING (responsable_control_id));


--
-- Name: control_lote_almacen_original; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.control_lote_almacen_original (
    lote_id bigint NOT NULL,
    deposito_id bigint NOT NULL,
    responsable_control_id bigint NOT NULL
);


--
-- Name: deposito; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.deposito (
    id bigint NOT NULL,
    nombre character varying(120) NOT NULL
);


--
-- Name: detalle_pedido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.detalle_pedido (
    pedido_id bigint NOT NULL,
    producto_id bigint NOT NULL,
    cantidad integer NOT NULL,
    precio_unitario numeric(12,2) NOT NULL,
    subtotal numeric(14,2) GENERATED ALWAYS AS (((cantidad)::numeric * precio_unitario)) STORED,
    CONSTRAINT ck_detalle_cantidad CHECK ((cantidad > 0)),
    CONSTRAINT ck_detalle_precio CHECK ((precio_unitario >= (0)::numeric))
);


--
-- Name: guardia_control_lote; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.guardia_control_lote (
    id smallint NOT NULL,
    turno boolean NOT NULL,
    CONSTRAINT guardia_control_lote_id_check CHECK ((id = 1))
);


--
-- Name: lote; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lote (
    id bigint NOT NULL,
    codigo character varying(40) NOT NULL
);


--
-- Name: pedido; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pedido (
    id bigint NOT NULL,
    usuario_id bigint NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    forma_pago public.forma_pago NOT NULL,
    estado public.estado_pedido DEFAULT 'PENDIENTE'::public.estado_pedido NOT NULL,
    total numeric(14,2) DEFAULT 0 NOT NULL,
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_pedido_total CHECK ((total >= (0)::numeric))
);


--
-- Name: producto; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.producto (
    id bigint NOT NULL,
    nombre character varying(120) NOT NULL,
    descripcion character varying(255),
    precio numeric(12,2) NOT NULL,
    stock integer DEFAULT 0 NOT NULL,
    categoria_id bigint NOT NULL,
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_producto_precio CHECK ((precio >= (0)::numeric)),
    CONSTRAINT ck_producto_stock CHECK ((stock >= 0))
);


--
-- Name: mv_facturacion_categoria_mes; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_facturacion_categoria_mes AS
 SELECT c.id AS categoria_id,
    c.nombre AS categoria_nombre,
    date_trunc('month'::text, p.fecha) AS mes,
    count(DISTINCT p.id) AS cantidad_pedidos,
    sum(d.cantidad) AS unidades,
    (sum(d.subtotal))::numeric(16,2) AS facturacion
   FROM (((public.categoria c
     JOIN public.producto pr ON ((pr.categoria_id = c.id)))
     JOIN public.detalle_pedido d ON ((d.producto_id = pr.id)))
     JOIN public.pedido p ON ((p.id = d.pedido_id)))
  WHERE ((p.eliminado = false) AND (p.estado <> 'CANCELADO'::public.estado_pedido))
  GROUP BY c.id, c.nombre, (date_trunc('month'::text, p.fecha))
  WITH NO DATA;


--
-- Name: mv_u4_ventas_categoria_dia; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_u4_ventas_categoria_dia AS
 SELECT ((ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'::text))::date AS fecha,
    c.nombre AS categoria,
    sum(dp.subtotal) AS total_vendido
   FROM (((public.detalle_pedido dp
     JOIN public.producto pr ON ((pr.id = dp.producto_id)))
     JOIN public.categoria c ON ((c.id = pr.categoria_id)))
     JOIN public.pedido ped ON ((ped.id = dp.pedido_id)))
  WHERE (ped.eliminado = false)
  GROUP BY (((ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'::text))::date), c.nombre
  WITH NO DATA;


--
-- Name: pedido_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.pedido ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.pedido_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: producto_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.producto ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.producto_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: usuario; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usuario (
    id bigint NOT NULL,
    nombre character varying(60) NOT NULL,
    apellido character varying(60) NOT NULL,
    email character varying(120) NOT NULL,
    contrasena character varying(255) NOT NULL,
    telefono character varying(30),
    eliminado boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ck_usuario_email CHECK (((POSITION(('@'::text) IN (email)) > 1) AND (POSITION(('.'::text) IN (split_part((email)::text, '@'::text, 2))) > 1)))
);


--
-- Name: usuario_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.usuario ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.usuario_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_detalle_pedido_producto; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_detalle_pedido_producto AS
 SELECT d.pedido_id,
    d.producto_id,
    pr.nombre AS producto_nombre,
    d.cantidad,
    d.precio_unitario,
    d.subtotal
   FROM (public.detalle_pedido d
     JOIN public.producto pr ON ((pr.id = d.producto_id)));


--
-- Name: v_pedidos_usuario; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_pedidos_usuario AS
 SELECT p.id AS pedido_id,
    p.fecha,
    p.forma_pago,
    p.estado,
    p.total,
    u.id AS usuario_id,
    u.nombre AS usuario_nombre,
    u.apellido AS usuario_apellido,
    u.email,
    u.telefono
   FROM (public.pedido p
     JOIN public.usuario u ON ((u.id = p.usuario_id)))
  WHERE ((p.eliminado = false) AND (u.eliminado = false));


--
-- Name: v_productos_vigentes_categoria; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_productos_vigentes_categoria AS
 SELECT pr.id AS producto_id,
    pr.nombre AS producto_nombre,
    pr.descripcion,
    pr.precio,
    pr.stock,
    c.id AS categoria_id,
    c.nombre AS categoria_nombre
   FROM (public.producto pr
     JOIN public.categoria c ON ((c.id = pr.categoria_id)))
  WHERE ((pr.eliminado = false) AND (c.eliminado = false));


--
-- Name: usuario_anon usuario_anon_pkey; Type: CONSTRAINT; Schema: datos_anon; Owner: -
--

ALTER TABLE ONLY datos_anon.usuario_anon
    ADD CONSTRAINT usuario_anon_pkey PRIMARY KEY (folio);


--
-- Name: categoria categoria_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria
    ADD CONSTRAINT categoria_nombre_key UNIQUE (nombre);


--
-- Name: categoria categoria_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categoria
    ADD CONSTRAINT categoria_pkey PRIMARY KEY (id);


--
-- Name: control_lote_almacen_original control_lote_almacen_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.control_lote_almacen_original
    ADD CONSTRAINT control_lote_almacen_pkey PRIMARY KEY (lote_id, deposito_id);


--
-- Name: deposito deposito_nombre_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposito
    ADD CONSTRAINT deposito_nombre_key UNIQUE (nombre);


--
-- Name: deposito deposito_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.deposito
    ADD CONSTRAINT deposito_pkey PRIMARY KEY (id);


--
-- Name: detalle_pedido detalle_pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_pedido
    ADD CONSTRAINT detalle_pedido_pkey PRIMARY KEY (pedido_id, producto_id);


--
-- Name: guardia_control_lote guardia_control_lote_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.guardia_control_lote
    ADD CONSTRAINT guardia_control_lote_pkey PRIMARY KEY (id);


--
-- Name: lote lote_codigo_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote
    ADD CONSTRAINT lote_codigo_key UNIQUE (codigo);


--
-- Name: lote lote_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote
    ADD CONSTRAINT lote_pkey PRIMARY KEY (id);


--
-- Name: lote_responsable lote_responsable_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_responsable
    ADD CONSTRAINT lote_responsable_pkey PRIMARY KEY (lote_id, responsable_control_id);


--
-- Name: pedido pedido_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pedido
    ADD CONSTRAINT pedido_pkey PRIMARY KEY (id);


--
-- Name: producto producto_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT producto_pkey PRIMARY KEY (id);


--
-- Name: responsable_deposito responsable_deposito_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.responsable_deposito
    ADD CONSTRAINT responsable_deposito_pkey PRIMARY KEY (responsable_control_id);


--
-- Name: usuario usuario_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_email_key UNIQUE (email);


--
-- Name: usuario usuario_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usuario
    ADD CONSTRAINT usuario_pkey PRIMARY KEY (id);


--
-- Name: idx_tp3_pedido_estado_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tp3_pedido_estado_fecha ON public.pedido USING btree (estado, fecha DESC) INCLUDE (usuario_id, total) WHERE (eliminado = false);


--
-- Name: idx_tp3_pedido_usuario_fecha; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tp3_pedido_usuario_fecha ON public.pedido USING btree (usuario_id, fecha DESC) WHERE (eliminado = false);


--
-- Name: idx_tp3_producto_categoria_precio; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tp3_producto_categoria_precio ON public.producto USING btree (categoria_id, precio DESC, id) WHERE (eliminado = false);


--
-- Name: idx_tp4_detalle_producto_cobertura; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tp4_detalle_producto_cobertura ON public.detalle_pedido USING btree (producto_id, pedido_id) INCLUDE (cantidad, subtotal);


--
-- Name: idx_u3_detalle_producto_pedido; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_u3_detalle_producto_pedido ON public.detalle_pedido USING btree (producto_id, pedido_id) INCLUDE (cantidad, precio_unitario);


--
-- Name: idx_u3_pedido_fecha_local_entregado; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_u3_pedido_fecha_local_entregado ON public.pedido USING btree ((fecha AT TIME ZONE 'America/Argentina/Buenos_Aires'::text)) INCLUDE (id, usuario_id, total) WHERE ((eliminado = false) AND (estado = 'ENTREGADO'::public.estado_pedido));


--
-- Name: idx_u3_producto_stock_vig; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_u3_producto_stock_vig ON public.producto USING btree (stock, id) INCLUDE (nombre, precio) WHERE (eliminado = false);


--
-- Name: idx_u4_ventas_categoria_dia_top; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_u4_ventas_categoria_dia_top ON public.mv_u4_ventas_categoria_dia USING btree (fecha, total_vendido DESC);


--
-- Name: ux_mv_facturacion_categoria_mes; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX ux_mv_facturacion_categoria_mes ON public.mv_facturacion_categoria_mes USING btree (categoria_id, mes);


--
-- Name: lote_responsable bloquear_lote_responsable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bloquear_lote_responsable BEFORE INSERT OR DELETE OR UPDATE ON public.lote_responsable FOR EACH STATEMENT EXECUTE FUNCTION public.bloquear_control_lote();


--
-- Name: responsable_deposito bloquear_responsable_deposito; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bloquear_responsable_deposito BEFORE INSERT OR DELETE OR UPDATE ON public.responsable_deposito FOR EACH STATEMENT EXECUTE FUNCTION public.bloquear_control_lote();


--
-- Name: detalle_pedido trg_recalcular_total; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_recalcular_total AFTER INSERT OR DELETE OR UPDATE ON public.detalle_pedido FOR EACH ROW EXECUTE FUNCTION public.recalcular_total_pedido();


--
-- Name: detalle_pedido trg_validar_detalle_pendiente; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_detalle_pendiente BEFORE INSERT OR DELETE OR UPDATE ON public.detalle_pedido FOR EACH ROW EXECUTE FUNCTION public.validar_detalle_pendiente();


--
-- Name: pedido trg_validar_estado_pedido; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_validar_estado_pedido BEFORE UPDATE OF estado ON public.pedido FOR EACH ROW EXECUTE FUNCTION public.validar_estado_pedido();


--
-- Name: categoria ventas_bloqueo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ventas_bloqueo BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.categoria FOR EACH STATEMENT EXECUTE FUNCTION public.u4_serializar_ventas();


--
-- Name: detalle_pedido ventas_bloqueo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ventas_bloqueo BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.detalle_pedido FOR EACH STATEMENT EXECUTE FUNCTION public.u4_serializar_ventas();


--
-- Name: pedido ventas_bloqueo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ventas_bloqueo BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.pedido FOR EACH STATEMENT EXECUTE FUNCTION public.u4_serializar_ventas();


--
-- Name: producto ventas_bloqueo; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ventas_bloqueo BEFORE INSERT OR DELETE OR UPDATE OR TRUNCATE ON public.producto FOR EACH STATEMENT EXECUTE FUNCTION public.u4_serializar_ventas();


--
-- Name: categoria ventas_refresco; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ventas_refresco AFTER INSERT OR DELETE OR UPDATE ON public.categoria FOR EACH STATEMENT EXECUTE FUNCTION public.u4_refrescar_ventas();


--
-- Name: detalle_pedido ventas_refresco; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ventas_refresco AFTER INSERT OR DELETE OR UPDATE ON public.detalle_pedido FOR EACH STATEMENT EXECUTE FUNCTION public.u4_refrescar_ventas();


--
-- Name: pedido ventas_refresco; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ventas_refresco AFTER INSERT OR DELETE OR UPDATE ON public.pedido FOR EACH STATEMENT EXECUTE FUNCTION public.u4_refrescar_ventas();


--
-- Name: producto ventas_refresco; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER ventas_refresco AFTER INSERT OR DELETE OR UPDATE ON public.producto FOR EACH STATEMENT EXECUTE FUNCTION public.u4_refrescar_ventas();


--
-- Name: lote_responsable verificar_lote_responsable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER verificar_lote_responsable AFTER INSERT OR DELETE OR UPDATE ON public.lote_responsable FOR EACH STATEMENT EXECUTE FUNCTION public.verificar_control_lote();


--
-- Name: responsable_deposito verificar_responsable_deposito; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER verificar_responsable_deposito AFTER INSERT OR DELETE OR UPDATE ON public.responsable_deposito FOR EACH STATEMENT EXECUTE FUNCTION public.verificar_control_lote();


--
-- Name: control_lote_almacen_original control_lote_almacen_deposito_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.control_lote_almacen_original
    ADD CONSTRAINT control_lote_almacen_deposito_id_fkey FOREIGN KEY (deposito_id) REFERENCES public.deposito(id) ON DELETE RESTRICT;


--
-- Name: control_lote_almacen_original control_lote_almacen_lote_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.control_lote_almacen_original
    ADD CONSTRAINT control_lote_almacen_lote_id_fkey FOREIGN KEY (lote_id) REFERENCES public.lote(id) ON DELETE RESTRICT;


--
-- Name: control_lote_almacen_original control_lote_almacen_responsable_control_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.control_lote_almacen_original
    ADD CONSTRAINT control_lote_almacen_responsable_control_id_fkey FOREIGN KEY (responsable_control_id) REFERENCES public.usuario(id) ON DELETE RESTRICT;


--
-- Name: detalle_pedido detalle_pedido_pedido_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_pedido
    ADD CONSTRAINT detalle_pedido_pedido_id_fkey FOREIGN KEY (pedido_id) REFERENCES public.pedido(id) ON DELETE RESTRICT;


--
-- Name: detalle_pedido detalle_pedido_producto_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.detalle_pedido
    ADD CONSTRAINT detalle_pedido_producto_id_fkey FOREIGN KEY (producto_id) REFERENCES public.producto(id) ON DELETE RESTRICT;


--
-- Name: lote_responsable lote_responsable_lote_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_responsable
    ADD CONSTRAINT lote_responsable_lote_id_fkey FOREIGN KEY (lote_id) REFERENCES public.lote(id) ON DELETE RESTRICT;


--
-- Name: lote_responsable lote_responsable_responsable_control_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lote_responsable
    ADD CONSTRAINT lote_responsable_responsable_control_id_fkey FOREIGN KEY (responsable_control_id) REFERENCES public.responsable_deposito(responsable_control_id) ON DELETE RESTRICT;


--
-- Name: pedido pedido_usuario_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pedido
    ADD CONSTRAINT pedido_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuario(id) ON DELETE RESTRICT;


--
-- Name: producto producto_categoria_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.producto
    ADD CONSTRAINT producto_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categoria(id) ON DELETE RESTRICT;


--
-- Name: responsable_deposito responsable_deposito_deposito_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.responsable_deposito
    ADD CONSTRAINT responsable_deposito_deposito_id_fkey FOREIGN KEY (deposito_id) REFERENCES public.deposito(id) ON DELETE RESTRICT;


--
-- Name: responsable_deposito responsable_deposito_responsable_control_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.responsable_deposito
    ADD CONSTRAINT responsable_deposito_responsable_control_id_fkey FOREIGN KEY (responsable_control_id) REFERENCES public.usuario(id) ON DELETE RESTRICT;


--
-- PostgreSQL database dump complete
--

\unrestrict NhjHRfMM2ka2gSmlONQZZgIfdqCDy5cKBvcFvgu1ecEeTiiREV9hIMB6VoduIju


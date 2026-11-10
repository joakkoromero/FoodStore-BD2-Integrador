-- Unidad 5 - Parte A. Exequiel Arancibia - Joaquin Romero.
-- Implementacion de Codex posterior a requirements/design reales de Kiro.
-- PostgreSQL 17; base privada Food Store U1-U4 restaurada, con una cuenta U5.
-- Primera instalacion: ejecutar mediante tools/instalar_seguridad.py.
-- No contiene contrasenas: los dos logins nacen con PASSWORD NULL y el
-- instalador configura sus secretos privados despues de esta transaccion.
-- No es idempotente: si ya existe cualquiera de los ocho roles, aborta.
-- No borra datos, objetos heredados, reglas de negocio ni enlaces de triggers.
-- Validacion humana pendiente. Las pruebas se guardan por separado.

BEGIN;
SET LOCAL search_path = pg_catalog;

DO $precondiciones$
DECLARE
    v_faltantes text;
BEGIN
    IF current_database() <> 'foodstore_u5_arancibia_romero'
       OR session_user <> 'u5_bootstrap' OR current_user <> session_user THEN
        RAISE EXCEPTION 'Ejecutar como bootstrap en la base privada U5 esperada';
    END IF;
    IF current_setting('server_version_num')::integer NOT BETWEEN 170000 AND 179999
       OR NOT (SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname = current_user) THEN
        RAISE EXCEPTION 'Se requiere PostgreSQL 17 y el bootstrap tecnico del laboratorio';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
        WHERE rolname IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                          'rol_reportes','rol_propietario','rol_funciones',
                          'app_web','admin_datos')
    ) THEN
        RAISE EXCEPTION 'Hay roles U5 preexistentes; revisar la instalacion sin reemplazarlos';
    END IF;
    SELECT pg_catalog.string_agg(nombre, ', ' ORDER BY nombre) INTO v_faltantes
    FROM (VALUES
        ('public.categoria'),('public.producto'),('public.usuario'),
        ('public.pedido'),('public.detalle_pedido'),('public.lote'),
        ('public.deposito'),('public.responsable_deposito'),
        ('public.lote_responsable'),('public.guardia_control_lote'),
        ('public.control_lote_almacen_original'),('public.control_lote_almacen'),
        ('public.v_productos_vigentes_categoria'),('public.v_detalle_pedido_producto'),
        ('public.v_pedidos_usuario'),('public.mv_facturacion_categoria_mes'),
        ('public.mv_u4_ventas_categoria_dia'),('datos_anon.usuario_anon')
    ) AS esperado(nombre)
    WHERE pg_catalog.to_regclass(nombre) IS NULL;
    IF v_faltantes IS NOT NULL THEN
        RAISE EXCEPTION 'Faltan objetos heredados: %', v_faltantes;
    END IF;
    IF pg_catalog.to_regprocedure('crypto.crypt(text,text)') IS NULL
       OR pg_catalog.to_regprocedure('crypto.gen_salt(text,integer)') IS NULL
       OR pg_catalog.to_regprocedure('public.recalcular_total_pedido()') IS NULL
       OR pg_catalog.to_regprocedure('public.u4_refrescar_ventas()') IS NULL
       OR pg_catalog.to_regprocedure('public.u4_serializar_ventas()') IS NULL
       OR pg_catalog.to_regprocedure('public.validar_detalle_pendiente()') IS NULL
       OR pg_catalog.to_regprocedure('public.validar_estado_pedido()') IS NULL THEN
        RAISE EXCEPTION 'No coincide la interfaz de funciones heredadas o pgcrypto';
    END IF;
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class AS c
        JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('public','datos_anon')
          AND c.relkind IN ('r','p','v','m','S')
          AND c.relowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = session_user)
    ) THEN
        RAISE EXCEPTION 'Existe un propietario inesperado en la copia del laboratorio';
    END IF;
END
$precondiciones$;

-- Los propietarios tecnicos no son grupos que se otorguen a los logins.
CREATE ROLE rol_app_lectura NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_app_escritura NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_soporte NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_reportes NOLOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_propietario NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE rol_funciones NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
CREATE ROLE app_web LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;
CREATE ROLE admin_datos LOGIN INHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD NULL;

GRANT rol_app_lectura, rol_app_escritura TO app_web
    WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
GRANT rol_soporte TO admin_datos
    WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;

-- Los validadores INVOKER de TP2 conservan nombres public sin calificar.
-- public queda disponible para ellos, pero nadie de negocio puede crear alli.
ALTER ROLE app_web IN DATABASE foodstore_u5_arancibia_romero
    SET search_path = pg_catalog, public;
ALTER ROLE admin_datos IN DATABASE foodstore_u5_arancibia_romero
    SET search_path = pg_catalog, public;

REVOKE CONNECT, CREATE, TEMPORARY ON DATABASE foodstore_u5_arancibia_romero FROM PUBLIC;
GRANT CONNECT ON DATABASE foodstore_u5_arancibia_romero TO app_web, admin_datos;
-- Necesario solo para la tabla temporal de equivalencia de la Parte D.
GRANT TEMPORARY ON DATABASE foodstore_u5_arancibia_romero TO rol_propietario;

ALTER SCHEMA public OWNER TO rol_propietario;
ALTER SCHEMA datos_anon OWNER TO rol_propietario;
REVOKE ALL PRIVILEGES ON SCHEMA public, datos_anon FROM PUBLIC, u5_bootstrap,
    rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
    app_web, admin_datos, rol_funciones;
REVOKE ALL PRIVILEGES ON SCHEMA crypto FROM PUBLIC,
    rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
    app_web, admin_datos, rol_funciones;
GRANT USAGE ON SCHEMA public TO rol_app_lectura, rol_app_escritura,
    rol_soporte, rol_reportes, rol_funciones;
GRANT USAGE ON SCHEMA datos_anon TO rol_reportes;
GRANT USAGE ON SCHEMA crypto TO rol_funciones;

-- ALTER TABLE transfiere tambien las secuencias IDENTITY dependientes.
-- Se inventarian tablas, vistas y MVs para conservar todos los objetos U1-U4.
DO $propiedad$
DECLARE
    obj record;
BEGIN
    FOR obj IN
        SELECT n.nspname, c.relname, c.relkind
        FROM pg_catalog.pg_class AS c
        JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m')
        ORDER BY CASE WHEN c.relkind IN ('r','p') THEN 0 ELSE 1 END, n.nspname, c.relname
    LOOP
        EXECUTE pg_catalog.format('ALTER %s %I.%I OWNER TO rol_propietario',
            CASE obj.relkind WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'MATERIALIZED VIEW' ELSE 'TABLE' END,
            obj.nspname, obj.relname);
    END LOOP;
    FOR obj IN
        SELECT n.nspname, c.relname
        FROM pg_catalog.pg_class AS c
        JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('public','datos_anon') AND c.relkind = 'S'
          AND c.relowner <> (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'rol_propietario')
          AND NOT EXISTS (
              SELECT 1 FROM pg_catalog.pg_depend AS d
              WHERE d.classid = 'pg_catalog.pg_class'::pg_catalog.regclass
                AND d.objid = c.oid AND d.deptype = 'i'
          )
    LOOP
        EXECUTE pg_catalog.format('ALTER SEQUENCE %I.%I OWNER TO rol_propietario',obj.nspname,obj.relname);
    END LOOP;
    FOR obj IN
        SELECT n.nspname, t.typname
        FROM pg_catalog.pg_type AS t
        JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
        WHERE n.nspname = 'public' AND t.typtype = 'e'
    LOOP
        EXECUTE pg_catalog.format('ALTER TYPE %I.%I OWNER TO rol_propietario',obj.nspname,obj.typname);
    END LOOP;
    FOR obj IN
        SELECT p.oid::pg_catalog.regprocedure AS identidad
        FROM pg_catalog.pg_proc AS p
        JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public' AND p.prokind = 'f'
    LOOP
        EXECUTE pg_catalog.format('ALTER FUNCTION %s OWNER TO rol_propietario',obj.identidad);
        EXECUTE pg_catalog.format('ALTER FUNCTION %s SECURITY INVOKER',obj.identidad);
    END LOOP;
END
$propiedad$;

-- Quitar ACL de tabla NO quita ACL por columna: se limpian las dos capas.
-- REVOKE no elimina la facultad del superusuario bootstrap; se retiran sus
-- entradas ACL, sin afirmar que pueda limitarse a un superusuario.
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public, datos_anon FROM PUBLIC,
    u5_bootstrap, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
    app_web, admin_datos, rol_funciones;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public, datos_anon FROM PUBLIC,
    u5_bootstrap, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
    app_web, admin_datos, rol_funciones;
DO $columnas$
DECLARE
    obj record;
BEGIN
    FOR obj IN
        SELECT n.nspname, c.relname,
               pg_catalog.string_agg(pg_catalog.quote_ident(a.attname),', ' ORDER BY a.attnum) AS columnas
        FROM pg_catalog.pg_class AS c
        JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
        JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.oid
        WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m')
          AND a.attnum > 0 AND NOT a.attisdropped
        GROUP BY n.nspname, c.relname
    LOOP
        EXECUTE pg_catalog.format(
            'REVOKE ALL PRIVILEGES (%s) ON TABLE %I.%I FROM PUBLIC, u5_bootstrap, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, app_web, admin_datos, rol_funciones',
            obj.columnas,obj.nspname,obj.relname);
    END LOOP;
END
$columnas$;
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public, crypto FROM PUBLIC,
    rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes,
    app_web, admin_datos, rol_funciones;
REVOKE ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public FROM u5_bootstrap;

-- No hay alternativa de texto plano para los hashes demostrativos heredados.
-- Cada intento deja solo resultado y timestamp, nunca identidad o credencial.
CREATE FUNCTION public.fn_autenticar(p_email text, p_password text)
RETURNS bigint
LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER
SET search_path = pg_catalog
AS $autenticar$
DECLARE
    v_id bigint;
    v_hash text;
    v_ok boolean := false;
BEGIN
    IF p_email IS NOT NULL AND p_password IS NOT NULL
       AND pg_catalog.octet_length(p_password) BETWEEN 1 AND 72 THEN
        SELECT u.id, u.contrasena INTO v_id, v_hash
        FROM public.usuario AS u
        WHERE u.email = p_email AND NOT u.eliminado;

        IF FOUND AND v_hash ~ '^[$]2[aby][$][0-9]{2}[$][./A-Za-z0-9]{53}$' THEN
            BEGIN
                v_ok := crypto.crypt(p_password,v_hash) = v_hash;
            EXCEPTION WHEN data_exception THEN
                -- Hash demostrativo o bcrypt invalido: falla de forma cerrada.
                v_ok := false;
            END;
        END IF;
    END IF;
    v_ok := COALESCE(v_ok,false);
    RAISE LOG 'U5_AUTH success=% timestamp=%',v_ok,pg_catalog.clock_timestamp();
    IF v_ok THEN RETURN v_id; END IF;
    RETURN NULL;
END
$autenticar$;
ALTER FUNCTION public.fn_autenticar(text,text) OWNER TO rol_funciones;
REVOKE EXECUTE ON FUNCTION public.fn_autenticar(text,text) FROM PUBLIC;

-- Contrato tecnico precisado en revision_automatica_codex.md:
-- void; longitud de 12..72 BYTES; invalidos=22023; usuario ausente=P0002.
CREATE FUNCTION public.fn_resetear_password(p_usuario_id bigint, p_password text)
RETURNS void
LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER
SET search_path = pg_catalog
AS $resetear$
BEGIN
    IF p_password IS NULL OR pg_catalog.octet_length(p_password) NOT BETWEEN 12 AND 72 THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Longitud de credencial fuera del intervalo permitido';
    END IF;
    UPDATE public.usuario
       SET contrasena = crypto.crypt(p_password,crypto.gen_salt('bf',10))
     WHERE id = p_usuario_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Usuario inexistente';
    END IF;
    RAISE LOG 'U5_PASSWORD_RESET success=true timestamp=%',pg_catalog.clock_timestamp();
    RETURN;
END
$resetear$;
ALTER FUNCTION public.fn_resetear_password(bigint,text) OWNER TO rol_funciones;
REVOKE EXECUTE ON FUNCTION public.fn_resetear_password(bigint,text) FROM PUBLIC;

-- Mismo OID y enlaces de trigger: solo se protege el contexto de ejecucion.
-- COALESCE y el recálculo del pedido anterior se conservan de TP2.
CREATE OR REPLACE FUNCTION public.recalcular_total_pedido()
RETURNS trigger
LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER
SET search_path = pg_catalog
AS $recalcular$
DECLARE
    v_pedido bigint;
BEGIN
    v_pedido := COALESCE(NEW.pedido_id,OLD.pedido_id);
    UPDATE public.pedido
       SET total = COALESCE((SELECT pg_catalog.sum(subtotal)
                            FROM public.detalle_pedido
                            WHERE pedido_id = v_pedido),0)
     WHERE id = v_pedido;
    IF TG_OP = 'UPDATE' AND OLD.pedido_id <> NEW.pedido_id THEN
        UPDATE public.pedido
           SET total = COALESCE((SELECT pg_catalog.sum(subtotal)
                                FROM public.detalle_pedido
                                WHERE pedido_id = OLD.pedido_id),0)
         WHERE id = OLD.pedido_id;
    END IF;
    RETURN NULL;
END
$recalcular$;
ALTER FUNCTION public.recalcular_total_pedido() OWNER TO rol_funciones;
REVOKE EXECUTE ON FUNCTION public.recalcular_total_pedido() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.u4_refrescar_ventas()
RETURNS trigger
LANGUAGE plpgsql VOLATILE PARALLEL UNSAFE SECURITY DEFINER
SET search_path = pg_catalog
AS $refrescar$
BEGIN
    -- Mismo camino heredado detalle -> pedido: evitar un REFRESH por fila.
    IF TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME='pedido'
       AND pg_catalog.pg_trigger_depth()>1 THEN
        RAISE DEBUG 'U4_REFRESH_SKIPPED table=% depth=%',TG_TABLE_NAME,pg_catalog.pg_trigger_depth();
        RETURN NULL;
    END IF;
    RAISE DEBUG 'U4_REFRESH_EXECUTED table=% depth=%',TG_TABLE_NAME,pg_catalog.pg_trigger_depth();
    REFRESH MATERIALIZED VIEW public.mv_u4_ventas_categoria_dia;
    RETURN NULL;
END
$refrescar$;
ALTER FUNCTION public.u4_refrescar_ventas() OWNER TO rol_funciones;
REVOKE EXECUTE ON FUNCTION public.u4_refrescar_ventas() FROM PUBLIC;

-- Auxiliares de las cuatro funciones, sin propiedad de tablas o secuencias.
GRANT SELECT (id,email,contrasena,eliminado), UPDATE (contrasena)
    ON public.usuario TO rol_funciones;
GRANT SELECT (pedido_id,subtotal) ON public.detalle_pedido TO rol_funciones;
GRANT SELECT (id), UPDATE (total) ON public.pedido TO rol_funciones;
GRANT MAINTAIN ON public.mv_u4_ventas_categoria_dia TO rol_funciones;
GRANT EXECUTE ON FUNCTION crypto.crypt(text,text), crypto.gen_salt(text,integer) TO rol_funciones;

-- Matriz de negocio. No se otorgan privilegios a las vistas TP5 ni a FNBC.
GRANT SELECT ON public.categoria, public.producto, public.pedido, public.detalle_pedido
    TO rol_app_lectura;
GRANT SELECT (id,nombre,apellido,email,telefono,eliminado,created_at)
    ON public.usuario TO rol_app_lectura;
GRANT INSERT (usuario_id,fecha,forma_pago), UPDATE (estado,forma_pago,eliminado)
    ON public.pedido TO rol_app_escritura;
GRANT INSERT (pedido_id,producto_id,cantidad,precio_unitario), UPDATE (cantidad,precio_unitario)
    ON public.detalle_pedido TO rol_app_escritura;
GRANT DELETE ON public.detalle_pedido TO rol_app_escritura;
GRANT SELECT (id,nombre,apellido,email,telefono,eliminado), UPDATE (telefono)
    ON public.usuario TO rol_soporte;
GRANT SELECT ON datos_anon.usuario_anon,
    public.mv_facturacion_categoria_mes, public.mv_u4_ventas_categoria_dia TO rol_reportes;
GRANT EXECUTE ON FUNCTION public.fn_autenticar(text,text) TO app_web;
GRANT EXECUTE ON FUNCTION public.fn_resetear_password(bigint,text) TO admin_datos;

-- Los defaults pertenecen al CREADOR efectivo, no a sus grupos heredados.
-- El REVOKE de PUBLIC sobre funciones es GLOBAL: un REVOKE por esquema no
-- elimina el EXECUTE publico que PostgreSQL concede por defecto globalmente.
-- Se cubren ambos propietarios y el bootstrap usado para futuras migraciones.
DO $defaults$
DECLARE
    creador text;
    esquema text;
BEGIN
    FOREACH creador IN ARRAY ARRAY['rol_propietario','rol_funciones','u5_bootstrap'] LOOP
        EXECUTE pg_catalog.format(
            'ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE ALL PRIVILEGES ON FUNCTIONS FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, app_web, admin_datos',creador);
        EXECUTE pg_catalog.format(
            'ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, app_web, admin_datos',creador);
        EXECUTE pg_catalog.format(
            'ALTER DEFAULT PRIVILEGES FOR ROLE %I REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, app_web, admin_datos',creador);
        FOREACH esquema IN ARRAY ARRAY['public','datos_anon'] LOOP
            EXECUTE pg_catalog.format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I REVOKE ALL PRIVILEGES ON TABLES FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, app_web, admin_datos',creador,esquema);
            EXECUTE pg_catalog.format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I REVOKE ALL PRIVILEGES ON SEQUENCES FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, app_web, admin_datos',creador,esquema);
            EXECUTE pg_catalog.format(
                'ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA %I REVOKE ALL PRIVILEGES ON FUNCTIONS FROM PUBLIC, rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, app_web, admin_datos',creador,esquema);
        END LOOP;
    END LOOP;
END
$defaults$;
ALTER DEFAULT PRIVILEGES FOR ROLE rol_propietario IN SCHEMA datos_anon
    GRANT SELECT ON TABLES TO rol_reportes;

COMMIT;

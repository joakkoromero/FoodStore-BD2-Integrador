# Fuentes saneadas para revisión estática: Unidad5

No ejecutar estas copias. Los literales personales/de carga se sustituyeron por placeholders; las comprobaciones en motor usarán las fuentes originales locales. Señalar archivo/línea y distinguir errores confirmables de hipótesis.

## outputs\Arancibia_Romero_U5\food-store-tp-u5\sql\auditoria_test.sql

SHA256 original: 8c74fa1ad63bd079a0dd1c4937ce04a8bb74989285a2e509ec83bf62338ec076
SHA256 saneado: 62e621f663188b26f88d81be76c6bde360b8b890b97cdd773cf08d8a623b4998

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Parte B: catalogo de sentencias parametrizadas para PostgreSQL 17.
-- Base: propuesta real OpenCode conservada en docs/ia/bc_respuesta.md.
-- Ajustes tecnicos posteriores: stock apto y RETURNING para probar filas.
-- Ejecutar mediante el cliente Python:
-- python tools/ejecutar_pruebas.py --phase audit
--
-- No ejecutar este archivo completo en psql. El cliente selecciona cada
-- sentencia por su marcador y enlaza los parametros con PQexecParams.
-- Ejecutar toda la prueba en una misma conexion real de app_web.
-- Los permisos propuestos son precondiciones por verificar, no hechos.
--
-- El cliente debe disponer de un usuario de prueba valido y elegir un
-- producto apto para agregar dos unidades. No compartir sus identificadores
-- ni los valores de las filas en la evidencia.
-- Los ids IDENTITY se generan al insertar; no se invocan secuencias.
-- Una conexion PostgreSQL fallida se prueba desde Python, no mediante SQL.

-- name: audit_begin
BEGIN;

-- name: audit_catalog_read
SELECT id,precio,stock
FROM public.producto
WHERE eliminado=FALSE AND stock>=2
ORDER BY id
LIMIT 3;

-- name: audit_insert_order
-- $1: id del usuario de prueba.
-- El cliente conserva el id devuelto y comprueba estado = PENDIENTE.
INSERT INTO public.pedido(usuario_id,fecha,forma_pago)
VALUES ($1::bigint,CURRENT_TIMESTAMP,'EFECTIVO'::public.forma_pago)
RETURNING id,estado;

-- name: audit_insert_detail
-- $1: id del pedido recien creado.
-- $2: id del producto elegido.
-- $3: precio unitario obtenido del catalogo.
INSERT INTO public.detalle_pedido(
    pedido_id,producto_id,cantidad,precio_unitario
)
VALUES ($1::bigint,$2::bigint,1,$3::numeric)
RETURNING cantidad=1 AS linea_creada;

-- name: audit_update_detail
-- Ejecutar mientras el pedido sigue PENDIENTE.
-- $1: id del pedido; $2: id del producto.
UPDATE public.detalle_pedido
SET cantidad=cantidad+1
WHERE pedido_id=$1::bigint AND producto_id=$2::bigint
RETURNING cantidad;

-- name: audit_confirm_order
-- Ejecutar solo despues de insertar y modificar el detalle.
-- $1: id del pedido.
UPDATE public.pedido
SET estado='CONFIRMADO'
WHERE id=$1::bigint AND estado='PENDIENTE'
RETURNING estado='CONFIRMADO' AS confirmado;

-- name: audit_order_total_invariant
-- $1: id del pedido.
SELECT p.total IS NOT DISTINCT FROM COALESCE(SUM(d.subtotal),0)
       AS total_correcto
FROM public.pedido p
LEFT JOIN public.detalle_pedido d ON d.pedido_id=p.id
WHERE p.id=$1::bigint
GROUP BY p.total;

-- name: audit_rollback
-- Ejecutar tambien ante errores, mientras la conexion siga disponible.
ROLLBACK;

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\sql\configurar_auditoria.sql

SHA256 original: 2c2a4654bdd60b3c29b9b9a1233404604049fc9021bd1ab68ea69f74bb8dfd5f
SHA256 saneado: 68aa301fe68c30d6bab3959bd4cc9b394ec702bae7fd5edf039ce2373565b55d

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Parte B: aplicar como administrador del laboratorio, fuera de una transaccion.
-- logging_collector=on y stderr,jsonlog ya se fijan al crear el cluster privado.
-- all incluye SELECT para que la lectura masiva de C sea visible en el log.
ALTER SYSTEM SET log_connections='on';
ALTER SYSTEM SET log_disconnections='on';
ALTER SYSTEM SET log_statement='all';
ALTER SYSTEM SET log_min_error_statement='error';
ALTER SYSTEM SET log_parameter_max_length='0';
ALTER SYSTEM SET log_parameter_max_length_on_error='0';
SELECT pg_catalog.pg_reload_conf();
-- Verificar estos valores en una CONEXION NUEVA antes de las pruebas.

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\sql\roles.sql

SHA256 original: 916b8b4e9d9b59abc5bc6edef4d3d35d27007dcd7c875cc1ec62d791197f75f5
SHA256 saneado: 010591b7d7900b013295bad84acdd623b67df3bf6e90576f1cf58c33b73c8899

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
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

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\sql\simulacro_incidente.sql

SHA256 original: bf96bb1e1f629967ee7e0febe12c2911a6c6516688b90683f330024db86847b1
SHA256 saneado: a04eb0edcfc7a480866f0294aa0e21104ef90f8bce56809a83b84b26d9b3f69d

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Parte C: catalogo de sentencias parametrizadas para PostgreSQL 17.
-- Propuesta real OpenCode conservada integra en docs/ia/bc_respuesta.md.
-- Ejecutar mediante el cliente Python:
-- python tools/ejecutar_pruebas.py --phase incident
--
-- Solo contra el cluster propio y aislado del laboratorio U5.
-- No ejecutar este archivo como un script secuencial en una sola conexion.
-- Los marcadores identifican sentencias que el cliente puede reutilizar.
--
-- Conexion de prueba: autenticada en PostgreSQL como app_web.
-- Conexion verificadora: independiente, con permisos suficientes para
-- comprobar membresias; no sustituye la conexion de prueba.
--
-- Orden orquestado por Python:
-- 1. Comprobar membresia desde la conexion verificadora.
--    Exigir false; si ya es true, detener el escenario y comunicarlo.
-- 2. Ejecutar incident_authenticate tres veces con clave sintetica
--    incorrecta y una vez con la correcta, siempre mediante parametros.
-- 3. Ejecutar incident_bulk_read desde app_web.
-- 4. Ejecutar incident_attempt_escalation desde app_web.
--    Exigir rechazo con SQLSTATE 42501.
-- 5. Repetir incident_membership_check desde la conexion verificadora,
--    con una consulta nueva que observe el estado posterior.
--    Exigir false.
--
-- Antes de enviar claves, verificar que el registro de parametros esta
-- desactivado: log_parameter_max_length = 0 y
-- log_parameter_max_length_on_error = 0.
-- El cliente tampoco registra parametros, claves ni valores recibidos.

-- name: incident_authenticate
-- $1: email de la cuenta sintetica de prueba.
-- $2: clave sintetica de prueba.
-- Reutilizar esta sentencia para los cuatro intentos.
-- El cliente comprueba NULL en los tres fallidos y el id esperado en
-- el exitoso; no comparte el email, la clave ni el id devuelto.
SELECT public.fn_autenticar($1::text,$2::text);

-- name: incident_bulk_read
-- Proyeccion publica propuesta: excluye credenciales y contactos.
-- El cliente consume todas las filas, cuenta y descarta sus valores.
-- Compartir solo conteos y metadatos, no filas ni identificadores.
SELECT id,nombre,apellido,eliminado,created_at
FROM public.usuario
ORDER BY id;

-- name: incident_attempt_escalation
-- Ejecutar exclusivamente desde la conexion PostgreSQL de app_web.
-- Usar autocommit para no dejar una transaccion explicita abortada.
-- Resultado exigido: error SQLSTATE 42501; no asumir que ya se obtuvo.
GRANT admin_datos TO app_web;

-- name: incident_membership_check
-- Ejecutar antes y despues desde la conexion verificadora separada.
-- Resultado exigido en ambas comprobaciones: false.
SELECT pg_catalog.pg_has_role('app_web','admin_datos','MEMBER');

-- El log nativo puede acreditar la consulta y el error del servidor.
-- No acredita por si solo cuantas filas recibio el cliente ni una
-- exfiltracion fuera del entorno.
-- No se ejecuta ninguna medida de contencion automaticamente.

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\sql\usuario_anon.sql

SHA256 original: 7e49e29525feecb9914cd8d540dfa32b8f2bef53c7fd6f98464f0158a51150a9
SHA256 saneado: 60375c5ee66472060a1f4ef5cfefa61cf2b98255e66f78ee75ca7efa6ecdd248

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Unidad 5 - Parte D: copia de laboratorio y equivalencia agregada.
-- Exequiel Arancibia - Joaquin Romero. PostgreSQL 17.
-- SQL generado por OpenCode 1.18.23, modelo openai/gpt-6.1-sol.
-- Prompt, respuesta completa y procedencia: docs/ia/d_*.
-- Ejecutar como rol_propietario, creador configurado en la Parte A,
-- con ON_ERROR_STOP o equivalente. Se necesitan CREATE en datos_anon y TEMP
-- para la auditoria temporal. Los defaults de A aplican al creador correcto.
-- Solo se reemplaza datos_anon.usuario_anon; no se modifica public.usuario.
-- DROP no usa CASCADE y queda dentro de la transaccion de reconstruccion.
-- Integracion Codex posterior a la respuesta conservada de OpenCode:
-- SET LOCAL ROLE aplica el creador real y el esquema ya provisto por A.
-- La ejecucion bootstrap anterior se conserva en docs/evidencias/d_bootstrap_*.
-- No copiar filas reales a prompts o entregables.

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET LOCAL ROLE rol_propietario;

-- Solo se reconstruye la copia de laboratorio.
-- Sin CASCADE: si existen dependencias que impiden reemplazarla,
-- la transaccion falla sin eliminarlas.
-- datos_anon es propiedad de rol_propietario y se configura en la Parte A.

DROP TABLE IF EXISTS datos_anon.usuario_anon;

CREATE TABLE datos_anon.usuario_anon (
    folio      bigint PRIMARY KEY CHECK (folio > 0),
    nombre     text NOT NULL,
    apellido   text NOT NULL,
    email      text NOT NULL,
    mes_alta   date NOT NULL,
    eliminado  boolean NOT NULL
);

-- El id original se utiliza unicamente para ordenar la numeracion.
-- No se almacena en la copia ni en una tabla intermedia.
WITH numerados AS (
    SELECT
        row_number() OVER (ORDER BY id) AS folio,
        date_trunc(
            'month',
            created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
        )::date AS mes_alta,
        eliminado
    FROM public.usuario
),
formateados AS (
    SELECT
        folio,
        lpad(
            folio::text,
            GREATEST(5, length(folio::text)),
            '0'
        ) AS numero,
        mes_alta,
        eliminado
    FROM numerados
)
INSERT INTO datos_anon.usuario_anon (
    folio, nombre, apellido, email, mes_alta, eliminado
)
SELECT
    folio,
    'Persona' || numero,
    'Laboratorio',
    'persona' || numero || '@example.invalid',
    mes_alta,
    eliminado
FROM formateados;

-- 1. Agregacion solicitada sobre la copia.
SELECT mes_alta, eliminado, count(*) AS cantidad
FROM datos_anon.usuario_anon
GROUP BY mes_alta, eliminado
ORDER BY mes_alta, eliminado;

-- 2. Consulta equivalente sobre el origen, sin mostrar datos personales.
SELECT
    date_trunc(
        'month',
        created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
    )::date AS mes_alta,
    eliminado,
    count(*) AS cantidad
FROM public.usuario
GROUP BY
    date_trunc(
        'month',
        created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
    )::date,
    eliminado
ORDER BY mes_alta, eliminado;

-- 3. Comparacion lado a lado.
-- FULL OUTER JOIN permite ver tambien grupos ausentes en alguno de los lados.
WITH origen AS (
    SELECT
        date_trunc(
            'month',
            created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
        )::date AS mes_alta,
        eliminado,
        count(*) AS cantidad
    FROM public.usuario
    GROUP BY
        date_trunc(
            'month',
            created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
        )::date,
        eliminado
),
copia AS (
    SELECT mes_alta, eliminado, count(*) AS cantidad
    FROM datos_anon.usuario_anon
    GROUP BY mes_alta, eliminado
)
SELECT
    mes_alta,
    eliminado,
    o.cantidad AS cantidad_origen,
    c.cantidad AS cantidad_copia,
    o.cantidad IS NOT DISTINCT FROM c.cantidad AS coincide
FROM origen AS o
FULL OUTER JOIN copia AS c USING (mes_alta, eliminado)
ORDER BY mes_alta, eliminado;

-- 4. Auditoria EXCEPT ALL en ambos sentidos.
-- La tabla temporal guarda solo diferencias entre resultados agregados.
CREATE TEMP TABLE auditoria_usuario_anon_diferencias
ON COMMIT DROP
AS
WITH origen AS (
    SELECT
        date_trunc(
            'month',
            created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
        )::date AS mes_alta,
        eliminado,
        count(*) AS cantidad
    FROM public.usuario
    GROUP BY
        date_trunc(
            'month',
            created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
        )::date,
        eliminado
),
copia AS (
    SELECT mes_alta, eliminado, count(*) AS cantidad
    FROM datos_anon.usuario_anon
    GROUP BY mes_alta, eliminado
),
origen_menos_copia AS (
    SELECT mes_alta, eliminado, cantidad FROM origen
    EXCEPT ALL
    SELECT mes_alta, eliminado, cantidad FROM copia
),
copia_menos_origen AS (
    SELECT mes_alta, eliminado, cantidad FROM copia
    EXCEPT ALL
    SELECT mes_alta, eliminado, cantidad FROM origen
)
SELECT
    'origen_menos_copia'::text AS sentido,
    mes_alta,
    eliminado,
    cantidad
FROM origen_menos_copia
UNION ALL
SELECT
    'copia_menos_origen'::text AS sentido,
    mes_alta,
    eliminado,
    cantidad
FROM copia_menos_origen;

-- Resultado esperado al probarlo: ninguna fila.
SELECT sentido, mes_alta, eliminado, cantidad
FROM pg_temp.auditoria_usuario_anon_diferencias
ORDER BY sentido, mes_alta, eliminado, cantidad;

-- 5. Afirmacion ejecutable: cualquier diferencia aborta la transaccion.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_temp.auditoria_usuario_anon_diferencias
    ) THEN
        RAISE EXCEPTION
            'Auditoria fallida: las agregaciones de origen y copia difieren';
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMIT;

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\activar_auditoria.py

SHA256 original: e9d7a1e6f8915e742f5e22a47fd706787421c8da26a822f4c53b7356e1535351
SHA256 saneado: 65e062204cef0e6f4976ab142dbd1bba3f6a8d908117d412ce6e6e5c30af3076

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Activate the Part B settings outside a transaction and verify a new session."""
from libpq_client import Connection,load_secrets,REPOSITORY_ROOT
import json
import time


def main():
    private=load_secrets()
    with Connection(private['bootstrap_user'],application_name='u5_audit_config') as db:
        # ALTER SYSTEM cannot run inside a transaction. Each named statement
        # here is static SQL from the delivered configuration file.
        text=(REPOSITORY_ROOT/'sql/configurar_auditoria.sql').read_text(encoding='utf-8')
        text='\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('--'))
        for statement in text.split(';'):
            if statement.strip(): db.execute(statement)
    expected={'logging_collector':'on','log_connections':'on',
        'log_disconnections':'on','log_statement':'all','log_min_error_statement':'error',
        'log_parameter_max_length':'0','log_parameter_max_length_on_error':'0'}
    keys=list(expected)+['log_destination','log_line_prefix','password_encryption',
        'log_timezone','timezone','listen_addresses','port','log_directory','log_filename']
    # Reload is asynchronous. Retry a new session briefly; never claim that
    # pg_reload_conf() alone proves the settings became active.
    for attempt in range(10):
        with Connection(private['bootstrap_user'],application_name='u5_audit_config_verify') as db:
            values={key:db.scalar('SHOW '+key) for key in keys}
            ready=all(values[k]==v for k,v in expected.items())
            if ready:
                values['server_version']=db.scalar('SHOW server_version')
                values['verified_at']=db.scalar('SELECT current_timestamp::text')
                break
        time.sleep(0.2)
    else:
        raise RuntimeError('Audit configuration did not take effect in a new session')
    (REPOSITORY_ROOT/'docs/configuracion_auditoria.json').write_text(
        json.dumps(values,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Audit settings verified in a new connection.')


if __name__=='__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\anonimizar_log.py

SHA256 original: 96f9ea2743492ccf9e3e697b6ae63a3c3734ef4755cc7fbe787e1ce585130a7a
SHA256 saneado: 1b8b08d1e5f4d8b4a8404a4441b05b843e3d2378ce2f5445d058e395646450c4

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Extract real incident sessions and sanitize an offline PostgreSQL log.

Usage: python tools/anonimizar_log.py INPUT_RAW OUTPUT_SANITIZED
Raw input must remain outside this repository and the workspace outputs folder.
The tool never invents events or prints log contents. Review the sanitized log
manually before sending it to an AI; the scan report records that requirement.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import sys

from libpq_client import ConfigurationError, REPOSITORY_ROOT, load_secrets


EMAIL = re.compile(r"(?i)[A-Z0-9.!#$%&*+/=?^_`{|}~-]+@[A-Z0-9.-]+\.[A-Z]{2,}")
ENTRY_START = re.compile(r"^\d{4}-\d{2}-\d{2}[ T]")
APP_FIELD = re.compile(r"\b(?:app|application_name)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s]+))")
SESSION_FIELD = re.compile(r"\b(?:session|session_id)\s*=\s*['\"]?([A-Za-z0-9_.:-]+)")
PID_FIELD = re.compile(r"(?:\[(\d+)\]|\bpid=(\d+))")
SQL_STRING = r"'(?:''|[^'])*'"
AUTH_LITERAL = re.compile(r"(?is)(\bfn_autenticar\s*\(\s*)("+SQL_STRING+r")(\s*,\s*)("+SQL_STRING+r")")
RESET_LITERAL = re.compile(r"(?is)(\bfn_resetear_password\s*\(\s*[^,()]+,\s*)("+SQL_STRING+r")")
PASSWORD_LITERAL = re.compile(r"(?i)(\bPASSWORD\s+)("+SQL_STRING+r")")
BCRYPT = re.compile(r"\$2[aby]\$[0-9]{2}\$[^\s'\",;()]*")
SCRAM = re.compile(r"(?i)SCRAM-SHA-256\$[A-Za-z0-9/+=:$.]+")
PERSON_FIELD = re.compile(r"(?i)\b(nombre|apellido|full_name|person_name|display_name)\s*=\s*('(?:''|[^'])*'|\"[^\"]*\"|[^\s,;]+)")
PHONE_FIELD = re.compile(r"(?i)\b(telefono|phone|telephone)\s*=\s*('(?:''|[^'])*'|\"[^\"]*\"|[^\s,;]+)")


@dataclass
class Entry:
    text: str
    application: str | None = None
    session: str | None = None
    pid: str | None = None


def _alias_email(value: str) -> str:
    if value.lower().endswith(("@anon.invalid", "@example.invalid")):
        return value
    suffix = hashlib.sha256(value.casefold().encode("utf-8")).hexdigest()[:12]
    return "cuenta_"+suffix+"@anon.invalid"


def _person_token(value: str) -> str:
    suffix = hashlib.sha256(value.encode("utf-8")).hexdigest()[:10]
    return "PERSONA_"+suffix


def _metadata(line: str) -> Entry:
    if line.lstrip().startswith("{"):
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            obj = None
        if isinstance(obj, dict):
            session = obj.get("session_id")
            pid = obj.get("pid")
            return Entry(line, obj.get("application_name"),
                         str(session) if session is not None else None,
                         str(pid) if pid is not None else None)
    app_match = APP_FIELD.search(line)
    session_match = SESSION_FIELD.search(line)
    pid_match = PID_FIELD.search(line)
    app = next((v for v in app_match.groups() if v is not None), None) if app_match else None
    pid = next((v for v in pid_match.groups() if v is not None), None) if pid_match else None
    return Entry(line, app, session_match.group(1) if session_match else None, pid)


def parse_entries(text: str) -> list[Entry]:
    """Keep multiline SQL/context lines attached to their actual log entry."""
    entries: list[Entry] = []
    for line in text.splitlines(keepends=True):
        if ENTRY_START.match(line) or line.lstrip().startswith("{"):
            entries.append(_metadata(line))
        elif entries:
            entries[-1].text += line
        else:
            entries.append(Entry(line))
    return entries


def extract_sessions(entries: list[Entry], application: str,
                     explicit_sessions: list[str]) -> tuple[str, dict]:
    matched = [e for e in entries if e.application and e.application.startswith(application)]
    sessions = {e.session for e in matched if e.session}
    sessions.update(explicit_sessions)
    # A backend PID is only a fallback for formats lacking session IDs. We
    # expose that weaker correlation in the report, rather than hiding it.
    fallback_pids = {e.pid for e in matched if not e.session and e.pid}
    if not sessions and not fallback_pids:
        raise ConfigurationError("No incident session matches the requested application or session IDs")
    selected = [e for e in entries if
                (e.session is not None and e.session in sessions)
                or (e.session is None and e.pid is not None and e.pid in fallback_pids)]
    if not selected:
        raise ConfigurationError("Requested session IDs do not occur in the raw log")
    # Preserve source order and every selected entry, including failed queries.
    return "".join(e.text for e in selected), {
        "application_prefix": application,
        "selected_entries": len(selected),
        "selected_sessions": sorted(sessions),
        "fallback_pid_correlation": bool(fallback_pids),
        "matched_application_entries": len(matched),
    }


def secret_inventory(data: dict) -> list[str]:
    """Collect private password/token values, including the role mapping.

    Identity/configuration fields are handled separately, so role names and
    event labels retain their investigative meaning in the sanitized log.
    """
    collected: set[str] = set()
    sensitive = re.compile(r"(?i)(password|passwd|passphrase|secret|token|credential|\bpwd\b)")
    role_keys = {"app_web", "admin_datos", "u5_bootstrap", "u5_admin", "tp_admin", "postgres"}

    def visit(value, path: tuple[str, ...]) -> None:
        if isinstance(value, dict):
            for key, nested in value.items():
                visit(nested, path+(str(key),))
        elif isinstance(value, list):
            for index, nested in enumerate(value):
                visit(nested, path+(str(index),))
        elif isinstance(value, str) and value:
            is_role_value = len(path) >= 2 and path[-2] in {"roles", "passwords", "db_passwords"}
            is_named_secret = any(sensitive.search(part) for part in path)
            is_flat_role = len(path) == 1 and path[0] in role_keys
            if is_role_value or is_named_secret or is_flat_role:
                if len(value) < 4:
                    raise ConfigurationError("A runtime secret is too short for reliable offline substring scanning")
                collected.add(value)

    visit(data, ())
    if not collected:
        raise ConfigurationError("Private runtime file contains no recognizable secret inventory")
    return sorted(collected, key=len, reverse=True)


def sanitize(text: str, secrets: list[str], private_redactions: dict[str, str]) -> tuple[str, dict]:
    counts: dict[str, int] = {}
    original_emails = EMAIL.findall(text)
    counts["auth_quoted_passwords"] = len(AUTH_LITERAL.findall(text))
    counts["reset_quoted_passwords"] = len(RESET_LITERAL.findall(text))
    counts["password_utility_literals"] = len(PASSWORD_LITERAL.findall(text))
    counts["known_secret_occurrences"] = sum(text.count(secret) for secret in secrets)

    def auth_replacement(match):
        account = match.group(2)[1:-1].replace("''", "'")
        account = _alias_email(account) if "@" in account else _person_token(account)
        return match.group(1)+"'"+account+"'"+match.group(3)+"'[CREDENTIAL_REDACTED]'"

    text = AUTH_LITERAL.sub(auth_replacement, text)
    text = RESET_LITERAL.sub(lambda m: m.group(1)+"'[CREDENTIAL_REDACTED]'", text)
    text = PASSWORD_LITERAL.sub(lambda m: m.group(1)+"'[CREDENTIAL_REDACTED]'", text)
    for secret in secrets:
        text = text.replace(secret, "[SECRET_REDACTED]")
    counts["bcrypt_hashes"] = len(BCRYPT.findall(text))
    counts["scram_verifiers"] = len(SCRAM.findall(text))
    text = BCRYPT.sub("[CREDENTIAL_HASH_REDACTED]", text)
    text = SCRAM.sub("[CREDENTIAL_HASH_REDACTED]", text)
    text = EMAIL.sub(lambda m: _alias_email(m.group()), text)
    counts["email_occurrences"] = len(original_emails)
    counts["email_occurrences_changed"] = sum(_alias_email(value) != value for value in original_emails)
    counts["person_fields"] = len(PERSON_FIELD.findall(text))
    text = PERSON_FIELD.sub(lambda m: m.group(1)+"='"+_person_token(m.group(2))+"'", text)
    counts["phone_fields"] = len(PHONE_FIELD.findall(text))
    text = PHONE_FIELD.sub(lambda m: m.group(1)+"='[PHONE_REDACTED]'", text)
    text, counts["database_labels"] = re.subn(
        r"(?i)\bfoodstore_(?:u[0-9]+|tp[0-9]+)(?:_[A-Za-z0-9]+)*\b", "foodstore_lab", text)
    text, counts["windows_user_paths"] = re.subn(
        r"(?i)([A-Z]:[\\/]+Users[\\/]+)[^\\/\r\n'\"]+", lambda m: m.group(1)+"USR_LOCAL", text)
    text, counts["unix_user_paths"] = re.subn(
        r"(/(?:home|Users)/)[^/\s'\"]+", lambda m: m.group(1)+"USR_LOCAL", text)
    counts["private_literal_replacements"] = 0
    for original, replacement in sorted(private_redactions.items(), key=lambda item: len(item[0]), reverse=True):
        if not original or not isinstance(replacement, str):
            raise ConfigurationError("Private redactions must map nonempty text to synthetic text")
        counts["private_literal_replacements"] += text.count(original)
        text = text.replace(original, replacement)

    # Final checks do not disclose which secret matched, or its value.
    if any(secret in text for secret in secrets):
        raise ConfigurationError("Sanitized output still contains a known runtime secret")
    if BCRYPT.search(text) or SCRAM.search(text):
        raise ConfigurationError("Sanitized output still contains a credential hash")
    remaining_emails = EMAIL.findall(text)
    if any(not value.lower().endswith(("@anon.invalid", "@example.invalid")) for value in remaining_emails):
        raise ConfigurationError("Sanitized output still contains a non-synthetic email")
    quoted_auth = AUTH_LITERAL.findall(text)
    quoted_reset = RESET_LITERAL.findall(text)
    if any("CREDENTIAL_REDACTED" not in m[-1] for m in quoted_auth+quoted_reset):
        raise ConfigurationError("A quoted authentication credential still requires review")
    return text, {
        "replacement_counts": counts,
        "secret_scan_passed": True,
        "credential_hash_scan_passed": True,
        "email_scan_passed": True,
        "raw_selected_contained_known_secrets": counts["known_secret_occurrences"] > 0,
        "raw_selected_contained_quoted_credentials": bool(
            counts["auth_quoted_passwords"]+counts["reset_quoted_passwords"]+counts["password_utility_literals"]),
        "manual_review_required": True,
        "manual_review_scope": [
            "Check names or identifying text outside recognized field formats",
            "Verify session selection covers the entire executed sequence",
            "Confirm event order, outcomes, role names, timestamps and loopback topology were preserved",
        ],
        "limitations": "Deterministic substitutions reduce disclosure; they do not establish irreversible anonymization or prove the original log was untampered.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_raw", type=Path)
    parser.add_argument("output_sanitized", type=Path)
    parser.add_argument("--application", default="u5_incident")
    parser.add_argument("--session", action="append", default=[], help="Also include this actual source session ID")
    parser.add_argument("--secrets", type=Path, help="Private file; otherwise U5_SECRET_FILE/default workspace private file")
    parser.add_argument("--redactions-file", type=Path, help="Optional private JSON literal-to-synthetic mapping for manual findings")
    parser.add_argument("--report", type=Path, help="Default: output filename followed by .scan.json")
    args = parser.parse_args()
    raw = args.input_raw.resolve()
    output = args.output_sanitized.resolve()
    if raw == output or raw.is_relative_to(REPOSITORY_ROOT):
        raise ConfigurationError("Keep raw input outside the repository and separate from sanitized output")
    for ancestor in REPOSITORY_ROOT.parents:
        if ancestor.name.casefold() == "outputs" and raw.is_relative_to(ancestor):
            raise ConfigurationError("Raw logs must not be stored inside the workspace outputs directory")
    raw_bytes = raw.read_bytes()
    raw_text = raw_bytes.decode("utf-8-sig")
    selected, selection = extract_sessions(parse_entries(raw_text), args.application, args.session)
    inventory = secret_inventory(load_secrets(args.secrets))
    redactions = {}
    if args.redactions_file:
        redaction_path = args.redactions_file.resolve()
        if redaction_path.is_relative_to(REPOSITORY_ROOT):
            raise ConfigurationError("The private redaction mapping must stay outside the repository")
        redactions = json.loads(redaction_path.read_text(encoding="utf-8-sig"))
        if not isinstance(redactions, dict) or not all(isinstance(k, str) for k in redactions):
            raise ConfigurationError("Private redactions must be a JSON object")
    sanitized, scan = sanitize(selected, inventory, redactions)
    report = {
        **selection, **scan,
        "source_file_sha256": hashlib.sha256(raw_bytes).hexdigest(),
        "selected_raw_sha256": hashlib.sha256(selected.encode("utf-8")).hexdigest(),
        "sanitized_sha256": hashlib.sha256(sanitized.encode("utf-8")).hexdigest(),
        "events_invented": False,
        "retained": "Source ordering, timestamps/time zone, PID/session correlation, service roles and loopback addresses",
    }
    report_path = args.report.resolve() if args.report else output.with_name(output.name+".scan.json")
    if report_path == raw or report_path == output:
        raise ConfigurationError("The scan report needs its own output path")
    output.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    # Preserve the exact UTF-8 bytes hashed above, including LF/CRLF source
    # endings. Text mode would translate newlines again on Windows.
    output.write_bytes(sanitized.encode("utf-8"))
    written_sha256 = hashlib.sha256(output.read_bytes()).hexdigest()
    if written_sha256 != report["sanitized_sha256"]:
        raise ConfigurationError("The sanitized file bytes do not match the recorded SHA-256")
    report["sanitized_file_sha256_verified"] = True
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    # Counts and hashes only: neither input contents nor private mappings.
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ConfigurationError, OSError, UnicodeError, json.JSONDecodeError) as error:
        # OSError path details are not needed in a shareable diagnostic.
        message = str(error) if isinstance(error, ConfigurationError) else "Unable to read or write the local log inputs/outputs"
        print(json.dumps({"status": "failed", "reason": message}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(2)

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\capturar_permisos.py

SHA256 original: f7836ae8c389dfc0a0b596da333f3551985a537f577cca64319ff5cc404f1e52
SHA256 saneado: ac9424b927c142bdcd8d399cfd4cd0bd3201444850d360b078b796ac850db4a2

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Capture the actual role, column, membership and default ACL evidence."""
from pathlib import Path
import json
import os
import subprocess

from libpq_client import Connection, load_secrets, REPOSITORY_ROOT

ROLE_NAMES=('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
            'app_web','admin_datos','rol_propietario','rol_funciones')

QUERIES={
 'atributos':"""SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,
    rolreplication,rolbypassrls FROM pg_catalog.pg_roles
    WHERE rolname=ANY($1::text[]) ORDER BY rolname""",
 'tablas':"""SELECT grantor,grantee,table_schema,table_name,privilege_type,is_grantable
    FROM information_schema.role_table_grants
    WHERE grantee=ANY($1::text[]) AND table_schema IN ('public','datos_anon')
    ORDER BY grantee,table_schema,table_name,privilege_type""",
 'columnas':"""SELECT grantee,table_schema,table_name,column_name,privilege_type,is_grantable
    FROM information_schema.role_column_grants
    WHERE grantee=ANY($1::text[]) AND table_schema IN ('public','datos_anon')
    ORDER BY grantee,table_schema,table_name,column_name,privilege_type""",
 'membresias':"""SELECT member.rolname AS miembro, parent.rolname AS rol,
    m.admin_option,m.inherit_option,m.set_option
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles member ON member.oid=m.member
    JOIN pg_catalog.pg_roles parent ON parent.oid=m.roleid
    WHERE member.rolname=ANY($1::text[]) ORDER BY 1,2""",
 'funciones':"""SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),
    r.rolname AS propietario,p.prosecdef,p.proconfig::text,p.proacl::text
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
    WHERE n.nspname='public' ORDER BY p.proname""",
 'defaults':"""SELECT pg_catalog.pg_get_userbyid(defaclrole) AS creador,
    COALESCE(n.nspname,'<global>') AS esquema,defaclobjtype,defaclacl::text
    FROM pg_catalog.pg_default_acl d
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid=d.defaclnamespace
    ORDER BY 1,2,3""",
 'propietarios':"""SELECT n.nspname,c.relname,c.relkind,r.rolname AS propietario
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
    WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m','S')
    ORDER BY 1,2""",
 'acl_tablas_catalogo':"""SELECT n.nspname,c.relname,
    CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
    a.privilege_type,a.is_grantable
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
    WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m')
    ORDER BY 1,2,3,4""",
 'esquemas_efectivos':"""SELECT r.rolname,n.nspname,
    has_schema_privilege(r.oid,n.oid,'USAGE') AS puede_usar,
    has_schema_privilege(r.oid,n.oid,'CREATE') AS puede_crear
    FROM pg_roles r CROSS JOIN pg_namespace n
    WHERE r.rolname=ANY($1::text[]) AND n.nspname IN ('public','datos_anon','crypto')
    ORDER BY 1,2""",
 'base_efectivos':"""SELECT rolname,
    has_database_privilege(oid,current_database(),'CONNECT') AS puede_conectar,
    has_database_privilege(oid,current_database(),'CREATE') AS puede_crear_esquemas,
    has_database_privilege(oid,current_database(),'TEMPORARY') AS puede_crear_temporales
    FROM pg_roles WHERE rolname=ANY($1::text[]) ORDER BY 1""",
}


def main():
    private=load_secrets()
    evidence=REPOSITORY_ROOT/'docs'/'evidencias'
    evidence.mkdir(exist_ok=True)
    environment=os.environ.copy()
    for key in ('PGHOSTADDR','PGSERVICE','PGSERVICEFILE','PGOPTIONS'):
        environment.pop(key,None)
    environment['PGPASSWORD']=private['bootstrap_password']
    environment['PGCLIENTENCODING']='UTF8'
    environment['PGAPPNAME']='u5_acl_psql'
    base=[r'C:\Program Files\PostgreSQL\17\bin\psql.exe','-X',
        '--host',private['host'],'--port',str(private['port']),
        '--dbname',private['database'],'--username',private['bootstrap_user'],
        '--set','ON_ERROR_STOP=1']
    for command,filename in [('\\du','a_psql_du.txt'),('\\ddp','a_psql_ddp.txt')]:
        result=subprocess.run(base+['--command',command],env=environment,
            capture_output=True,text=True,encoding='utf-8',errors='replace',check=False)
        if result.returncode:
            raise RuntimeError('Role/default capture failed; no raw errors exported')
        (evidence/filename).write_text(result.stdout,encoding='utf-8')
    outputs={}
    with Connection(private['bootstrap_user'],application_name='u5_acl_capture') as db:
        for name,sql in QUERIES.items():
            params=['{'+','.join(ROLE_NAMES)+'}'] if '$1' in sql else None
            rows=db.execute(sql,params)
            outputs[name]={'columnas':rows.columns,'filas':rows.rows}
        timestamp=db.scalar('SELECT current_timestamp::text')
    target=evidence/'a_permisos.json'
    target.write_text(json.dumps({'fecha':timestamp,'origen':'Consultas reales PostgreSQL',
        'evidencia':outputs},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for name,content in outputs.items():
        lines=['\t'.join(content['columnas'])]
        lines += ['\t'.join('NULL' if v is None else str(v) for v in row) for row in content['filas']]
        (evidence/f'a_{name}.tsv').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('Captured actual roles, table/column privileges, memberships and default ACLs.')


if __name__=='__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\crear_cuenta_prueba.py

SHA256 original: 30c4d0c5724830691c0b8bdd6b14b5dcf0d99ec268f8e8620beb2546b537e664
SHA256 saneado: 7ea96340b8e774165167d49bff33a0b73b492c88113254420c4e1463ce48584b

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Add one synthetic business account without changing inherited user records.

Run only during private bootstrap (log_statement=none, error statements=panic).
Secrets are bound parameters. No password/hash or personal row is printed.
"""
from pathlib import Path
import json

from libpq_client import Connection, load_secrets


def main():
    secret = load_secrets()
    with Connection(secret["bootstrap_user"], application_name="u5_setup_fixture") as db:
        if db.scalar("SHOW log_statement") != "none":
            raise RuntimeError("Create the account before enabling statement logging")
        db.execute("BEGIN")
        try:
            db.execute("CREATE SCHEMA IF NOT EXISTS crypto")
            db.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA crypto")
            existing = db.scalar("SELECT id FROM public.usuario WHERE email=$1::text", [secret["business_email"]])
            if existing is not None:
                raise RuntimeError("Synthetic account already exists; refusing to change it")
            old_count = db.scalar("SELECT count(*) FROM public.usuario")
            old_hash = db.scalar("SELECT md5(string_agg(row_to_json(u)::text,'|' ORDER BY id)) FROM public.usuario u")
            added = db.scalar("""INSERT INTO public.usuario
                (nombre,apellido,email,contrasena,telefono,created_at)
                VALUES ('Cuenta','Laboratorio',$1::text,
                    crypto.crypt($2::text,crypto.gen_salt('bf',10)),NULL,current_timestamp)
                RETURNING id""", [secret["business_email"], secret["business_password"]])
            unchanged = db.scalar("""SELECT md5(string_agg(row_to_json(u)::text,'|' ORDER BY id))
                FROM public.usuario u WHERE id <> $1::bigint""", [added])
            if old_hash != unchanged:
                raise RuntimeError("Inherited-user fingerprint changed")
            db.execute("COMMIT")
        except Exception:
            db.execute("ROLLBACK")
            raise
    evidence = {"usuarios_heredados":int(old_count),"cuentas_sinteticas_agregadas":1,
                "usuarios_totales":int(old_count)+1,"huella_heredada_antes":old_hash,
                "huella_heredada_despues":unchanged,"conservacion_verificada":old_hash==unchanged,
                "clave": "Aleatoria y privada; no incluida en esta evidencia"}
    target = Path(__file__).resolve().parents[1]/"docs"/"continuidad_verificada.json"
    target.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Synthetic account created; inherited-user fingerprint unchanged.")


if __name__ == "__main__":
    main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\ejecutar_anonimizacion.py

SHA256 original: f3673a1526c29ee348b5af191d7beb9230c44817ccb8ee3754119bf9c2adfe36
SHA256 saneado: 32e309c32bb073189dc328693adca0454be6b0eaf883936c00765ff1660148c8

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Execute and capture Part D; exported evidence contains aggregates only."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from libpq_client import Connection, load_secrets

ROOT=Path(__file__).resolve().parents[1]
GROUP_REAL="""SELECT date_trunc('month',created_at AT TIME ZONE
 'America/Argentina/Buenos_Aires')::date AS mes_alta,eliminado,count(*) AS cantidad
 FROM public.usuario GROUP BY 1,2"""
GROUP_ANON="""SELECT mes_alta,eliminado,count(*) AS cantidad
 FROM datos_anon.usuario_anon GROUP BY 1,2"""


def effective_sql(source: str, *, bootstrap: bool) -> str:
    """Adapt only the unique creator line for explicit pre-A preparation."""
    creator_line=re.compile(r'^[ \t]*SET[ \t]+LOCAL[ \t]+ROLE[ \t]+rol_propietario;[ \t]*\r?$',
                            re.MULTILINE | re.IGNORECASE)
    if len(creator_line.findall(source))!=1:
        raise RuntimeError('Part D SQL must contain one unambiguous creator line')
    if bootstrap:
        return creator_line.sub('CREATE SCHEMA IF NOT EXISTS datos_anon;',source,count=1)
    return source


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bootstrap',action='store_true',
        help='Explicit pre-A mode: create the anonymous schema as bootstrap instead of SET LOCAL ROLE')
    args=parser.parse_args()
    secret=load_secrets()
    sql=ROOT/'sql'/'usuario_anon.sql'
    if not sql.is_file(): raise RuntimeError('Part D SQL is missing')
    source_bytes=sql.read_bytes()
    sqltext=effective_sql(source_bytes.decode('utf-8-sig'),bootstrap=args.bootstrap).encode('utf-8')
    environment=os.environ.copy()
    for key in ('PGHOSTADDR','PGSERVICE','PGSERVICEFILE','PGOPTIONS'):
        environment.pop(key,None)
    environment['PGPASSWORD']=secret['bootstrap_password']
    environment['PGCLIENTENCODING']='UTF8'
    environment['PGAPPNAME']='u5_anonymize_psql'
    command=[r'C:\Program Files\PostgreSQL\17\bin\psql.exe','-X',
        '--host',secret['host'],'--port',str(secret['port']),
        '--dbname',secret['database'],'--username',secret['bootstrap_user'],
        '--set','ON_ERROR_STOP=1','--file','-']
    # A byte payload preserves the exact effective SQL whose SHA-256 is
    # recorded, without Windows text-pipe newline conversion or a temp SQL file.
    completed=subprocess.run(command,env=environment,capture_output=True,
        input=sqltext,shell=False,check=False)
    # No raw errors are exported or printed. The SQL deliberately selects
    # only aggregates; the captured stdout is an actual psql execution.
    if completed.returncode:
        raise RuntimeError('Part D SQL failed; no evidence of success was generated')
    (ROOT/'docs'/'d_ejecucion_psql.txt').write_bytes(completed.stdout)
    with Connection(secret['bootstrap_user'],host=secret['host'],port=secret['port'],
                    dbname=secret['database'],application_name='u5_equivalencia') as db:
        db.execute('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        real=db.execute(GROUP_REAL+' ORDER BY 1,2')
        anon=db.execute(GROUP_ANON+' ORDER BY 1,2')
        diffs=db.execute('WITH origen AS ('+GROUP_REAL+'), copia AS ('+GROUP_ANON+''')
          SELECT 'origen_menos_copia' AS sentido,count(*) AS diferencias FROM
            (TABLE origen EXCEPT ALL TABLE copia) x
          UNION ALL
          SELECT 'copia_menos_origen',count(*) FROM
            (TABLE copia EXCEPT ALL TABLE origen) x''')
        before_hash=json.loads((ROOT/'docs'/'continuidad_verificada.json').read_text(encoding='utf-8'))['huella_heredada_antes']
        now_hash=db.scalar("SELECT md5(string_agg(row_to_json(u)::text,'|' ORDER BY id)) FROM public.usuario u WHERE id<=20000")
        timestamp=db.scalar('SELECT current_timestamp::text')
        counts=[int(db.scalar('SELECT count(*) FROM '+name)) for name in ('public.usuario','datos_anon.usuario_anon')]
        columns=db.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='datos_anon' AND table_name='usuario_anon' ORDER BY ordinal_position").rows
        table_owner=db.scalar("SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE oid='datos_anon.usuario_anon'::regclass")
        reports_exist=db.scalar("SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='rol_reportes')")=='t'
        reports_select=(db.scalar("SELECT pg_catalog.has_table_privilege('rol_reportes','datos_anon.usuario_anon','SELECT')")=='t'
                        if reports_exist else None)
        db.execute('COMMIT')
    if real.rows!=anon.rows or any(int(row[1])!=0 for row in diffs.rows) or now_hash!=before_hash:
        raise RuntimeError('Part D equivalence/conservation gate failed')
    expected_owner=secret['bootstrap_user'] if args.bootstrap else 'rol_propietario'
    if table_owner!=expected_owner or (not args.bootstrap and reports_select is not True):
        raise RuntimeError('Part D creator/reporting privilege gate failed')
    evidence={'fecha':timestamp,'columnas_agregadas':real.columns,
        'resultado_real':real.rows,'resultado_anon':anon.rows,
        'diferencias_except_all':diffs.rows,'conteos':counts,
        'columnas_copia':[x[0] for x in columns],
        'usuarios_heredados_intactos':now_hash==before_hash,
        'equivalencia_verificada':True,'sql_ejecutado_realmente':True,
        'modo_ejecucion':'bootstrap' if args.bootstrap else 'propietario',
        'sql_fuente_sha256':hashlib.sha256(source_bytes).hexdigest(),
        'sql_efectivo_sha256':hashlib.sha256(sqltext).hexdigest(),
        'propietario_tabla':table_owner,'rol_reportes_existe':reports_exist,
        'rol_reportes_select':reports_select}
    (ROOT/'docs'/'d_equivalencia.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    rows=['| Mes local de alta | Eliminado | Usuario real | Usuario anon | Coincide |',
          '|---|---|---:|---:|---|']
    for left,right in zip(real.rows,anon.rows):
        rows.append(f'| {left[0]} | {left[1]} | {left[2]} | {right[2]} | Sí |')
    (ROOT/'docs'/'d_resultados_lado_a_lado.md').write_text('\n'.join(rows)+'\n',encoding='utf-8')
    print(f'Part D verified: {counts[0]} users; {len(real.rows)} groups; differences 0/0.')


if __name__=='__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\ejecutar_pruebas.py

SHA256 original: 193087d9e0a3a258fe0a3be7a164a742f204088516f3e6e578999e8d13e5fbb6
SHA256 saneado: aae4901ce7e72f2c416905bc25c115e55c80de6f852471dabc536b9c2d82f3d8

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Run real U5 role/audit/incident checks after roles.sql has been applied.

Importing this module runs nothing. Authentication/reset parameters use libpq
binds. Evidence contains roles, timestamps, counts, booleans and SQLSTATE only;
it never contains a business email, password, hash, raw error or usuario row.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import secrets as random_secrets
import sys

from libpq_client import (
    Connection, ConnectionFailure, DatabaseError, ConfigurationError,
    DEFAULT_HOST, DEFAULT_PORT, DEFAULT_DATABASE, REPOSITORY_ROOT, load_secrets,
)


class VerificationFailure(RuntimeError):
    """A deliberately non-sensitive verification failure."""


PUBLIC_USER_COLUMNS = ["id", "nombre", "apellido", "eliminado", "created_at"]
CONTACT_COLUMNS = ["id", "nombre", "apellido", "email", "telefono", "eliminado"]
GROUP_ROLES = ["rol_app_lectura", "rol_app_escritura", "rol_soporte", "rol_reportes"]
LOGIN_ROLES = ["app_web", "admin_datos"]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def ensure(condition: bool, label: str) -> None:
    if not condition:
        raise VerificationFailure(label)


def bool_value(value) -> bool:
    ensure(value in {"t", "f", "true", "false", True, False}, "Unexpected boolean result")
    return value in {"t", "true", True}


def load_queries(filename: str) -> dict[str, str]:
    text = (REPOSITORY_ROOT/"sql"/filename).read_text(encoding="utf-8")
    result = {}
    current = None
    lines = []
    for line in text.splitlines():
        marker = re.fullmatch(r"\s*--\s*name:\s*([a-z0-9_]+)\s*", line)
        if marker:
            if current:
                result[current] = "\n".join(lines).strip()
            current, lines = marker.group(1), []
        elif current and not line.lstrip().startswith("--"):
            lines.append(line)
    if current:
        result[current] = "\n".join(lines).strip()
    ensure(bool(result) and all(result.values()), "SQL catalog is missing named statements")
    return result


class Harness:
    def __init__(self, *, secret_file=None, evidence_dir=None):
        self.secret_file = secret_file
        self.private = load_secrets(secret_file)
        self.bootstrap_user = self.private.get("bootstrap_user", "u5_bootstrap")
        self.app_user = self.private.get("app_user", "app_web")
        self.admin_user = self.private.get("admin_user", "admin_datos")
        ensure(self.app_user == "app_web" and self.admin_user == "admin_datos", "Unexpected laboratory login role configuration")
        self.evidence_dir = Path(evidence_dir or REPOSITORY_ROOT/"docs"/"evidencias").resolve()
        self.evidence_dir.mkdir(parents=True, exist_ok=True)
        self.current_evidence = None

    def connect(self, user: str, application: str, password=None) -> Connection:
        return Connection(
            user, password, application_name=application, secret_file=self.secret_file,
            host=self.private.get("host", DEFAULT_HOST),
            port=self.private.get("port", DEFAULT_PORT),
            dbname=self.private.get("dbname", self.private.get("database", DEFAULT_DATABASE)),
        )

    def credentials(self) -> tuple[str, str]:
        auth = self.private.get("app_auth", {})
        email = self.private.get("business_email") or auth.get("email")
        password = self.private.get("business_password") or auth.get("password")
        ensure(isinstance(email, str) and isinstance(password, str) and bool(email) and bool(password), "Business authentication fixture is not configured")
        return email, password

    def record(self, step: str, actor: str, **safe_fields) -> None:
        ensure(self.current_evidence is not None, "No active evidence phase")
        self.current_evidence["events"].append({
            "timestamp_utc": utc_now(), "step": step, "actor": actor, **safe_fields,
        })

    def fixture_id(self, bootstrap: Connection) -> str:
        email, _ = self.credentials()
        value = bootstrap.scalar("SELECT id FROM public.usuario WHERE email=$1::text AND eliminado=FALSE;", [email])
        ensure(value is not None and value.isdigit(), "Business authentication fixture was not found")
        return value

    def counts(self, bootstrap: Connection) -> dict:
        result = bootstrap.execute("""
SELECT (SELECT count(*) FROM public.usuario),
       (SELECT count(*) FROM public.pedido),
       (SELECT count(*) FROM public.detalle_pedido);
""")
        return dict(zip(("usuario", "pedido", "detalle_pedido"), map(int, result.rows[0])))

    def verify_logging_prerequisites(self, phase: str) -> None:
        # Check before sending any email/password parameter. These names and
        # setting values are configuration metadata, not business-user data.
        with self.connect(self.bootstrap_user, "u5_logging_verifier") as bootstrap:
            result = bootstrap.execute("""
SELECT name,setting FROM pg_catalog.pg_settings
WHERE name IN ('log_parameter_max_length','log_parameter_max_length_on_error',
               'log_statement','log_connections','log_disconnections',
               'log_min_error_statement') ORDER BY name;
""")
            settings = dict(result.rows)
        ensure(settings.get("log_parameter_max_length") == "0"
               and settings.get("log_parameter_max_length_on_error") == "0",
               "Parameter logging must be disabled before credential checks")
        if phase in {"audit", "incident"}:
            ensure(settings.get("log_statement") == "all"
                   and settings.get("log_connections") == "on"
                   and settings.get("log_disconnections") == "on"
                   and settings.get("log_min_error_statement") == "error",
                   "Native audit logging is not configured for the requested phase")
        self.current_evidence["runtime_logging"] = settings
        self.record("logging_prerequisites_verified", self.bootstrap_user,
                    bind_parameters_logged=False, credential_checks_started=False)

    def expect_error(self, connection: Connection, *, name: str, actor: str,
                     sql: str, expected: str, params=None, savepoint=False) -> None:
        if savepoint:
            connection.execute("SAVEPOINT u5_expected_rejection;")
        observed = None
        try:
            result = connection.execute(sql, params)
            del result
        except DatabaseError as error:
            observed = error.sqlstate
            if observed != expected:
                self.record(name, actor, expected_sqlstate=expected, observed_sqlstate=observed,
                            rejection_verified=False)
            ensure(observed == expected, "Unexpected SQLSTATE in permission verification")
        finally:
            if savepoint:
                connection.execute("ROLLBACK TO SAVEPOINT u5_expected_rejection;")
                connection.execute("RELEASE SAVEPOINT u5_expected_rejection;")
        self.record(name, actor, expected_sqlstate=expected, observed_sqlstate=observed,
                    rejection_verified=observed == expected)
        ensure(observed == expected, "An operation requiring rejection unexpectedly succeeded")

    def phase_audit(self) -> dict:
        queries = load_queries("auditoria_test.sql")
        with self.connect(self.bootstrap_user, "u5_audit_verifier") as bootstrap:
            before = self.counts(bootstrap)
            business_id = self.fixture_id(bootstrap)
            with self.connect(self.app_user, "u5_audit_test") as app:
                app.execute(queries["audit_begin"])
                try:
                    catalog = app.execute(queries["audit_catalog_read"])
                    ensure(bool(catalog.rows), "No active product has sufficient stock for the reversible fixture")
                    product_id, catalog_price = catalog.rows[0][:2]
                    self.record("read_catalog", self.app_user, rows_received=len(catalog.rows), columns=catalog.columns)
                    del catalog
                    order = app.execute(queries["audit_insert_order"], [business_id])
                    ensure(len(order.rows) == 1 and len(order.rows[0]) == 2
                           and order.rows[0][0].isdigit() and order.rows[0][1] == "PENDIENTE",
                           "Order INSERT did not return one identity in the initial pending state")
                    order_id = order.rows[0][0]
                    self.record("insert_pending_order", self.app_user, successful=True,
                                rows_inserted=len(order.rows), initial_state_pending=True)
                    del order
                    inserted = app.execute(queries["audit_insert_detail"], [order_id, product_id, catalog_price])
                    ensure(len(inserted.rows) == 1 and bool_value(inserted.rows[0][0]), "Detail INSERT did not create the expected row")
                    self.record("insert_detail", self.app_user, successful=True, rows_inserted=len(inserted.rows))
                    del inserted
                    updated = app.execute(queries["audit_update_detail"], [order_id, product_id])
                    ensure(len(updated.rows) == 1 and updated.rows[0][0] == "2", "Detail UPDATE did not change the expected row")
                    self.record("update_pending_detail", self.app_user, successful=True, rows_updated=len(updated.rows))
                    del updated
                    ensure(bool_value(app.scalar(queries["audit_order_total_invariant"], [order_id])), "Inherited order-total invariant failed")
                    self.record("inherited_total_verified", self.app_user, invariant_holds=True)
                    confirmed = app.execute(queries["audit_confirm_order"], [order_id])
                    ensure(len(confirmed.rows) == 1 and bool_value(confirmed.rows[0][0]), "Order state UPDATE did not confirm the expected row")
                    self.record("valid_state_transition", self.app_user, successful=True, rows_updated=len(confirmed.rows))
                    del confirmed
                finally:
                    app.execute(queries["audit_rollback"])
                    self.record("rollback_test_data", self.app_user, rolled_back=True)
            after = self.counts(bootstrap)
            ensure(before == after, "Audit test left persistent source rows")
            self.record("source_counts_preserved", self.bootstrap_user, before=before, after=after)
        wrong = random_secrets.token_urlsafe(32)
        try:
            bad = self.connect(self.app_user, "u5_audit_failed_login", wrong)
        except ConnectionFailure as error:
            ensure(error.classification == "password_authentication_failed",
                   "Invalid-login probe failed for a reason other than password authentication")
            self.record("postgresql_login_failed", self.app_user, failure_type=type(error).__name__,
                        classification=error.classification, observed_sqlstate=error.sqlstate,
                        sqlstate_source="No PGresult is available during handshake; inspect the actual server log")
        else:
            bad.close()
            raise VerificationFailure("The deliberately invalid PostgreSQL login unexpectedly succeeded")
        return {"counts_before": before, "counts_after": after,
                "data_rolled_back": True, "postgresql_failed_login_verified": True,
                "identity_sequence_values_restored": False,
                "note": "ROLLBACK removes the test rows but does not recover consumed identity values or delete audit logs. Native statement logs record attempts, including rolled-back work. No user rows are exported."}

    def phase_incident(self) -> dict:
        queries = load_queries("simulacro_incidente.sql")
        email, password = self.credentials()
        with self.connect(self.bootstrap_user, "u5_verifier_incident") as bootstrap:
            expected_count = int(bootstrap.scalar("SELECT count(*) FROM public.usuario;"))
            expected_id = self.fixture_id(bootstrap)
            before_member = bool_value(bootstrap.scalar(queries["incident_membership_check"]))
            ensure(not before_member, "Privilege model already grants the forbidden administrative membership")
            self.record("membership_before", self.bootstrap_user, administrative_membership=False)
            with self.connect(self.app_user, "u5_incident") as app:
                actor = app.execute("SELECT session_user,current_user;").rows[0]
                ensure(actor == (self.app_user, self.app_user), "Incident is not executing under the intended low-privilege login")
                self.record("database_actor_verified", self.app_user, session_role=actor[0], current_role=actor[1])
                for attempt in range(1, 4):
                    wrong = random_secrets.token_urlsafe(32)
                    while wrong == password:
                        wrong = random_secrets.token_urlsafe(32)
                    accepted = app.scalar(queries["incident_authenticate"], [email, wrong])
                    ensure(accepted is None, "A deliberately invalid business password was accepted")
                    self.record("business_authentication", self.app_user, attempt=attempt, accepted=False)
                accepted = app.scalar(queries["incident_authenticate"], [email, password])
                ensure(accepted == expected_id, "The correct business credential was not accepted for the fixture")
                self.record("business_authentication", self.app_user, attempt=4, accepted=True)
                actor_after = app.execute("SELECT session_user,current_user;").rows[0]
                ensure(actor_after == actor, "Business authentication unexpectedly changed the database role")
                self.record("database_actor_after_business_auth", self.app_user,
                            session_role=actor_after[0], current_role=actor_after[1], role_unchanged=True)
                mass = app.execute(queries["incident_bulk_read"])
                received_count = len(mass.rows)
                columns = list(mass.columns)
                ensure(columns == PUBLIC_USER_COLUMNS and "contrasena" not in columns, "Bulk SELECT projected an unexpected or credential column")
                ensure(received_count == expected_count, "Bulk SELECT did not actually retrieve the complete authorized projection")
                self.record("bulk_read_received_and_discarded", self.app_user,
                            rows_received=received_count, expected_rows=expected_count,
                            columns=columns, credential_column_present=False, user_values_exported=False)
                del mass
                self.expect_error(app, name="administrative_membership_escalation",
                                  actor=self.app_user, sql=queries["incident_attempt_escalation"], expected="42501")
            after_member = bool_value(bootstrap.scalar(queries["incident_membership_check"]))
            ensure(not after_member, "Forbidden administrative membership appeared after the attempted escalation")
            self.record("membership_after", self.bootstrap_user, administrative_membership=False)
        return {"failed_business_authentications": 3, "successful_business_authentications": 1,
                "rows_received": received_count, "expected_rows": expected_count,
                "escalation_sqlstate": "42501", "membership_before": before_member,
                "membership_after": after_member, "user_values_exported": False,
                "containment_executed": False,
                "evidence_limit": "The client proves the received-row count; the native SELECT log alone does not prove row delivery, off-host extraction or malicious intent."}

    def permission_snapshot(self, bootstrap: Connection) -> dict:
        roles = GROUP_ROLES+LOGIN_ROLES+["rol_propietario", "rol_funciones"]
        result = bootstrap.execute("""
SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls
FROM pg_catalog.pg_roles WHERE rolname=ANY($1::text[]) ORDER BY rolname;
""", ["{"+",".join(roles)+"}"])
        ensure(len(result.rows) == len(roles), "One or more specified roles are missing")
        snapshot = []
        for row in result.rows:
            name, canlogin, *dangerous = row
            ensure(not any(bool_value(v) for v in dangerous), "A laboratory role has a forbidden administrative attribute")
            ensure(bool_value(canlogin) == (name in LOGIN_ROLES), "Unexpected LOGIN attribute")
            snapshot.append(dict(zip(result.columns, [name, bool_value(canlogin)]+[bool_value(v) for v in dangerous])))
        for login in LOGIN_ROLES:
            for owner in ("rol_propietario", "rol_funciones"):
                ensure(not bool_value(bootstrap.scalar("SELECT pg_catalog.pg_has_role($1::name,$2::name,'MEMBER');", [login, owner])), "An application login inherits a protected owner role")
        return {"roles": snapshot}

    def phase_permissions(self) -> dict:
        """Behavior matrix based on the final Kiro specification and review.

        Run after the actual generated requirements/design and roles.sql have
        been reviewed. The full ACL dump/exact specification comparison remains
        an additional deliverable; these tests do not replace that comparison.
        """
        with self.connect(self.bootstrap_user, "u5_permissions_verifier") as bootstrap:
            snapshot = self.permission_snapshot(bootstrap)
            sequence_last = bootstrap.scalar("SELECT last_value::bigint FROM public.pedido_id_seq;")
            business_id = self.fixture_id(bootstrap)
            missing_business_id = bootstrap.scalar("SELECT (COALESCE(MAX(id),0)+1)::text FROM public.usuario;")
        with self.connect(self.app_user, "u5_permissions_app") as app:
            app.execute("BEGIN;")
            try:
                for label, sql in (
                    ("deny_user_credentials_read", "SELECT contrasena FROM public.usuario LIMIT 1;"),
                    ("deny_user_star_read", "SELECT * FROM public.usuario LIMIT 1;"),
                    ("deny_user_credentials_update", "UPDATE public.usuario SET contrasena=contrasena WHERE FALSE;"),
                    ("deny_user_delete", "DELETE FROM public.usuario WHERE FALSE;"),
                    ("deny_order_delete", "DELETE FROM public.pedido WHERE FALSE;"),
                    ("deny_derived_order_total_update", "UPDATE public.pedido SET total=total WHERE FALSE;"),
                    ("deny_admin_set_role", "SET ROLE admin_datos;"),
                    ("deny_owner_set_role", "SET ROLE rol_propietario;"),
                    ("deny_inherited_group_set_role", "SET ROLE rol_app_lectura;"),
                    ("deny_role_creation", "CREATE ROLE u5_unexpected_role_probe NOLOGIN;"),
                ):
                    self.expect_error(app, name=label, actor=self.app_user, sql=sql, expected="42501", savepoint=True)
                for privilege in ("USAGE", "SELECT", "UPDATE"):
                    allowed = bool_value(app.scalar("SELECT pg_catalog.has_sequence_privilege(current_user,'public.pedido_id_seq',$1::text);", [privilege]))
                    ensure(not allowed, "Direct identity-sequence privilege is broader than specified")
                    self.record("identity_sequence_acl", self.app_user, privilege=privilege, allowed=False)
                self.expect_error(app, name="deny_direct_nextval", actor=self.app_user,
                                  sql="SELECT pg_catalog.nextval('public.pedido_id_seq'::regclass);", expected="42501", savepoint=True)
                self.expect_error(app, name="deny_direct_setval", actor=self.app_user,
                                  sql="SELECT pg_catalog.setval('public.pedido_id_seq'::regclass,$1::bigint,TRUE);",
                                  params=[sequence_last], expected="42501", savepoint=True)
                self.expect_error(app, name="deny_password_reset_function", actor=self.app_user,
                                  sql="SELECT public.fn_resetear_password($1::bigint,$2::text);",
                                  params=[business_id, self.credentials()[1]], expected="42501", savepoint=True)
                for column in ("subtotal",):
                    allowed = bool_value(app.scalar("SELECT pg_catalog.has_column_privilege(current_user,'public.detalle_pedido',$1::text,'UPDATE');", [column]))
                    ensure(not allowed, "Generated detail value is directly writable by the application")
                    self.record("deny_generated_column_acl", self.app_user, column=column, allowed=False)
            finally:
                app.execute("ROLLBACK;")
        with self.connect(self.admin_user, "u5_permissions_admin") as admin:
            admin.execute("BEGIN;")
            try:
                read = admin.execute("SELECT id,nombre,apellido,email,telefono,eliminado FROM public.usuario LIMIT 1;")
                ensure(read.columns == CONTACT_COLUMNS, "Support received columns outside its final specification")
                self.record("support_contact_read", self.admin_user, rows_received=len(read.rows), columns=read.columns)
                del read
                contact_update = admin.execute("UPDATE public.usuario SET telefono=telefono WHERE FALSE RETURNING 1;")
                ensure(not contact_update.rows, "The empty support UPDATE unexpectedly changed rows")
                self.record("support_contact_update", self.admin_user, successful=True,
                            rows_updated=len(contact_update.rows))
                del contact_update
                admin.execute("SELECT public.fn_resetear_password($1::bigint,$2::text);", [business_id, self.credentials()[1]])
                self.record("admin_password_reset_allowed", self.admin_user, successful=True, rolled_back=True)
                for label, sql in (
                    ("deny_support_hash_read", "SELECT contrasena FROM public.usuario LIMIT 1;"),
                    ("deny_support_created_at_read", "SELECT created_at FROM public.usuario LIMIT 1;"),
                    ("deny_support_user_delete", "DELETE FROM public.usuario WHERE FALSE;"),
                    ("deny_support_order_read", "SELECT id FROM public.pedido LIMIT 1;"),
                    ("deny_support_other_column_update", "UPDATE public.usuario SET nombre=nombre WHERE FALSE;"),
                    ("deny_support_email_update", "UPDATE public.usuario SET email=email WHERE FALSE;"),
                    ("deny_support_owner_set_role", "SET ROLE rol_propietario;"),
                    ("deny_support_function_owner_set_role", "SET ROLE rol_funciones;"),
                ):
                    self.expect_error(admin, name=label, actor=self.admin_user,
                                      sql=sql, expected="42501", savepoint=True)
                self.expect_error(admin, name="reset_missing_user_rejected", actor=self.admin_user,
                                  sql="SELECT public.fn_resetear_password($1::bigint,$2::text);",
                                  params=[missing_business_id, self.credentials()[1]],
                                  expected="P0002", savepoint=True)
                for label, invalid in (
                    ("reset_password_null_rejected", None),
                    ("reset_password_11_bytes_rejected", random_secrets.token_urlsafe(16)[:11]),
                    ("reset_password_73_bytes_rejected", random_secrets.token_urlsafe(64)[:73]),
                    ("reset_password_multibyte_74_bytes_rejected", "\u00e9"*37),
                ):
                    self.expect_error(admin, name=label, actor=self.admin_user,
                                      sql="SELECT public.fn_resetear_password($1::bigint,$2::text);",
                                      params=[business_id, invalid], expected="22023", savepoint=True)
                for byte_length in (12, 72):
                    boundary = random_secrets.token_urlsafe(64)[:byte_length]
                    reset = admin.execute("SELECT public.fn_resetear_password($1::bigint,$2::text);",
                                          [business_id, boundary])
                    ensure(len(reset.rows) == 1, "A valid password boundary was not accepted")
                    self.record("reset_password_boundary_allowed", self.admin_user,
                                password_bytes=byte_length, successful=True, rolled_back=True)
                    del reset, boundary
            finally:
                admin.execute("ROLLBACK;")
        with self.connect(self.bootstrap_user, "u5_permissions_groups") as bootstrap:
            for role in GROUP_ROLES:
                bootstrap.execute("BEGIN;")
                try:
                    bootstrap.execute("SET LOCAL ROLE "+role+";")
                    if role == "rol_app_lectura":
                        result = bootstrap.execute("SELECT id,nombre,apellido,eliminado,created_at FROM public.usuario LIMIT 1;")
                        self.record("reader_projection_allowed", role, rows_received=len(result.rows), columns=result.columns)
                        del result
                        self.expect_error(bootstrap, name="reader_write_denied", actor=role,
                                          sql="UPDATE public.producto SET stock=stock WHERE FALSE;", expected="42501", savepoint=True)
                    elif role == "rol_app_escritura":
                        allowed = bool_value(bootstrap.scalar("SELECT pg_catalog.has_column_privilege(current_user,'public.pedido','usuario_id','INSERT');"))
                        ensure(allowed, "Writer group lacks its scoped order INSERT")
                        self.record("writer_scoped_insert_acl", role, allowed=True)
                        ensure(not bool_value(bootstrap.scalar("SELECT pg_catalog.has_column_privilege(current_user,'public.pedido','total','UPDATE');")), "Writer group directly controls a derived total")
                    elif role == "rol_soporte":
                        result = bootstrap.execute("SELECT email,telefono FROM public.usuario LIMIT 1;")
                        self.record("support_group_contact_read", role, rows_received=len(result.rows), columns=result.columns)
                        del result
                    elif role == "rol_reportes":
                        count = int(bootstrap.scalar("SELECT count(*) FROM public.mv_u4_ventas_categoria_dia;"))
                        self.record("reports_aggregate_read", role, rows_received=1, aggregate_groups=count)
                        self.expect_error(bootstrap, name="reports_base_user_read_denied", actor=role,
                                          sql="SELECT id FROM public.usuario LIMIT 1;", expected="42501", savepoint=True)
                    self.expect_error(bootstrap, name="group_user_hash_read_denied", actor=role,
                                      sql="SELECT contrasena FROM public.usuario LIMIT 1;", expected="42501", savepoint=True)
                finally:
                    bootstrap.execute("ROLLBACK;")
            for role in GROUP_ROLES+LOGIN_ROLES:
                for table in ("lote", "deposito", "responsable_deposito", "lote_responsable", "control_lote_almacen"):
                    allowed = bool_value(bootstrap.scalar("SELECT pg_catalog.has_table_privilege($1::name,$2::text,'SELECT');", [role, "public."+table]))
                    ensure(not allowed, "An application/report/support role can access the protected FNBC extension")
                self.record("fnbc_extension_not_granted", role, protected_objects_checked=5, allowed=False)
        return {**snapshot, "minimum_behavioral_matrix_verified": True,
                "all_test_mutations_rolled_back": True,
                "note": "Group behavior uses bootstrap SET LOCAL ROLE, clearly distinguished from actual app_web/admin_datos login connections."}

    def verify_function_defaults(self, bootstrap: Connection) -> list[dict]:
        """Probe real creator defaults inside the caller's rolled-back transaction.

        rol_funciones gets CREATE only for this transaction, solely to create a
        harmless probe as the actual role. ROLLBACK removes the grant and all
        functions; this does not broaden the persistent implementation policy.
        """
        probes = [
            (self.bootstrap_user, "u5_default_probe_fn_bootstrap"),
            ("rol_propietario", "u5_default_probe_fn_propietario"),
            ("rol_funciones", "u5_default_probe_fn_funciones"),
        ]
        observations = []
        for creator, name in probes:
            bootstrap.execute("RESET ROLE;")
            signature = "public."+name+"()"
            ensure(bootstrap.scalar("SELECT pg_catalog.to_regprocedure($1::text);", [signature]) is None,
                   "A default-function probe already exists")
            if creator == "rol_funciones":
                ensure(not bool_value(bootstrap.scalar(
                    "SELECT pg_catalog.has_schema_privilege('rol_funciones','public','CREATE');")),
                    "The function owner unexpectedly has persistent CREATE on public")
                bootstrap.execute("GRANT CREATE ON SCHEMA public TO rol_funciones;")
            if creator != self.bootstrap_user:
                # Both alternative role names and every function name above are
                # fixed test identifiers, never configuration/user input.
                bootstrap.execute("SET LOCAL ROLE "+creator+";")
            bootstrap.execute("CREATE FUNCTION public."+name+"() RETURNS integer "
                              "LANGUAGE sql SET search_path=pg_catalog AS 'SELECT 1';")
            bootstrap.execute("RESET ROLE;")
            public_execute = int(bootstrap.scalar("""
SELECT count(*) FROM pg_catalog.pg_proc p,
LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
WHERE p.oid=$1::regprocedure AND a.grantee=0 AND a.privilege_type='EXECUTE';
""", [signature]))
            ensure(public_execute == 0, "A creator retains global PUBLIC EXECUTE on future functions")
            checked_roles = []
            for role in GROUP_ROLES+LOGIN_ROLES:
                allowed = bool_value(bootstrap.scalar(
                    "SELECT pg_catalog.has_function_privilege($1::name,$2::text,'EXECUTE');",
                    [role, signature]))
                ensure(not allowed, "A future function is executable by an unapproved business role")
                bootstrap.execute("SET LOCAL ROLE "+role+";")
                self.expect_error(bootstrap, name="future_function_execution_denied", actor=role,
                                  sql="SELECT public."+name+"();", expected="42501", savepoint=True)
                bootstrap.execute("RESET ROLE;")
                checked_roles.append(role)
            observation = {"creator_role": creator, "public_execute_entries": public_execute,
                           "denied_roles": checked_roles,
                           "temporary_create_grant": creator == "rol_funciones"}
            observations.append(observation)
            self.record("future_function_creator_default", self.bootstrap_user, **observation)
        return observations

    def phase_defaults(self) -> dict:
        with self.connect(self.bootstrap_user, "u5_defaults_verifier") as bootstrap:
            bootstrap.execute("BEGIN;")
            try:
                ensure(bootstrap.scalar("SELECT to_regclass('public.u5_default_probe_restricted');") is None,
                       "A default-privilege probe object already exists")
                ensure(bootstrap.scalar("SELECT to_regclass('datos_anon.u5_default_probe_anonymous');") is None,
                       "A default-privilege probe object already exists")
                bootstrap.execute("SET LOCAL ROLE rol_propietario;")
                bootstrap.execute("CREATE TABLE public.u5_default_probe_restricted(marker integer);")
                bootstrap.execute("CREATE TABLE datos_anon.u5_default_probe_anonymous(marker integer);")
                bootstrap.execute("RESET ROLE;")
                for role in GROUP_ROLES+LOGIN_ROLES:
                    for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE"):
                        allowed = bool_value(bootstrap.scalar("SELECT pg_catalog.has_table_privilege($1::name,'public.u5_default_probe_restricted',$2::text);", [role, privilege]))
                        ensure(not allowed, "A future public table exposes broader default privileges")
                        self.record("future_public_table_default", role, privilege=privilege, allowed=False)
                        anonymous = bool_value(bootstrap.scalar("SELECT pg_catalog.has_table_privilege($1::name,'datos_anon.u5_default_probe_anonymous',$2::text);", [role, privilege]))
                        expected = role == "rol_reportes" and privilege == "SELECT"
                        ensure(anonymous == expected, "A future anonymous table does not match the reporting-only default policy")
                        self.record("future_anonymous_table_default", role, privilege=privilege, allowed=anonymous)
                public_entries = int(bootstrap.scalar("""
SELECT count(*) FROM pg_catalog.pg_class c,
LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
WHERE c.oid IN ('public.u5_default_probe_restricted'::regclass,
               'datos_anon.u5_default_probe_anonymous'::regclass)
  AND a.grantee=0;
"""))
                ensure(public_entries == 0, "Future probe tables retain PUBLIC grants")
                bootstrap.execute("SET LOCAL ROLE rol_reportes;")
                received = int(bootstrap.scalar("SELECT count(*) FROM datos_anon.u5_default_probe_anonymous;"))
                ensure(received == 0, "Anonymous probe unexpectedly contains data")
                self.record("future_anonymous_table_select_works", "rol_reportes", rows_received=1, aggregate_count=0)
                bootstrap.execute("RESET ROLE;")
                function_defaults = self.verify_function_defaults(bootstrap)
            finally:
                bootstrap.execute("ROLLBACK;")
            remaining = int(bootstrap.scalar("""
SELECT count(*) FROM pg_catalog.pg_class
WHERE relname IN ('u5_default_probe_restricted','u5_default_probe_anonymous');
"""))
            ensure(remaining == 0, "Default-privilege probes were not rolled back")
            remaining_functions = int(bootstrap.scalar("""
SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('u5_default_probe_fn_bootstrap',
  'u5_default_probe_fn_propietario','u5_default_probe_fn_funciones');
"""))
            ensure(remaining_functions == 0, "Default-function probes were not rolled back")
            function_owner_create_after = bool_value(bootstrap.scalar(
                "SELECT pg_catalog.has_schema_privilege('rol_funciones','public','CREATE');"))
            ensure(not function_owner_create_after, "The temporary function-owner CREATE grant persisted")
        return {"creator_role": "rol_propietario", "future_public_default": "deny application access",
                "future_anonymous_default": "rol_reportes SELECT only", "public_grants": 0,
                "probe_objects_remaining": remaining, "function_defaults": function_defaults,
                "probe_functions_remaining": remaining_functions,
                "function_owner_create_after": function_owner_create_after, "rolled_back": True,
                "temporary_probe_grant": "Only transaction-scoped CREATE on public for rol_funciones; removed by ROLLBACK"}

    def run_phase(self, phase: str) -> dict:
        evidence = {"phase": phase, "status": "running", "started_at_utc": utc_now(),
                    "events": [], "private_values_exported": False}
        self.current_evidence = evidence
        try:
            self.verify_logging_prerequisites(phase)
            evidence["result"] = getattr(self, "phase_"+phase)()
            evidence["status"] = "passed"
        except DatabaseError as error:
            evidence.update(status="failed", failure={"type": type(error).__name__,
                            "sqlstate": error.sqlstate, "classification": error.classification,
                            "operation": error.operation, "status": error.status})
            raise
        except Exception as error:
            evidence.update(status="failed", failure={"type": type(error).__name__,
                            "reason": str(error) if isinstance(error, VerificationFailure) else "Local verification could not complete"})
            raise
        finally:
            evidence["finished_at_utc"] = utc_now()
            path = self.evidence_dir/(phase+"_resultados.json")
            path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
            self.current_evidence = None
        return {"phase": phase, "status": evidence["status"], "events": len(evidence["events"])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", required=True, choices=("audit", "incident", "permissions", "defaults", "all"))
    parser.add_argument("--secrets", type=Path, help="Private runtime JSON outside Git")
    parser.add_argument("--evidence-dir", type=Path, help="Public evidence directory; contains counts/roles/results only")
    args = parser.parse_args()
    try:
        harness = Harness(secret_file=args.secrets, evidence_dir=args.evidence_dir)
        phases = ("permissions", "defaults", "audit", "incident") if args.phase == "all" else (args.phase,)
        summaries = [harness.run_phase(phase) for phase in phases]
    except (ConfigurationError, VerificationFailure, DatabaseError):
        print(json.dumps({"status": "failed", "reason": "Verification stopped; inspect the sanitized phase evidence"}), file=sys.stderr)
        return 1
    except Exception:
        print(json.dumps({"status": "failed", "reason": "Local verification could not complete"}), file=sys.stderr)
        return 1
    print(json.dumps({"status": "passed", "phases": summaries}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\empaquetar_entrega.py

SHA256 original: f2fcbf7535573d07868bc0155510d1d6928326fcc3a0bab96cef8e834bdd375b
SHA256 saneado: 8136677d5b0fde0e68a1850116dc43b48c32b82c1b4fb63a143d9af462316480

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Package the deliverable and its complete Git history, then verify the ZIP.

Run --dry-run before delivery. No database or network connection is made.
The manifest covers every archived file except the manifest itself.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'food-store-tp-u5'
MANIFEST = PREFIX + '/MANIFIESTO_ENTREGA.json'
REQUIRED = (
    'sql/roles.sql', 'sql/auditoria_test.sql', 'sql/simulacro_incidente.sql',
    'sql/usuario_anon.sql', 'docs/kiro_roles_spec/requirements.md',
    'docs/kiro_roles_spec/design.md', 'docs/informe_auditoria.md',
    'docs/informe_roles.md', 'docs/continuidad_y_alcance.md',
    'docs/evidencias/a_psql_du.txt', 'docs/evidencias/a_tablas.tsv',
    'docs/evidencias/a_columnas.tsv', 'docs/evidencias/a_permisos.json',
    'docs/log_auditoria_prueba.txt', 'docs/log_simulacro_anonimizado.txt',
    'docs/informe_incidente.md', 'docs/verificacion_equivalencia.md',
    'docs/ia/c_reconstruccion_prompt.txt', 'docs/ia/c_reconstruccion_respuesta.md',
    'docs/ia/c_reconstruccion_metadatos.json',
    'BITACORA.md', 'README.md', 'docs/TP_U5_FoodStore_Arancibia_Romero.pdf',
)
EXCLUDED_PARTS = {
    '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.cache',
    '.venv', 'venv', 'node_modules', 'private', 'privado', 'privados',
    'runtime', 'logs_privados', '.opencode',
}
EXCLUDED_SUFFIXES = {'.pyc', '.pyo', '.dump', '.raw', '.pem', '.key', '.p12', '.pfx'}
SECRET_PATTERNS = (
    rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    rb'\b(?:sk-proj-|sk-)[A-Za-z0-9_-]{24,}\b',
    rb'\b(?:ghp_|gho_|ghs_|github_pat_)[A-Za-z0-9_]{24,}\b',
    rb'\bAKIA[0-9A-Z]{16}\b',
    rb'(?i)\b(?:postgres(?:ql)?|https?)://[^\s/:]+:[^\s/@]+@',
    rb'(?im)^\s*(?:PGPASSWORD|OPENAI_API_KEY|ANTHROPIC_API_KEY|AWS_SECRET_ACCESS_KEY)\s*=\s*["\']?[^\s"\'<>]{8,}',
    rb'(?i)SCRAM-SHA-256\$[0-9]+:[A-Za-z0-9+/=]+\$',
)


def git(*arguments, data=None, repo=None, allowed=(0,)):
    env = os.environ.copy()
    env['GIT_OPTIONAL_LOCKS'] = '0'
    result = subprocess.run(['git', '-C', str(repo or ROOT), *arguments], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, check=False)
    if result.returncode not in allowed:
        # Keep diagnostics free of file content, credentials and remote URLs.
        raise RuntimeError('Git verification failed: ' + arguments[0])
    return result.stdout


def excluded_name(name):
    parts = PurePosixPath(name).parts
    folded = [part.casefold() for part in parts]
    if any(part in EXCLUDED_PARTS for part in folded): return True
    basename = folded[-1] if folded else ''
    return (basename == '.env' or basename.startswith('.env.')
            or 'secret' in basename or basename in ('.pgpass', 'pgpass.conf')
            or Path(basename).suffix in EXCLUDED_SUFFIXES
            or basename.endswith(('.zip', '.partial')))


def scan_content(data, label):
    if any(re.search(pattern, data) for pattern in SECRET_PATTERNS):
        raise RuntimeError('Potential credential detected; review locally: ' + label)


def check_git_history():
    """Scan decoded objects, including unreachable objects shipped in .git."""
    listing = git('cat-file', '--batch-all-objects',
                  '--batch-check=%(objectname) %(objecttype) %(objectsize)')
    objects = []
    for row in listing.decode('ascii').splitlines():
        oid, kind, size = row.split()
        if int(size) > 50_000_000:
            raise RuntimeError('Git object exceeds the delivery review limit')
        objects.append(oid)
    raw = git('cat-file', '--batch', data=('\n'.join(objects)+'\n').encode('ascii'))
    offset = 0
    for oid in objects:
        end = raw.index(b'\n', offset)
        header = raw[offset:end].split()
        if len(header) != 3 or header[0].decode('ascii') != oid:
            raise RuntimeError('Unexpected Git object stream')
        size = int(header[2]);start = end+1
        scan_content(raw[start:start+size], 'Git object ' + oid[:12])
        offset = start+size+1
    # A formerly committed private file would also be shipped in Git history.
    for row in git('rev-list', '--objects', '--all').decode('utf-8', 'replace').splitlines():
        if ' ' in row and excluded_name(row.split(' ', 1)[1]):
            raise RuntimeError('Excluded material is present in Git history; review locally')
    return len(objects)


def inventory():
    git_dir = ROOT / '.git'
    if not git_dir.is_dir() or git_dir.is_symlink():
        raise RuntimeError('Delivery requires a standalone repository with a .git directory')
    if (git_dir/'shallow').exists() or (git_dir/'objects/info/alternates').exists():
        raise RuntimeError('Git history depends on incomplete or external objects')
    git('fsck', '--full')
    work = set(git('ls-files', '--cached', '--others', '--exclude-standard', '-z')
               .decode('utf-8').split('\0')) - {''}
    encoded = ('\0'.join(sorted(work))+'\0').encode('utf-8')
    ignored = set(git('check-ignore', '--no-index', '--stdin', '-z', data=encoded,
                      allowed=(0, 1)).decode('utf-8').split('\0')) - {''}
    names = {name for name in work-ignored if not excluded_name(name)}
    for path in git_dir.rglob('*'):
        relative = path.relative_to(ROOT).as_posix()
        if path.is_symlink(): raise RuntimeError('Symlink found in Git metadata')
        if path.name.endswith('.lock'):
            raise RuntimeError('Git operation is active; package after it finishes')
        # Hooks are executable local settings, not project history.
        if path.is_file() and not relative.startswith('.git/hooks/'):
            names.add(relative)
    if 'MANIFIESTO_ENTREGA.json' in names:
        raise RuntimeError('The manifest must be generated only inside the archive')
    for name in sorted(names):
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError('A delivery entry is missing or is a symlink: ' + name)
        if not path.resolve().is_relative_to(ROOT.resolve()):
            raise RuntimeError('Delivery entry is outside the repository')
    return sorted(names)


def verify_archive(path, expected_head=None):
    with ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)): raise RuntimeError('Duplicate archive entries')
        if sum(info.file_size for info in archive.infolist()) > 250_000_000:
            raise RuntimeError('Archive exceeds the delivery review limit')
        for name in names:
            parts = PurePosixPath(name).parts
            if (not parts or parts[0] != PREFIX or '..' in parts
                    or '\\' in name or name.startswith('/')
                    or any(':' in part or part.endswith((' ', '.')) for part in parts)):
                raise RuntimeError('Unsafe archive member')
        if archive.testzip() is not None: raise RuntimeError('ZIP CRC verification failed')
        manifest = json.loads(archive.read(MANIFEST))
        expected = {PREFIX+'/'+entry['path']: entry for entry in manifest['files']}
        if set(names) != set(expected) | {MANIFEST}:
            raise RuntimeError('Archive content does not match the manifest')
        for name, entry in expected.items():
            data = archive.read(name)
            if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
                raise RuntimeError('Archive SHA-256 verification failed: ' + name)
        if expected_head and manifest['git_head'] != expected_head:
            raise RuntimeError('Archive HEAD differs from the reviewed repository')
        # Extract only after names and every byte have been verified. This does
        # not execute project code or hooks and does not contact a remote.
        with tempfile.TemporaryDirectory(prefix='foodstore-verify-',dir=path.resolve().parent) as temporary:
            archive.extractall(temporary)
            restored = Path(temporary) / PREFIX
            git('fsck', '--full', repo=restored)
            head = git('rev-parse', 'HEAD', repo=restored).decode().strip()
            count = int(git('rev-list', '--all', '--count', repo=restored).decode())
            if head != manifest['git_head'] or count != manifest['git_commit_count']:
                raise RuntimeError('Restored Git history differs from the manifest')
    return {'files': len(expected), 'git_head': head, 'git_commit_count': count,
            'manifest_hashes_verified': True, 'restored_git_verified': True}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=ROOT.parent/'Arancibia_Romero_TP_U5_repositorio.zip')
    parser.add_argument('--dry-run', action='store_true', help='Check inputs without writing a ZIP')
    parser.add_argument('--verify', type=Path, help='Verify an existing archive without creating one')
    args = parser.parse_args(argv)
    if args.verify:
        print(json.dumps(verify_archive(args.verify), ensure_ascii=False, indent=2));return
    names = inventory()
    missing = [name for name in REQUIRED if name not in names]
    dirty = bool(git('status', '--porcelain', '--untracked-files=all').strip())
    objects = check_git_history()
    entries = []
    for name in names:
        data = (ROOT/name).read_bytes()
        if not name.startswith('.git/objects/'):
            scan_content(data, name)
        entries.append({'path': name, 'bytes': len(data),
                        'sha256': hashlib.sha256(data).hexdigest()})
    head = git('rev-parse', 'HEAD').decode().strip()
    count = int(git('rev-list', '--all', '--count').decode())
    if args.dry_run:
        print(json.dumps({'dry_run': True, 'archive_created': False,
                          'files_selected': len(entries), 'git_objects_reviewed': objects,
                          'git_commit_count': count, 'clean_worktree': not dirty,
                          'missing_required': missing,
                          'ready': not missing and not dirty}, ensure_ascii=False, indent=2))
        return
    if missing: raise RuntimeError('Required deliverables are missing: ' + ', '.join(missing))
    if dirty: raise RuntimeError('Commit the completed deliverables before packaging')
    target = args.output.resolve()
    if target.is_relative_to(ROOT.resolve()):
        raise RuntimeError('Write the archive outside the repository')
    if target.exists(): raise FileExistsError('Output already exists; choose a new output name')
    target.parent.mkdir(parents=True, exist_ok=True)
    manifest = {'format_version': 1, 'repository': PREFIX,
                'created_utc': datetime.now(timezone.utc).isoformat(),
                'git_head': head, 'git_commit_count': count,
                'git_objects_reviewed': objects,
                'exclusions': ['Git-ignored files (including tracked ignored paths)',
                               'Private material and caches', '.git/hooks', 'ZIP outputs'],
                'credential_check': 'Known credential patterns in files and all decoded Git objects',
                'files': entries}
    handle, temporary = tempfile.mkstemp(prefix=target.stem+'-', suffix='.partial', dir=target.parent)
    os.close(handle);temporary = Path(temporary)
    try:
        with ZipFile(temporary, 'w', ZIP_DEFLATED, compresslevel=9) as archive:
            for entry in entries:
                archive.write(ROOT/entry['path'], PREFIX+'/'+entry['path'])
            archive.writestr(MANIFEST, json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
        verification = verify_archive(temporary, head)
        temporary.rename(target)
    finally:
        if temporary.exists(): temporary.unlink()
    print(json.dumps({'output': str(target), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                      **verification}, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\generar_informe_pdf.py

SHA256 original: f5250335e88650fb234aa0f723d8c8d1ca0c2508a9fc0eb10335f064c82102e0
SHA256 saneado: 4dbc172245ef001484bbbe4dc6ab5a88225acab8bbb5d92e33b79dc785bba336

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Render the verified Markdown reports as a complementary, readable PDF.

SQL sources, complete AI transcripts, Git history and machine evidence remain
in the repository. This document does not replace those reproducible sources.
"""
from __future__ import annotations

import argparse
import re
import textwrap
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
    Preformatted,
)

ROOT = Path(__file__).resolve().parents[1]
BLUE = colors.HexColor('#153956')
TEAL = colors.HexColor('#087F8C')
PALE = colors.HexColor('#EDF4F7')
INK = colors.HexColor('#243443')
WIDTH = A4[0]-100


def table_cells(line):
    """Split a Markdown row without treating escaped/code pipes as borders."""
    line=line.strip()
    if line.startswith('|'): line=line[1:]
    if line.endswith('|') and not line.endswith('\\|'): line=line[:-1]
    cells=[];current=[];in_code=False;i=0
    while i<len(line):
        char=line[i]
        if char=='\\' and i+1<len(line) and line[i+1]=='|':
            current.append('|');i+=2;continue
        if char=='`': in_code=not in_code
        if char=='|' and not in_code:
            cells.append(''.join(current).strip());current=[]
        else: current.append(char)
        i+=1
    cells.append(''.join(current).strip())
    return cells


def starts_block(line):
    line=line.lstrip()
    return (line.startswith(('#','|','```','~~~','- ','* '))
            or bool(re.match(r'^\d+[.)]\s+',line))
            or line in ('---','***'))


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,
                        help='Explicit PDF destination for review or final delivery')
    args=parser.parse_args(argv)
    for name, filename in [('Arial','arial.ttf'),('ArialBold','arialbd.ttf'),
                           ('Consolas','consola.ttf')]:
        pdfmetrics.registerFont(TTFont(name, 'C:/Windows/Fonts/'+filename))
    pdfmetrics.registerFontFamily('Arial',normal='Arial',bold='ArialBold')
    styles = {
        'title': ParagraphStyle('title',fontName='ArialBold',fontSize=26,leading=31,textColor=BLUE,spaceAfter=18),
        'h1': ParagraphStyle('h1',fontName='ArialBold',fontSize=17,leading=21,textColor=BLUE,spaceAfter=12,keepWithNext=True),
        'h2': ParagraphStyle('h2',fontName='ArialBold',fontSize=12,leading=16,textColor=TEAL,spaceBefore=12,spaceAfter=7,keepWithNext=True),
        'body': ParagraphStyle('body',fontName='Arial',fontSize=10,leading=14.1,textColor=INK,spaceAfter=8,splitLongWords=True),
        'small': ParagraphStyle('small',fontName='Arial',fontSize=8.1,leading=10.8,textColor=INK,spaceAfter=5),
        'cell': ParagraphStyle('cell',fontName='Arial',fontSize=8.4,leading=11,textColor=INK,splitLongWords=True),
        'headcell': ParagraphStyle('headcell',fontName='ArialBold',fontSize=8.4,leading=11,textColor=colors.white,splitLongWords=True),
        'code': ParagraphStyle('code',fontName='Consolas',fontSize=8,leading=10.6,textColor=INK,spaceAfter=0),
    }
    story=[]

    def markup(value):
        value=escape(value)
        value=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'\1 (\2)',value)
        value=re.sub(r'\*\*([^*]+)\*\*',r'<b>\1</b>',value)
        value=re.sub(r'`([^`]+)`',r'<font name="Consolas">\1</font>',value)
        return value

    def paragraph(value,sty='body'):
        story.append(Paragraph(markup(value),styles[sty]))

    def code(lines):
        wrapped=[]
        for line in lines:
            wrapped.extend(textwrap.wrap(line,width=100,replace_whitespace=False,
                           break_long_words=True,break_on_hyphens=False,subsequent_indent='  ') or [''])
        # Individual lines let the page engine split long SQL/log blocks.
        for line in wrapped:
            story.append(Preformatted(line,styles['code']))
        story.append(Spacer(1,8))

    def table(rows):
        cells=[[Paragraph(markup(x),styles['headcell' if i==0 else 'cell'])
                for x in row] for i,row in enumerate(rows)]
        n=len(cells[0])
        widths=[WIDTH/n]*n
        if n==3: widths=[WIDTH*.29,WIDTH*.31,WIDTH*.40]
        t=Table(cells,colWidths=widths,repeatRows=1,hAlign='LEFT',splitInRow=0)
        t.setStyle(TableStyle([
            ('BACKGROUND',(0,0),(-1,0),BLUE),('VALIGN',(0,0),(-1,-1),'TOP'),
            ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,PALE]),
            ('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),
            ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6),
            ('LINEBELOW',(0,0),(-1,0),.5,TEAL),
        ]))
        story.extend([t,Spacer(1,9)])

    def markdown(path):
        lines=path.read_text(encoding='utf-8-sig').splitlines()
        i=0
        while i<len(lines):
            line=lines[i].strip()
            if not line:
                i+=1;continue
            fence=re.match(r'^(`{3,}|~{3,})',line)
            if fence:
                delimiter=fence.group(1);block=[];i+=1
                close=re.compile(r'^'+re.escape(delimiter[0])+'{'+str(len(delimiter))+r',}\s*$')
                while i<len(lines) and not close.fullmatch(lines[i].strip()):
                    block.append(lines[i]);i+=1
                if i==len(lines):
                    raise ValueError(f'Unclosed code fence in {path}')
                code(block);i+=1;continue
            if line.startswith('|'):
                rows=[]
                while i<len(lines) and lines[i].strip().startswith('|'):
                    cells=table_cells(lines[i])
                    if not all(re.fullmatch(r':?-{3,}:?',x) for x in cells): rows.append(cells)
                    i+=1
                if rows and len({len(row) for row in rows})==1: table(rows)
                else:
                    for row in rows: paragraph(' / '.join(row),'small')
                continue
            if line.startswith('#'):
                level=len(line)-len(line.lstrip('#'))
                paragraph(line.lstrip('#').strip(),'h1' if level==1 else 'h2')
                i+=1;continue
            if line.startswith(('- ','* ')) or re.match(r'^\d+[.)]\s+',line):
                paragraph(line);i+=1;continue
            if line in ('---','***'):
                i+=1;continue
            block=[line];i+=1
            while i<len(lines) and lines[i].strip() and not starts_block(lines[i]):
                block.append(lines[i].strip());i+=1
            paragraph(' '.join(block))

    paragraph('TECNICATURA UNIVERSITARIA EN PROGRAMACIÓN','small')
    story.append(Spacer(1,25))
    paragraph('Administración y seguridad de Food Store','title')
    paragraph('Trabajo práctico - Unidad 5 | Base de Datos II','h2')
    paragraph('Exequiel Arancibia · Joaquin Romero')
    paragraph('Ciclo lectivo 2026 · PostgreSQL 17.11')
    story.append(Spacer(1,16))
    paragraph('Roles, auditoría, reconstrucción de incidentes y protección de datos personales. Resolución sobre la base acumulada de los TP1 a TP5 y la Unidad 4.')
    paragraph('Este informe acompaña al repositorio entregado como ZIP. Allí se incluyen SQL, herramientas, respuestas completas de IA, resultados de ejecución e historial Git. Las credenciales y los logs originales se conservan fuera del repositorio.')
    sections=[
        ('Continuidad con los trabajos anteriores','docs/continuidad_y_alcance.md'),
        ('Parte A - Especificación y permisos','docs/informe_roles.md'),
        ('Parte B - Auditoría','docs/informe_auditoria.md'),
        ('Parte C - Simulacro e interpretación','docs/informe_incidente.md'),
        ('Parte D - Anonimización y equivalencia','docs/verificacion_equivalencia.md'),
        ('Parte E - Bitácora de IA','BITACORA.md'),
        ('Conformidad de cierre','docs/validacion_humana.md'),
        ('Ejecución y archivos de entrega','README.md'),
    ]
    for title,filename in sections:
        path=ROOT/filename
        if not path.is_file(): raise FileNotFoundError(f'Required report missing: {filename}')
        story.append(PageBreak())
        paragraph(title,'small')
        markdown(path)

    def footer(canvas,doc):
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor('#D3E0E7'))
        canvas.line(50,43,A4[0]-50,43)
        canvas.setFont('Arial',8)
        canvas.setFillColor(INK)
        canvas.drawString(50,29,'Food Store · Unidad 5 · Arancibia / Romero')
        canvas.drawRightString(A4[0]-50,29,str(doc.page))
        canvas.restoreState()

    target=args.output or ROOT/'docs'/'TP_U5_FoodStore_Arancibia_Romero.pdf'
    target=target.resolve()
    target.parent.mkdir(parents=True,exist_ok=True)
    SimpleDocTemplate(str(target),pagesize=A4,rightMargin=50,leftMargin=50,
        topMargin=48,bottomMargin=57,title='TP Unidad 5 - Food Store',
        author='Exequiel Arancibia; Joaquin Romero').build(story,onFirstPage=footer,onLaterPages=footer)
    print(target)


if __name__=='__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\instalar_seguridad.py

SHA256 original: 6aa6c76a273693740a8dd5d9f79f6dd363d6999b51ba2640e67ffce1ae1dca3b
SHA256 saneado: 35dff13d7f32e442b7e390b18f4cd684f307b6ad2aa5e51f3feee4f24e07e82f

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Apply the planned role SQL without publishing database login passwords.

Requires the actual Kiro requirements/design and a completed roles.sql.
Run during private bootstrap, then enable the audit configuration separately.
"""
from pathlib import Path

from libpq_client import Connection, load_secrets, password_for_role

ROOT=Path(__file__).resolve().parents[1]


def main():
    required=[ROOT/'docs/kiro_roles_spec'/name for name in ('requirements.md','design.md')]
    required.append(ROOT/'sql/roles.sql')
    if not all(path.is_file() for path in required):
        raise RuntimeError('Actual Kiro specification and role SQL are required before installation')
    secret=load_secrets()
    with Connection(secret['bootstrap_user'],application_name='u5_security_install') as db:
        if db.scalar('SHOW log_statement')!='none' or db.scalar('SHOW log_min_error_statement')!='panic':
            raise RuntimeError('Install during private bootstrap before statement/error-statement logging')
        # Avoid SQL context output in the unlikely event password setup fails.
        # No errors are printed by this client. Reconnect before auditing.
        db.execute("SET log_error_verbosity='terse'")
        db.execute((ROOT/'sql/roles.sql').read_text(encoding='utf-8-sig'))
        db.execute('BEGIN')
        try:
            db.execute("SELECT pg_catalog.set_config('u5.app_password',$1::text,true)",[password_for_role('app_web',secret)])
            db.execute("SELECT pg_catalog.set_config('u5.admin_password',$1::text,true)",[password_for_role('admin_datos',secret)])
            db.execute("""DO $private_setup$
            BEGIN
              EXECUTE pg_catalog.format('ALTER ROLE app_web PASSWORD %L',
                  pg_catalog.current_setting('u5.app_password'));
              EXECUTE pg_catalog.format('ALTER ROLE admin_datos PASSWORD %L',
                  pg_catalog.current_setting('u5.admin_password'));
            END
            $private_setup$""")
            db.execute('COMMIT')
        except Exception:
            db.execute('ROLLBACK')
            raise
    print('Role SQL applied; random login passwords remain private. Enable audit next.')


if __name__=='__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\libpq_client.py

SHA256 original: 750c981c5d49303301e9a08566daede5f667fdc5afebc0f570013a52e20bd2ef
SHA256 saneado: b2c36289f9f3063bcc17d6bf20cf2f962e90a1dd6896344d5c635827358aa97f

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Small libpq client for the isolated Food Store U5 laboratory.

Importing this module opens no connection. Bind authentication/reset secrets as
parameters: execute(sql, params=[...]) uses PQexecParams, not SQL interpolation.
No query text, parameter value, raw server error, or result row is printed.
"""

from __future__ import annotations

import ctypes
from datetime import date, datetime
import json
import os
from pathlib import Path
import re
from typing import NamedTuple, Sequence


LIBPQ_PATH = Path(r"C:\Program Files\PostgreSQL\17\bin\libpq.dll")
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 55605
DEFAULT_DATABASE = "foodstore_u5_arancibia_romero"


class ConfigurationError(RuntimeError):
    """Invalid local configuration; messages never include secret values."""


class DatabaseError(RuntimeError):
    """Sanitized database failure. SQLSTATE is observed, never guessed."""

    def __init__(self, *, operation: str, sqlstate: str | None = None,
                 status: str = "UNKNOWN", classification: str = "database_error"):
        self.operation = operation
        self.sqlstate = sqlstate
        self.status = status
        self.classification = classification
        super().__init__(
            f"Database operation failed: operation={operation}; "
            f"status={status}; sqlstate={sqlstate or 'unavailable'}; "
            f"classification={classification}"
        )


class ConnectionFailure(DatabaseError):
    """Connection/handshake failed; no PGresult SQLSTATE is available."""


class QueryResult(NamedTuple):
    columns: list[str]
    rows: list[tuple[str | None, ...]]
    status: str
    sqlstate: str | None

    def __repr__(self) -> str:
        # An accidental print(result) must not dump all usuario records.
        return (
            f"QueryResult(columns={self.columns!r}, row_count={len(self.rows)}, "
            f"status={self.status!r}, sqlstate={self.sqlstate!r})"
        )


def default_secrets_path() -> Path:
    explicit = os.environ.get("U5_SECRET_FILE")
    if explicit:
        return Path(explicit).expanduser().resolve()
    sibling = REPOSITORY_ROOT.parent / "food-store-tp-u5-runtime" / "secrets.json"
    if sibling.is_file():
        return sibling.resolve()
    for ancestor in Path(__file__).resolve().parents:
        candidate = ancestor / "work" / "unidad5" / "private" / "secrets.json"
        if candidate.is_file():
            return candidate.resolve()
    raise ConfigurationError("Private secrets file unavailable; set U5_SECRET_FILE")


def load_secrets(path: str | os.PathLike | None = None) -> dict:
    """Read private runtime data, refusing a secrets file inside this repo.

    Preferred shape: {"roles": {"app_web": "...", "admin_datos": "..."},
    "app_auth": {"email": "...", "password": "..."}}.
    A role value may also be {"password": "..."}. Values are never logged.
    """
    selected = Path(path).expanduser().resolve() if path else default_secrets_path()
    if selected.is_relative_to(REPOSITORY_ROOT):
        raise ConfigurationError("Runtime secrets must remain outside the Git repository")
    try:
        content = json.loads(selected.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise ConfigurationError("Unable to read the private runtime secrets file") from None
    if not isinstance(content, dict):
        raise ConfigurationError("Private runtime secrets must be a JSON object")
    return content


def password_for_role(user: str, secrets: dict) -> str:
    """Support the preferred roles mapping and a flat role-to-password map."""
    roles = secrets.get("roles", {})
    value = roles.get(user) if isinstance(roles, dict) else None
    if value is None:
        value = secrets.get(user)
    if isinstance(value, dict):
        value = value.get("password")
    if not isinstance(value, str) or not value:
        raise ConfigurationError("No password configured for the requested laboratory role")
    return value


_LIBPQ = None


def _library():
    global _LIBPQ
    if _LIBPQ is not None:
        return _LIBPQ
    if os.name != "nt" or not hasattr(os, "add_dll_directory"):
        raise ConfigurationError("This laboratory client requires Windows and PostgreSQL 17 libpq")
    if not LIBPQ_PATH.is_file():
        raise ConfigurationError("PostgreSQL 17 libpq.dll was not found at the configured location")
    try:
        # Dependencies are resolved only while loading this DLL. The directory
        # handle is closed afterward; loaded modules retain their references.
        with os.add_dll_directory(str(LIBPQ_PATH.parent)):
            lib = ctypes.CDLL(str(LIBPQ_PATH))
    except OSError:
        raise ConfigurationError("Unable to load PostgreSQL 17 libpq and its dependencies") from None
    pointer = ctypes.c_void_p
    char_array = ctypes.POINTER(ctypes.c_char_p)
    lib.PQconnectdbParams.argtypes = [char_array, char_array, ctypes.c_int]
    lib.PQconnectdbParams.restype = pointer
    lib.PQstatus.argtypes = [pointer]
    lib.PQstatus.restype = ctypes.c_int
    lib.PQerrorMessage.argtypes = [pointer]
    lib.PQerrorMessage.restype = ctypes.c_char_p
    lib.PQfinish.argtypes = [pointer]
    lib.PQfinish.restype = None
    lib.PQexec.argtypes = [pointer, ctypes.c_char_p]
    lib.PQexec.restype = pointer
    lib.PQexecParams.argtypes = [
        pointer, ctypes.c_char_p, ctypes.c_int,
        ctypes.POINTER(ctypes.c_uint), char_array,
        ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.c_int,
    ]
    lib.PQexecParams.restype = pointer
    lib.PQresultStatus.argtypes = [pointer]
    lib.PQresultStatus.restype = ctypes.c_int
    lib.PQresultErrorField.argtypes = [pointer, ctypes.c_int]
    lib.PQresultErrorField.restype = ctypes.c_char_p
    lib.PQntuples.argtypes = [pointer]
    lib.PQntuples.restype = ctypes.c_int
    lib.PQnfields.argtypes = [pointer]
    lib.PQnfields.restype = ctypes.c_int
    lib.PQfname.argtypes = [pointer, ctypes.c_int]
    lib.PQfname.restype = ctypes.c_char_p
    lib.PQgetisnull.argtypes = [pointer, ctypes.c_int, ctypes.c_int]
    lib.PQgetisnull.restype = ctypes.c_int
    lib.PQgetlength.argtypes = [pointer, ctypes.c_int, ctypes.c_int]
    lib.PQgetlength.restype = ctypes.c_int
    lib.PQgetvalue.argtypes = [pointer, ctypes.c_int, ctypes.c_int]
    lib.PQgetvalue.restype = pointer
    lib.PQclear.argtypes = [pointer]
    lib.PQclear.restype = None
    _LIBPQ = lib
    return lib


_STATUS = {
    0: "PGRES_EMPTY_QUERY", 1: "PGRES_COMMAND_OK", 2: "PGRES_TUPLES_OK",
    3: "PGRES_COPY_OUT", 4: "PGRES_COPY_IN", 5: "PGRES_BAD_RESPONSE",
    6: "PGRES_NONFATAL_ERROR", 7: "PGRES_FATAL_ERROR", 8: "PGRES_COPY_BOTH",
    9: "PGRES_SINGLE_TUPLE", 10: "PGRES_PIPELINE_SYNC",
    11: "PGRES_PIPELINE_ABORTED", 12: "PGRES_TUPLES_CHUNK",
}


def _encoded(value) -> bytes | None:
    if value is None:
        return None
    if isinstance(value, bool):
        value = "true" if value else "false"
    elif isinstance(value, (date, datetime)):
        value = value.isoformat()
    encoded = value if isinstance(value, bytes) else str(value).encode("utf-8")
    if b"\x00" in encoded:
        raise ConfigurationError("NUL bytes are not accepted in text parameters")
    return encoded


def _connection_classification(message: bytes | None) -> str:
    # Classify internally, then discard the raw message. No account, endpoint,
    # supplied password, or connection string is included in the exception.
    lowered = (message or b"").decode("utf-8", errors="replace").lower()
    if "password authentication failed" in lowered:
        return "password_authentication_failed"
    if "no password supplied" in lowered:
        return "password_required"
    if "no pg_hba.conf entry" in lowered:
        return "connection_policy_rejected"
    if any(term in lowered for term in ("connection refused", "could not connect", "timeout expired")):
        return "network_or_server_unavailable"
    return "connection_or_authentication_failed"


class Connection:
    """A synchronous, single-owner connection to the isolated local U5 DB."""

    def __init__(self, user: str, password: str | None = None, *,
                 host: str | None = None, port: int | None = None,
                 dbname: str | None = None, application_name: str = "u5_tool",
                 connect_timeout: int = 10,
                 secret_file: str | os.PathLike | None = None):
        self._conn = None
        self._lib = _library()
        runtime = {}
        if password is None or host is None or port is None or dbname is None:
            runtime = load_secrets(secret_file)
        if password is None:
            password = password_for_role(user, runtime)
        host = host if host is not None else runtime.get("host", DEFAULT_HOST)
        port = port if port is not None else runtime.get("port", DEFAULT_PORT)
        dbname = dbname if dbname is not None else runtime.get("dbname", runtime.get("database", DEFAULT_DATABASE))
        if not isinstance(host, str) or not host or not isinstance(dbname, str) or not dbname:
            raise ConfigurationError("Runtime host and database must be nonempty strings")
        try:
            port = int(port)
        except (TypeError, ValueError):
            raise ConfigurationError("Runtime port must be a valid TCP port") from None
        if not 1 <= port <= 65535:
            raise ConfigurationError("Runtime port must be a valid TCP port")
        fields = {
            "host": host, "port": str(port), "dbname": dbname, "user": user,
            "password": password, "application_name": application_name,
            "connect_timeout": str(connect_timeout), "client_encoding": "UTF8",
        }
        keys = (ctypes.c_char_p*(len(fields)+1))(*[_encoded(k) for k in fields], None)
        values = (ctypes.c_char_p*(len(fields)+1))(*[_encoded(v) for v in fields.values()], None)
        conn = self._lib.PQconnectdbParams(keys, values, 0)
        if not conn:
            raise ConnectionFailure(operation="connect", status="NO_CONNECTION", classification="connection_allocation_failed")
        if self._lib.PQstatus(conn) != 0:
            classification = _connection_classification(self._lib.PQerrorMessage(conn))
            self._lib.PQfinish(conn)
            raise ConnectionFailure(operation="connect", status="CONNECTION_BAD", classification=classification)
        self._conn = conn

    @property
    def closed(self) -> bool:
        return self._conn is None

    def execute(self, sql: str, params: Sequence | None = None) -> QueryResult:
        if self.closed:
            raise DatabaseError(operation="query", status="CLOSED", classification="closed_connection")
        if not isinstance(sql, str) or "\x00" in sql:
            raise ConfigurationError("SQL must be text without NUL bytes")
        encoded_sql = sql.encode("utf-8")
        if params is None:
            result = self._lib.PQexec(self._conn, encoded_sql)
        else:
            if isinstance(params, (str, bytes, bytearray)):
                raise ConfigurationError("Parameters must be a sequence of separate values")
            encoded_values = [_encoded(value) for value in params]
            values = (ctypes.c_char_p*len(encoded_values))(*encoded_values)
            result = self._lib.PQexecParams(
                self._conn, encoded_sql, len(encoded_values), None,
                values, None, None, 0,
            )
        if not result:
            raise DatabaseError(operation="query", status="NO_RESULT", classification="no_result_or_connection_failure")
        try:
            status_code = self._lib.PQresultStatus(result)
            status = _STATUS.get(status_code, f"PGRES_STATUS_{status_code}")
            state_raw = self._lib.PQresultErrorField(result, ord("C"))
            sqlstate = state_raw.decode("ascii", errors="replace") if state_raw else None
            if sqlstate and not re.fullmatch(r"[0-9A-Z]{5}", sqlstate):
                sqlstate = None
            if status_code not in (0, 1, 2):
                if status_code in (3, 4, 8):
                    # COPY is outside this wrapper's contract. Closing prevents
                    # the connection being reused while COPY is still active.
                    self.close()
                raise DatabaseError(operation="query", sqlstate=sqlstate, status=status)
            field_count = self._lib.PQnfields(result)
            columns = [(self._lib.PQfname(result, index) or b"").decode("utf-8")
                       for index in range(field_count)]
            rows = []
            for row in range(self._lib.PQntuples(result)):
                values = []
                for column in range(field_count):
                    if self._lib.PQgetisnull(result, row, column):
                        values.append(None)
                    else:
                        pointer = self._lib.PQgetvalue(result, row, column)
                        length = self._lib.PQgetlength(result, row, column)
                        values.append(ctypes.string_at(pointer, length).decode("utf-8"))
                rows.append(tuple(values))
            return QueryResult(columns, rows, status, sqlstate)
        finally:
            self._lib.PQclear(result)

    def scalar(self, sql: str, params: Sequence | None = None) -> str | None:
        result = self.execute(sql, params)
        return result.rows[0][0] if result.rows and result.columns else None

    def close(self) -> None:
        if self._conn is not None:
            connection, self._conn = self._conn, None
            self._lib.PQfinish(connection)

    def __enter__(self):
        if self.closed:
            raise DatabaseError(operation="context", status="CLOSED", classification="closed_connection")
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()
        return False

    def __del__(self):
        if getattr(self, "_conn", None) is not None:
            self.close()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\opencode_consulta.py

SHA256 original: 28b87af6df59f448d954d1f925988916b7d3fc7e5999d51ab1de2dc25af9cb82
SHA256 saneado: 03f941dc2934cbe99657ebce8d4eb80e67b33a94aff8067644d4254261323f56

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Run an actual, tool-denied OpenCode consultation and retain its provenance.

Only supply material already sanitized for disclosure. The complete event stream
and diagnostic output are stored outside this repository; the repository receives
the exact prompt, answer text, and non-secret run metadata. This program does not
execute generated SQL and does not represent technical review as human approval.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


REPOSITORY = Path(__file__).resolve().parents[1]
TASK_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_EXECUTABLE = Path(
    r"C:\Users\ASPIRE LITE 16\AppData\Roaming\npm\node_modules\opencode-ai\bin\opencode.exe"
)
DEFAULT_MODEL = "openai/gpt-6.1-sol"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def parse_events(raw: str) -> tuple[list[dict], list[str]]:
    events, unparsable = [], []
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            unparsable.append(line)
        else:
            if isinstance(event, dict):
                events.append(event)
            else:
                unparsable.append(line)
    return events, unparsable


def extract_answer(events: list[dict]) -> str:
    chunks = []
    for event in events:
        if event.get("type") != "text":
            continue
        part = event.get("part", {})
        text = part.get("text") if isinstance(part, dict) else None
        if isinstance(text, str) and text.strip():
            chunks.append(text)
    return "\n\n".join(chunks).strip()


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True,
                        help="Artifact label, for example d or a_revision")
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--file", dest="attachments", type=Path,
                        action="append", default=[],
                        help="Previously sanitized context attachment; repeatable")
    parser.add_argument("--executable", type=Path, default=DEFAULT_EXECUTABLE)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--working-dir", type=Path,
                        default=TASK_ROOT / "work/unidad5/opencode")
    parser.add_argument("--output-dir", type=Path,
                        default=REPOSITORY / "docs/ia")
    parser.add_argument("--private-dir", type=Path,
                        default=TASK_ROOT / "work/unidad5/private/opencode")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--retry-failed", action="store_true",
                        help="Retry an unsuccessful consultation, preserving its metadata privately")
    return parser.parse_args()


def main() -> int:
    args = arguments()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", args.prefix):
        raise SystemExit("Invalid artifact prefix")
    if is_within(args.private_dir, REPOSITORY):
        raise SystemExit("Raw events must be stored outside the deliverable repository")
    if not args.executable.is_file() or not args.prompt_file.is_file():
        raise SystemExit("Missing executable or prompt file")
    for attachment in args.attachments:
        if not attachment.is_file():
            raise SystemExit("A sanitized attachment does not exist")
    if args.timeout < 1:
        raise SystemExit("Timeout must be positive")

    prompt = args.prompt_file.read_text(encoding="utf-8")
    if not prompt.strip():
        raise SystemExit("Empty prompt")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.private_dir.mkdir(parents=True, exist_ok=True)
    args.working_dir.mkdir(parents=True, exist_ok=True)
    prompt_output = args.output_dir / f"{args.prefix}_prompt.txt"
    answer_output = args.output_dir / f"{args.prefix}_respuesta.md"
    metadata_output = args.output_dir / f"{args.prefix}_metadatos.json"
    prior_attempts = []
    if any(path.exists() for path in (answer_output, metadata_output)):
        if not args.retry_failed or answer_output.exists() or not metadata_output.exists():
            raise SystemExit("Answer/metadata already exist; use a new prefix for a new consultation")
        previous = json.loads(metadata_output.read_text(encoding="utf-8"))
        if previous.get("status") != "failed":
            raise SystemExit("A completed consultation cannot be retried under the same prefix")
        prior_attempts = previous.get("prior_failed_attempts", []) + [{
            key: previous.get(key) for key in (
                "started_at_utc", "finished_at_utc", "returncode", "timed_out",
                "event_count", "error_event_count", "raw_jsonl_sha256", "status"
            )
        }]
        failed_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        (args.private_dir / f"{args.prefix}_{failed_id}_previous_metadata.json").write_text(
            json.dumps(previous, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    if prompt_output.resolve() != args.prompt_file.resolve():
        prompt_output.write_text(prompt, encoding="utf-8")

    # Feed immutable byte-for-byte snapshots, so later SQL corrections cannot
    # replace the evidence of what the assistant actually received.
    snapshots = []
    if args.attachments:
        attachment_dir = args.output_dir / f"{args.prefix}_adjuntos"
        attachment_dir.mkdir(parents=True, exist_ok=True)
        for index, original in enumerate(args.attachments, 1):
            snapshot = attachment_dir / f"{index:02d}_{original.name}"
            source = original.read_bytes()
            if snapshot.exists() and snapshot.read_bytes() != source:
                raise SystemExit("An existing attachment snapshot differs; use a new consultation prefix")
            if not snapshot.exists():
                snapshot.write_bytes(source)
            snapshots.append((original, snapshot))

    environment = os.environ.copy()
    environment["OPENCODE_CONFIG_CONTENT"] = json.dumps({"permission": "deny"})
    version = subprocess.run(
        [str(args.executable), "--version"], env=environment,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        shell=False, timeout=30, check=False,
    )
    if version.returncode != 0:
        raise SystemExit("Unable to read installed OpenCode version")
    command = [str(args.executable), "run", prompt, "--pure", "--agent", "plan",
               "--format", "json", "--model", args.model,
               "--dir", str(args.working_dir.resolve())]
    for original, snapshot in snapshots:
        command.extend(["--file", str(snapshot.resolve())])

    started = utc_now()
    identifier = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    raw_output = args.private_dir / f"{args.prefix}_{identifier}.jsonl"
    raw_errors = args.private_dir / f"{args.prefix}_{identifier}.stderr.txt"
    timed_out = False
    try:
        completed = subprocess.run(
            command, env=environment, capture_output=True, text=True,
            encoding="utf-8", errors="replace", shell=False,
            timeout=args.timeout, check=False,
        )
        stdout, stderr, returncode = (
            completed.stdout, completed.stderr, completed.returncode
        )
    except subprocess.TimeoutExpired as error:
        timed_out = True
        stdout = error.stdout or ""
        stderr = error.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        returncode = None
    raw_output.write_text(stdout, encoding="utf-8")
    raw_errors.write_text(stderr, encoding="utf-8")
    events, invalid = parse_events(stdout)
    answer = extract_answer(events)
    errors = [event for event in events if event.get("type") == "error"]
    tool_events = [event for event in events
                   if event.get("type") in {"tool_use", "tool"}]
    successful = returncode == 0 and bool(answer) and not errors and not timed_out
    if answer:
        answer_output.write_text(answer + "\n", encoding="utf-8")
    attachments = []
    for original, snapshot in snapshots:
        item = {"name": original.name, "sha256": sha256(snapshot)}
        if is_within(snapshot, REPOSITORY):
            item["repository_path"] = snapshot.resolve().relative_to(REPOSITORY).as_posix()
        if is_within(original, REPOSITORY):
            item["source_path_at_consultation"] = original.resolve().relative_to(REPOSITORY).as_posix()
        attachments.append(item)
    metadata = {
        "tool": "OpenCode",
        "installed_version": version.stdout.strip(),
        "requested_model": args.model,
        "agent": "plan", "pure": True,
        "permission_config": {"permission": "deny"},
        "started_at_utc": started, "finished_at_utc": utc_now(),
        "prompt_sha256": sha256(prompt_output),
        "attachments": attachments,
        "returncode": returncode, "timed_out": timed_out,
        "event_count": len(events), "unparsed_line_count": len(invalid),
        "error_event_count": len(errors), "tool_event_count": len(tool_events),
        "answer_sha256": sha256(answer_output) if answer_output.exists() else None,
        "raw_jsonl_sha256": sha256(raw_output),
        "raw_event_storage": "Private work directory outside deliverable repository",
        "status": "completed" if successful else "failed",
        "prior_failed_attempts": prior_attempts,
        "sql_executed": False,
        "human_validation": "Pending; this consultation does not establish human approval",
    }
    metadata_output.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # Never print raw output, errors, authentication material, or environment.
    print(json.dumps({"prefix": args.prefix, "status": metadata["status"],
                      "model": args.model, "event_count": len(events),
                      "answer_characters": len(answer)}, ensure_ascii=False))
    return 0 if successful else 1


if __name__ == "__main__":
    sys.exit(main())

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\preparar_laboratorio.py

SHA256 original: 01114896e1a3af4877f76b8c620569cc74070b5f7d20790b69c620170111f7b4
SHA256 saneado: 71f9879d73aa65dda5a9257ec2729742f4d06dde3299c5ea27f3c23903e1d8f0

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Preparar una instancia PostgreSQL 17 privada para Food Store Unidad 5.

Codigo generado con asistencia de Codex; no acredita uso de Kiro u OpenCode.
Solo biblioteca estandar. Importar este modulo no inicia procesos ni conexiones.
El respaldo debe permanecer fuera del repositorio. El runtime, sus claves y los
logs sin anonimizar son privados y no forman parte de la entrega Git.

Este preparador NO crea roles de aplicacion, NO escribe roles.sql y NO modifica
los permisos del esquema public. Esos pasos requieren la especificacion previa.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import subprocess
import sys
import traceback


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DATABASE = "foodstore_u5_arancibia_romero"
BOOTSTRAP_USER = "u5_bootstrap"
HOST = "127.0.0.1"


class PreparationError(RuntimeError):
    """Mensaje publico deliberadamente sanitizado."""


def hidden_process_options() -> dict:
    if os.name != "nt":
        return {}
    startup = subprocess.STARTUPINFO()
    startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startup.wShowWindow = 0
    return {
        "creationflags": subprocess.CREATE_NO_WINDOW,
        "startupinfo": startup,
    }


class PrivateLog:
    def __init__(self, path: Path):
        self.path = path

    def write(self, text: str) -> None:
        with self.path.open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
            if not text.endswith("\n"):
                handle.write("\n")


def private_command(arguments: list[str], *, log: PrivateLog,
                    environment: dict | None = None,
                    timeout: int = 180) -> subprocess.CompletedProcess:
    """No imprimir salida de herramientas, consultas ni parametros privados."""
    log.write("COMANDO: " + subprocess.list2cmdline(arguments))
    try:
        result = subprocess.run(
            arguments,
            env=environment,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
            check=False,
            **hidden_process_options(),
        )
    except Exception:
        log.write(traceback.format_exc())
        raise PreparationError("Una herramienta local no pudo completarse") from None
    log.write("STDOUT:\n" + result.stdout)
    log.write("STDERR:\n" + result.stderr)
    log.write(f"EXITCODE: {result.returncode}\n")
    if result.returncode != 0:
        raise PreparationError("Una herramienta local devolvio un error; revisar el log privado")
    return result


def pg_binary_directory(explicit: str | None) -> Path:
    if explicit:
        selected = Path(explicit).expanduser().resolve()
    else:
        preferred = Path(os.environ.get("ProgramFiles", r"C:\Program Files")) / "PostgreSQL" / "17" / "bin"
        if preferred.is_dir():
            selected = preferred.resolve()
        else:
            executable = shutil.which("pg_ctl.exe")
            if not executable:
                raise PreparationError("No se encontro PostgreSQL 17; indicar --pg-bin")
            selected = Path(executable).resolve().parent
    if not all((selected / name).is_file() for name in
               ("initdb.exe", "pg_ctl.exe", "createdb.exe", "pg_restore.exe", "psql.exe")):
        raise PreparationError("El directorio --pg-bin no contiene las herramientas requeridas")
    return selected


def current_user_sid() -> str:
    try:
        result = subprocess.run(
            ["whoami.exe", "/user", "/fo", "csv", "/nh"],
            capture_output=True, text=True, encoding="utf-8", errors="replace",
            timeout=15, check=False, **hidden_process_options(),
        )
        rows = list(csv.reader(io.StringIO(result.stdout)))
        sid = next(field for row in rows for field in row
                   if re.fullmatch(r"S-\d+(?:-\d+)+", field))
        if result.returncode:
            raise ValueError("whoami")
        return sid
    except Exception:
        raise PreparationError("No se pudo identificar el usuario Windows para proteger el runtime") from None


def create_private_runtime(runtime: Path) -> PrivateLog:
    """Crear solo un directorio nuevo; no cambiar ACL de carpetas existentes."""
    if runtime.exists():
        if (runtime / "pgdata").exists():
            raise PreparationError("Ya existe pgdata; no se borra ni reutiliza un cluster")
        raise PreparationError("El runtime debe ser un directorio nuevo; no se sobrescribe su contenido")
    if not runtime.parent.is_dir():
        raise PreparationError("Debe existir el directorio padre del runtime elegido")
    sid = current_user_sid()
    runtime.mkdir(exist_ok=False)
    arguments = [
        "icacls.exe", str(runtime), "/inheritance:r", "/grant:r",
        f"*{sid}:(OI)(CI)F",
        "*S-1-5-18:(OI)(CI)F",       # SYSTEM, independiente del idioma.
        "*S-1-5-32-544:(OI)(CI)F",   # Administradores locales.
    ]
    try:
        result = subprocess.run(
            arguments, capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=20, check=False, **hidden_process_options(),
        )
    except Exception:
        raise PreparationError("No se pudo aplicar la ACL privada; no se generaron claves") from None
    if result.returncode:
        raise PreparationError("Fallo la ACL privada; no se generaron claves")
    # Solo despues de proteger la carpeta se escriben logs y material secreto.
    log = PrivateLog(runtime / "preparacion_privada.log")
    log.write("ACL runtime: usuario Windows actual, SYSTEM y Administradores locales.")
    log.write(result.stdout)
    log.write(result.stderr)
    return log


def write_new_private_file(path: Path, content: str) -> None:
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(content)


def dump_digest(source: Path) -> str:
    digest = hashlib.sha256()
    with source.open("rb") as handle:
        if handle.read(5) != b"PGDMP":
            raise PreparationError("--source-dump debe ser un respaldo PostgreSQL en formato custom")
        handle.seek(0)
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def validate_port(port: int) -> None:
    if not 1024 <= port <= 65535:
        raise PreparationError("El puerto debe estar entre 1024 y 65535")
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            probe.bind((HOST, port))
    except OSError:
        raise PreparationError("El puerto local elegido no esta libre; no se toca el servidor existente") from None


def postgresql_settings(port: int) -> str:
    return f"""
# Laboratorio U5 privado: se agrega antes del primer inicio.
listen_addresses = '{HOST}'
port = {port}
cluster_name = 'foodstore_u5_desarrollo'
timezone = 'America/Argentina/Buenos_Aires'
log_timezone = 'America/Argentina/Buenos_Aires'
password_encryption = 'secreto_saneado_b8d966c6866f'
logging_collector = on
log_destination = 'stderr,jsonlog'
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_file_mode = 0600
log_line_prefix = '%m [%p] user=%u db=%d app=%a client=%r sqlstate=%e session=%c '
log_connections = on
log_disconnections = on
log_statement = 'none'
log_min_error_statement = 'panic'
log_parameter_max_length = 0
log_parameter_max_length_on_error = 0
"""


def prepare(arguments: argparse.Namespace) -> tuple[Path, Path]:
    if os.name != "nt":
        raise PreparationError("Este preparador requiere Windows y PostgreSQL 17")
    runtime = Path(arguments.runtime).expanduser().resolve()
    source = Path(arguments.source_dump).expanduser().resolve()
    if runtime.is_relative_to(REPOSITORY_ROOT):
        raise PreparationError("El runtime privado debe quedar fuera del repositorio Git")
    if source.is_relative_to(REPOSITORY_ROOT):
        raise PreparationError("El respaldo privado debe quedar fuera del repositorio Git")
    if (runtime / "pgdata").exists():
        raise PreparationError("Ya existe pgdata; no se borra ni reutiliza un cluster")
    if runtime.exists():
        raise PreparationError("El runtime debe ser un directorio nuevo; no se sobrescribe su contenido")
    if not source.is_file():
        raise PreparationError("No se encontro el respaldo privado indicado")
    pg_bin = pg_binary_directory(arguments.pg_bin)
    source_sha = dump_digest(source)
    validate_port(arguments.port)
    log = create_private_runtime(runtime)
    pgdata = runtime / "pgdata"
    secret_path = runtime / "secrets.json"
    connection_path = runtime / "connection.json"
    init_password_path = runtime / "initpw"
    server_start_attempted = False
    initialization_password_created = False
    successful = False
    try:
        version = private_command([str(pg_bin / "initdb.exe"), "--version"], log=log)
        if not re.search(r"\b17(?:\.|\s|$)", version.stdout):
            raise PreparationError("Se requiere PostgreSQL 17 para reproducir este laboratorio")

        bootstrap_password = secrets.token_urlsafe(32)
        app_password = secrets.token_urlsafe(32)
        admin_password = secrets.token_urlsafe(32)
        business_password = secrets.token_urlsafe(32)
        business_email = "laboratorio.u5." + secrets.token_hex(8) + "@example.invalid"
        private_secrets = {
            "bootstrap_user": BOOTSTRAP_USER,
            "bootstrap_password": bootstrap_password,
            "app_user": "app_web",
            "app_password": app_password,
            "admin_user": "admin_datos",
            "admin_password": admin_password,
            "business_email": business_email,
            "business_password": business_password,
            "roles": {
                BOOTSTRAP_USER: bootstrap_password,
                "app_web": app_password,
                "admin_datos": admin_password,
            },
            "app_auth": {"email": business_email, "password": business_password},
            "host": HOST,
            "port": arguments.port,
            "database": DATABASE,
        }
        write_new_private_file(secret_path, json.dumps(private_secrets, ensure_ascii=False, indent=2) + "\n")
        connection = {
            "host": HOST,
            "port": arguments.port,
            "dbname": DATABASE,
            "bootstrap_user": BOOTSTRAP_USER,
            "pg_bin": str(pg_bin),
            "pgdata": str(pgdata),
            "secret_file": str(secret_path),
            "source_dump_sha256": source_sha,
            "connection_args": ["-h", HOST, "-p", str(arguments.port), "-U", BOOTSTRAP_USER, "-d", DATABASE],
            "state": "preparacion_iniciada",
            "scope": "Cluster nuevo de desarrollo; sin roles ni cambios de permisos U5",
        }
        write_new_private_file(connection_path, json.dumps(connection, ensure_ascii=False, indent=2) + "\n")
        write_new_private_file(init_password_path, bootstrap_password + "\n")
        initialization_password_created = True
        try:
            private_command([
                str(pg_bin / "initdb.exe"), "-D", str(pgdata),
                "--username", BOOTSTRAP_USER, "-A", "scram-sha-256",
                "--pwfile", str(init_password_path), "--encoding", "UTF8", "--locale", "C",
            ], log=log)
        finally:
            # Solo se elimina ESTE archivo literal creado por esta ejecucion.
            # No se borran carpetas, pgdata ni ningun respaldo o archivo previo.
            if initialization_password_created:
                init_password_path.unlink(missing_ok=True)
                initialization_password_created = False

        with (pgdata / "postgresql.conf").open("a", encoding="utf-8", newline="\n") as handle:
            handle.write(postgresql_settings(arguments.port))
        server_start_attempted = True
        private_command([
            str(pg_bin / "pg_ctl.exe"), "-D", str(pgdata), "-l", str(runtime / "arranque_privado.log"),
            "-w", "-t", "60", "start",
        ], log=log, timeout=90)

        # La contrasena viaja en el entorno privado del proceso, no en argv,
        # stdout, archivos SQL, Git, cadenas de conexion ni el comando impreso.
        # No heredar PGHOSTADDR/PGSERVICE/PGOPTIONS de otra instalacion: podrian
        # dirigir una herramienta a un servidor distinto pese al -h explicito.
        environment = {key: value for key, value in os.environ.items()
                       if not key.upper().startswith("PG")}
        environment.update({
            "PGHOST": HOST, "PGPORT": str(arguments.port), "PGUSER": BOOTSTRAP_USER,
            "PGPASSWORD": bootstrap_password, "PGCLIENTENCODING": "UTF8", "PGCONNECT_TIMEOUT": "10",
            "PGAPPNAME": "u5_preparar_laboratorio",
        })
        private_command([
            str(pg_bin / "createdb.exe"), "-w", "-h", HOST, "-p", str(arguments.port),
            "-U", BOOTSTRAP_USER, "--encoding", "UTF8", DATABASE,
        ], log=log, environment=environment)
        private_command([
            str(pg_bin / "pg_restore.exe"), "-w", "-h", HOST, "-p", str(arguments.port),
            "-U", BOOTSTRAP_USER, "--dbname", DATABASE, "--format=custom",
            "--no-owner", "--no-privileges", "--exit-on-error", str(source),
        ], log=log, environment=environment, timeout=900)
        connection["state"] = "respaldo_restaurado_sin_roles_u5"
        connection_path.write_text(json.dumps(connection, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        successful = True
        log.write("Preparacion finalizada. No se crearon roles U5 ni se modificaron ACL de public.")
        return secret_path, connection_path
    except Exception:
        log.write(traceback.format_exc())
        raise PreparationError("La preparacion no termino; revisar preparacion_privada.log en el runtime") from None
    finally:
        if initialization_password_created:
            init_password_path.unlink(missing_ok=True)
        if not successful and server_start_attempted and (pgdata / "postmaster.pid").is_file():
            # Solo se detiene el cluster que esta ejecucion intento iniciar.
            # Su ruta resuelta debe seguir dentro del runtime nuevo y privado.
            if pgdata.resolve().is_relative_to(runtime) and pgdata.resolve() == runtime / "pgdata":
                try:
                    private_command([
                        str(pg_bin / "pg_ctl.exe"), "-D", str(pgdata), "-m", "fast", "-w", "-t", "30", "stop",
                    ], log=log, timeout=45)
                except PreparationError:
                    log.write("No se confirmo la detencion del cluster nuevo; revisar su estado localmente.")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Crear un cluster PostgreSQL 17 privado y restaurar la copia de desarrollo U5. No aplicar roles."
    )
    parser.add_argument("--source-dump", required=True, help="Respaldo custom privado, fuera del repositorio; nunca se copia a Git")
    parser.add_argument(
        "--runtime", default=str(REPOSITORY_ROOT.parent / "food-store-tp-u5-runtime"),
        help="Directorio externo nuevo para datos, claves y logs privados; nunca dentro del repositorio",
    )
    parser.add_argument("--pg-bin", help="Directorio bin de PostgreSQL 17; se detecta su instalacion Windows")
    parser.add_argument("--port", type=int, default=55605, help="Puerto IPv4 local libre; predeterminado 55605")
    args = parser.parse_args(argv)
    try:
        secret_path, connection_path = prepare(args)
    except PreparationError as exc:
        print("ERROR: " + str(exc), file=sys.stderr)
        return 1
    except Exception:
        # No publicar traceback ni errores de herramientas con datos sensibles.
        print("ERROR: no se completo la preparacion; revisar el runtime privado si fue creado", file=sys.stderr)
        return 1
    print("Laboratorio privado preparado; la etapa de roles U5 todavia no fue aplicada.")
    print("SECRETS=" + str(secret_path))
    print("CONNECTION=" + str(connection_path))
    quoted_secret = str(secret_path).replace("'", "''")
    print("Siguiente comando (PowerShell): $env:U5_SECRET_FILE = '" + quoted_secret + "'")
    print("Despues, seguir el README para aplicar la especificacion y los roles aprobados.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\rotar_log.py

SHA256 original: 09820b3049598d134e859bbff46e14d2dd7287a44a81dbffb6e364af00dbfd47
SHA256 saneado: 92437126de0ac69d5e171a03ec4582719cc1649c4c763d55f38637003b91f18c

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Rotate the private server JSON log, preserving the source for capture."""
import json
import time
from libpq_client import Connection, load_secrets


def main():
    secret = load_secrets()
    with Connection(secret['bootstrap_user'], application_name='u5_rotate_log') as db:
        query = 'SELECT pg_catalog.pg_current_logfile($1::text)'
        before = db.scalar(query, ['jsonlog'])
        requested = db.scalar('SELECT pg_catalog.pg_rotate_logfile()')
        if requested != 't':
            raise RuntimeError('Server did not accept log rotation')
        for attempt in range(20):
            time.sleep(0.1)
            after = db.scalar(query, ['jsonlog'])
            if before != after:
                break
        else:
            raise RuntimeError('Rotation not observed; source may still be active')
    print(json.dumps({'previous_json_log':before,'current_json_log':after,
                      'rotation_observed':True}))


if __name__ == '__main__':
    main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\verificar_conservacion.py

SHA256 original: 43032979d45abf5f6aa1f5a512aabfab2e724f654905ffd7ae6c8980e5dfafaa
SHA256 saneado: f803e7e85b0b21a04293ce3b46882acd6bea8d86fc8fd9b016a19a895103099a

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Compare complete inherited business tables without exporting their rows."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from pathlib import Path

from libpq_client import Connection, load_secrets, REPOSITORY_ROOT

TABLES = {'categoria': 'id', 'producto': 'id', 'usuario': 'id',
          'pedido': 'id', 'detalle_pedido': 'pedido_id,producto_id'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('before', 'after'), required=True)
    parser.add_argument('--evidence-dir', type=Path,
                        help='Fresh evidence directory for an independent reproduction')
    args = parser.parse_args()
    secret = load_secrets()
    directory = args.evidence_dir or REPOSITORY_ROOT/'docs'/'evidencias'
    target = directory/('conservacion_'+args.phase+'.json')
    if target.exists():
        raise RuntimeError('Existing conservation evidence must not be overwritten')
    evidence = {'phase': args.phase, 'started_at_utc': datetime.now(timezone.utc).isoformat(),
                'method': 'count plus MD5 of ordered, complete row JSON digests; no source rows exported',
                'tables': {}}
    with Connection(secret['bootstrap_user'], application_name='u5_conservation') as db:
        db.execute('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY')
        db.execute("SET LOCAL TimeZone='America/Argentina/Buenos_Aires'")
        db.execute("SET LOCAL DateStyle='ISO,YMD'")
        for table, order in TABLES.items():
            # Table and column names are fixed above, never supplied by the user.
            row = db.execute('SELECT count(*)::text, pg_catalog.md5('
                "pg_catalog.string_agg(pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY "
                +order+')) FROM public.'+table+' AS t').rows[0]
            evidence['tables'][table] = {'rows': int(row[0]), 'ordered_complete_row_md5': row[1]}
        db.execute('COMMIT')
    if args.phase == 'after':
        before = json.loads(target.with_name('conservacion_before.json').read_text(encoding='utf-8'))
        evidence['same_as_before'] = evidence['tables'] == before['tables']
        if not evidence['same_as_before']:
            raise RuntimeError('Business content changed; stop and investigate before packaging')
    evidence['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(evidence, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'phase': args.phase, 'tables_checked': len(TABLES),
                      'same_as_before': evidence.get('same_as_before'), 'source_rows_exported': False}))


if __name__ == '__main__':
    main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\verificar_matriz.py

SHA256 original: e15a36d6151f1c11ff82efbc10ca2671f071333fff49617f3e486fae97b35272
SHA256 saneado: 9df98dd1439816f3b784359fa68c65ed99db7bb0b98dc482e674d2223c3659b0

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Compare real explicit business ACLs with the final Kiro matrix."""
import json
from datetime import datetime, timezone
from libpq_client import Connection, load_secrets, REPOSITORY_ROOT


def main():
    expected = set()
    def add(role, table, privilege, columns=None, schema='public'):
        for column in columns or ['<table>']:
            expected.add((role, schema, table, column, privilege, 'f'))
    for table in ('categoria', 'producto', 'pedido', 'detalle_pedido'):
        add('rol_app_lectura', table, 'SELECT')
    add('rol_app_lectura', 'usuario', 'SELECT', ['id','nombre','apellido','email','telefono','eliminado','created_at'])
    add('rol_app_escritura', 'pedido', 'INSERT', ['usuario_id','fecha','forma_pago'])
    add('rol_app_escritura', 'pedido', 'UPDATE', ['estado','forma_pago','eliminado'])
    add('rol_app_escritura', 'detalle_pedido', 'INSERT', ['pedido_id','producto_id','cantidad','precio_unitario'])
    add('rol_app_escritura', 'detalle_pedido', 'UPDATE', ['cantidad','precio_unitario'])
    add('rol_app_escritura', 'detalle_pedido', 'DELETE')
    add('rol_soporte', 'usuario', 'SELECT', ['id','nombre','apellido','email','telefono','eliminado'])
    add('rol_soporte', 'usuario', 'UPDATE', ['telefono'])
    for table in ('mv_facturacion_categoria_mes','mv_u4_ventas_categoria_dia'):
        add('rol_reportes', table, 'SELECT')
    add('rol_reportes', 'usuario_anon', 'SELECT', schema='datos_anon')
    add('rol_funciones', 'usuario', 'SELECT', ['id','email','contrasena','eliminado'])
    add('rol_funciones', 'usuario', 'UPDATE', ['contrasena'])
    add('rol_funciones', 'detalle_pedido', 'SELECT', ['pedido_id','subtotal'])
    add('rol_funciones', 'pedido', 'SELECT', ['id'])
    add('rol_funciones', 'pedido', 'UPDATE', ['total'])
    add('rol_funciones', 'mv_u4_ventas_categoria_dia', 'MAINTAIN')
    secret = load_secrets()
    with Connection(secret['bootstrap_user'], application_name='u5_exact_acl') as db:
        result = db.execute("""
WITH acl AS (
 SELECT c.relowner,n.nspname,c.relname,'<table>'::text AS columna,
        a.grantee,a.privilege_type,a.is_grantable
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m','S')
 UNION ALL
 SELECT c.relowner,n.nspname,c.relname,t.attname,a.grantee,a.privilege_type,a.is_grantable
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 JOIN pg_catalog.pg_attribute t ON t.attrelid=c.oid
 CROSS JOIN LATERAL pg_catalog.aclexplode(t.attacl) a
 WHERE n.nspname IN ('public','datos_anon') AND t.attnum>0 AND NOT t.attisdropped
)
SELECT CASE WHEN grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(grantee) END,
       nspname,relname,columna,privilege_type,is_grantable
FROM acl WHERE grantee<>relowner ORDER BY 1,2,3,4,5
""")
        actual = set(result.rows)
        memberships = set(db.execute("""
SELECT mbr.rolname,par.rolname,m.admin_option,m.inherit_option,m.set_option
FROM pg_catalog.pg_auth_members m
JOIN pg_catalog.pg_roles mbr ON mbr.oid=m.member
JOIN pg_catalog.pg_roles par ON par.oid=m.roleid
WHERE mbr.rolname IN ('app_web','admin_datos','rol_app_lectura','rol_app_escritura',
 'rol_soporte','rol_reportes','rol_propietario','rol_funciones')
""").rows)
        expected_memberships = {('app_web','rol_app_lectura','f','t','f'),
            ('app_web','rol_app_escritura','f','t','f'),('admin_datos','rol_soporte','f','t','f')}
    evidence = {'fecha_utc': datetime.now(timezone.utc).isoformat(),
        'expected_explicit_business_acl_entries': len(expected),
        'actual_explicit_business_acl_entries': len(actual),
        'missing': sorted(expected-actual), 'unexpected': sorted(actual-expected),
        'missing_memberships': sorted(expected_memberships-memberships),
        'unexpected_memberships': sorted(memberships-expected_memberships),
        'source': 'Final Kiro requirements/design plus documented Codex precision; actual catalog ACLs',
        'note': 'Owner implicit privileges excluded; column ACLs and table ACLs compared separately. No RLS isolation claimed.'}
    evidence['passed'] = not any(evidence[k] for k in ('missing','unexpected','missing_memberships','unexpected_memberships'))
    target = REPOSITORY_ROOT/'docs'/'evidencias'/'a_comparacion_exacta.json'
    target.parent.mkdir(exist_ok=True)
    target.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'exact_acl_matrix_passed': evidence['passed'], 'entries': len(actual),
                      'missing':len(evidence['missing']), 'unexpected':len(evidence['unexpected'])}))
    if not evidence['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\verificar_privacidad.py

SHA256 original: 0aeb0f38f950f5e902d14946483f971aef832f0dc0edb7c84aa82404cee1d1d5
SHA256 saneado: ec76a600030458e1a6fcdb643edcae28abe71fb4b9ff40a1a271250b9473621e

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Scan deliverable files and decoded Git objects for known private values.

Complements the package pattern scan; does not certify complete anonymization.
The private inventory and any matching value are never printed or exported.
"""
import io
import json
from datetime import datetime, timezone
import subprocess

from anonimizar_log import secret_inventory, BCRYPT, SCRAM
from libpq_client import load_secrets, REPOSITORY_ROOT


def git(*args, data=None):
    result = subprocess.run(['git','-C',str(REPOSITORY_ROOT),*args],input=data,
                            capture_output=True,check=False)
    if result.returncode:
        raise RuntimeError('Unable to inspect repository; no diagnostic values exported')
    return result.stdout


def main():
    private = load_secrets()
    values = secret_inventory(private)
    email = private.get('business_email') or private.get('app_auth',{}).get('email')
    if email:
        values.append(email)
    encoded = [value.encode('utf-8') for value in set(values)]
    checked_pdfs = 0
    def check(data):
        nonlocal checked_pdfs
        if any(value in data for value in encoded):
            raise RuntimeError('Private inventory match found; inspect locally before delivery')
        text = data.decode('utf-8',errors='replace')
        if BCRYPT.search(text) or SCRAM.search(text):
            raise RuntimeError('Credential verifier pattern found; inspect locally before delivery')
        if data.startswith(b'%PDF-'):
            from pypdf import PdfReader
            extracted = '\n'.join(page.extract_text() for page in PdfReader(io.BytesIO(data)).pages)
            if any(value in extracted for value in values) or BCRYPT.search(extracted) or SCRAM.search(extracted):
                raise RuntimeError('Private match found in PDF text; inspect locally before delivery')
            checked_pdfs += 1
    names = set(git('ls-files','--cached','--others','--exclude-standard','-z').decode('utf-8').split('\0'))-{''}
    for name in names:
        check((REPOSITORY_ROOT/name).read_bytes())
    objects = git('cat-file','--batch-all-objects','--batch-check=%(objectname)').splitlines()
    payload = git('cat-file','--batch',data=b'\n'.join(objects)+b'\n')
    offset = 0
    for oid in objects:
        end = payload.index(b'\n',offset)
        size = int(payload[offset:end].split()[2])
        check(payload[end+1:end+1+size])
        offset = end+1+size+1
    evidence = {'checked_at_utc':datetime.now(timezone.utc).isoformat(),
        'worktree_files_scanned':len(names),'decoded_git_objects_scanned':len(objects),
        'pdf_payloads_text_scanned':checked_pdfs,
        'known_private_inventory_matches':0,'bcrypt_scram_verifier_matches':0,
        'private_inventory_exported':False,'passed':True,
        'scope':'Known private values and credential verifier patterns; complementary to package pattern scan, not a proof of irreversible anonymity'}
    target = REPOSITORY_ROOT/'docs'/'evidencias'/'privacidad_entrega.json'
    target.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(evidence,ensure_ascii=False))


if __name__ == '__main__':
    main()

`````

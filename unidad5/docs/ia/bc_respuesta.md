### `auditoria_test.sql`

```sql
-- Parte B: catalogo de sentencias parametrizadas para PostgreSQL 17.
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
VALUES ($1::bigint,$2::bigint,1,$3::numeric);

-- name: audit_update_detail
-- Ejecutar mientras el pedido sigue PENDIENTE.
-- $1: id del pedido; $2: id del producto.
UPDATE public.detalle_pedido
SET cantidad=cantidad+1
WHERE pedido_id=$1::bigint AND producto_id=$2::bigint;

-- name: audit_confirm_order
-- Ejecutar solo despues de insertar y modificar el detalle.
-- $1: id del pedido.
UPDATE public.pedido
SET estado='CONFIRMADO'
WHERE id=$1::bigint AND estado='PENDIENTE';

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
```

### `simulacro_incidente.sql`

```sql
-- Parte C: catalogo de sentencias parametrizadas para PostgreSQL 17.
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
```

**Revisión Breve**
- **Parte B:** el `SELECT` original estaba fuera de `BEGIN/ROLLBACK`. Ahora queda dentro. El pedido devuelve también su estado inicial y la confirmación exige `PENDIENTE`, evitando que una actualización sin esa precondición se considere prueba de la transición.
- **Comprobaciones del cliente:** debe exigir una fila afectada en cada `INSERT` y `UPDATE`, un único pedido devuelto con estado `PENDIENTE`, y una fila con `total_correcto = true`. Cero filas en la consulta de invariantes no significa éxito. Si no hay productos aptos o usuario de prueba válido, debe informar una precondición incumplida.
- **Limpieza:** ejecutar `ROLLBACK` en un bloque `finally` cuando la conexión siga disponible. Esto revierte los datos transaccionales, pero no recupera valores consumidos por las secuencias `IDENTITY` ni borra los registros de auditoría.
- **Parte C:** faltaba precisar que la misma consulta de membresía se reutiliza antes y después desde otra conexión. La verificadora debe usar autocommit o transacciones nuevas para no reutilizar una instantánea anterior. No debe continuar silenciosamente si la membresía inicial ya existe.
- **Errores esperados:** comprobar el campo SQLSTATE de libpq, no el texto localizado del error. Un fallo de conexión, una función inexistente o cualquier error distinto de `42501` no demuestra que el intento de escalamiento haya sido rechazado por el motivo esperado. Si el `GRANT` tiene éxito, registrar el fallo de la prueba y comunicarlo, sin aplicar contención automática.
- **Claves y evidencia:** usar parámetros no basta si el servidor, el cliente o su trazado los registran. Deben verificarse ambos ajustes de longitud y excluir valores sensibles de excepciones y trazas. El cliente debe consumir el resultado completo antes de informar el conteo; una lectura interrumpida no acredita recepción completa. Los logs deben anonimizarse antes de compartirse.
- **Identidades distintas:** `fn_autenticar` autentica una cuenta de negocio de Food Store, no abre otra sesión PostgreSQL ni cambia `session_user`. Si es `SECURITY DEFINER`, `current_user` cambia temporalmente al propietario durante su ejecución y vuelve al contexto anterior al terminar; no pasa a representar al usuario de negocio autenticado.

Estos catálogos no implementan ni validan los permisos propuestos. No se ejecutó ninguna prueba ni se obtuvieron resultados; la especificación pendiente de Kiro y la decisión final corresponden al equipo.

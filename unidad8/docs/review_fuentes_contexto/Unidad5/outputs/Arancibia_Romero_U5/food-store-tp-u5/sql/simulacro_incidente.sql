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

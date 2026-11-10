-- Unidad 6 - Food Store. Exequiel Arancibia / Joaquin Romero.
-- Implementacion tecnica: Codex, segun SPEC_U6.md y AGENTS.md.
-- Uso: psql -X -w -v ON_ERROR_STOP=1 -d foodstore -f health_check.sql
-- Solo agregados/estadisticas. No exporta filas ni texto SQL de sesiones.
\set ON_ERROR_STOP on
\set QUIET 1
\pset pager off
\pset null '(NULL)'

BEGIN READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL TIME ZONE 'America/Argentina/Buenos_Aires';
SET LOCAL application_name = 'u6_health_check';

DO $base_correcta$
BEGIN
    IF pg_catalog.current_database() <> 'foodstore' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'health_check.sql requiere la base foodstore';
    END IF;
END
$base_correcta$;

\echo 'CONTROL 1 - Tamano de la base principal'
SELECT pg_catalog.current_database() AS base,
       pg_catalog.clock_timestamp() AS observado_en,
       pg_catalog.pg_database_size(pg_catalog.current_database()) AS bytes,
       pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(pg_catalog.current_database())) AS tamano;

\echo 'CONTROL 2 - Conexiones y contadores acumulados; no son tasas ni filas de negocio'
SELECT datname AS base, numbackends AS conexiones,
       xact_commit AS transacciones_confirmadas,
       xact_rollback AS transacciones_revertidas,
       deadlocks AS interbloqueos, stats_reset AS reinicio_contadores
FROM pg_catalog.pg_stat_database
WHERE datname = pg_catalog.current_database();

\echo 'CONTROL 3 - Estado estimado de tablas; n_live_tup NO equivale a COUNT(*)'
SELECT schemaname AS esquema, relname AS tabla,
       n_live_tup AS filas_vivas_estimadas,
       n_dead_tup AS tuplas_muertas_estimadas,
       n_mod_since_analyze AS cambios_estimados_desde_analyze,
       last_vacuum, last_autovacuum, last_analyze, last_autoanalyze
FROM pg_catalog.pg_stat_user_tables
ORDER BY n_dead_tup DESC, schemaname, relname;

\echo 'CONTROL 4 - Consultas activas ajenas al chequeo; sin texto SQL, usuario ni direccion'
-- pg_stat_activity.query solo se usa para una clasificacion de lista cerrada.
-- WITH puede contener escrituras: no se rotula automaticamente como lectura.
-- Los application_name no reconocidos tambien se ocultan porque son texto libre.
SELECT pid, backend_type AS tipo_backend, state AS estado,
       pg_catalog.clock_timestamp() - query_start AS duracion,
       wait_event_type AS tipo_espera, wait_event AS espera,
       CASE
           WHEN application_name IN ('psql','pg_dump','pg_restore','u6_backup','u6_restore_test')
               THEN application_name
           ELSE '[aplicacion omitida]'
       END AS aplicacion,
       CASE
           WHEN query ~* '^[[:space:]]*SELECT([[:space:](]|$)' THEN 'SELECT'
           WHEN query ~* '^[[:space:]]*WITH([[:space:](]|$)' THEN 'WITH'
           WHEN query ~* '^[[:space:]]*INSERT([[:space:]]|$)' THEN 'INSERT'
           WHEN query ~* '^[[:space:]]*UPDATE([[:space:]]|$)' THEN 'UPDATE'
           WHEN query ~* '^[[:space:]]*DELETE([[:space:]]|$)' THEN 'DELETE'
           WHEN query ~* '^[[:space:]]*ANALYZE([[:space:](]|$)' THEN 'ANALYZE'
           WHEN query ~* '^[[:space:]]*VACUUM([[:space:](]|$)' THEN 'VACUUM'
           ELSE 'OTRA / NO VISIBLE'
       END AS clase_de_consulta
FROM pg_catalog.pg_stat_activity
WHERE datname = pg_catalog.current_database()
  AND state = 'active'
  AND pid <> pg_catalog.pg_backend_pid()
ORDER BY query_start NULLS LAST, pid;

COMMIT;

-- Cero consultas activas es un resultado valido; no se fabrica actividad.
-- Usuarios sin pg_read_all_stats pueden tener visibilidad limitada de otras
-- sesiones. Las estadisticas pueden retrasarse; NULL no prueba daemon apagado.

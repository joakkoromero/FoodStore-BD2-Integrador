-- Unidad 6 - Food Store. Exequiel Arancibia / Joaquin Romero.
-- Implementacion tecnica: Codex, segun SPEC_U6.md y observacion previa.
-- Uso: psql -X -w -v ON_ERROR_STOP=1 -d foodstore -f maintenance.sql
-- No modifica filas, permisos ni autovacuum. Actualiza estadisticas puntuales.
-- Ejecutar como operador tecnico autorizado, no como login de aplicacion.
\set ON_ERROR_STOP on
\set QUIET 1
\pset pager off
\pset null '(NULL)'

SET search_path = pg_catalog;
SET TIME ZONE 'America/Argentina/Buenos_Aires';
SET application_name = 'u6_maintenance';
SET lock_timeout = '5s';
SET statement_timeout = '60s';

DO $base_correcta$
BEGIN
    IF pg_catalog.current_database() <> 'foodstore' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'maintenance.sql requiere la base foodstore';
    END IF;
END
$base_correcta$;

\echo 'ANTES 1 - Configuracion efectiva de autovacuum y recoleccion de estadisticas'
SELECT pg_catalog.clock_timestamp() AS observado_en,
       pg_catalog.current_setting('autovacuum') AS autovacuum,
       pg_catalog.current_setting('track_counts') AS track_counts,
       pg_catalog.current_setting('autovacuum_analyze_threshold') AS umbral_analyze,
       pg_catalog.current_setting('autovacuum_analyze_scale_factor') AS factor_analyze,
       pg_catalog.current_setting('autovacuum_vacuum_threshold') AS umbral_vacuum,
       pg_catalog.current_setting('autovacuum_vacuum_scale_factor') AS factor_vacuum;

\echo 'ANTES 2 - Tablas de la copia: estimaciones e historiales, con opciones por tabla'
SELECT s.schemaname AS esquema, s.relname AS tabla,
       s.n_live_tup AS filas_vivas_estimadas,
       s.n_dead_tup AS tuplas_muertas_estimadas,
       s.n_mod_since_analyze AS cambios_estimados_desde_analyze,
       s.last_vacuum, s.last_autovacuum, s.last_analyze, s.last_autoanalyze,
       c.reloptions AS opciones_de_tabla
FROM pg_catalog.pg_stat_user_tables AS s
JOIN pg_catalog.pg_class AS c ON c.oid = s.relid
ORDER BY s.n_dead_tup DESC, s.schemaname, s.relname;

\echo 'ANTES 3 - Conteos reales de las dos tablas elegidas; no inferir vaciado de una estimacion 0'
SELECT 'pedido' AS tabla, pg_catalog.count(*) AS filas_reales FROM public.pedido
UNION ALL
SELECT 'detalle_pedido', pg_catalog.count(*) FROM public.detalle_pedido;

\echo 'DECISION - ANALYZE puntual si last_analyze y last_autoanalyze son ambos NULL por tabla'
-- Observacion previa de esta copia: autovacuum=on, ambas tablas tienen
-- filas reales y estimaciones/historiales recien iniciados. Ausencia de
-- historial NO demuestra ausencia de pg_statistic. Se admite refrescar una
-- linea base documentada de la copia, sin reclamar tuplas muertas inexistentes.
-- No hay motivo observado para VACUUM FULL ni para desactivar autovacuum.
SELECT relname AS tabla,
       CASE WHEN last_analyze IS NULL AND last_autoanalyze IS NULL
            THEN 'ANALYZE puntual: establecer linea base de la copia'
            ELSE 'Sin ANALYZE manual: ya hay historial registrado'
       END AS decision
FROM pg_catalog.pg_stat_user_tables
WHERE relid IN ('public.pedido'::pg_catalog.regclass,
                'public.detalle_pedido'::pg_catalog.regclass)
ORDER BY relname;

-- Cada sentencia de psql se confirma por separado. ANALYZE es admisible
-- dentro de DO; no se utiliza VACUUM, que tiene otras restricciones.
DO $analyze_condicional$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_stat_user_tables
        WHERE relid = 'public.pedido'::pg_catalog.regclass
          AND last_analyze IS NULL AND last_autoanalyze IS NULL
    ) THEN
        EXECUTE 'ANALYZE public.pedido';
        RAISE NOTICE 'ANALYZE public.pedido completado para la linea base de la copia';
    END IF;
    IF EXISTS (
        SELECT 1 FROM pg_catalog.pg_stat_user_tables
        WHERE relid = 'public.detalle_pedido'::pg_catalog.regclass
          AND last_analyze IS NULL AND last_autoanalyze IS NULL
    ) THEN
        EXECUTE 'ANALYZE public.detalle_pedido';
        RAISE NOTICE 'ANALYZE public.detalle_pedido completado para la linea base de la copia';
    END IF;
END
$analyze_condicional$;

-- Descartar cualquier cache estadistica del lector antes de la observacion
-- posterior; el servidor puede tener un breve retraso de publicacion.
DO $lectura_nueva$
BEGIN
    PERFORM pg_catalog.pg_stat_clear_snapshot();
END
$lectura_nueva$;

\echo 'DESPUES - Valores realmente visibles, sin sustituir NULL por un resultado inventado'
SELECT schemaname AS esquema, relname AS tabla,
       n_live_tup AS filas_vivas_estimadas,
       n_dead_tup AS tuplas_muertas_estimadas,
       n_mod_since_analyze AS cambios_estimados_desde_analyze,
       last_analyze, last_autoanalyze,
       analyze_count AS analyze_manuales_registrados
FROM pg_catalog.pg_stat_user_tables
WHERE relid IN ('public.pedido'::pg_catalog.regclass,
                'public.detalle_pedido'::pg_catalog.regclass)
ORDER BY relname;

-- Si aparece historial al repetir, la condicion evita ANALYZE innecesario.
-- Esta politica es del laboratorio; NULL aislado no prueba estadisticas malas.

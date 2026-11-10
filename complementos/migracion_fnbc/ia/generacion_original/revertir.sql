DO $down_guard$
BEGIN
    IF pg_catalog.current_database() <> 'foodstore_tpi_migracion_nov10'
       OR pg_catalog.to_regnamespace('tpi_migracion') IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Unexpected migration destination';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class AS c
        JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname = 'tpi_migracion'
          AND c.relname = 'control_legacy'
          AND c.relkind = 'v'
    ) OR pg_catalog.to_regclass(
        'tpi_migracion.control_legacy_fnbc_archivada') IS NOT NULL
      OR pg_catalog.to_regclass(
        'tpi_migracion.control_legacy_new') IS NOT NULL
      OR pg_catalog.to_regclass(
        'tpi_migracion.down_snapshot') IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = '55000',
            MESSAGE = 'Active normalized state is required';
    END IF;
END
$down_guard$;

LOCK TABLE
    tpi_migracion.responsable_deposito,
    tpi_migracion.lote_responsable
IN SHARE ROW EXCLUSIVE MODE;

DO $active_guard$
BEGIN
    IF (SELECT active
        FROM tpi_migracion._migration_guard
        WHERE id = 1) IS DISTINCT FROM true THEN
        RAISE EXCEPTION USING ERRCODE = '25006',
            MESSAGE = 'Normalized lifecycle is not active';
    END IF;
END
$active_guard$;

CREATE TABLE tpi_migracion.down_snapshot AS
SELECT lr.lote_id, rd.deposito_id, lr.responsable_control_id
FROM tpi_migracion.lote_responsable AS lr
JOIN tpi_migracion.responsable_deposito AS rd
  ON rd.responsable_control_id = lr.responsable_control_id;

DO $snapshot_validation$
BEGIN
    IF (SELECT pg_catalog.count(*)
        FROM tpi_migracion.down_snapshot) <> 4
       OR tpi_migracion.fn_relation_hash(
            'tpi_migracion.down_snapshot'::regclass)
          IS DISTINCT FROM (
            SELECT sha256
            FROM tpi_migracion.migration_manifest
            WHERE phase = 'confirmed_changes')
       OR NOT EXISTS (
            SELECT 1
            FROM tpi_migracion.migration_manifest
            WHERE phase = 'confirmed_changes'
              AND row_count = 4
              AND pg_catalog.jsonb_typeof(details -> 'rows') = 'array'
              AND pg_catalog.jsonb_array_length(details -> 'rows') = 4
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Current join differs from confirmed snapshot';
    END IF;

    IF EXISTS (
        SELECT responsable_control_id
        FROM tpi_migracion.down_snapshot
        GROUP BY responsable_control_id
        HAVING pg_catalog.count(DISTINCT deposito_id) > 1
    ) OR EXISTS (
        SELECT lote_id, deposito_id
        FROM tpi_migracion.down_snapshot
        GROUP BY lote_id, deposito_id
        HAVING pg_catalog.count(*) > 1
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Snapshot violates a functional dependency';
    END IF;

    IF EXISTS (
        (SELECT * FROM tpi_migracion.down_snapshot
         EXCEPT ALL
         SELECT expected.*
         FROM tpi_migracion.migration_manifest AS m
         CROSS JOIN LATERAL pg_catalog.jsonb_to_recordset(
             m.details -> 'rows'
         ) AS expected(
             lote_id bigint,
             deposito_id bigint,
             responsable_control_id bigint
         )
         WHERE m.phase = 'confirmed_changes')
        UNION ALL
        (SELECT expected.*
         FROM tpi_migracion.migration_manifest AS m
         CROSS JOIN LATERAL pg_catalog.jsonb_to_recordset(
             m.details -> 'rows'
         ) AS expected(
             lote_id bigint,
             deposito_id bigint,
             responsable_control_id bigint
         )
         WHERE m.phase = 'confirmed_changes'
         EXCEPT ALL
         SELECT * FROM tpi_migracion.down_snapshot)
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Snapshot multiset differs from confirmed rows';
    END IF;
END
$snapshot_validation$;

CREATE TABLE tpi_migracion.control_legacy_new (
    lote_id bigint NOT NULL,
    deposito_id bigint NOT NULL,
    responsable_control_id bigint NOT NULL,
    PRIMARY KEY (lote_id, deposito_id),
    FOREIGN KEY (lote_id) REFERENCES public.lote(id),
    FOREIGN KEY (deposito_id) REFERENCES public.deposito(id),
    FOREIGN KEY (responsable_control_id) REFERENCES public.usuario(id)
);

INSERT INTO tpi_migracion.control_legacy_new
    (lote_id, deposito_id, responsable_control_id)
SELECT lote_id, deposito_id, responsable_control_id
FROM tpi_migracion.down_snapshot;

DO $reconstruction_validation$
BEGIN
    IF EXISTS (
        (SELECT * FROM tpi_migracion.control_legacy_new
         EXCEPT ALL
         SELECT * FROM tpi_migracion.down_snapshot)
        UNION ALL
        (SELECT * FROM tpi_migracion.down_snapshot
         EXCEPT ALL
         SELECT * FROM tpi_migracion.control_legacy_new)
    ) OR (SELECT pg_catalog.count(*)
          FROM tpi_migracion.control_legacy_new) <> 4 THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Reconstruction differs from current join';
    END IF;
END
$reconstruction_validation$;

ALTER VIEW tpi_migracion.control_legacy
RENAME TO control_legacy_fnbc_archivada;

ALTER TABLE tpi_migracion.control_legacy_new
RENAME TO control_legacy;

UPDATE tpi_migracion._migration_guard
SET active = false,
    ts = pg_catalog.clock_timestamp()
WHERE id = 1 AND active;

INSERT INTO tpi_migracion.migration_manifest
    (phase, row_count, sha256, details)
SELECT 'down', pg_catalog.count(*),
       tpi_migracion.fn_relation_hash(
           'tpi_migracion.control_legacy'::regclass),
       '{"normalized_archive_readonly":true}'::jsonb
FROM tpi_migracion.control_legacy;

DO $down_final$
BEGIN
    IF tpi_migracion.fn_relation_hash(
            'tpi_migracion.control_legacy_checkpoint'::regclass)
          IS DISTINCT FROM (
            SELECT sha256
            FROM tpi_migracion.migration_manifest
            WHERE phase = 'checkpoint_initial')
       OR tpi_migracion.fn_relation_hash(
            'tpi_migracion.control_legacy'::regclass)
          IS DISTINCT FROM (
            SELECT sha256
            FROM tpi_migracion.migration_manifest
            WHERE phase = 'confirmed_changes')
       OR (SELECT active
           FROM tpi_migracion._migration_guard
           WHERE id = 1) IS DISTINCT FROM false THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Final down verification failed';
    END IF;

    IF pg_catalog.current_setting(
        'tpi_migracion.inject_down_error', true
    ) = 'on' THEN
        RAISE EXCEPTION USING ERRCODE = 'P7501',
            MESSAGE = 'Dedicated laboratory down failure';
    END IF;
END
$down_final$;

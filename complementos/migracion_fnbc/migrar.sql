DO $migration_guard$
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
          AND c.relkind = 'r'
    ) OR pg_catalog.to_regclass(
        'tpi_migracion.control_legacy_pre_migracion') IS NOT NULL
      OR pg_catalog.to_regclass(
        'tpi_migracion.responsable_deposito') IS NOT NULL
      OR pg_catalog.to_regclass(
        'tpi_migracion.lote_responsable') IS NOT NULL
      OR pg_catalog.to_regclass(
        'tpi_migracion._migration_guard') IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = '55000',
            MESSAGE = 'Prepared state is required';
    END IF;
END
$migration_guard$;

LOCK TABLE tpi_migracion.control_legacy IN ACCESS EXCLUSIVE MODE;

SELECT tpi_migracion.fn_check_fd_rd();

DO $initial_state$
BEGIN
    IF (SELECT pg_catalog.count(*)
        FROM tpi_migracion.control_legacy) <> 3
       OR tpi_migracion.fn_relation_hash(
            'tpi_migracion.control_legacy'::regclass)
          IS DISTINCT FROM (
            SELECT sha256
            FROM tpi_migracion.migration_manifest
            WHERE phase = 'legacy_initial')
       OR tpi_migracion.fn_relation_hash(
            'tpi_migracion.control_legacy_checkpoint'::regclass)
          IS DISTINCT FROM (
            SELECT sha256
            FROM tpi_migracion.migration_manifest
            WHERE phase = 'checkpoint_initial') THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Prepared data or checkpoint changed';
    END IF;
END
$initial_state$;

CREATE TABLE tpi_migracion.responsable_deposito (
    responsable_control_id bigint PRIMARY KEY,
    deposito_id bigint NOT NULL,
    FOREIGN KEY (responsable_control_id) REFERENCES public.usuario(id),
    FOREIGN KEY (deposito_id) REFERENCES public.deposito(id)
);

CREATE TABLE tpi_migracion.lote_responsable (
    lote_id bigint NOT NULL,
    responsable_control_id bigint NOT NULL,
    PRIMARY KEY (lote_id, responsable_control_id),
    FOREIGN KEY (lote_id) REFERENCES public.lote(id),
    FOREIGN KEY (responsable_control_id)
        REFERENCES tpi_migracion.responsable_deposito(responsable_control_id)
);

CREATE TABLE tpi_migracion._migration_guard (
    id bigint PRIMARY KEY CHECK (id = 1),
    turno boolean NOT NULL,
    active boolean NOT NULL,
    locked_by text,
    ts timestamp with time zone NOT NULL
);

INSERT INTO tpi_migracion._migration_guard
    (id, turno, active, locked_by, ts)
VALUES (1, false, true, NULL, pg_catalog.clock_timestamp());

CREATE FUNCTION tpi_migracion.fn_guard_normalized()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $guard$
DECLARE
    guard_id bigint;
BEGIN
    UPDATE tpi_migracion._migration_guard
    SET turno = NOT turno,
        locked_by = pg_catalog.pg_backend_pid()::text,
        ts = pg_catalog.clock_timestamp()
    WHERE id = 1 AND active
    RETURNING id INTO guard_id;

    IF guard_id IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '25006',
            MESSAGE = 'Normalized archive is read only';
    END IF;

    RETURN NULL;
END
$guard$;

CREATE FUNCTION tpi_migracion.fn_validate_fd_ld_r()
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $fd$
BEGIN
    IF EXISTS (
        SELECT lr.lote_id, rd.deposito_id
        FROM tpi_migracion.lote_responsable AS lr
        JOIN tpi_migracion.responsable_deposito AS rd
          ON rd.responsable_control_id = lr.responsable_control_id
        GROUP BY lr.lote_id, rd.deposito_id
        HAVING pg_catalog.count(*) > 1
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23505',
            MESSAGE = 'Functional dependency LD to R is violated',
            CONSTRAINT = 'control_join_ld_unique';
    END IF;
END
$fd$;

CREATE FUNCTION tpi_migracion.fn_after_normalized()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $after$
BEGIN
    PERFORM tpi_migracion.fn_validate_fd_ld_r();
    RETURN NULL;
END
$after$;

CREATE TRIGGER trg_before_rd
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
ON tpi_migracion.responsable_deposito
FOR EACH STATEMENT
EXECUTE FUNCTION tpi_migracion.fn_guard_normalized();

CREATE TRIGGER trg_after_rd
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
ON tpi_migracion.responsable_deposito
FOR EACH STATEMENT
EXECUTE FUNCTION tpi_migracion.fn_after_normalized();

CREATE TRIGGER trg_before_lr
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
ON tpi_migracion.lote_responsable
FOR EACH STATEMENT
EXECUTE FUNCTION tpi_migracion.fn_guard_normalized();

CREATE TRIGGER trg_after_lr
AFTER INSERT OR UPDATE OR DELETE OR TRUNCATE
ON tpi_migracion.lote_responsable
FOR EACH STATEMENT
EXECUTE FUNCTION tpi_migracion.fn_after_normalized();

INSERT INTO tpi_migracion.responsable_deposito
    (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM tpi_migracion.control_legacy;

INSERT INTO tpi_migracion.lote_responsable
    (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM tpi_migracion.control_legacy;

ALTER TABLE tpi_migracion.control_legacy
RENAME TO control_legacy_pre_migracion;

CREATE VIEW tpi_migracion.control_legacy AS
SELECT lr.lote_id, rd.deposito_id, lr.responsable_control_id
FROM tpi_migracion.lote_responsable AS lr
JOIN tpi_migracion.responsable_deposito AS rd
  ON rd.responsable_control_id = lr.responsable_control_id;

DO $migration_validation$
BEGIN
    PERFORM tpi_migracion.fn_validate_fd_ld_r();

    IF (SELECT pg_catalog.count(*)
        FROM tpi_migracion.control_legacy) <> 3
       OR (SELECT pg_catalog.count(*)
           FROM tpi_migracion.responsable_deposito) <> 2
       OR (SELECT pg_catalog.count(*)
           FROM tpi_migracion.lote_responsable) <> 3
       OR EXISTS (
           (SELECT * FROM tpi_migracion.control_legacy
            EXCEPT ALL
            SELECT * FROM tpi_migracion.control_legacy_checkpoint)
           UNION ALL
           (SELECT * FROM tpi_migracion.control_legacy_checkpoint
            EXCEPT ALL
            SELECT * FROM tpi_migracion.control_legacy)
       ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Migration is not lossless';
    END IF;
END
$migration_validation$;

INSERT INTO tpi_migracion.migration_manifest
    (phase, row_count, sha256)
SELECT 'migration', pg_catalog.count(*),
       tpi_migracion.fn_relation_hash(
           'tpi_migracion.control_legacy'::regclass)
FROM tpi_migracion.control_legacy;

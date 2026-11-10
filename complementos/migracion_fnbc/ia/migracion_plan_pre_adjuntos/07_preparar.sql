DO $prepare_guard$
BEGIN
    IF pg_catalog.current_database() <> 'foodstore_tpi_migracion_nov10' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Unexpected working database';
    END IF;

    IF pg_catalog.to_regnamespace('tpi_migracion') IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE = '42P06',
            MESSAGE = 'Destination schema must not exist';
    END IF;

    IF EXISTS (
        (SELECT lote_id, deposito_id, responsable_control_id
         FROM public.control_lote_almacen_original
         EXCEPT ALL
         SELECT *
         FROM (VALUES
             (501::bigint, 30::bigint, 801::bigint),
             (502::bigint, 30::bigint, 801::bigint),
             (503::bigint, 31::bigint, 802::bigint)
         ) AS expected(lote_id, deposito_id, responsable_control_id))
        UNION ALL
        (SELECT *
         FROM (VALUES
             (501::bigint, 30::bigint, 801::bigint),
             (502::bigint, 30::bigint, 801::bigint),
             (503::bigint, 31::bigint, 802::bigint)
         ) AS expected(lote_id, deposito_id, responsable_control_id)
         EXCEPT ALL
         SELECT lote_id, deposito_id, responsable_control_id
         FROM public.control_lote_almacen_original)
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Source fixture differs from the three required rows';
    END IF;
END
$prepare_guard$;

CREATE SCHEMA tpi_migracion;

CREATE TABLE tpi_migracion.control_legacy (
    lote_id bigint NOT NULL,
    deposito_id bigint NOT NULL,
    responsable_control_id bigint NOT NULL,
    PRIMARY KEY (lote_id, deposito_id),
    FOREIGN KEY (lote_id) REFERENCES public.lote(id),
    FOREIGN KEY (deposito_id) REFERENCES public.deposito(id),
    FOREIGN KEY (responsable_control_id) REFERENCES public.usuario(id)
);

CREATE TABLE tpi_migracion.control_legacy_checkpoint (
    lote_id bigint NOT NULL,
    deposito_id bigint NOT NULL,
    responsable_control_id bigint NOT NULL,
    PRIMARY KEY (lote_id, deposito_id),
    FOREIGN KEY (lote_id) REFERENCES public.lote(id),
    FOREIGN KEY (deposito_id) REFERENCES public.deposito(id),
    FOREIGN KEY (responsable_control_id) REFERENCES public.usuario(id)
);

CREATE TABLE tpi_migracion.migration_manifest (
    phase text PRIMARY KEY,
    row_count bigint NOT NULL CHECK (row_count >= 0),
    sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    recorded_at timestamp with time zone NOT NULL
        DEFAULT pg_catalog.clock_timestamp()
);

INSERT INTO tpi_migracion.control_legacy
    (lote_id, deposito_id, responsable_control_id)
SELECT lote_id, deposito_id, responsable_control_id
FROM public.control_lote_almacen_original;

INSERT INTO tpi_migracion.control_legacy_checkpoint
    (lote_id, deposito_id, responsable_control_id)
SELECT lote_id, deposito_id, responsable_control_id
FROM tpi_migracion.control_legacy;

CREATE FUNCTION tpi_migracion.fn_relation_hash(relation_name regclass)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = pg_catalog
AS $hash$
DECLARE
    namespace_name text;
    table_name text;
    result_hash text;
BEGIN
    SELECT n.nspname, c.relname
    INTO STRICT namespace_name, table_name
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE c.oid = relation_name;

    IF namespace_name <> 'tpi_migracion' THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Hash helper accepts destination relations only';
    END IF;

    EXECUTE pg_catalog.format(
        'SELECT pg_catalog.encode(pg_catalog.sha256(' ||
        'pg_catalog.convert_to(COALESCE(pg_catalog.string_agg(' ||
        'lote_id::text || '','' || deposito_id::text || '','' || ' ||
        'responsable_control_id::text, '';'' ORDER BY ' ||
        'lote_id, deposito_id, responsable_control_id), ''''), ' ||
        '''UTF8'')), ''hex'') FROM %I.%I',
        namespace_name, table_name
    ) INTO result_hash;

    RETURN result_hash;
END
$hash$;

CREATE FUNCTION tpi_migracion.fn_checkpoint_readonly()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $checkpoint$
BEGIN
    RAISE EXCEPTION USING ERRCODE = '25006',
        MESSAGE = 'Checkpoint is read only';
END
$checkpoint$;

CREATE TRIGGER checkpoint_readonly
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE
ON tpi_migracion.control_legacy_checkpoint
FOR EACH STATEMENT
EXECUTE FUNCTION tpi_migracion.fn_checkpoint_readonly();

CREATE FUNCTION tpi_migracion.fn_check_fd_rd()
RETURNS void
LANGUAGE plpgsql
VOLATILE
SET search_path = pg_catalog
AS $precondition$
BEGIN
    IF pg_catalog.current_database() <> 'foodstore_tpi_migracion_nov10'
       OR pg_catalog.to_regnamespace('tpi_migracion') IS NULL THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'Unexpected migration destination';
    END IF;

    IF EXISTS (
        SELECT responsable_control_id
        FROM tpi_migracion.control_legacy
        GROUP BY responsable_control_id
        HAVING pg_catalog.count(DISTINCT deposito_id) > 1
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Functional dependency R to D is violated';
    END IF;
END
$precondition$;

INSERT INTO tpi_migracion.migration_manifest
    (phase, row_count, sha256)
SELECT 'legacy_initial', pg_catalog.count(*),
       tpi_migracion.fn_relation_hash(
           'tpi_migracion.control_legacy'::regclass)
FROM tpi_migracion.control_legacy;

INSERT INTO tpi_migracion.migration_manifest
    (phase, row_count, sha256)
SELECT 'checkpoint_initial', pg_catalog.count(*),
       tpi_migracion.fn_relation_hash(
           'tpi_migracion.control_legacy_checkpoint'::regclass)
FROM tpi_migracion.control_legacy_checkpoint;

DO $prepared$
BEGIN
    IF (SELECT pg_catalog.count(*)
        FROM tpi_migracion.control_legacy) <> 3
       OR (SELECT pg_catalog.count(*)
           FROM tpi_migracion.control_legacy_checkpoint) <> 3
       OR tpi_migracion.fn_relation_hash(
           'tpi_migracion.control_legacy'::regclass)
          <> tpi_migracion.fn_relation_hash(
           'tpi_migracion.control_legacy_checkpoint'::regclass) THEN
        RAISE EXCEPTION USING ERRCODE = '23514',
            MESSAGE = 'Preparation verification failed';
    END IF;
END
$prepared$;

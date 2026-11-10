-- Food Store - Trabajo Practico Unidad 4.
-- Integrantes: Exequiel Arancibia - Joaquin Romero.
-- Parte 1: FNBC de ControlLoteAlmacen.
-- PostgreSQL 16 o superior. Archivo UTF-8.
-- Base: foodstore_u4_arancibia_romero; respaldo TP4 con ampliaciones del TP5.
--
-- PRIMERA EJECUCION
-- Ejecutar este archivo completo sobre la copia indicada, con ON_ERROR_STOP=1.
-- La extension se incorpora a public, donde ya existe el Food Store heredado.
-- No se crea, reemplaza ni carga usuario: se reutilizan sus IDs 801, 802 y 803.
-- Solo se agregan los maestros nuevos lote y deposito y las relaciones del TP.
-- No contiene DROP. CREATE TABLE falla si ya se ejecuto esta extension.
-- Las FK nuevas mantienen la politica ON DELETE RESTRICT de TP1/TP2.
-- Las tablas pedido y detalle_pedido y sus restricciones heredadas se conservan.
--
-- Notación: L = LoteID; D = DepositoID; R = ResponsableControlID.
-- Dependencias funcionales de negocio: LD -> R y R -> D.
-- Claves candidatas: LD y LR; todos los atributos son primos.
-- R -> D viola FNBC porque R+ = RD y no determina L.
-- Descomposición: RD y LR. R es la intersección y clave de RD:
-- la reunión natural es sin pérdida. Ambas relaciones quedan en FNBC.

BEGIN;

SET LOCAL search_path = pg_catalog, public;

-- 1. Comprobar la copia y los responsables ya existentes antes del DDL.
DO $$
BEGIN
    IF current_database() <> 'foodstore_u4_arancibia_romero' THEN
        RAISE EXCEPTION 'Base incorrecta: se esperaba foodstore_u4_arancibia_romero, se obtuvo %',
            current_database();
    END IF;
    IF to_regclass('public.usuario') IS NULL THEN
        RAISE EXCEPTION 'Falta public.usuario: primero restaurar la base acumulativa TP1-TP5';
    END IF;
    IF (SELECT COUNT(*) FROM public.usuario WHERE id IN (801, 802, 803)) <> 3 THEN
        RAISE EXCEPTION 'La copia debe conservar los usuarios existentes 801, 802 y 803';
    END IF;
END
$$;

-- Lote y deposito no existen en los antecedentes: son la extension mayorista
-- de la guia U4. Se agregan datos descriptivos y claves BIGINT compatibles.
CREATE TABLE public.lote (
    id BIGINT PRIMARY KEY,
    codigo VARCHAR(40) NOT NULL UNIQUE
);

CREATE TABLE public.deposito (
    id BIGINT PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL UNIQUE
);

INSERT INTO public.lote (id, codigo) VALUES
    (501, 'LOTE-U4-501'),
    (502, 'LOTE-U4-502'),
    (503, 'LOTE-U4-503');

INSERT INTO public.deposito (id, nombre) VALUES
    (30, 'Deposito Central Food Store'),
    (31, 'Deposito Norte Food Store');

-- 2. Esquema original de la consigna.
-- Su PK impone LD -> R, pero no impone por sí sola R -> D.
CREATE TABLE public.control_lote_almacen (
    lote_id BIGINT NOT NULL REFERENCES public.lote(id) ON DELETE RESTRICT,
    deposito_id BIGINT NOT NULL REFERENCES public.deposito(id) ON DELETE RESTRICT,
    responsable_control_id BIGINT NOT NULL REFERENCES public.usuario(id) ON DELETE RESTRICT,
    PRIMARY KEY (lote_id, deposito_id)
);

INSERT INTO public.control_lote_almacen
    (lote_id, deposito_id, responsable_control_id)
VALUES
    (501, 30, 801),
    (502, 30, 801),
    (503, 31, 802);

-- 3. Validar la dependencia de negocio antes de migrar.
-- Si un responsable aparece con depósitos diferentes, no se elige uno
-- arbitrariamente: se interrumpe la transacción para corregir la fuente.
DO $$
BEGIN
    IF EXISTS (
        SELECT responsable_control_id
        FROM public.control_lote_almacen
        GROUP BY responsable_control_id
        HAVING COUNT(DISTINCT deposito_id) > 1
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'La instancia original incumple ResponsableControlID -> DepositoID';
    END IF;
END
$$;

-- La copia original se conserva solo como evidencia estática de la migración.
-- El nombre operativo original pasará a ser una vista de compatibilidad.
ALTER TABLE public.control_lote_almacen
    RENAME TO control_lote_almacen_original;

-- 4. Tablas descompuestas en FNBC.
CREATE TABLE public.responsable_deposito (
    responsable_control_id BIGINT PRIMARY KEY
        REFERENCES public.usuario(id) ON DELETE RESTRICT,
    deposito_id BIGINT NOT NULL
        REFERENCES public.deposito(id) ON DELETE RESTRICT
);

CREATE TABLE public.lote_responsable (
    lote_id BIGINT NOT NULL
        REFERENCES public.lote(id) ON DELETE RESTRICT,
    responsable_control_id BIGINT NOT NULL
        REFERENCES public.responsable_deposito(responsable_control_id) ON DELETE RESTRICT,
    PRIMARY KEY (lote_id, responsable_control_id)
);

-- 5. Migrar las proyecciones; R -> D permite una sola fila maestra por R.
INSERT INTO public.responsable_deposito
    (responsable_control_id, deposito_id)
SELECT DISTINCT responsable_control_id, deposito_id
FROM public.control_lote_almacen_original;

INSERT INTO public.lote_responsable
    (lote_id, responsable_control_id)
SELECT lote_id, responsable_control_id
FROM public.control_lote_almacen_original;

-- El único nombre común de ambas tablas es responsable_control_id.
-- La lista SELECT conserva el orden de columnas de la relación original.
CREATE VIEW public.control_lote_almacen AS
SELECT lote_id, deposito_id, responsable_control_id
FROM public.lote_responsable
NATURAL JOIN public.responsable_deposito;

-- 6. Preservar la regla LD -> R después de descomponer.
-- IMPORTANTE: la descomposición es sin pérdida, pero NO preserva LD -> R
-- mediante las PK y FK locales. Por ejemplo, R801 y R803 podrían pertenecer
-- ambos a D30 y asignarse los dos a L501. Las PK y FK lo permitirían.
-- UNIQUE(lote_id, deposito_id) no es declarable en lote_responsable, porque
-- deposito_id no pertenece a esa tabla. Reintroducirlo duplicaría el maestro.
--
-- Se usa un bloqueo de escritura sobre una única fila técnica, seguido de
-- una validación del JOIN. La guardia no copia ningún dato del negocio.
-- El UPDATE mantiene la exclusión hasta COMMIT/ROLLBACK; ambas tablas usan
-- la misma guardia. Esto serializa sus escrituras y evita comprobaciones
-- concurrentes que acepten por separado una combinación inválida.
-- Las funciones son VOLATILE: en READ COMMITTED, las consultas internas
-- posteriores al bloqueo ven los cambios ya confirmados. Si una transacción
-- REPEATABLE READ/SERIALIZABLE conserva un snapshot anterior al cambio de
-- la guardia por otra transacción, PostgreSQL la aborta por serialización;
-- la aplicación debe reintentar la transacción completa.
-- El costo de esta solución didáctica es una menor concurrencia de escritura.
CREATE TABLE public.guardia_control_lote (
    id SMALLINT PRIMARY KEY CHECK (id = 1),
    turno BOOLEAN NOT NULL
);

INSERT INTO public.guardia_control_lote (id, turno) VALUES (1, FALSE);

CREATE FUNCTION public.bloquear_control_lote()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
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

CREATE FUNCTION public.verificar_control_lote()
RETURNS trigger
LANGUAGE plpgsql
VOLATILE
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

CREATE TRIGGER bloquear_lote_responsable
BEFORE INSERT OR UPDATE OR DELETE
ON public.lote_responsable
FOR EACH STATEMENT
EXECUTE FUNCTION public.bloquear_control_lote();

CREATE TRIGGER verificar_lote_responsable
AFTER INSERT OR UPDATE OR DELETE
ON public.lote_responsable
FOR EACH STATEMENT
EXECUTE FUNCTION public.verificar_control_lote();

CREATE TRIGGER bloquear_responsable_deposito
BEFORE INSERT OR UPDATE OR DELETE
ON public.responsable_deposito
FOR EACH STATEMENT
EXECUTE FUNCTION public.bloquear_control_lote();

CREATE TRIGGER verificar_responsable_deposito
AFTER INSERT OR UPDATE OR DELETE
ON public.responsable_deposito
FOR EACH STATEMENT
EXECUTE FUNCTION public.verificar_control_lote();

-- 7. Pruebas de la regla que no preservan las FK por sí solas.
-- Los bloques internos capturan solo la violación esperada. Si el trigger
-- permite una operación inválida, la transacción completa se interrumpe.
-- Al terminar se eliminan las filas auxiliares: la vista sigue con 3 filas.
DO $$
DECLARE
    rechazo BOOLEAN := FALSE;
BEGIN
    INSERT INTO public.responsable_deposito
        (responsable_control_id, deposito_id)
    VALUES (803, 30);

    BEGIN
        INSERT INTO public.lote_responsable
            (lote_id, responsable_control_id)
        VALUES (501, 803);
    EXCEPTION
        WHEN unique_violation THEN
            rechazo := TRUE;
    END;

    IF NOT rechazo THEN
        RAISE EXCEPTION 'Prueba fallida: se permitió duplicar un lote y depósito';
    END IF;

    DELETE FROM public.responsable_deposito
    WHERE responsable_control_id = 803;

    RAISE NOTICE 'Correcto: se rechazó un segundo responsable para L501 y D30';
END
$$;

DO $$
DECLARE
    rechazo BOOLEAN := FALSE;
BEGIN
    INSERT INTO public.responsable_deposito
        (responsable_control_id, deposito_id)
    VALUES (803, 31);

    -- L501 puede tener controles en D30 y D31 simultáneamente.
    INSERT INTO public.lote_responsable
        (lote_id, responsable_control_id)
    VALUES (501, 803);

    BEGIN
        -- Mover R803 a D30 produciría dos responsables de L501 en D30.
        UPDATE public.responsable_deposito
        SET deposito_id = 30
        WHERE responsable_control_id = 803;
    EXCEPTION
        WHEN unique_violation THEN
            rechazo := TRUE;
    END;

    IF NOT rechazo THEN
        RAISE EXCEPTION 'Prueba fallida: el cambio maestro permitió duplicar LD';
    END IF;

    DELETE FROM public.lote_responsable
    WHERE lote_id = 501 AND responsable_control_id = 803;
    DELETE FROM public.responsable_deposito
    WHERE responsable_control_id = 803;

    RAISE NOTICE 'Correcto: también se rechazó el cambio maestro que duplicaba LD';
END
$$;

-- 8. Afirmación ejecutable de equivalencia: se comparan ambos sentidos.
-- EXCEPT ALL también verifica multiplicidades, además de valores.
DO $$
BEGIN
    IF EXISTS (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM public.control_lote_almacen_original
        EXCEPT ALL
        SELECT lote_id, deposito_id, responsable_control_id
        FROM public.control_lote_almacen
    ) OR EXISTS (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM public.control_lote_almacen
        EXCEPT ALL
        SELECT lote_id, deposito_id, responsable_control_id
        FROM public.control_lote_almacen_original
    ) THEN
        RAISE EXCEPTION 'La migración no reconstruye la instancia original';
    END IF;
END
$$;

COMMIT;

-- 9. Evidencia visible posterior a la confirmación.
-- Resultado esperado: diferencias = 0.
SELECT COUNT(*) AS diferencias
FROM (
    (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM public.control_lote_almacen_original
        EXCEPT ALL
        SELECT lote_id, deposito_id, responsable_control_id
        FROM public.control_lote_almacen
    )
    UNION ALL
    (
        SELECT lote_id, deposito_id, responsable_control_id
        FROM public.control_lote_almacen
        EXCEPT ALL
        SELECT lote_id, deposito_id, responsable_control_id
        FROM public.control_lote_almacen_original
    )
) AS diferencias_bilaterales;

-- Resultado esperado (3 filas):
-- lote_id | deposito_id | responsable_control_id
-- 501     | 30          | 801
-- 502     | 30          | 801
-- 503     | 31          | 802
SELECT lote_id, deposito_id, responsable_control_id
FROM public.control_lote_almacen
ORDER BY lote_id, deposito_id, responsable_control_id;

-- Auditoría de LD -> R. Resultado esperado: cero filas.
SELECT lote_id, deposito_id, COUNT(*) AS cantidad_responsables
FROM public.control_lote_almacen
GROUP BY lote_id, deposito_id
HAVING COUNT(*) > 1;

-- Auditoría de R -> D. Resultado esperado: cero filas.
SELECT responsable_control_id, COUNT(DISTINCT deposito_id) AS cantidad_depositos
FROM public.control_lote_almacen
GROUP BY responsable_control_id
HAVING COUNT(DISTINCT deposito_id) > 1;

-- Referencias técnicas oficiales para los detalles de concurrencia:
-- https://www.postgresql.org/docs/17/xfunc-volatility.html
-- https://www.postgresql.org/docs/15/transaction-iso.html

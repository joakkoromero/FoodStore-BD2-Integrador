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

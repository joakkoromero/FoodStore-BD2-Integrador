\set ON_ERROR_STOP on

BEGIN READ ONLY;

SET LOCAL TIME ZONE 'UTC';
SET LOCAL DateStyle = 'ISO, YMD';

DO $guard$
BEGIN
    IF current_database() <> 'foodstore_u8_arancibia_romero' THEN
        RAISE EXCEPTION
            'Validacion de copia: se requiere foodstore_u8_arancibia_romero';
    END IF;
END
$guard$;

-- Este archivo solo lee. El runner conserva y compara estos resultados.
-- Precio C2 y baja C4 son preparaciones administrativas en la copia.
-- No se permite que el semaforo cree pedidos ni modifique stock.
-- La huella de productos completos cambia deliberadamente por C2/C4.
-- La huella estructural sin precio/eliminado y el stock deben permanecer iguales.

WITH
fixture AS (
    SELECT
        p.id AS producto_id,
        p.nombre,
        p.precio,
        p.stock,
        p.categoria_id,
        p.eliminado,
        p.created_at,
        p.descripcion
    FROM public.producto AS p
    JOIN public.categoria AS c ON c.id = p.categoria_id
    WHERE c.nombre = 'U8-FERIA-Arancibia-Romero'
      AND p.nombre IN (
          'U8 - Muzzarella', 'U8 - Empanadas',
          'U8 - Fugazzeta', 'U8 - Agua'
      )
),
huellas AS (
    SELECT
        producto_id,
        encode(
            sha256(convert_to(row_to_json(f)::text, 'UTF8')),
            'hex'
        ) AS completa,
        encode(
            sha256(convert_to(
                json_build_array(
                    producto_id, nombre, stock, categoria_id,
                    created_at, descripcion
                )::text,
                'UTF8'
            )),
            'hex'
        ) AS estable
    FROM fixture AS f
)
SELECT json_build_object(
    'base', current_database(),
    'pedidos', (SELECT count(*) FROM public.pedido),
    'productos_fixture', (SELECT count(*) FROM fixture),
    'suma_stock', (SELECT sum(stock::bigint) FROM fixture),
    'vector_stock', (
        SELECT json_agg(
            json_build_object('producto_id', producto_id, 'stock', stock)
            ORDER BY producto_id
        )
        FROM fixture
    ),
    'estado_administrativo', (
        SELECT json_agg(
            json_build_object(
                'producto_id', producto_id,
                'precio_centavos', (precio * 100)::bigint,
                'eliminado', eliminado
            )
            ORDER BY producto_id
        )
        FROM fixture
    ),
    'huella_producto_completa', (
        SELECT encode(
            sha256(convert_to(
                coalesce(string_agg(completa, '' ORDER BY producto_id), ''),
                'UTF8'
            )),
            'hex'
        )
        FROM huellas
    ),
    'huella_producto_sin_precio_ni_baja', (
        SELECT encode(
            sha256(convert_to(
                coalesce(string_agg(estable, '' ORDER BY producto_id), ''),
                'UTF8'
            )),
            'hex'
        )
        FROM huellas
    )
)::text;

COMMIT;

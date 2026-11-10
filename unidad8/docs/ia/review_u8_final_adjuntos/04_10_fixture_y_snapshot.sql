\set ON_ERROR_STOP on

BEGIN;

DO $guard$
BEGIN
    IF current_database() <> 'foodstore_u8_arancibia_romero' THEN
        RAISE EXCEPTION
            'Destino incorrecto: se requiere foodstore_u8_arancibia_romero';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.categoria
        WHERE nombre = 'U8-FERIA-Arancibia-Romero'
    ) OR EXISTS (
        SELECT 1 FROM public.producto
        WHERE nombre IN (
            'U8 - Muzzarella', 'U8 - Empanadas',
            'U8 - Fugazzeta', 'U8 - Agua'
        )
    ) THEN
        RAISE EXCEPTION
            'Fixture o nombres ya existentes; se aborta sin modificar filas previas';
    END IF;

    IF to_regclass('public.v_snapshot_movil') IS NOT NULL THEN
        RAISE EXCEPTION
            'public.v_snapshot_movil ya existe; no se reemplaza';
    END IF;
END
$guard$;

INSERT INTO public.categoria (nombre, descripcion, eliminado)
VALUES (
    'U8-FERIA-Arancibia-Romero',
    'Fixture ficticio de laboratorio U8; no representa ventas',
    false
);

INSERT INTO public.producto
    (nombre, descripcion, precio, stock, categoria_id, eliminado)
SELECT
    f.nombre,
    'Producto ficticio del fixture U8',
    f.precio,
    f.stock,
    c.id,
    false
FROM public.categoria AS c
CROSS JOIN (
    VALUES
        ('U8 - Muzzarella', 9000.00::numeric(12,2), 10),
        ('U8 - Empanadas', 1200.00::numeric(12,2), 4),
        ('U8 - Fugazzeta', 8000.00::numeric(12,2), 5),
        ('U8 - Agua', 1500.00::numeric(12,2), 20)
) AS f(nombre, precio, stock)
WHERE c.nombre = 'U8-FERIA-Arancibia-Romero';

CREATE VIEW public.v_snapshot_movil AS
SELECT
    p.id AS producto_id,
    p.nombre,
    (p.precio * 100)::bigint AS precio_centavos,
    p.stock,
    (p.stock > 0) AS disponible,
    (p.eliminado OR c.eliminado) AS eliminado,
    now() AS capturado_en
FROM public.producto AS p
JOIN public.categoria AS c ON c.id = p.categoria_id
WHERE c.nombre = 'U8-FERIA-Arancibia-Romero'
  AND p.nombre IN (
      'U8 - Muzzarella', 'U8 - Empanadas',
      'U8 - Fugazzeta', 'U8 - Agua'
  );

DO $verify$
BEGIN
    IF (SELECT count(*) FROM public.v_snapshot_movil) <> 4 THEN
        RAISE EXCEPTION 'Se esperaban exactamente cuatro productos fixture';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.v_snapshot_movil
        WHERE precio_centavos IS NULL
           OR stock IS NULL
           OR disponible IS NULL
           OR eliminado IS NULL
    ) THEN
        RAISE EXCEPTION 'Fixture con valores nulos no exportables';
    END IF;
END
$verify$;

COMMIT;

SELECT *
FROM public.v_snapshot_movil
ORDER BY producto_id;

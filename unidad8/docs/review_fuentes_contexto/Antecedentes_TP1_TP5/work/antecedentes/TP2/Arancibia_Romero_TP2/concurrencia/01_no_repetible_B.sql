-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
BEGIN;
UPDATE producto SET precio=1200.00 WHERE id=1;
COMMIT;
-- Antes de repetir la verificacion: UPDATE producto SET precio=1050 WHERE id=1;

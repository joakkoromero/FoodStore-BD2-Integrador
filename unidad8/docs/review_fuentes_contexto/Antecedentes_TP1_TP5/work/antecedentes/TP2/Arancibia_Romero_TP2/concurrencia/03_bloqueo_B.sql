-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
BEGIN;
SELECT id,nombre,stock FROM producto WHERE id=1 FOR UPDATE;
-- queda esperando hasta el COMMIT/ROLLBACK de A
UPDATE producto SET stock=stock+1 WHERE id=1;
ROLLBACK;

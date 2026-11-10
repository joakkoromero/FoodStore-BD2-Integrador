-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
BEGIN;
SELECT id FROM producto WHERE id=1 FOR UPDATE;
-- B bloquea id=2
SELECT id FROM producto WHERE id=2 FOR UPDATE;
-- una sesion recibe ERROR 40P01
ROLLBACK;

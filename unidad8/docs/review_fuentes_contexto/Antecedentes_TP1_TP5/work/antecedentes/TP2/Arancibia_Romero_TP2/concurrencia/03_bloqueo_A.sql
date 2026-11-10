-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
BEGIN;
SELECT id,nombre,stock FROM producto WHERE id=1 FOR UPDATE;
-- mantener abierta; ejecutar Sesion B, que queda esperando
SELECT pg_sleep(5);
COMMIT; -- libera el bloqueo; B continua

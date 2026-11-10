-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Sesion A - READ COMMITTED
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT precio FROM producto WHERE id=1; -- 1050.00
-- ejecutar Sesion B
SELECT precio FROM producto WHERE id=1; -- 1200.00
ROLLBACK;

-- Verificacion en REPEATABLE READ
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT precio FROM producto WHERE id=1; -- 1050.00
-- ejecutar nuevamente Sesion B
SELECT precio FROM producto WHERE id=1; -- sigue 1050.00
ROLLBACK;

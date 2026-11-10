-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
BEGIN ISOLATION LEVEL READ COMMITTED;
SELECT count(*) FROM producto WHERE categoria_id=1 AND eliminado=FALSE; -- 2
-- ejecutar Sesion B
SELECT count(*) FROM producto WHERE categoria_id=1 AND eliminado=FALSE; -- 3
ROLLBACK;

BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT count(*) FROM producto WHERE categoria_id=1 AND eliminado=FALSE; -- 2
-- ejecutar nuevamente Sesion B
SELECT count(*) FROM producto WHERE categoria_id=1 AND eliminado=FALSE; -- sigue 2
ROLLBACK;

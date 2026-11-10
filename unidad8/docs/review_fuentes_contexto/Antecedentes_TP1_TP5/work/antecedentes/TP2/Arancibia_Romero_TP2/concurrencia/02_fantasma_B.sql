-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
BEGIN;
INSERT INTO producto(nombre,precio,stock,categoria_id)
VALUES ('Producto fantasma TP2',100.00,1,1);
COMMIT;
-- Limpiar entre pruebas: DELETE FROM producto WHERE nombre='Producto fantasma TP2';

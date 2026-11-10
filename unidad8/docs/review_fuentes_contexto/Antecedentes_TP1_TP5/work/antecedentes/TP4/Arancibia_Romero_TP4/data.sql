-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Seed inicial de Food Store reutilizado en TP3
BEGIN;
INSERT INTO categoria (nombre, descripcion) VALUES
 ('DATO_FICTICIO_SANEADO_e780c3af5578','DATO_FICTICIO_SANEADO_9e7386e98f7f'),
 ('DATO_FICTICIO_SANEADO_f63b916ad481','DATO_FICTICIO_SANEADO_119e87451c6b');

INSERT INTO producto (nombre, precio, stock, categoria_id) VALUES
 ('DATO_FICTICIO_SANEADO_3f8fd42f376a',1050.00,50,1), ('DATO_FICTICIO_SANEADO_580f452e6f00',800.00,100,2),
 ('DATO_FICTICIO_SANEADO_447667352a1e',1500.00,40,1);

INSERT INTO usuario (nombre, apellido, email, contrasena, telefono) VALUES
 ('DATO_FICTICIO_SANEADO_dea210f058b4','DATO_FICTICIO_SANEADO_d9e1b51ac980','persona_7b82d4dc39cc@ejemplo.invalid','DATO_FICTICIO_SANEADO_2f6601880bf6','0000000000'),
 ('DATO_FICTICIO_SANEADO_1be075b9041a','DATO_FICTICIO_SANEADO_3b4ca471d9af','persona_07b4590b7f54@ejemplo.invalid','DATO_FICTICIO_SANEADO_f3d766872793',NULL),
 ('DATO_FICTICIO_SANEADO_c14d56be84c2','DATO_FICTICIO_SANEADO_7c8c32faff7c','persona_f2512bd20535@ejemplo.invalid','DATO_FICTICIO_SANEADO_6c74f7db15fe','0000000000');

INSERT INTO pedido (usuario_id, fecha, forma_pago) VALUES
 (1,'2026-03-01 12:00-03','EFECTIVO'),
 (2,'2026-03-01 13:00-03','TARJETA'),
 (1,'2026-03-05 20:00-03','TRANSFERENCIA'),
 (3,'2026-03-06 21:00-03','EFECTIVO'),
 (2,'2026-03-07 21:30-03','TARJETA');

INSERT INTO detalle_pedido (pedido_id, producto_id, cantidad, precio_unitario) VALUES
 (1,1,2,1000.00),(1,2,1,800.00),(2,3,1,1500.00),
 (3,1,3,1050.00),(4,2,4,800.00),(4,3,2,1500.00),(5,1,1,1050.00);

UPDATE pedido SET estado='ENTREGADO'  WHERE id IN (1,2,3,4);
UPDATE pedido SET estado='CONFIRMADO' WHERE id=5;
COMMIT;

-- Control esperado: 2800, 1500, 3150, 6200 y 1050.
SELECT id, total FROM pedido ORDER BY id;

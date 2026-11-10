# Guion para ensayo de defensa - diez minutos

Material para que el equipo realice el ensayo. No se registra como una actividad presencial ya realizada.

| Tiempo | Qué mostrar | Qué explicar |
|---|---|---|
| 0:00-2:00 | Mapa PostgreSQL / MongoDB U7 / SQLite | Quién escribe y quién manda. La tablet prepara; el verde simulado no es venta. |
| 2:00-4:00 | Esquema, foreign_keys=1, STRICT e índice parcial | Centavos exactos, FK, UUID y atomicidad del borrador completo. Por qué UNIQUE global en id_local impediría reintentar tras un conflicto. |
| 4:00-6:30 | Caso C2 o C4 desde la evidencia y una ejecución local preparada | Precio cambiado: conflicto, aceptación simulada y UUID nuevo. O baja: lápida conservada y producto oculto. Mostrar estado/motivo y SQL que los produjo. |
| 6:30-8:00 | C6 y C7 | UUID repetido da error; repetir semáforo no cambia históricos. Un CHECK/FK aborta la sentencia y ROLLBACK revierte también el encabezado. |
| 8:00-9:30 | Tres hallazgos y decisiones del review | Eliminar detalle final:23514, total de app:42501, INSERT final vacío de administrador y guarda corregida. Distinguir permisos de la app y del propietario. |
| 9:30-10:00 | Conservación y mantenimiento | Huellas de la fuente y stock sin cambios; al restaurar servidor se invalidan cachés y se reconcilian colas. |

## Preguntas para responder sin ayuda

1. ¿Por qué SQLite es relacional y embebida, y no un servidor NoSQL?
2. ¿Qué pasa si no se activa foreign_keys en otra conexión?
3. ¿Por qué se eligen centavos INTEGER64 y se convierte NUMERIC a BIGINT en PostgreSQL?
4. ¿Por qué el semáforo compara con snapshot_servidor y usa LEFT JOIN?
5. ¿Por qué gana el rojo aunque otro producto tenga un precio distinto?
6. ¿Qué diferencia hay entre el UUID del borrador y el de cada solicitud?
7. ¿Por qué no se borra físicamente el producto dado de baja de la caché?
8. ¿Qué hace una transacción que falla en SQLite y por qué se necesita ROLLBACK explícito?
9. ¿Dónde se implementaría la protección real contra ventas duplicadas?
10. ¿Qué se verificó realmente y qué límites tienen las huellas y el review estático?

Para una demostración desde cero se usa una carpeta nueva sólo con fuentes y una copia PostgreSQL nueva, según README; la entrega original se conserva. Para una demostración rápida offline pueden abrirse en modo de lectura la SQLite y las salidas registradas, sin presentar esas lecturas como una nueva ejecución del caso.

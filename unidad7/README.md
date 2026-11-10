# Food Store - Trabajo Práctico Unidad 7

Integrantes: Exequiel Arancibia y Joaquin Romero.

El informe explica las consignas 1 a 7 y contiene salidas de ejecución reales.
La fuente canónica es `foodstore`, acumulada en las unidades 4 a 6; se seleccionaron
los pedidos 1 a 5 ya existentes. No se agregaron pedidos al origen.

## Archivos

- `output/pdf/TP_U7_FoodStore_Arancibia_Romero.pdf`: informe de exactamente cinco
  páginas; incluye fuentes y evidencias como adjuntos PDF extraíbles.
- `consultas_mongodb.js`: crea y valida `foodstore_u7.pedidos`, importa la muestra,
  ejecuta cuatro consultas y pruebas negativas. No elimina colecciones.
- `consultas_postgresql.sql`: exportación y consultas equivalentes en transacción
  de sólo lectura, acotadas a los mismos cinco pedidos.
- `pedidos_migrados.ejson`: muestra fiel con identificadores Long, cantidades Int32,
  fechas UTC y dinero Decimal128. Alias de clientes de presentación, sin PII real.
- `docs/evidencias`: salidas, huellas de conservación y validación cruzada.
- `docs/ia/consulta_respuesta.md`: prompt, respuesta y contraste de IA.

## Reproducción

1. Con PostgreSQL 17 y la base acumulada del equipo, ejecutar:
   `psql -X -v ON_ERROR_STOP=1 -d foodstore -f consultas_postgresql.sql`.
   Utilizar la conexión y las credenciales propias; no se incluyen secretos.
2. Situarse en esta carpeta, junto al archivo EJSON. Con MongoDB 8.0 y mongosh,
   ejecutar `mongosh <conexion propia autenticada> --quiet --file consultas_mongodb.js`.
   La cuenta requiere administrar únicamente la base de laboratorio `foodstore_u7`.
3. Si la colección ya existe, el script exige que su contenido sea idéntico a la
   muestra antes de reaplicar el validador. Ante diferencias aborta sin reemplazarla.
4. Comparar las salidas b/c: estado ENTREGADO -> [1,2,3,4]; producto 1 -> [1,3,5].
   El umbral total > 3000.00 devuelve [3,4].

Entorno realmente usado: PostgreSQL 17.11, MongoDB Community 8.0.34 y mongosh 2.14.1,
Windows, servicios privados autenticados de laboratorio en loopback. Las descargas
portátiles provienen de distribuidores oficiales con SHA256 oficial coincidente.
No se instaló un servicio ni se publicó una instancia en Internet.

Las validaciones certifican esta muestra y las fuentes ejecutadas; no evalúan
rendimiento, replicación ni sincronización entre motores. El repositorio es local,
sin remoto. Los commits técnicos se identifican como Codex, no como los alumnos.

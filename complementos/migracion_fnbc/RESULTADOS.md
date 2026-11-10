# Resultado real del complemento FNBC del TPI

Ensayo nuevo del 10/11/2026, distinto de la migracion U4 historica. Termino con estado SUCCESS y exit code 0. Intervalo observado: 15:02:03-15:04:22 de Argentina (18:02:03-18:04:22 UTC); duracion total 139,056s. Esta duracion es la del ensayo completo FNBC, no el RTO del simulacro de desastre.

## Procedencia y aislamiento

Las specs genuinas Kiro se guardaron en el commit 89f81022a2c103493d501b43e951eade62dde34f antes de generar implementacion. Se conservo el Build original en 37911595538ed433b9f8287cea29b223d870526a. La implementacion corregida y el Plan final completo se congelaron antes de ejecutar en c3711ccb7e0d75d6f2a1cd28d3af14478b44ef5e. Se verificaron los seis hashes de fuentes, metadatos originales, snapshots y rangos completos del runner 1-740/741-1480; al terminar esos seis archivos mantenian sus bytes. Las decisiones FD01-FD07 estan en ia/decisiones_review.json.

Se creo una copia NUEVA foodstore_tpi_migracion_nov10 con la herramienta oficial createdb y template foodstore, sin DROP, reemplazos ni reutilizacion silenciosa. Solo se escribio el esquema nuevo tpi_migracion. Se valido el respaldo fuente SUCCESS de 8.224.005bytes, SHA256 8067e36dca81ea6b8c5a870d1bddc2927634a33aad842d22d96bf09c1bd82b19, antes del ensayo y se volvio a verificar durante las fases. El respaldo no se incluye en el paquete; no se generaron dumps intermedios de los cuatro registros nuevos, porque la reversion no elimina objetos y conserva la version normalizada.

## Resultados de las fases

| Control real | Resultado |
|---|---|
| Fuente que viola R->D e intento del mismo migrar.sql | Rechazo 23514 y ROLLBACK; tabla/checkpoint 3, catalogo intacto |
| Migracion completa con ROLLBACK | Tres filas dentro; equivalencia bilateral 0; desde otra conexion se recupero tabla inicial y catalogo exacto |
| Mismo cuerpo con COMMIT | Vista operativa de 3 filas; PK/FK validadas; EXCEPT ALL bilateral 0 |
| PK y regla LD por INSERT/UPDATE | Rechazos 23505 exactos |
| Dos FK inexistentes | Rechazos 23503 exactos |
| UPDATE maestro valido previo | Aceptado y revertido; fixture de 3 filas antes de concurrencia |
| Concurrencia real | A 41952 confirmo; B 24484 espero Lock con A en pg_blocking_pids y recibio 23505; monitor 41324; cleanup confirmado aparte |
| Cambios validos posteriores al COMMIT | JOIN actual 4 filas, distintas del checkpoint 3 |
| Error inyectado durante down | P7501 observado; ROLLBACK restauro vista, catalogo, nombres, ciclo activo y 4 filas |
| Down confirmado | Tabla heredada 4 filas desde JOIN ACTUAL, diferencias bilaterales 0; vista/RD/LR archivadas y ciclo inactivo |
| Proteccion final del archivo/checkpoint | Doce operaciones negativas de DML/TRUNCATE rechazadas 25006, sin alterar filas ni hashes |

El mismo SHA256 del cuerpo migrar.sql se uso para precondicion invalida, ensayo ROLLBACK y COMMIT: ce96500b44174630964c396feabe91dbd7624e18896a608a32e4d7a2a51e2bd1.

Las cuatro filas conservadas al revertir, en orden L,D,R, son:

- (501,30,803)
- (501,31,801)
- (502,31,801)
- (503,31,802)

Su SHA256 es d2738ca769e58fb867ab2dc2b7d678ded2a9d6031525506d18dc0b375487a1d4. El checkpoint inicial sigue con las tres filas originales. Volver a copiar ciegamente ese checkpoint habria perdido el cambio confirmado; la reconstruccion se hizo desde la reunion actual bajo bloqueo.

## Conservacion y limites

Once observaciones de fase verificaron las cinco tablas centrales y una huella adicional de extensiones/catalogo. En la copia y en la fuente oficial los before/after coincidieron: categoria 2, producto 50.000, usuario 20.001, pedido 225.000 y detalle_pedido 499.997. No se modificaron public ni la fuente. Las filas personales se agregaron dentro de PostgreSQL; no se exportaron. No se crearon secuencias. La evidencia no prueba inmutabilidad del cluster ni ausencia de cambios transitorios de terceros.

Los triggers protegen la politica de aplicacion y el ciclo del ensayo; no impiden que un propietario altere el DDL o la guardia. READ COMMITTED se probo realmente; los abortos posibles 40001 en otros aislamientos se documentan, sin afirmar haberlos probado. La revision y las pruebas fueron tecnicas automatizadas: no se atribuyen firmas ni revision humana del equipo.

Evidencia principal: ../../docs/evidencias_tpi/migracion_fnbc.json. Proveniencia completa y hashes: seccion provenance del mismo archivo. No quedan pruebas adicionales necesarias dentro de este alcance.

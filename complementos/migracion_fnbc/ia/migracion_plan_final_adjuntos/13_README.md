# Complemento nuevo FNBC del TPI

Fecha de especificacion: 10/11/2026. Este procedimiento no atribuye a Kiro la migracion historica U4. Las respuestas reales, la generacion original y las decisiones de revision se conservan en docs/kiro_migracion e ia/. La ejecucion concreta se acredita solamente con el JSON de evidencias y su estado SUCCESS; este README no acredita firmas ni lectura humana.

## Alcance y origen de las fuentes

PostgreSQL 16+ con PL/pgSQL; laboratorio observado sobre 17.11. Python 3.12+ y biblioteca estandar. El cliente reutilizado unidad5/tools/libpq_client.py requiere el libpq.dll de PostgreSQL instalado en Windows, en la ruta declarada por ese cliente; no se promete portabilidad sin adaptar ese requisito.

La unica base que se escribe es foodstore_tpi_migracion_nov10 y el unico esquema nuevo es tpi_migracion. La copia debe existir, conservar las tablas/maestros heredados y no tener ese esquema. No se crean ni borran bases, usuarios, permisos, maestros public o secuencias. El operador crea una copia nueva a partir del Food Store acumulado, conserva el respaldo previo verificado y evita escritores externos. El programa no reemplaza una copia existente ni limpia una instalacion parcial.

| Fuente | Origen y funcion |
|---|---|
| preparar.sql | OpenCode Build: base/esquema, tabla heredada, checkpoint protegido, manifiesto y prevalidacion |
| migrar.sql | OpenCode Build: cuerpo unico para ROLLBACK/COMMIT, RD/LR, guardia y vista |
| revertir.sql | OpenCode Build: captura actual, reconstruccion, renombrado y archivo protegido |
| reproducir.py | OpenCode Build, correcciones Codex registradas: orquestacion y evidencia |
| README.md | OpenCode Build, adecuacion Codex al formato real de wrappers/respaldos |
| preparar_proveniencia.py | Complemento Codex: construye indice de artefactos reales, sin conectar motores |

Los SQL son cuerpos sin control transaccional propio de nivel superior. Los BEGIN/END de PL/pgSQL son normales. El runner abre y cierra las transacciones y verifica antes de confirmar. Se reutiliza el mismo archivo migrar.sql en el ensayo ROLLBACK y en el COMMIT.

## Datos y objetos conservados

La fuente public.control_lote_almacen_original debe tener exactamente (501,30,801), (502,30,801), (503,31,802), en orden de columnas lote_id,deposito_id,responsable_control_id. Los responsables ya existen en public.usuario; no se exportan nombres ni contactos.

La preparacion confirma control_legacy (tabla) y control_legacy_checkpoint (tabla protegida) con tres filas. La migracion conserva la tabla anterior como control_legacy_pre_migracion, crea RD/LR, _migration_guard, funciones y triggers y deja control_legacy como vista. Tras probar reglas y concurrencia se confirman tres cambios validos: R801 pasa a D31, R803 pertenece a D30 y L501 se asigna tambien a R803. El JOIN actual tiene cuatro filas: (501,30,803), (501,31,801), (502,31,801), (503,31,802).

Down captura ese JOIN actual bajo bloqueo en down_snapshot y reconstruye control_legacy_new. Compara hash y EXCEPT ALL bilateral con las cuatro filas confirmadas. Renombra la vista a control_legacy_fnbc_archivada y la tabla nueva a control_legacy. NO hay DROP ni CASCADE: las relaciones normalizadas y los checkpoints se conservan. La marca active=false hace que los triggers rechacen DML posterior en RD/LR con 25006; el checkpoint tambien rechaza escrituras desde su preparacion. Un propietario capaz de alterar DDL puede cambiar estas protecciones: no se afirma lo contrario.

## Respaldo y privacidad

Se requiere un manifiesto privado U6 autentico: status=SUCCESS, database=foodstore, file=basename seguro, size=bytes positivos, sha256=64 hex, startUtc/endUtc con zona y baseline con counts y fingerprints MD5 de 32 hex. El SHA256 corresponde al dump completo; las huellas MD5 de las tablas son otra receta y no se confunden.

El manifiesto real puede estar en logs/ y el dump en el directorio hermano backups/, o ambos en la misma carpeta. Se exige un unico candidato, basename, formato custom PGDMP, bytes y SHA256 exactos. No se altera ni reescribe el manifiesto privado. Sus tiempos deben preceder al ensayo. Los archivos privados deben permanecer fuera del repositorio y con permisos adecuados; el runner no publica ni imprime sus contenidos.

Antes de cada fase se vuelve a validar EL MISMO respaldo fuente inicial. Esto no crea un respaldo nuevo del estado intermedio de cuatro filas. La reversion ensayada no elimina objetos y conserva tambien la version normalizada; cualquier uso posterior con operaciones destructivas exigiria un respaldo actualizado de esa copia. La restauracion real de ese respaldo se documenta por el simulacro de mantenimiento, no por la simple verificacion de su hash en este runner.

## Puerta de revision real

Se conservan los metadatos originales OpenCode sin inventarles campos. El wrapper real registra agent=build/plan, pure=true, permission_config.permission=deny, tool_event_count=0, error_event_count=0, returncode=0, status=completed y sql_executed=false. Tambien enlaza SHA256 de prompt, respuesta, snapshots y las tres specs congeladas en Git antes de consultar.

La cobertura de codigo se registra aparte en ia/plan_cobertura_fuentes.json, como mapa tecnico Codex. Lista los seis hashes finales. Para el runner largo conserva partes de menos de 40 KB con rangos continuos y cuerpo SOURCE_BEGIN/SOURCE_END; se comprueba que los snapshots recibidos por Plan reconstruyan todas las lineas exactas del archivo. Los otros archivos se adjuntan completos. La respuesta real debe revisarse para confirmar cobertura completa y resolver sus hallazgos; el mapa no equivale a una firma humana ni a una aprobacion del proveedor inventada.

El indice de ejecucion enlaza tres specs, tres entradas Codex previas, prompt/respuesta/metadatos Build/Plan y ese mapa de cobertura. Las versiones deben estar en Git. La decision tecnica allow_execution pertenece a Codex y se distingue de la revision humana del equipo. Un cambio posterior de una fuente obliga a nuevo Plan y nuevos hashes; no se edita el historial real para aparentar que fue revisado.

## Reproducir

1. Leer specs, aclaraciones y las seis fuentes; revisar el Plan real y sus decisiones. Preparar PostgreSQL, copia NUEVA, secreto JSON externo compatible con el cliente U5 y manifiesto/dump privados. Evitar escritores externos.
2. Confirmar en Git las fuentes finales y todos los artefactos de revision, antes de crear el indice. No ejecutar el generador ni el SQL original archivado en ia/generacion_original.
3. Construir un indice nuevo con el helper (el flag representa una decision tecnica automatizada, no una firma humana):

```console
python complementos/migracion_fnbc/preparar_proveniencia.py --output C:\privado\migracion_indice.json --plan-prefix migracion_plan_final --permitir-ejecucion-tecnica
```

4. Ejecutar desde la raiz, sin exponer el contenido del secreto:

```console
python complementos/migracion_fnbc/reproducir.py --secret-file C:\privado\secrets.json --backup-manifest C:\privado\logs\respaldo.manifest.json --provenance C:\privado\migracion_indice.json
```

Los paths anteriores son ejemplos, no archivos de credenciales entregados. Defaults: host 127.0.0.1, puerto 55605, usuario u5_bootstrap, fuente foodstore. El nombre de la copia de escritura es fijo. El JSON final se escribe en docs/evidencias_tpi/migracion_fnbc.json; se rechaza sobrescribir evidencia. Conservar intentos fallidos con otro nombre si corresponde, sin borrar una instalacion parcial.

## Pruebas y limites

- Precondicion negativa: INSERT valido para PK/FK pero que viola R->D y ejecucion del MISMO migrar.sql real; se espera 23514 y ROLLBACK sin objetos parciales.
- Migracion completa con ROLLBACK y observacion desde conexion nueva: tabla y tres filas iniciales, catalogo exacto restaurado. Luego mismo cuerpo y COMMIT, vista y reunion equivalentes.
- PK 23505, FK 23503 y duplicacion LD por INSERT o UPDATE maestro 23505. UPDATE maestro valido se acepta pero termina ROLLBACK antes de concurrencia.
- Dos escritores independientes y un monitor: B espera Lock y pg_blocking_pids(B) incluye A antes del COMMIT de A. A confirma; B falla 23505. Se limpia lo confirmado con otra transaccion explicita, no con un SAVEPOINT antiguo.
- Cambios validos confirmados producen las cuatro filas actuales. Down con error P7501 despues de reconstruir/renombrar/desactivar debe volver por ROLLBACK a la vista, catalogo, lifecycle activo y cuatro filas normalizadas. Luego el down se confirma.
- Desde conexion nueva: tabla operativa de cuatro filas, checkpoint de tres, vista archivada y RD/LR presentes; rechazos 25006 y hashes intactos. TRUNCATE de RD sola puede fallar antes por FK entrante; el runner prueba ambas juntas y LR sola.
- Cinco huellas PRINCIPALES individuales: categoria, producto, usuario, pedido y detalle_pedido. Una sexta entrada resume todas las extensiones/restantes y el inventario de public. Se comparan antes/despues por base y no entre recetas distintas. La fuente original se consulta en solo lectura; las filas personales se agregan dentro de PostgreSQL y no salen.
- READ COMMITTED se prueba realmente. REPEATABLE READ/SERIALIZABLE pueden abortar 40001 por la guardia y requerir reintento completo; no se declaran ejecutados.
- Se verifica ausencia de secuencias nuevas; las huellas no prueban inmutabilidad del cluster, secuencias ajenas ni cambios transitorios de terceros.
- Todo error inesperado aborta y registra FAILED; una captura general nunca se usa como exito de una negativa. No hay assert eliminable con -O. La ausencia de un JSON exitoso no demuestra exito.

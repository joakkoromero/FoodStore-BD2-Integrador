# Revisión técnica de la generación real de OpenCode para U6

La consulta real `u6_generacion` terminó el 03/11/2026 a las
21:38:41.318865 UTC, mediante OpenCode 1.18.23, modelo solicitado
`openai/gpt-6.1-sol`, agente `plan` y herramientas denegadas. Recibió únicamente
las copias conservadas de `SPEC_U6.md` y `AGENTS.md`, con autorización explícita
del usuario. El prompt, la respuesta completa y los metadatos originales se
conservan sin reescribirlos; los eventos de transporte permanecen privados.

Esta revisión y las adaptaciones son asistencia automática de Codex. No se
atribuyen a una persona ni se presentan como aprobación humana. La consulta de
OpenCode no ejecutó los scripts ni SQL: su texto declara que son propuestas.

## Integración efectuada antes de ejecutar

Se extrajeron los bloques reales `backup_foodstore.ps1` y `restore_test.ps1` como
base de los archivos finales. Las funciones repetidas se factorizaron en
`tools/ps_common.ps1`, que debe acompañar a ambos scripts. La respuesta completa
permite distinguir el código recibido de estas correcciones posteriores.

| Observación verificable de la propuesta | Integración técnica de Codex |
|---|---|
| `createdb` usa `--connection-limit=0`; la ayuda del ejecutable PostgreSQL 17 del laboratorio no ofrece esa opción. La respuesta además supone aislamiento desde la creación. | Se conserva `createdb --template=template0` y, enseguida, se ejecutan `ALTER DATABASE ... CONNECTION LIMIT 0` y los REVOKE de conexión desde `postgres`. Se comprueba que no haya conexiones al destino antes de restaurar. Este cierre es consecutivo, no atómico; requiere la ventana privada de operadores en loopback. |
| Los bloques incluyen `throw "$Name: codigo $code"`. La propia respuesta avisa al final que esa sintaxis necesita corrección. | Se aplica la forma `${Name}`. El parser local encontró el error en ambos bloques extraídos y aceptó los tres archivos finales. No se presenta como una advertencia descubierta únicamente por Codex. |
| `ConvertFrom-Json -AsHashtable` seguido de `ParseExact(...,'o',...)` puede recibir un `DateTime` en PowerShell 7.6.5 en lugar de la cadena ISO original. Una prueba offline de revisión reprodujo el fallo de conversión cultural. | La lectura de manifiestos usa `-DateKind String`, preservando el texto ISO. Se declara PowerShell 7.5 o superior como dependencia; el entorno dispone de 7.6.5. |
| Los argumentos `-h` no neutralizan por sí solos todas las variables heredadas de libpq. | Se limpian `PGHOSTADDR`, `PGSERVICE`, `PGSERVICEFILE`, `PGOPTIONS` y `PGPASSWORD`; se conserva el `PGPASSFILE` externo, se comprueban ACL y se fija UTF-8. No se imprime ni se incorpora la clave a argv. |
| La primera integración de Codex intentó quitar esas variables con `SetEnvironmentVariable(...,$null,...)`; en el runtime usado dejó un servicio vacío. El preflight falló antes de llegar al servidor con `service file "" not found`. | Se corrige con `Remove-Item -LiteralPath Env:<clave>`, comprobando ausencia de las cinco claves y conservación de PGPASSFILE. La consulta local de preflight de solo lectura luego devolvió código nativo 0 y resultado 1. Este error corresponde a la integración de Codex, no a la respuesta de OpenCode; tampoco se presenta ese fallo temprano como una prueba fallida de pg_dump. |
| La propuesta deposita todos los archivos en la raíz de WorkDir. La consigna solicita una carpeta `logs`. | `WorkDir/backups` contiene `.partial` y `.dump`; `WorkDir/logs` contiene los registros, manifiestos y resultados. Se comprueba privacidad de ambas rutas y se usa creación/movimiento sin sobrescritura. |
| La propuesta solicita huellas de 64 caracteres y tres invalidaciones, según el detalle adicional pedido en el prompt inicial. | Se adapta al contrato SQL final acordado: cinco conteos, cinco huellas MD5 de 32 caracteres y exactamente dos invalidaciones (`productos`, `detalles`). SHA-256 sigue verificando el archivo de respaldo; no se confunden ambas funciones. El contador adicional de pedidos no se impone como una nueva regla de negocio. |
| El bloque original exige indicar seis roles, cuyos nombres no estaban enumerados en los adjuntos. | Se incorporan los seis nombres reales del proyecto como valores predeterminados y se exige coincidencia con ese conjunto. Se comprueban su existencia y ausencia de SUPERUSER, sin cambiar roles globales. |
| La propuesta cierra esquemas y rutinas mediante REVOKE, pero no verifica después todos los permisos efectivos. | Se añade una comprobación ejecutable del límite de conexiones y de la ausencia de CONNECT/TEMPORARY, USAGE/CREATE y EXECUTE efectivo para los seis roles de negocio en el destino. No se habilita la aplicación. |
| La propuesta imprime medidas y agregados en el log. | Se conserva el registro y se agrega un resultado JSON privado con medidas, comparación, estado aislado y `roleAclRecovery=false`. El RTO se detiene después de validar y comparar, antes de escribir esa evidencia auxiliar. |

## SQL final y diferencias de alcance

`health_check.sql`, `maintenance.sql` y `validaciones.sql` fueron implementados
por Codex a partir de la especificación y del esquema heredado, y contrastados
con la propuesta de OpenCode. No se atribuye a OpenCode una reproducción literal
de esos archivos finales. En particular, se conserva la zona y representación
estable de U5 para las huellas y el contrato JSON acordado con el orquestador.

La propuesta de mantenimiento usa un umbral de modificaciones y respeta opciones
por tabla. La política final del laboratorio decide un ANALYZE puntual sobre
pedido/detalle a partir de la observación de la copia, registra antes y después
y no convierte una estimación cero o un historial NULL en una afirmación de
tabla vacía o estadísticas ausentes. Ninguna versión justifica VACUUM FULL
periódico ni desactivar autovacuum.

## Alcance de las comprobaciones

La revisión estática local con `Parser.ParseFile` aceptó los dos scripts y su
helper sin errores. Esta operación no ejecuta backup, restore, SQL ni conexiones.
Los resultados reales de ejecución, cuando el operador los obtenga, corresponden
a evidencias separadas; una revisión sintáctica no prueba recuperación.

Durante el diagnóstico posterior se autorizó y ejecutó únicamente el SELECT
local de versión y condición de superusuario utilizado por el preflight, con
PGPASSFILE externo. Esa lectura confirmó la corrección de la limpieza del
entorno; el revisor no ejecutó por ello un backup ni una restauración. Una prueba
offline adicional usa valores de entorno sintéticos y verifica que las cinco
claves se eliminen realmente sin borrar PGPASSFILE.

El backup exige `-ConfirmNoWrites` como declaración de la ventana establecida por
el operador, y compara dos lecturas de la línea base. No bloquea escritores, no
comparte automáticamente un snapshot con pg_dump y no detecta cambios revertidos
entre las dos observaciones ni todos los cambios de DDL.

La restauración usa `--no-owner --no-privileges --exit-on-error`: conserva datos y
objetos del archivo, pero cambia propietarios de funciones DEFINER y no recupera
la política de roles/ACL de U5. Se mantiene como copia descartable aislada. Las
comparaciones cubren las cinco tablas solicitadas; no certifican equivalencia de
contenido de todas las demás relaciones o de cada definición de objeto.

RPO se interpreta como antigüedad conservadora desde el inicio registrado del
respaldo hasta el inicio del ensayo, no como pérdida observada ni PITR. RTO
incluye creación, aislamiento, restauración y comparación final; no se registra
éxito si falla una validación o se incumple el objetivo configurado.

Fuentes primarias: [pg_dump 17](https://www.postgresql.org/docs/17/app-pgdump.html),
[pg_restore 17](https://www.postgresql.org/docs/17/app-pgrestore.html) y
[CREATE DATABASE 17](https://www.postgresql.org/docs/17/sql-createdatabase.html).
La ayuda CLI real del laboratorio y la salida de pruebas efectivas tienen
prioridad para comprobar qué opciones y resultados estuvieron disponibles.

Cierre de ejecución real del 03/11/2026: el backup iniciado a las
21:56:43.4752209 UTC terminó con código 0 y produjo un archivo de 8.224.005 bytes,
SHA-256 `b7909e09d63c4a84fca707a7774020d725a074fdd6efa54bd8ec19836af9dfb3`,
según [backup_ejecucion.json](../evidencias/backup_ejecucion.json) y
[respaldo_manifest.json](../evidencias/respaldo_manifest.json). El ensayo comenzó
a las 21:57:15.2836191 UTC y registró validación a las 21:57:26.6756885 UTC, con
`SUCCESS`, RTO monotónico de 11,3500773 s y antigüedad de referencia RPO de
31,8083982 s; coincidieron los cinco conteos y sus huellas y ambas invalidaciones
fueron cero ([restauracion_resultado.json](../evidencias/restauracion_resultado.json)).
El fallo controlado de pg_dump produjo código 1 sin dump completado ni manifiesto
exitoso y restauró la ACL; el intento sobre el destino ya existente también fue
rechazado con código 1
([fallo_pg_dump_controlado.json](../evidencias/fallo_pg_dump_controlado.json),
[restore_existing_ejecucion.json](../evidencias/restore_existing_ejecucion.json)).
El control complementario de las 22:13:01.735781 UTC, expresamente fuera del RTO,
comprobó 12 tablas base, 22 relaciones, 10 funciones, 25 índices, 35 restricciones,
15 triggers y definiciones coincidentes; las materializadas conservaron 14 y 286
filas con iguales huellas de contenido, y tanto Food Store principal como U5
permanecieron intactos
([cierre_conservacion.json](../evidencias/cierre_conservacion.json)). Las huellas
de los dos scripts principales actuales coinciden con las registradas en sus
ejecuciones; no se modificaron sus fuentes después de esos éxitos ni se
repetieron conexiones para esta comprobación de archivos.

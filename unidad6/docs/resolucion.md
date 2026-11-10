# Resolución y evidencias - Unidad 6

Exequiel Arancibia y Joaquin Romero. Base de Datos II, ciclo 2026.
Todas las medidas de este informe proceden del laboratorio ejecutado el
03/11/2026; no son estimaciones de una salida que se esperaba obtener.

## 1. Continuidad del proyecto y alcance

Se retomó la base acumulada de los TP1-TP5 y las Unidades 4 y 5. En el
servidor privado se creó `foodstore` como copia de la base U5, conservando
datos, propietarios y objetos. Se mantuvo el origen U5 sin reemplazarlo.
La copia conserva el catálogo, baja lógica, precios históricos, subtotal
GENERATED, reglas de pedidos de TP2, índices y vistas de TP5, FNBC y
materializada diaria de U4, además de las funciones y datos_anon de U5.

La guía llama `cliente` a la entidad que nuestro modelo implementa como
`public.usuario`. Por eso se adapta esa referencia a usuario y se conservan
sus 20.000 registros heredados más la cuenta sintética U5. No se creó una
tabla ficticia cliente ni se reemplazó el proyecto por un ejemplo mínimo.

| Objeto principal | Filas exactas antes del respaldo |
|---|---:|
| public.categoria | 2 |
| public.usuario, equivalente a cliente | 20.001 |
| public.producto | 50.000 |
| public.pedido | 225.000 |
| public.detalle_pedido | 499.997 |

El entorno observado es PostgreSQL **17.11**, PowerShell **7.6.5**, Windows,
`127.0.0.1:55605`. Cumple PostgreSQL 16 o superior. Las versiones finales
de los scripts requieren PowerShell 7.5+ por el manejo explícito de fechas
JSON. Las operaciones se realizaron con el administrador técnico del
laboratorio; no se ampliaron permisos de los roles de aplicación.

## 2. Parte 1 - Especificación y frecuencia

La primera página contiene SPEC_U6 íntegra, con las cuatro tareas exigidas,
frecuencias y criterios ejecutables de éxito. Los horarios propuestos se
interpretan en UTC-03. Son una propuesta de programación: no se instaló una
tarea recurrente ni se presenta una ejecución manual como si fuera un cron.

Se propone respaldo diario 02:00, salud diaria 02:15, revisión semanal
domingo 03:00 y restauración semanal domingo 03:30. Un error requiere
investigación y no se considera una copia válida para cumplir el RPO diario.
Los objetivos previstos antes de las pruebas son RPO <=24 h y RTO <=120 s
para este equipo de laboratorio.

## 3. Parte 2 - Respaldo automatizable probado

El script backup_foodstore.ps1 se ejecutó manualmente, con su dependencia
tools/ps_common.ps1. Sigue este procedimiento:

1. Comprueba loopback, versión 17, operador autorizado, rutas privadas,
   PGPASSFILE protegido y confirmación de una ventana sin escrituras.
2. Ejecuta validaciones.sql y guarda una línea base coherente de conteos,
   huellas y controles lógicos. No imprime registros personales.
3. Inicia pg_dump -Fc hacia un nombre UTC único terminado en .partial.
   Comprueba inmediatamente el código nativo de salida.
4. Verifica tamaño no vacío y lectura del TOC con pg_restore --list; repite
   la línea base y exige igualdad para detectar cambios observables.
5. Calcula SHA-256 y publica el archivo .dump sin sobrescritura. Sólo después
   publica el manifiesto SUCCESS, también sin sobrescribir otro archivo.
6. Guarda el registro en la carpeta logs. Si una fase falla, devuelve código
   distinto de cero; un parcial o un dump sin manifiesto no se elige como válido.

Las claves no aparecen en el código, argumentos, PDF ni adjuntos. Se usa
PGPASSFILE externo con ACL restringida al operador, SYSTEM y Administradores.
Se eliminan variables libpq que podrían redirigir una conexión, y se utiliza
-w para evitar una solicitud interactiva de contraseña. Estas medidas no
sustituyen un diseño de cuentas de producción con responsabilidades separadas.

### Evidencia del respaldo real

| Campo observado | Resultado |
|---|---|
| Archivo | foodstore_20261103T2156409509091Z_fd85fddaeb454d6e8aaa06735a9d316d.dump |
| Formato | Custom, generado con -Fc; TOC leído correctamente. |
| Inicio de pg_dump | 03/11/2026 21:56:43,475 UTC = 18:56:43,475 UTC-03. |
| Finalización y publicación | 21:56:47,637 UTC = 18:56:47,637 UTC-03. |
| Tamaño | 8.224.005 bytes, aproximadamente 7,843 MiB. |
| Estado y salida del script | SUCCESS, código 0. |
| SHA-256 | `b7909e09d63c4a84fca707a7774020d725a074fdd6efa54bd8ec19836af9dfb3` |

El nombre se fecha al iniciar el trabajo; el manifiesto distingue ese momento
del inicio posterior de pg_dump. Para discutir el RPO se usa este último,
no la fecha del nombre ni la última modificación del archivo.

Fragmento real del log de éxito:

```text
SUCCESS backup archivo=foodstore_20261103T2156409509091Z_fd85fddaeb454d6e8aaa06735a9d316d.dump
bytes=8224005 sha256=b7909e09d63c4a84fca707a7774020d725a074fdd6efa54bd8ec19836af9dfb3
```

La línea se distribuye visualmente para legibilidad; el log íntegro y el
manifiesto se incluyen como adjuntos de evidencia. El .dump permanece privado:
la plataforma solicita un único PDF y el archivo contiene datos y material
de autenticación almacenado. Se aporta evidencia de su creación, tamaño,
integridad y restauración efectiva, sin inventar un límite de tamaño del aula.

### Control de error real

Se denegó temporalmente la creación de archivos únicamente en el directorio
vacío de backups de esta copia. pg_dump falló realmente y el script devolvió
código **1**, sin .dump completado ni manifiesto SUCCESS. La ACL original se
restauró en finally y después se ejecutó el respaldo exitoso anterior.
Fue una prueba deliberada del manejo de errores, no un incidente de producción.

## 4. Parte 3 - Salud y mantenimiento

health_check.sql se ejecutó con psql -X y ON_ERROR_STOP. Sus cuatro controles
son consultas de sólo lectura; el resultado se conservó completo.

| Control | Observación real e interpretación |
|---|---|
| Tamaño de foodstore | 171.054.771 bytes en la observación anterior al mantenimiento. |
| Conexiones/transacciones | Se consultaron numbackends, commits, rollbacks, deadlocks y reinicio de contadores de la base. Son acumulados, no tasas ni ventas. |
| Estado de tablas | Se obtuvieron estimaciones de 14 relaciones estadísticas, incluyendo las materializadas, y sus históricos de vacuum/ANALYZE. |
| Consultas activas | No había otras consultas activas al tomar la muestra; cero es una salida válida. Se excluye el chequeo propio y no se publica SQL crudo, direcciones ni identidades personales. |

La copia recién creada tenía n_live_tup=0 y ambos históricos de ANALYZE en
NULL para pedido/detalle, pese a los conteos reales de 225.000 y 499.997.
Esto no significa que estuvieran vacías ni prueba ausencia de pg_statistic.
Autovacuum y track_counts estaban **on**; no se desactivaron.

maintenance.sql observó configuración, opciones por tabla, estimaciones y
conteos reales antes de decidir. Aplicó un **ANALYZE puntual** a esas dos
tablas, sólo cuando no había histórico de análisis manual ni automático,
para establecer una línea base documentada de la copia.

| Tabla | n_live_tup antes | Después | n_dead_tup después | last_analyze observado, UTC-03 |
|---|---:|---:|---:|---|
| pedido | 0 | 225.000 | 4 | 03/11/2026 18:40:10,232 |
| detalle_pedido | 0 | 499.997 | 2 | 03/11/2026 18:40:10,302 |

Son estimaciones estadísticas, comparadas separadamente con COUNT(*).
El análisis registra un contador manual por tabla; no modifica sus filas.
No se ejecutó VACUUM FULL ni se justificó una reescritura por estas pocas
tuplas muertas estimadas. ANALYZE actualiza estadísticas del planificador;
VACUUM ordinario tiene otros fines y no equivale a VACUUM FULL.
[Mantenimiento rutinario de PostgreSQL 17](https://www.postgresql.org/docs/17/routine-vacuuming.html).

## 5. Parte 4 - Recuperación contra reloj

restore_test.ps1 valida primero los clientes, endpoint, permisos del operador,
ausencia del destino y manifiesto exitoso más reciente. Rechaza archivos fuera
de las rutas admitidas, verifica tamaño/SHA-256 y comprueba la línea base.
Ese preflight no forma parte del intervalo definido por la consigna.

Inmediatamente antes de createdb inicia Stopwatch. A continuación:

1. Crea exclusivamente foodstore_restore_test desde template0.
2. Limita conexiones a cero para no administradores y revoca CONNECT/TEMP
   de PUBLIC y los seis roles de negocio. Comprueba que no haya otra sesión.
3. Restaura el archivo con --no-owner --no-privileges --exit-on-error,
   sin --create, --clean ni DROP.
4. Cierra acceso a esquemas y rutinas restauradas y verifica permisos efectivos.
5. Ejecuta validaciones.sql en un snapshot de sólo lectura; compara
   explícitamente todos los conteos, huellas y controles lógicos.
6. Detiene el cronómetro sólo tras esas comprobaciones exitosas y registra
   el resultado. Un error o comparación falsa nunca produce SUCCESS.

createdb y el cierre de permisos son comandos consecutivos, no atómicos:
se usó un servidor privado en loopback con ventana exclusiva de operadores.
La copia descartable no se habilitó a la aplicación. Restaurar sin owners/ACL
cambia propietarios de funciones DEFINER y no reconstruye la seguridad U5;
esa diferencia es intencional y queda acotada por el aislamiento.
[Opciones de pg_restore 17](https://www.postgresql.org/docs/17/app-pgrestore.html).

### Resultados mínimos: línea base y restauración

| Tabla real | Antes del respaldo | Restaurada | Coincidencia |
|---|---:|---:|---|
| categoria | 2 | 2 | Sí |
| usuario, equivalente a cliente | 20.001 | 20.001 | Sí |
| producto | 50.000 | 50.000 | Sí |
| pedido | 225.000 | 225.000 | Sí |
| detalle_pedido | 499.997 | 499.997 | Sí |

| Restricción lógica | Resultado esperado | Resultado restaurado |
|---|---:|---:|
| producto.precio <0 o stock <0 | 0 | 0 |
| detalle.cantidad <=0 o precio_unitario <0 | 0 | 0 |
| Huellas completas distintas en las cinco tablas | 0 | 0 |

Los campos examinados son NOT NULL en el modelo heredado. Las huellas son
checksums MD5 de filas completas ordenadas y no hashes de contraseñas,
pruebas de anonimato ni firmas criptográficas de autenticidad. El archivo
de respaldo se verifica con SHA-256, con una finalidad diferente.

### RTO y RPO observados

| Medida | Valor real | Evaluación |
|---|---|---|
| Inicio del ensayo | 03/11/2026 21:57:15,284 UTC / 18:57:15,284 UTC-03 | Antes de createdb. |
| RTO monotónico | **11,3500773 segundos** | Menor a 120 s. Incluye creación, aislamiento, restore y comparaciones. |
| Antigüedad de referencia al iniciar | **31,8083982 segundos** | Menor a 24 h. |
| Hora del registro final | 21:57:26,676 UTC | Posterior al stop y a escribir el log; no se usa su diferencia como sustituto del cronómetro. |

RTO es duración de recuperación. RPO expresa cuánto retrocede la información
recuperable: aquí se discute mediante la antigüedad del respaldo pedida por
la guía. La referencia temporal es el inicio registrado de pg_dump, anterior
a su snapshot interno; es una cota conservadora, no una marca exacta de
snapshot exportado. Las dos lecturas de línea base no comparten automáticamente
ese snapshot y se trabajó sin escritores; sus datos coincidieron.

No hubo borrado real de la principal ni se midieron transacciones perdidas.
Un dump diario no proporciona por sí solo recuperación a un instante mediante
WAL/PITR. Estos resultados son de este equipo y ensayo; los objetivos
propuestos no se presentan como garantía de un servicio productivo.
[pg_dump 17 y copias consistentes](https://www.postgresql.org/docs/17/app-pgdump.html).

### Controles complementarios posteriores

Fuera del intervalo RTO se compararon **las 12 tablas base** y sus huellas,
22 relaciones inventariadas, 10 funciones públicas, 25 índices, el inventario de 35 restricciones,
15 triggers y definiciones de vistas: coincidieron. Ambas materializadas
también coincidieron: mensual con 14 filas y diaria con 286, verificadas por
contenido completo. La principal foodstore y el origen U5 conservaron sus
datos y propietarios. Estos controles adicionales no sustituyen ni alteran
la medición mínima del cronómetro.

La línea base ordena las huellas por PK y el postflight por representación
JSON: sólo se comparan fuente y destino dentro del mismo método, no los
valores entre ambos archivos. El inventario de restricciones verifica nombre,
tipo y estado validado; no se presenta como una revisión semántica exhaustiva
de cada definición de restricción.

Finalmente, se volvió a invocar el script con foodstore_restore_test existente:
devolvió código **1** en preflight, sin crear, eliminar ni sobrescribir la base.

## 6. Parte 5 - Informe y verificación de la asistencia

La segunda página es el informe post-incidente de una página como máximo.
La especificación también ocupa una sola página. El resto de este documento
son evidencias y anexos, separados de esos dos límites.

OpenCode **1.18.23**, modelo openai/gpt-6.1-sol, recibió únicamente SPEC_U6 y
AGENTS, con autorización explícita. Generó una propuesta sin herramientas
ni ejecución. Codex revisó e integró los scripts, contrastó las consultas y
ejecutó las pruebas. No se atribuye esa revisión automática a una persona.

| Hallazgo real | Corrección y comprobación |
|---|---|
| La propuesta incluía --connection-limit=0 en createdb. | La ayuda real de PostgreSQL 17 demuestra que no admite esa opción. Se quitó y se aplicó ALTER DATABASE inmediatamente después; el ensayo completo pasó. |
| El manejo JSON convertía fechas ISO a DateTime antes de ParseExact. | Se preservan cadenas con -DateKind String y se declara PowerShell 7.5+. El manifiesto real fue leído y la recuperación pasó. |
| Una integración de Codex dejó variables libpq vacías con SetEnvironmentVariable. | Se detectó service file vacío en el preflight, se sustituyó por Remove-Item Env: y se probó su eliminación efectiva. No se culpa a OpenCode por este fallo. |
| La salida propuesta no separaba una carpeta logs y difería del contrato de huellas. | Se implementaron backups/logs, cinco MD5 de 32 caracteres y dos controles lógicos; SHA-256 verifica el dump. |

El error de sintaxis ${Name} también se corrigió: la propia respuesta ya lo
advertía, por lo que no se presenta como un descubrimiento independiente.
Prompt, respuesta íntegra, metadatos y revisión quedan adjuntos al PDF.
La persona solicitante revisó las conclusiones y confirmó expresamente la
entrega. El alcance consta en revision_humana.md, también adjunto; no se
confunde esa conformidad con las pruebas automáticas ni con la autorización
previa de envío a OpenCode.

## 7. Uso de los archivos incluidos

Los anexos muestran íntegramente las fuentes requeridas. También se adjuntan
sus bytes exactos dentro del PDF, junto con evidencias revisadas: un lector
con panel de archivos adjuntos permite guardarlas sin reconstruir líneas
envueltas visualmente. No hay JavaScript ni ejecución automática del PDF.

`tools/ps_common.ps1` debe permanecer en su carpeta tools junto a los scripts.

Para repetir sobre un laboratorio propio equivalente, configurar PGPASSFILE
fuera de Git y proteger sus permisos. No copiar una contraseña a un comando.
Reemplazar PgBin y WorkDir por rutas locales; preparar un directorio de trabajo
privado existente y confirmar que no hay escritores. Los comandos ejecutados
siguen este patrón, con el usuario técnico correspondiente:

```powershell
$env:PGPASSFILE = 'C:\ruta_privada\pgpass.conf'
$pgBinU6 = 'C:\Program Files\PostgreSQL\17\bin'
$trabajoU6 = 'C:\ruta_privada\u6_runtime'
pwsh -NoProfile -File .\backup_foodstore.ps1 -DbUser u5_bootstrap `
  -PgBin $pgBinU6 -WorkDir $trabajoU6 -ConfirmNoWrites
pwsh -NoProfile -File .\restore_test.ps1 -DbUser u5_bootstrap `
  -PgBin $pgBinU6 -WorkDir $trabajoU6
```

Los valores predeterminados de este laboratorio son host 127.0.0.1 y puerto
55605; se pueden indicar explícitamente. Un destino existente se conserva:
el script no lo elimina para repetir. La copia, claves y logs privados quedan
fuera de los fuentes entregados. Los horarios recurrentes permanecen como plan.

## Referencias primarias

- PostgreSQL 17: [Respaldo y restauración](https://www.postgresql.org/docs/17/backup.html).
- PostgreSQL 17: [pg_dump](https://www.postgresql.org/docs/17/app-pgdump.html) y [pg_restore](https://www.postgresql.org/docs/17/app-pgrestore.html).
- PostgreSQL 17: [Monitoreo de actividad](https://www.postgresql.org/docs/17/monitoring.html).
- PostgreSQL 17: [Mantenimiento rutinario](https://www.postgresql.org/docs/17/maintenance.html) y [vacuum/ANALYZE](https://www.postgresql.org/docs/17/routine-vacuuming.html).
- OpenCode: [Instrucciones AGENTS.md](https://opencode.ai/v2/docs/instructions).

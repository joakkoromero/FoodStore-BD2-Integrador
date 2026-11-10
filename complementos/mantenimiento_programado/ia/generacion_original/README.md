# Respaldo Diario FoodStore TPI

## Estado Y Alcance

Estos cuatro archivos son propuestas de código para revisión previa. No se ejecutaron comandos, no se consultó PostgreSQL y no se registraron tareas para producir esta entrega. No existen resultados de ensayo acreditados por estos archivos.

El complemento busca completar el objetivo 7 mediante una configuración diaria entregable y un ensayo posterior, real y coordinado, del Programador de tareas de Windows.

U6 anterior solamente proponía horarios. Este complemento no modifica esa historia, sus evidencias ni sus fuentes. Reutiliza backup_foodstore.ps1, validaciones.sql y tools/ps_common.ps1 sin reescribirlos.

La revisión automatizada de Codex u otra herramienta no constituye firma ni revisión humana del equipo.

## Requisitos

- Windows con Programador de tareas disponible.
- PowerShell Core 7.5 o posterior. El entorno informado dispone de 7.6.5.
- Clientes PostgreSQL 17: psql.exe, pg_dump.exe y pg_restore.exe. El entorno informado dispone de PostgreSQL 17.11.
- Dependencias U6 existentes y revisadas por el operador.
- Usuario actual con sesión iniciada y permisos ordinarios suficientes.
- PostgreSQL ya disponible por coordinación externa. Ningún archivo inicia el servidor.
- Acceso autorizado a foodstore por 127.0.0.1, con DbUser exactamente u5_bootstrap y un puerto entre 1 y 65535.
- Directorios existentes: no se crean automáticamente directorios ni se corrigen ACL.
- Directorio de backups, resultados, configuración y archivo de contraseñas fuera del paquete y fuera de Git.
- Scripts y clientes instalados en ubicaciones de confianza, no modificables por terceros no autorizados.

Las rutas admitidas son rutas locales absolutas con unidad, por ejemplo C:\Lab Privado\resultados. Se admiten espacios. Se rechazan rutas UNC, rutas de dispositivo, comillas dobles, caracteres de control y flujos alternativos NTFS.

No se usan descargas, perfiles de PowerShell, ExecutionPolicy Bypass, servicios nuevos, permisos SQL nuevos ni elevación automática.

## Contrato Privado

ConfigPath debe ser un archivo JSON externo a Git, con exactamente estas ocho claves, respetando mayúsculas y minúsculas:

- U6Root: ruta absoluta al directorio de las dependencias originales.
- PgBin: ruta absoluta al directorio de clientes PostgreSQL 17.
- DbUser: cadena literal u5_bootstrap.
- HostName: cadena literal 127.0.0.1.
- Port: número entero JSON entre 1 y 65535.
- PassFile: ruta absoluta a un archivo de contraseñas existente.
- BackupWorkDir: directorio privado existente para los archivos producidos por U6.
- WindowExpiresUtc: instante UTC ISO8601, terminado en Z o +00:00.

El JSON se interpreta mediante ConvertFrom-Json -DateKind String. No se imprime su contenido. PassFile contiene solamente una ruta: nunca se incorpora la contraseña al JSON ni a los argumentos de procesos.

El operador debe generar WindowExpiresUtc únicamente después de coordinar una ventana sin escritores. Su valor debe ser posterior al momento de validación y no superar los siguientes 60 minutos.

Un ejemplo de expresión para calcular el vencimiento, que no escribe ni confirma por sí misma la ventana, es: `[DateTimeOffset]::UtcNow.AddMinutes(15).ToString('o')`.

No reutilizar una confirmación vieja. Una programación diaria no renueva esta autorización.

## ACL Y Rutas

Antes de leer la configuración, utilizar PassFile, ejecutar el backup o escribir resultados, el runner valida los destinos correspondientes.

ConfigPath, PassFile, BackupWorkDir y el directorio de resultados deben tener DACL protegida, sin herencia habilitada. Los únicos SID admitidos en reglas de permiso son:

- El SID del usuario Windows actual.
- SYSTEM: S-1-5-18.
- Administradores: S-1-5-32-544.
- OWNER RIGHTS: S-1-3-4, solamente si el propietario resuelve al usuario actual.

El propietario debe ser el usuario actual, SYSTEM o Administradores. Las entradas que concedan acceso a otras identidades se rechazan, aunque otra regla pudiera denegarlo. Las reglas de denegación no conceden permisos.

Los archivos de manifiesto y dump pueden heredar permisos desde la carpeta privada, pero tampoco pueden conceder acceso a otras identidades.

Se recorren los ancestros para rechazar reparse points, directorios llamados .git y directorios que contengan un marcador .git, incluido el archivo usado por Git worktrees.

El código no modifica ACL ajenas. El operador debe preparar y revisar las ubicaciones privadas antes del ensayo.

Estos controles no aíslan de un administrador del equipo ni eliminan todas las carreras de sustitución de rutas. No admitir modificaciones concurrentes de configuración, permisos, scripts, dependencias ni directorios durante el trabajo.

## Interfaz De U6 A Revisar

No se suministraron fuentes internas. Por eso no se afirma que se haya comprobado la interfaz real de U6.

Antes del único ensayo, el operador debe revisar que backup_foodstore.ps1 acepte:

`-HostName -Port -DbUser -PgBin -WorkDir -ConfirmNoWrites`

También debe revisar que U6 realice solamente el backup y las lecturas o metadatos locales autorizados: ninguna restauración, DROP, modificación de foodstore, cambio de roles o cambio de ACL.

El runner ejecuta U6 en un proceso hijo mediante:

`pwsh -NoLogo -NoProfile -NonInteractive -File backup_foodstore.ps1`

Nunca se ejecuta U6 con dot-sourcing ni dentro del proceso del runner, porque puede utilizar exit.

### Manifiesto Esperado

La especificación exige comprobar un manifiesto, pero no define su formato interno. Esta propuesta adopta el siguiente contrato explícito y falla de forma cerrada si U6 no lo cumple. No representa un formato observado ni una afirmación sobre las fuentes ausentes.

U6 debe crear un archivo JSON nuevo debajo de BackupWorkDir que contenga:

- status: cadena literal SUCCESS.
- startedUtc: instante UTC ISO8601 con Z o +00:00.
- sourceDatabase: cadena literal foodstore.
- backupFile: ruta absoluta al dump dentro de BackupWorkDir, o ruta relativa a BackupWorkDir.
- backupBytes: entero JSON positivo.
- backupSha256: cadena hexadecimal SHA256 de 64 caracteres.
- baseline: objeto con exactamente counts, invalid y fingerprints.
- baseline.counts: objeto de etiquetas técnicas y enteros no negativos.
- baseline.invalid: objeto de etiquetas técnicas y enteros no negativos.
- baseline.fingerprints: objeto de etiquetas técnicas y cadenas SHA256 hexadecimales de 64 caracteres.

Las etiquetas técnicas admiten letras ASCII, números, punto y guion bajo; deben comenzar por letra o guion bajo y tener como máximo 128 caracteres. No deben contener identidades del negocio, muestras de registros ni valores personales.

Puede haber otros campos en la raíz del manifiesto, pero el runner no los incorpora al resumen.

Antes del ensayo se debe cotejar este contrato con el manifiesto real de U6. Si difiere, revisar únicamente la lectura y validación del manifiesto en el runner con información verificada. No modificar U6, inventar un manifiesto compatible ni omitir sus comprobaciones.

La ausencia de las fuentes impide garantizar aquí la compatibilidad de ese formato. Esta comprobación es un requisito pendiente de revisión, no una ejecución pendiente que deba iniciarse automáticamente.

## Ejecución Del Runner

Validación local sin conexión SQL, backup ni resultado:

`& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'C:\Complemento\run_backup_job.ps1' -ConfigPath 'C:\Lab Privado\config.json' -ResultDirectory 'C:\Lab Privado\resultados' -ValidateOnly`

Esta validación sí ejecuta los clientes PostgreSQL con --version, pero no los conecta a una base.

Ejemplo de ejecución manual, solamente después de coordinación explícita y no como evidencia de disparo horario:

`& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'C:\Complemento\run_backup_job.ps1' -ConfigPath 'C:\Lab Privado\config.json' -ResultPath 'C:\Lab Privado\resultados\resultado-unico.json'`

ResultPath debe ser nuevo. Una colisión no se sobrescribe.

Para la tarea diaria se utiliza ResultDirectory. Cada invocación genera un nombre nuevo con instante UTC y GUID. Esto evita que el segundo día intente sobrescribir el resultado del primero.

El runner valida WindowExpiresUtc y ejecuta una consulta a pg_stat_activity mediante psql -X -w. Rechaza cualquier otra sesión cliente conectada a foodstore.

Esta consulta es una precondición observada: no bloquea conexiones nuevas y no demuestra que el negocio haya sido bloqueado. El operador mantiene la ventana sin escritores hasta finalizar el trabajo.

Antes de iniciar U6 se vuelve a comprobar el vencimiento y la privacidad de los destinos.

Los procesos nativos reciben PGPASSFILE y PGCONNECT_TIMEOUT=10. Se eliminan las variables heredadas cuyo nombre comienza por PG y se establece explícitamente el endpoint autorizado. Esto elimina, entre otras, PGHOSTADDR, PGSERVICE, PGSERVICEFILE, PGOPTIONS y PGPASSWORD heredadas.

No se lee ni imprime la contraseña. La salida y los diagnósticos nativos se capturan en memoria y no se publican ni se guardan en el paquete.

Después de la salida cero de U6 se exige exactamente un manifiesto SUCCESS nuevo, no presente antes de invocar U6, con inicio igual o posterior al comienzo del job y no posterior a la validación.

Se comprueban ubicación privada, existencia, tamaño y SHA256 del dump. El resumen incluye exclusivamente estado, tiempos UTC, base origen, nombre base del archivo, tamaño, SHA256, baseline validada y código nativo.

Un hash no anonimiza el dump, el nombre de archivo ni el contenido de los metadatos. Dumps, manifiestos y resúmenes permanecen privados.

Un fallo devuelve 1. No se fabrica SUCCESS. Cuando el destino ya fue validado y es posible escribirlo, se crea un resumen FAILED con un código de fase genérico. Si no es seguro escribir, no se crea resultado.

Los resultados se escriben mediante FileMode.CreateNew. Un fallo o escritura parcial del resultado también devuelve 1. No se reintenta ni sobrescribe ese archivo.

## XML Y Registro

Los cuatro archivos deben conservarse juntos. La plantilla contiene marcadores deliberadamente no importables y ninguna identidad personal.

crear_tarea_diaria.ps1 carga la plantilla sin permitir DTD, inserta valores mediante el DOM XML y construye argumentos de rutas entrecomillados. No usa Invoke-Expression ni concatena órdenes ejecutables arbitrarias.

El XML operativo contiene SID y rutas locales: es privado. XmlPath debe ser un archivo nuevo dentro de una carpeta privada existente.

Ejemplo de exportación sin registrar tarea:

`& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'C:\Complemento\crear_tarea_diaria.ps1' -ConfigPath 'C:\Lab Privado\config.json' -ResultDirectory 'C:\Lab Privado\resultados' -XmlPath 'C:\Lab Privado\evidencia\propuesta.xml' -ExportOnly`

La validación exige una confirmación vigente incluso para ExportOnly. Esta operación no conecta a PostgreSQL, no ejecuta U6 y no registra tareas.

Si se omite FirstRun, se elige el próximo horario futuro elegible de las 02:00 con desplazamiento UTC-03. La frecuencia es diaria, DaysInterval=1.

Una confirmación creada hoy puede expirar antes de ese horario. El registro no la prolonga: el operador debe renovar la configuración dentro de una ventana realmente coordinada antes de cada ejecución. De lo contrario, el runner falla de forma segura.

La tarea utiliza exclusivamente:

- SID del usuario Windows actual.
- InteractiveToken: necesita sesión iniciada.
- LeastPrivilege: sin solicitar privilegios elevados.
- Una acción pwsh con -NoLogo -NoProfile -NonInteractive.
- IgnoreNew para instancias superpuestas de esta misma tarea.
- Límite de ejecución de diez minutos.
- Sin reintentos automáticos.
- Sin despertar el equipo.
- Ejecución permitida con batería.
- Sin recuperación automática de horarios perdidos.
- Sin inicio manual habilitado en la configuración.
- Sin contraseña ni credenciales almacenadas.

El registro usa la API oficial del Programador con TASK_CREATE, nunca TASK_UPDATE ni TASK_CREATE_OR_UPDATE. No reemplaza una tarea preexistente.

El único formato de nombre aceptado es FoodStore-TPI-Lab-[GUIDhex32]. Si se omite TaskName, se genera un GUID nuevo.

IgnoreNew solamente controla instancias de esa tarea. No es un bloqueo global contra otros trabajos, usuarios o clientes SQL.

## Ensayo Coordinado

El ensayo requiere autorización explícita del operador. No ejecutar estos pasos solamente porque los archivos hayan sido generados.

1. El responsable del laboratorio coordina una ventana sin escritores y confirma que PostgreSQL ya está disponible.
2. El operador revisa las fuentes U6 originales, los cuatro archivos, el contrato del manifiesto y las ACL.
3. El operador crea o renueva el JSON privado con vencimiento futuro de hasta 60 minutos.
4. Se conserva abierta la sesión del usuario que registrará la tarea.
5. Se genera un nombre exclusivo: `$nombre = 'FoodStore-TPI-Lab-' + [guid]::NewGuid().ToString('N')`.
6. Se calcula el primer disparo: `$inicio = [DateTimeOffset]::UtcNow.AddSeconds(90).ToString('o')`.
7. Se registra únicamente la tarea temporal mediante el comando siguiente.
8. Se espera el disparo horario real. No utilizar Start-ScheduledTask ni una ejecución manual del runner para simularlo.
9. Se verifica que la tarea haya terminado, que LastRunTime corresponda al ensayo y que exista el resumen privado esperado.
10. Se exporta evidencia y se deshabilita o retira exclusivamente la tarea temporal identificada por $nombre.
11. Se revisa y sanea el material antes de incorporarlo al entregable.

Comando de registro para el paso 7:

`& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoLogo -NoProfile -NonInteractive -File 'C:\Complemento\crear_tarea_diaria.ps1' -ConfigPath 'C:\Lab Privado\config.json' -ResultDirectory 'C:\Lab Privado\resultados' -XmlPath 'C:\Lab Privado\evidencia\registro-original.xml' -TaskName $nombre -FirstRun $inicio`

Calcular $inicio inmediatamente antes de ejecutar el comando. Si las validaciones consumen el margen disponible, el registro falla o debe posponerse con una nueva revisión; no forzar un disparo manual.

Una tarea detenida por el límite del Programador puede no alcanzar a escribir su resumen. La ausencia de resumen es un fallo o resultado no acreditado, nunca un éxito implícito.

## Evidencia Privada

Utilizar nombres de archivo nuevos y una carpeta previamente validada como privada. No guardar estas evidencias directamente en Git.

Obtener exclusivamente la tarea del ensayo:

`$tarea = Get-ScheduledTask -TaskPath '\' -TaskName $nombre -ErrorAction Stop`

Obtener su información:

`$info = Get-ScheduledTaskInfo -TaskPath '\' -TaskName $nombre -ErrorAction Stop`

Comprobar que no siga en ejecución antes de finalizar el ensayo:

`$tarea.State`

Registrar privadamente acción, principal, trigger y datos del Programador:

`$evidencia = [ordered]@{ TaskName = $nombre; Action = @($tarea.Actions | Select-Object Execute, Arguments, WorkingDirectory); Principal = ($tarea.Principal | Select-Object UserId, LogonType, RunLevel); Trigger = @($tarea.Triggers | Select-Object StartBoundary, Enabled, DaysInterval); LastRunTime = $info.LastRunTime; LastTaskResult = $info.LastTaskResult; CapturedUtc = [DateTimeOffset]::UtcNow.ToString('o') }`

Convertir sin imprimir:

`$evidenciaJson = ConvertTo-Json -InputObject $evidencia -Depth 12`

Guardar mediante creación exclusiva:

`$archivoEvidencia = [IO.FileStream]::new('C:\Lab Privado\evidencia\scheduler-original.json', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)`

Escribir y cerrar incluso ante un error:

`try { $bytesEvidencia = [Text.UTF8Encoding]::new($false).GetBytes($evidenciaJson); $archivoEvidencia.Write($bytesEvidencia, 0, $bytesEvidencia.Length); $archivoEvidencia.Flush($true) } finally { $archivoEvidencia.Dispose() }`

Exportar el XML realmente registrado, no solamente el XML propuesto:

`$xmlOriginal = Export-ScheduledTask -TaskPath '\' -TaskName $nombre -ErrorAction Stop`

Crear su archivo privado sin sobrescritura:

`$archivoXml = [IO.FileStream]::new('C:\Lab Privado\evidencia\scheduler-original.xml', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)`

Escribir y cerrar:

`try { $bytesXml = [Text.UTF8Encoding]::new($false).GetBytes($xmlOriginal); $archivoXml.Write($bytesXml, 0, $bytesXml.Length); $archivoXml.Flush($true) } finally { $archivoXml.Dispose() }`

Calcular el hash del original privado:

`$hashOriginal = (Get-FileHash -LiteralPath 'C:\Lab Privado\evidencia\scheduler-original.xml' -Algorithm SHA256).Hash.ToLowerInvariant()`

Conservar el valor de $hashOriginal como referencia del original, sin publicar su ruta privada.

Examinar el resumen JSON correspondiente al ensayo dentro del entorno privado. Correlacionar startedUtc y finishedUtc con el disparo observado. No atribuir al ensayo un resumen previo o ajeno.

LastTaskResult=0 por sí solo no reemplaza la comprobación del resumen SUCCESS y del manifiesto. A su vez, un resumen no demuestra por sí solo que el inicio haya sido horario: se requieren los datos del Programador.

No se proporcionan aquí valores de LastRunTime, LastTaskResult, hash, tamaño, duración ni baseline porque todavía no se ejecutó el ensayo.

## Saneamiento

El XML operativo y el exportado contienen datos locales. No incluirlos sin sanear en la entrega.

Sobre una copia en memoria del XML realmente exportado, utilizar un DOM XML y reemplazar:

- UserId por @@CURRENT_USER_SID@@.
- Command por @@PWSH_EXE@@.
- Arguments por la acción con los marcadores de la plantilla.
- WorkingDirectory por @@SCRIPT_DIRECTORY@@.
- Cualquier Author, URI, SecurityDescriptor u otro campo con identidades o rutas locales por un marcador, o eliminarlo si es metadato no necesario para la evidencia.

Mantener los valores observados de LogonType, RunLevel, StartBoundary, DaysInterval y Settings. No convertir valores observados incorrectos en valores esperados.

Ejemplo de inicio de la copia DOM, sin imprimir el XML: `[xml]$xmlSaneado = $xmlOriginal`.

La plantilla entregada sirve de referencia para los marcadores, no sustituye al XML observado. El XML saneado es evidencia para revisión y puede dejar de ser importable.

Guardar el XML saneado en un archivo nuevo. Acompañarlo con el SHA256 del original privado y una nota que explique qué campos fueron sustituidos.

Sanear también el JSON de evidencia: sustituir SID y rutas de Action y Principal; conservar LogonType, RunLevel, trigger, LastRunTime y LastTaskResult observados. No publicar identidades del negocio ni diagnósticos nativos.

Revisar manualmente todos los archivos antes de incorporarlos al paquete. No asumir que un hash, una extensión JSON o los marcadores garantizan anonimato.

## Retiro Del Ensayo

Una vez exportada la evidencia y comprobado que no hay una ejecución en curso, deshabilitar exclusivamente la tarea temporal:

`Disable-ScheduledTask -TaskPath '\' -TaskName $nombre -ErrorAction Stop | Out-Null`

Si corresponde retirarla, utilizar exclusivamente su nombre exacto:

`Unregister-ScheduledTask -TaskPath '\' -TaskName $nombre -Confirm -ErrorAction Stop`

No usar comodines, no retirar otras tareas y no borrar backups ni evidencias privadas como parte de estos comandos.

Verificar después el estado deshabilitado o la ausencia de esa tarea, según la acción elegida. Registrar esa comprobación sin inventar un resultado.

Si hay un error durante la creación o la exportación, comprobar el estado de la tarea exacta antes de repetir. El XML privado puede existir aunque el registro haya fallado.

## Responsables Y Límites

- Responsable del laboratorio: autoriza horario, disponibilidad del equipo y ausencia de escritores.
- Operador: prepara ACL y configuración privada, revisa dependencias, registra la tarea, observa el disparo y la deshabilita o retira.
- Revisor del equipo: contrasta código, manifiesto real, evidencia y saneamiento.
- Responsable de operación futura: define retención, monitorización, renovación diaria de la ventana y respuesta ante fallos antes de considerar un servicio permanente.

Una tarea diaria registrada, ensayada y retirada no equivale a un servicio productivo permanente activo.

Este diseño no mantiene sesiones bloqueadas, no detiene el negocio, no garantiza equipo encendido o sesión iniciada, no renueva confirmaciones y no acredita recuperabilidad mediante una restauración nueva.

La única operación de base autorizada para U6 en este complemento es el backup, además de las lecturas necesarias. Se mantienen origen, roles y ACL SQL. No se inicia PostgreSQL, no se ejecutan restauraciones ni DROP y no se modifica foodstore.

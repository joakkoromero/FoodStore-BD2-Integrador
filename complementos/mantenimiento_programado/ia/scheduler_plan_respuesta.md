**Hallazgos**
La revisión estática identifica **un defecto de privacidad que considero bloqueante antes del ensayo real** y dos problemas de selección/compatibilidad de manifiestos. No ejecuté herramientas ni código, ni examiné fuentes U6. Los efectos indicados son consecuencias posibles del código, no resultados observados.

### 1. Alta: los destinos internos del backup no se validan antes de escribir

**Ubicación:** `02_run_backup_job.ps1`, líneas 401-402, 502-524 y 540-541/620-621; SPEC, líneas 14 y 26.

**Causa:** antes de invocar U6 se valida la ACL y la cadena de ancestros de `BackupWorkDir`, pero no las de sus subdirectorios existentes `backups` y `logs`. Un directorio raíz privado no garantiza que sus descendientes tengan ACL privadas o que no sean puntos de redirección. Las comprobaciones posteriores del manifiesto y del dump ocurren después de que U6 haya escrito.

**Efecto:** si alguno de esos subdirectorios ya existe con permisos más amplios o como una redirección, el proceso hijo puede escribir dumps o metadatos fuera de las garantías de privacidad. Rechazar el resultado después no revierte esa exposición.

**Corrección propuesta:** antes de ejecutar U6, comprobar también tipo, ACL, ausencia de reparse points y cadena de ancestros de los destinos internos existentes definidos por el contrato, al menos `backups` y `logs`. Para los que deban crearse, asegurar previamente una creación privada y validar el resultado antes de delegar las escrituras. Rechazar configuraciones inseguras sin modificar automáticamente ACL ajenas.

**Distinción:** que existan subdirectorios inseguros es una condición del entorno; delegar escrituras sin comprobarlos es el defecto del runner. Con directorios correctamente preparados, esa condición puede no presentarse.

### 2. Media: se buscan manifiestos fuera del directorio contractual

**Ubicación:** `02_run_backup_job.ps1`, líneas 497-500 y 534-575; SPEC, línea 26.

**Causa:** tanto el inventario previo como la búsqueda posterior recorren todos los JSON de `BackupWorkDir`, aunque el contrato sitúa los manifiestos en `BackupWorkDir/logs`. Los candidatos se conservan por su contenido, sin exigir esa ubicación.

**Efecto:** un JSON nuevo fuera de `logs` puede ser aceptado como manifiesto o causar un rechazo por duplicidad. También puede abortarse un backup válido por un JSON ajeno demasiado grande o con metadatos `SUCCESS` inválidos. La verificación posterior del dump no corrige la selección incorrecta de la fuente del manifiesto.

**Corrección propuesta:** limitar ambos inventarios al directorio contractual `logs`, previamente validado como privado y sin redirecciones. Mantener allí la exigencia de exactamente un `SUCCESS` nuevo y las validaciones temporales, de contenido y de archivo.

### 3. Media: se impone un formato de nombre de dump no declarado en el contrato

**Ubicación:** `02_run_backup_job.ps1`, líneas 604-607; SPEC, línea 26.

**Causa:** el runner exige el patrón exacto `foodstore_[8 dígitos]T[13 dígitos]Z_[32 hex minúsculos].dump`. El contrato adjunto sólo garantiza que `file` es un basename y que el dump está en `BackupWorkDir/backups`; no establece ese patrón.

**Efecto:** puede rechazarse un manifiesto conforme al contrato, incluso con código nativo cero y dump correcto. **No afirmo que el U6 real produzca un nombre incompatible:** sus fuentes no están adjuntas. El problema verificable es que el consumidor incorpora una restricción adicional no especificada.

**Corrección propuesta:** validar que sea un nombre de archivo simple y válido para Windows, sin rutas, separadores, ADS ni componentes especiales, y resolverlo exclusivamente dentro de `backups`. Alternativamente, incorporar el patrón exacto a la SPEC, pero sólo después de confirmar que forma parte del contrato real.

**Cobertura**
Leí íntegramente el contenido visible de los cinco adjuntos. No se observa truncamiento.

| Archivo adjunto | Cobertura | Última línea visible |
|---|---:|---:|
| `01_SPEC_SCHEDULER.md` | Completa | 27 |
| `02_run_backup_job.ps1` | Completa | 702 |
| `03_crear_tarea_diaria.ps1` | Completa | 332 |
| `04_tarea_diaria.template.xml` | Completa | 47 |
| `05_README.md` | Completa | 31 |

**Controles Revisados**
- **Sintaxis PowerShell:** no identifico errores sintácticos verificables por lectura. Esto no equivale a una validación mediante parser.
- **Secretos y argumentos:** no se lee ni imprime el contenido de `PassFile`; se transmite su ruta mediante `PGPASSFILE`. El hijo elimina las variables `PG*` heredadas y establece las necesarias. Se usa `ArgumentList` para los procesos y se rechazan comillas dobles en las rutas.
- **Errores:** se comprueban los códigos nativos tras finalizar cada proceso. U6 se ejecuta en un hijo, por lo que su `exit` no termina prematuramente el runner. Un fallo de escritura del resumen devuelve error; `CreateNew` evita sobrescrituras.
- **Validación del dump:** se contrastan tamaño y SHA256 manteniendo abierto el archivo sin compartir escritura ni borrado. El resumen de baseline se restringe a las etiquetas y tipos declarados.
- **Calendario y principal:** el XML configura calendario diario, `DaysInterval=1`, inicio con desplazamiento explícito, SID actual, `InteractiveToken` y `LeastPrivilege`. El registro usa `TASK_CREATE=2`, sin contraseña y sin reemplazo deliberado de tareas existentes.
- **Limpieza acotada:** los scripts no eliminan tareas ni respaldos. El README prescribe retirar únicamente la tarea temporal; esa limpieza es manual, no una operación implementada o verificada en estos adjuntos.

**Límites Residuales**
- El chequeo de sesiones es una observación, no un cerrojo. No impide conexiones o escritores posteriores; la coordinación del operador sigue siendo necesaria.
- Una confirmación vence en un máximo de 60 minutos. Registrar un calendario diario no renueva la autorización ni garantiza que la ventana siga vigente al primer disparo.
- Se requiere equipo encendido, sesión iniciada, permisos efectivos y dependencias disponibles. Su ausencia es una condición operativa, no por sí misma un defecto del código.
- Las validaciones de rutas y ACL no eliminan todas las carreras entre comprobación y uso. Los destinos privados deben permanecer bajo control de las identidades autorizadas.
- Un timeout o una terminación puede dejar archivos parciales. No hay limpieza automática ni reintentos ciegos; corresponde inspección privada.
- El procedimiento de evidencia debe incluir expresamente el **hash del XML original privado**, exigido por la SPEC, línea 20, pero omitido en las instrucciones resumidas del README, línea 29.
- Hashes y fingerprints no acreditan anonimato. Tampoco esta revisión acredita un disparo real, un backup exitoso, la retirada de la tarea o un servicio permanente activo.

**Conclusión**
Corregiría el control previo de los destinos internos antes de autorizar el ensayo, y ajustaría la selección y el contrato del manifiesto. No encuentro otros fallos bloqueantes verificables por lectura en la sintaxis, el calendario diario o la configuración de token y privilegios. La compatibilidad efectiva con U6 y Windows Scheduler permanece pendiente de validación operativa coordinada.

## Hallazgo

### 1. Alta: la cadena de ancestros se valida contra redirecciones, pero no contra sustitución desde un padre modificable

**Ubicación:** `02_run_backup_job.ps1:52-82` (`Assert-PathChain`) y `84-135` (`Assert-PrivateItem`). Afecta también las validaciones previas a U6 de las líneas `510-519`. Requisito relacionado: `01_SPEC_SCHEDULER.md:14,29`.

**Causa:** `Assert-PathChain` recorre todos los ancestros y rechaza reparse points y ubicaciones Git, pero no examina sus ACL. `Assert-PrivateItem` comprueba propietario y entradas Allow únicamente del objeto final recibido.

**Efecto:** un directorio final puede superar los controles aunque un tercero tenga permisos suficientes sobre su padre para eliminarlo, renombrarlo o sustituirlo. En Windows, ciertos permisos sobre el padre, como eliminación de hijos, pueden permitir esa operación aunque la ACL del hijo sea restrictiva. La sustitución puede usar directorios normales, sin reparse points. Esto debilita la garantía de privacidad e integridad entre la validación y el uso de configuración, credenciales, resultados o destinos de respaldo.

Es una **omisión real del control**; su explotación depende de las ACL efectivas del entorno. No afirmo que esos permisos existan en la máquina del operador ni que haya ocurrido una exposición.

**Corrección propuesta:** comprobar también que los ancestros no concedan a identidades ajenas capacidades que permitan sustituir o redirigir los objetos protegidos. Diferenciar permisos de lectura/tránsito de permisos de modificación y sustitución: aplicar indiscriminadamente a cada ancestro la regla de “ningún Allow ajeno” rechazaría muchas rutas Windows normales. Precisar esa distinción en la SPEC y conservar el rechazo seguro, sin reparar automáticamente ACL ajenas.

Las revalidaciones actuales reducen la ventana de riesgo, pero no sustituyen este control.

## Cobertura

Leí todas las líneas incluidas en los cinco adjuntos. No hay truncamiento visible en el material proporcionado.

| Archivo adjunto | Líneas revisadas | Última línea visible |
|---|---:|---:|
| `01_SPEC_SCHEDULER.md` | 1-30 | 30 |
| `02_run_backup_job.ps1` | 1-714 | 714 |
| `03_crear_tarea_diaria.ps1` | 1-332 | 332 |
| `04_tarea_diaria.template.xml` | 1-47 | 47 |
| `05_README.md` | 1-35 | 35 |

No utilicé herramientas, no ejecuté código y no inspeccioné U6. Los nombres numerados se consideran nombres de los adjuntos; el README indica los nombres operativos que deben mantenerse juntos.

## Controles Revisados

No identifiqué otros defectos bloqueantes verificables en el texto adjunto:

- **Sintaxis PowerShell:** no detecté errores sintácticos por lectura estática. Esto no equivale a una validación mediante parser.
- **Configuración y secretos:** se exige el conjunto exacto de claves, se detectan duplicados y se utiliza `-DateKind String`. El endpoint y el usuario están restringidos. No se lee el contenido de `PassFile`, no se coloca la contraseña en argumentos y no se publican diagnósticos nativos.
- **Entorno libpq:** el proceso hijo elimina las variables heredadas cuyo nombre empieza por `PG` y configura explícitamente las necesarias, incluido `PGPASSFILE` y el timeout.
- **Invocación y errores:** U6 se ejecuta mediante un proceso `pwsh` independiente y `ArgumentList`, no por evaluación de texto. Los códigos de salida se recogen inmediatamente tras finalizar los procesos. Los errores conducen a salida `1`; los resultados usan `CreateNew` y un fallo de escritura no se convierte en éxito.
- **Manifiestos:** ambos inventarios se limitan a `logs/*.manifest.json`, sin recursión. Se exige exactamente un `SUCCESS` nuevo con inicio dentro del intervalo del job; se comprueban metadatos, basename, baseline, tamaño y SHA256. El dump permanece abierto sin compartir escritura ni borrado durante la verificación. Todo ello se evalúa contra el contrato declarado, no contra fuentes U6 observadas.
- **Calendario y principal:** la plantilla y el creador establecen calendario diario, `DaysInterval=1`, `StartBoundary` con desplazamiento explícito, SID actual, `InteractiveToken` y `LeastPrivilege`. Se usa `TASK_CREATE=2`, sin reemplazo deliberado de tareas existentes ni contraseña almacenada.
- **Settings:** figuran `IgnoreNew`, límite de diez minutos, ausencia de reintentos, sin despertar el equipo y ejecución permitida en batería. No se introduce inicio manual para simular el disparo.
- **Limpieza acotada:** los scripts no eliminan tareas ni respaldos. La deshabilitación y retirada de la única tarea temporal quedan como procedimiento del operador en la SPEC y el README. No hay automatización de limpieza cuya delimitación pueda verificarse adicionalmente.

## Límites Residuales

- La consulta de sesiones es una observación puntual, no un cerrojo. Pueden entrar nuevos escritores después; los adjuntos lo declaran correctamente.
- La confirmación de ventana no se renueva sola. Una tarea diaria con confirmación expirada fallará antes del backup; esto es comportamiento previsto, no un defecto del calendario.
- `InteractiveToken` requiere una sesión iniciada. La disponibilidad del equipo, permisos efectivos de registro, políticas locales y acceso PostgreSQL son condiciones del entorno pendientes de comprobar.
- Las comprobaciones de rutas y ACL no son atómicas con todas las aperturas posteriores. El modelo depende de proteger las ubicaciones frente a cambios por terceros; el hallazgo anterior afecta precisamente esa protección.
- La exportación de evidencia, el saneamiento de SID/rutas, la conservación de hashes y la retirada de la tarea son pasos documentados, no ejecutados ni acreditados aquí.
- SHA256 comprueba integridad del dump; los hashes y fingerprints no garantizan anonimato. Esta revisión tampoco acredita restaurabilidad ni resultados operativos.

**Conclusión:** no daría conformidad final sin resolver el control de ancestros indicado. Fuera de ese hallazgo, no encontré otro bloqueo verificable por lectura estática. No se acredita ninguna tarea instalada, ejecución programada, respaldo exitoso ni servicio permanente activo.

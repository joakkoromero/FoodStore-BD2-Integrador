**La revisión es parcial por truncamiento del adjunto:** el contenido recibido termina en la línea 1069 del bundle, dentro de `tools/opencode_consulta.py`. No aparecen los cuerpos de `tools/ps_common.ps1` ni de `validaciones.sql`. Por eso no es posible afirmar que se revisaron todos los archivos del bundle completo ni cerrar la evaluación de nativos, manifiestos, huellas y snapshots.

No ejecuté comandos, utilicé herramientas ni modifiqué archivos. Los hallazgos siguientes corresponden exclusivamente al código visible.

## 1. Inventario

Las referencias de línea son **relativas a cada bloque de archivo recibido**, contando los dos comentarios iniciales de saneamiento. No son las líneas del Markdown contenedor; las fuentes originales podrían tener otro desplazamiento.

| Archivo | Estado | Alcance Revisado |
|---|---|---|
| `backup_foodstore.ps1` | Hallazgos U6-01 y U6-02; dependencia pendiente | Bloque completo, líneas 1–92. Preflight, ejecución declarada de clientes, baselines, publicación del dump y manifiesto, logs y salida. No se puede comprobar la implementación de los helpers. |
| `health_check.sql` | Sin hallazgo concreto en lo visible | Bloque completo, líneas 1–82. Transacción de solo lectura, selección de base, estadísticas y exposición acotada de información de sesiones. |
| `maintenance.sql` | Sin hallazgo concreto en lo visible | Bloque completo, líneas 1–114. Selección de base, timeouts, consultas previas y posteriores, y `ANALYZE` condicional. |
| `restore_test.ps1` | Hallazgo U6-02; verificaciones condicionadas pendientes | Bloque completo, líneas 1–131. Preflight, destino fijo, creación, cierre de conexiones, restauración, aislamiento, comparación y medición temporal. Faltan las implementaciones de selección de manifiesto y comprobación de aislamiento. |
| `tools/generar_informe_u6.py` | Hallazgo condicionado U6-03 | Bloque completo, líneas 1–467. Renderizado, selección de fuentes, filtros de publicación, adjuntos, integridad y límites de páginas. |
| `tools/opencode_consulta.py` | No concluyente: archivo truncado | Líneas 1–131 y comienzo de la siguiente. Argumentos, validación inicial de rutas y preparación del reintento. No se recibió la ejecución del proceso ni su tratamiento final. |

**Dependencias mencionadas, pero sin cuerpo recibido:**

| Archivo | Estado | Alcance Pendiente |
|---|---|---|
| `tools/ps_common.ps1` | No revisable | `Pg`, `Log`, `Assert-Private`, `Assert-Clients`, `New-Writer`, `New-RunToken`, `Assert-Baseline`, `Read-BackupManifest` y `Assert-Isolation`. |
| `validaciones.sql` | No revisable | Snapshot, tablas cubiertas, conteos, construcción y estabilidad de huellas, validaciones y formato JSON. |

Los documentos consumidos por el generador, como `SPEC_U6.md`, `AGENTS.md` y los informes de `docs/`, tampoco tienen su contenido disponible en este extracto. Sus menciones no permiten inventariarlos como fuentes efectivamente revisadas.

## 2. Hallazgos

Prioridades: **P2**, defecto relevante de robustez o diagnóstico; **P3**, riesgo condicionado de publicación. Las pruebas indicadas son propuestas para U8, no resultados obtenidos.

| ID | Prioridad | Archivo / Línea Relativa | Condición y Consecuencia | Certeza | Prueba Mínima Propuesta |
|---|---|---|---|---|---|
| U6-01 | P2 | `backup_foodstore.ps1:74–85` | El `.partial` se renombra a `.dump` **antes** de escribir y publicar el manifiesto. Si falla la escritura o el segundo renombrado, queda un dump definitivo sin manifiesto y el script termina con error. La publicación del conjunto no es atómica ni tiene recuperación visible. | **Confirmado estructuralmente.** La consecuencia sobre la selección automática depende de `Read-BackupManifest`, ausente. No demuestra corrupción del dump ni selección incorrecta. | En una copia de laboratorio, provocar un fallo de publicación del manifiesto después del primer renombrado. Comprobar salida, residuos y que el selector no considere exitoso ese dump. |
| U6-02 | P2 | `backup_foodstore.ps1:87–89`; `restore_test.ps1:124–127` | Los `catch` registran únicamente la fase y luego salen con código 1. La causa de las excepciones PowerShell locales queda descartada: por ejemplo, errores de JSON, archivos o renombrados. Distintos fallos de una misma fase producen el mismo mensaje final. | **Confirmado para el diagnóstico local visible.** No se puede afirmar que se pierda también stderr de los nativos: eso depende de `Pg`. | En una copia de prueba, usar un manifiesto inválido o provocar un fallo de archivo controlado. Verificar si los artefactos conservan una causa identificable, sin revelar datos sensibles. |
| U6-03 | P3 | `tools/generar_informe_u6.py:384–391, 406–409`; contraste con `293–307` | Los informes Markdown se renderizan directamente, sin pasar por `public_path` y su control de patrones de credenciales. Si `docs/resolucion.md` o `docs/informe_post_incidente.md` incorporan accidentalmente un literal sensible, el generador puede publicarlo en el cuerpo del PDF aunque filtre los adjuntos. | **Brecha de cobertura confirmada; exposición condicionada al contenido.** No se observó ningún secreto ni se afirma que los informes actuales lo contengan. | En una copia descartable, agregar un marcador sintético que coincida con un patrón existente a un informe. Comprobar que el control no lo rechaza antes de renderizar; no usar credenciales reales. |

### Controles Que Acotan Los Hallazgos

- El respaldo exige endpoint loopback, confirmación de ventana sin escrituras, PostgreSQL 17 y superusuario; verifica tamaño y legibilidad del TOC, calcula SHA-256 y compara dos baselines.
- El uso de `.partial` y de renombrados separados mejora la publicación de **cada archivo**. U6-01 afecta la coordinación entre dump y manifiesto, no niega ese control.
- Ambos PowerShell tienen salida explícita 1 ante excepciones capturadas y salida 0 al finalizar. U6-02 es un problema de diagnóstico, no una afirmación de falso éxito en esos caminos.
- La restauración fija el destino en `foodstore_restore_test`, rechaza su existencia previa, usa `template0` y no contiene un reemplazo deliberado de `foodstore`.
- `--no-owner` y `--no-privileges`, junto con `roleAclRecovery=$false`, son coherentes con el alcance declarado: no se promete reconstruir la seguridad U5.
- El generador sí valida nombres y bytes extraídos de los adjuntos, calcula hashes y comprueba límites de página. Eso no sustituye el filtrado de los textos que renderiza directamente.

### Hipótesis Condicionadas y Verificaciones Pendientes

Estas observaciones **no son defectos confirmados** con el material disponible.

| Tema / Referencia | Qué Falta Confirmar | Prueba Local o de Motor Propuesta |
|---|---|---|
| Nativos: `backup_foodstore.ps1:15, 60`; `restore_test.ps1:16, 95–109` | Se deshabilita `$PSNativeCommandUseErrorActionPreference`. Es correcto si `Pg` captura inmediatamente `$LASTEXITCODE` y lanza ante un código no cero. Sin ese helper no puede validarse el contrato de errores. | Hacer fallar cada cliente de manera controlada y comprobar que el llamador termina con código 1 y nunca publica éxito. |
| Selección del respaldo: `restore_test.ps1:64–65` | No se ve si `Read-BackupManifest` verifica estado, nombre confinado a `backups`, tamaño, hash, fechas y esquema del baseline. Tampoco puede evaluarse el uso de `ConvertFrom-Json -DateKind String`. | Probar manifiestos sintéticos con hash incorrecto, ruta fuera del directorio, JSON inválido y fecha futura. Deben rechazarse antes de crear el destino. |
| Baselines: `backup_foodstore.ps1:54–69`; `restore_test.ps1:113–118` | Los bucles comparan claves del baseline de referencia, no la igualdad explícita de ambos conjuntos de claves. Puede estar cubierto por `Assert-Baseline`; no corresponde afirmar lo contrario sin verlo. | Añadir y quitar claves de cada sección y comprobar rechazo. |
| Snapshot y huellas: llamadas a `validaciones.sql` | No se sabe si todas las consultas usan un snapshot coherente, ni si las huellas tienen orden estable, codificación inequívoca de `NULL` y cobertura suficiente. | Revisar el SQL y contrastar ejecuciones con cambios concurrentes controlados y variaciones de orden de lectura. |
| Aislamiento: `restore_test.ps1:87–108` | El código reconoce la ventana entre `createdb` y el cierre. `CONNECTION LIMIT 0` no expulsa sesiones existentes; el conteo posterior las detecta, pero no las elimina. Es aceptable bajo el supuesto declarado de operadores controlados, no una garantía frente a superusuarios concurrentes. | Verificar ausencia de sesiones y acceso denegado con los seis roles; revisar además el alcance efectivo de `Assert-Isolation`. |

### Observaciones Sin Hallazgo

**RTO y RPO.** El cronómetro comienza antes de `createdb` y termina después de aislamiento, validación y comparación de huellas (`restore_test.ps1:95, 99, 113–120`). Por tanto, el tiempo evaluado incluye esos controles y es más conservador que un RTO limitado a validaciones mínimas. Si U8 distingue controles posteriores adicionales, debe documentar el punto de corte real del script, sin atribuirle una medición separada inexistente.

Los límites rechazan RTO superior a 120 segundos, antigüedad superior a 24 horas y antigüedad negativa. El RPO se calcula desde el inicio declarado del respaldo hasta el inicio del ensayo; no representa pérdida real de datos. Esto coincide con la limitación expresada por el usuario.

**Mantenimiento.** Se usan nombres de tablas calificados, verificación de base, `lock_timeout` y `statement_timeout`. No hay `VACUUM FULL`, desactivación de autovacuum ni modificación deliberada de filas. El criterio de `ANALYZE` basado en historiales nulos está identificado como política del laboratorio, no como demostración de estadísticas defectuosas. El retraso de publicación estadística también está reconocido.

**Health check.** Utiliza transacción de solo lectura y evita exportar texto SQL, usuario o dirección de sesiones. La clasificación por prefijo no es un parser SQL, pero se presenta como clasificación limitada y trata `WITH` por separado. No hay evidencia suficiente para convertir esa limitación en un defecto.

**Wrapper OpenCode.** El fragmento valida prefijo, existencia de entradas, timeout positivo y ubicación del directorio privado fuera del repositorio. Sin el resto no se puede confirmar la denegación de herramientas, propagación de errores, tratamiento del timeout, selección de respuesta ni persistencia final de metadatos. La descripción del módulo no prueba esas propiedades.

## 3. Límites

- **No se completó la revisión exhaustiva solicitada:** faltan dos dependencias centrales y la parte final del wrapper.
- No se ejecutaron estas copias saneadas ni se interpretaron placeholders como defectos.
- No se certifican compatibilidad en motor, permisos reales, ACL del sistema de archivos, restauración, integridad operativa ni resultados históricos.
- Dos baselines iguales no prueban por sí solos ausencia de escrituras intermedias. Existe, además, una confirmación explícita de ventana sin escrituras; su cumplimiento es una condición operativa.
- `pg_restore --list` verifica que el archivo pueda listar su contenido, no que toda restauración vaya a completarse. El ensayo de restauración es un control separado.
- Las pruebas históricas no adjuntas no se consideran verificadas por esta consulta.
- No se propone modificar la entrega histórica ni implantar alta disponibilidad. Los hallazgos y verificaciones quedan como insumos para prueba y documentación en U8.

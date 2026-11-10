## 1. Inventario

Se revisaron íntegramente los **cuatro archivos recibidos**, incluidos los auxiliares:

| Archivo | Alcance revisado | Estado |
|---|---|---|
| `tools/empaquetar_entrega.py` | Inventario, exclusiones, inspección de objetos Git, detección de credenciales, manifiesto, creación del ZIP y verificación con restauración temporal. | Revisión estática completa. Una mejora de robustez y límites de cobertura descritos abajo. |
| `tools/generar_informe_pdf.py` | Fuentes, estilos, transformación de Markdown, tablas, bloques de código, selección de informes y escritura del PDF. | Revisión estática completa. Un defecto de fidelidad en código en línea. La ejecución sobre los informes reales no está acreditada. |
| `tools/instalar_seguridad.py` | Precondiciones, configuración de logging comprobada, aplicación del SQL, asignación parametrizada de contraseñas y transacción de esa asignación. | Revisión estática completa. Un defecto en la suficiencia de las comprobaciones de logging. La política efectiva de roles depende del SQL no incluido en esta continuación. |
| `tools/libpq_client.py` | Configuración privada, carga de DLL, declaraciones `ctypes`, conexión, parámetros, resultados, errores y liberación de recursos. | Revisión estática completa. Una omisión en el tratamiento de mensajes `NOTICE`. |

**El adjunto no aparece truncado.** El último archivo completamente visible es `tools/libpq_client.py`, incluido su método `__del__`.

Las líneas indicadas a continuación son **relativas a cada archivo**, contando las dos líneas iniciales de la copia saneada. No son los números de línea del Markdown contenedor.

## 2. Hallazgos

Prioridades: **P1**, exposición potencial de credenciales durante una operación sensible; **P2**, exposición potencial por una vía no controlada; **P3**, robustez o fidelidad sin compromiso de seguridad demostrado.

| ID | Prioridad y tipo | Archivo / líneas | Condición concreta | Consecuencia | Certeza | Prueba mínima propuesta, no ejecutada |
|---|---|---|---|---|---|---|
| U5-C03-01 | **P1 · Defecto demostrable de la precondición de seguridad** | `tools/instalar_seguridad.py:22-26, 30-39` | Se permite continuar cuando `log_statement=none` y `log_min_error_statement=panic`, aunque esté activo otro mecanismo de registro de sentencias, por ejemplo `log_min_duration_statement=0`, con registro de parámetros habilitado. | Las llamadas parametrizadas a `set_config` pueden dejar las contraseñas de roles en el log. Usar parámetros evita interpolación SQL, pero no impide que PostgreSQL registre sus valores. | La insuficiencia de la comprobación es confirmable en el código. **No se demuestra que la configuración histórica tuviera esa vía activa ni que hubiera una filtración.** | En un laboratorio descartable con PostgreSQL 17.11, configurar esos dos valores aceptados, `log_min_duration_statement=0` y `log_parameter_max_length=-1`. Ejecutar una llamada equivalente a `set_config` con una cadena centinela no secreta y comprobar localmente el log. |
| U5-C03-02 | **P2 · Defecto demostrable en el control de salida del cliente** | `tools/libpq_client.py:115-167, 240-247, 253-301` | Se carga y utiliza libpq sin instalar un receptor o procesador de avisos. Si el servidor envía un `NOTICE`, queda activo el procesamiento predeterminado de libpq, que escribe en `stderr`. | Un mensaje del servidor puede salir sin el saneamiento aplicado a `DatabaseError`. Si el aviso contiene datos personales o sensibles, estos pueden terminar en consola o en registros capturados del proceso. | La ausencia del control es confirmable. **El contenido sensible de un aviso y su ocurrencia histórica no están demostrados.** | Con el cliente original local y una base de prueba, capturar `stderr` y ejecutar `DO $$ BEGIN RAISE NOTICE 'U5_NOTICE_CENTINELA'; END $$;`. Comprobar si la cadena sale por `stderr`, sin usar datos reales. |
| U5-C03-03 | **P3 · Defecto demostrable de fidelidad** | `tools/generar_informe_pdf.py:81-86` | `markup()` transforma enlaces y negritas antes de reconocer los fragmentos de código en línea. Por ejemplo, un fragmento delimitado por backticks cuyo contenido sea `**literal**` se convierte primero en una etiqueta de negrita. | El PDF pierde los asteriscos literales y presenta formato dentro de lo que debía ser código. También pueden reescribirse expresiones con sintaxis de enlace dentro de código en línea. | El comportamiento de la transformación es confirmable estáticamente. **No está demostrado que los informes reales contengan un caso afectado.** | En una copia de prueba de los originales, generar un informe mínimo con código en línea que contenga `**literal**` y `[x](y)`. Comparar el texto y el formato del PDF con los literales de entrada. |
| U5-C03-04 | **P3 · Mejora de robustez** | `tools/empaquetar_entrega.py:84-101, 145-146` | El límite de 50 MB se aplica a cada objeto Git, pero `cat-file --batch` recupera todos los objetos y `subprocess.run` acumula la salida completa en memoria. El límite total del ZIP se comprueba después y no protege esta fase. | Un repositorio con muchos objetos menores al límite puede consumir mucha memoria o abortar antes de terminar el `--dry-run` o el empaquetado. | El procesamiento acumulativo es confirmable. **No se demuestra que el tamaño del repositorio recibido alcance una situación problemática.** | En un repositorio descartable, crear varios objetos incomprimibles, cada uno menor de 50 MB, y medir el consumo máximo durante la revisión del historial. Una comprobación local menos costosa puede verificar que se rechaza anticipadamente una suma de tamaños superior al presupuesto que se decida establecer. |

### Interpretación y Corrección

- **U5-C03-01:** el control debe cubrir las vías efectivas de registro de sentencias y parámetros relevantes para el laboratorio, no solamente `log_statement` y `log_min_error_statement`. Los módulos de auditoría, si existen, requieren una comprobación adicional. `log_error_verbosity='terse'` reduce contexto de errores, pero no desactiva el logging de duración ni sus parámetros.
- **U5-C03-02:** conviene definir explícitamente una política de avisos con `PQsetNoticeProcessor` o `PQsetNoticeReceiver`. Si se implementa mediante un callback de `ctypes`, debe conservarse su referencia durante toda la conexión. El hallazgo no implica que `DatabaseError` publique el error bruto: esa ruta sí está saneada.
- **U5-C03-03:** los fragmentos de código en línea deben quedar protegidos frente a las sustituciones del resto del marcado.
- **U5-C03-04:** basta con establecer un presupuesto acumulado antes de recuperar los objetos o procesarlos de forma incremental. Es una mejora de resistencia, no evidencia de un fallo ocurrido.

## 3. Controles Reconocidos

**Empaquetado**
- Exige un repositorio independiente y rechaza repositorios superficiales o con `alternates`.
- Ejecuta `git fsck --full` y examina el contenido decodificado de todos los objetos enumerados, incluidos los inalcanzables.
- Rechaza enlaces simbólicos, archivos faltantes y determinados materiales privados.
- Exige los entregables de `REQUIRED` y un árbol de trabajo limpio antes de crear el ZIP.
- Comprueba duplicados, rutas peligrosas, CRC, tamaños y SHA-256 contra el manifiesto.
- Restaura en un directorio temporal y contrasta integridad Git, `HEAD` y cantidad de commits.
- Usa un archivo temporal y elimina ese temporal ante fallos.

**Instalación**
- Comprueba la existencia de la especificación y del SQL antes de conectarse.
- No interpola las contraseñas en las llamadas del cliente: usa parámetros.
- Usa `%L` para construir los comandos dinámicos de asignación de contraseñas.
- Agrupa la asignación de las dos contraseñas en una transacción con intento de rollback.
- Reduce la verbosidad de errores durante esa operación.

**Cliente libpq**
- Carga la biblioteca de forma diferida: importar el módulo no abre una conexión.
- Rechaza secretos ubicados dentro del repositorio.
- Valida puerto y determinados campos de conexión; rechaza NUL en SQL y parámetros de texto.
- Separa valores de parámetros mediante `PQexecParams`.
- Expone errores saneados y SQLSTATE observado, sin incorporar el mensaje bruto del servidor.
- Distingue `NULL` de cadenas vacías y utiliza la longitud de cada valor.
- Libera `PGresult` mediante `finally`, ofrece cierre por contexto y cierra la conexión ante `COPY` no soportado.
- Evita volcar las filas en la representación habitual de `QueryResult`.

**PDF**
- Escapa el texto antes de introducir etiquetas de ReportLab.
- Detecta cercas de código sin cierre.
- Divide los bloques de código en elementos pequeños para facilitar la paginación.
- Repite las cabeceras de tabla y exige la existencia de los informes enumerados.
- Explicita que el PDF no sustituye SQL, historial, transcripciones ni evidencia reproducible.

## 4. Límites y Dependencias

### Seguridad y Evidencia
- Esta continuación **no vuelve a evaluar los cinco SQL ni los dos auxiliares cubiertos por la primera revisión**. No corresponde confirmar ni contradecir sus ACL, propietarios, funciones `SECURITY DEFINER` o resultados de pruebas sin su contenido y evidencia.
- La política de mínimo privilegio depende de `sql/roles.sql`. La existencia del archivo no demuestra que sus permisos sean correctos.
- El SQL de roles se ejecuta **antes** del `BEGIN` que protege las contraseñas. Si ese SQL confirma sus cambios y luego falla la asignación de contraseñas, ambas fases no serán atómicas. La consecuencia concreta depende de las transacciones, atributos de login y estado previo definidos en el SQL no adjunto; **no se declara un fallo confirmado de la instalación**.
- Los parámetros de logging efectivos, las extensiones de auditoría y los mensajes emitidos por funciones o triggers no están adjuntos.
- No se acreditan pruebas históricas, ausencia de filtraciones ni aprobación humana.

### Alcance Del Empaquetado
- La detección de credenciales es una **lista de patrones conocidos**, como declara el propio manifiesto. No garantiza ausencia de datos personales, contraseñas arbitrarias o formatos no contemplados.
- Excluir un archivo del inventario de trabajo **no lo elimina del historial**. La comprobación de nombres históricos usa `excluded_name()` sobre objetos alcanzables, pero no aplica las reglas completas de `.gitignore` a todas las rutas históricas. Un archivo hoy ignorado puede seguir en los objetos enviados. Esto limita el alcance de las exclusiones; no demuestra que exista material privado en este repositorio.
- Los objetos inalcanzables sí se inspeccionan por patrones de contenido. Sin embargo, eso no equivale a comprobar todas sus rutas históricas con las reglas de exclusión.
- `--verify` comprueba coherencia del ZIP, del manifiesto y del historial restaurado. **No vuelve a exigir `REQUIRED` ni vuelve a ejecutar la revisión de credenciales.**
- Los hashes internos detectan discrepancias respecto del manifiesto, pero no autentican al autor del archivo. Un ZIP y su manifiesto modificados conjuntamente requieren una referencia externa confiable para detectar esa sustitución.

### Entorno y PDF
- El cliente exige explícitamente Windows y una instalación determinada de PostgreSQL 17. El PDF también depende de fuentes en `C:/Windows/Fonts/`. Son restricciones del entorno observado, no fallos por sí mismas.
- Los informes Markdown y la versión instalada de ReportLab no están adjuntos. Las tablas usan `splitInRow=0`: una fila mayor que el área útil de una página puede impedir la composición. Es un **riesgo condicionado al contenido**, no un fallo demostrado de los informes reales.
- El renderizador implementa un subconjunto de Markdown, no un analizador general. No se presupone soporte de todas las construcciones del formato.

**No se utilizaron herramientas, no se ejecutaron pruebas y no se modificaron archivos.** Esta revisión es exclusivamente estática sobre las cuatro copias saneadas visibles y debe interpretarse junto con los resultados anteriores.

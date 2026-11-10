## Inventario

El adjunto está completo: contiene **seis archivos**, todos visibles hasta su final. El último es `tools/verificar_matriz.py`. Las referencias siguientes son **líneas relativas a cada archivo**, contando como línea 1 el comentario `# COPIA SANEADA...`, no las líneas del Markdown contenedor.

| Archivo | Alcance revisado | Estado |
|---|---|---|
| `tools/opencode_consulta.py` | Argumentos, validación de rutas, preservación de adjuntos, ejecución de la consulta, timeout, extracción de respuesta, reintentos y metadatos. | Revisión estática completa. Un defecto confirmado en el reintento de consultas fallidas con respuesta parcial. |
| `tools/preparar_laboratorio.py` | Selección de herramientas, ACL de Windows, creación del runtime, secretos, inicialización, configuración, restauración y limpieza ante fallos. | Revisión estática completa. Sin defecto funcional confirmado en el alcance recibido; hay dependencias y límites de seguridad indicados abajo. |
| `tools/rotar_log.py` | Solicitud de rotación, sondeo del archivo activo y salida utilizada como evidencia. | Revisión estática completa. Un defecto condicionado por el nombre del archivo generado durante la rotación. |
| `tools/verificar_conservacion.py` | Tablas incluidas, snapshot transaccional, resumen de filas, comparación antes/después y escritura de evidencia. | Revisión estática completa. Sin defecto confirmado para el alcance declarado; no equivale a verificar todo el estado de la base. |
| `tools/verificar_matriz.py` | Matriz esperada, lectura de ACL de relaciones y columnas, membresías, comparación y resultado. | Revisión estática completa. Sin defecto confirmado respecto de su propósito de comparar ACL explícitas; no certifica por sí solo privilegios efectivos completos. |

No ejecuté herramientas ni pruebas, ni modifiqué archivos. Esta revisión no acredita las pruebas históricas ni aprobación humana.

## Hallazgos

Prioridad **P2**: problema funcional de severidad media, bajo la condición especificada. Las pruebas propuestas deben realizarse sobre los originales locales, no sobre las copias saneadas.

| ID | Prioridad / clasificación | Archivo y líneas | Condición concreta | Consecuencia | Certeza | Prueba mínima propuesta |
|---|---|---|---|---|---|---|
| U5-C04-01 | P2 · Defecto demostrable | `tools/opencode_consulta.py:123–128, 202–204` | La consulta produce texto y después termina con error, timeout o código distinto de cero. El programa guarda `*_respuesta.md` aunque el estado sea `failed`. Al invocarlo nuevamente con `--retry-failed`, rechaza el reintento porque existe ese archivo de respuesta. | El reintento previsto no funciona para fallos con respuesta parcial. La consulta queda bloqueada bajo ese prefijo, aunque sus metadatos indiquen fallo. | **Confirmada por el flujo del código.** No depende de la implementación interna de OpenCode: basta con que exista texto antes de un fallo. | Prueba local con un ejecutable de prueba que responda a `--version`, emita un evento JSON `text` y termine con código 1. Verificar que se generan respuesta y metadatos `failed`; repetir con `--retry-failed` y comprobar el rechazo. |
| U5-C04-02 | P2 · Defecto bajo condición concreta | `tools/rotar_log.py:12–23`; configuración relacionada en `tools/preparar_laboratorio.py:200` | La rotación se procesa dentro del mismo segundo que determinó el nombre del log activo. La configuración utiliza `postgresql-%Y-%m-%d_%H%M%S.log`; en ese caso, la rotación puede reabrir el mismo nombre. El helper solo considera éxito si cambia la ruta devuelta por `pg_current_logfile`. | Una rotación aceptada y procesada puede notificarse como fallo. Si la ruta sigue siendo la misma, esperar más no provoca por sí solo otra rotación ni vuelve inactivo ese archivo, por lo que tampoco queda disponible la fuente cerrada que necesita la captura. | **Confirmado el límite del algoritmo y la colisión posible del nombre.** Su aparición en las ejecuciones históricas no está acreditada. | En un laboratorio PostgreSQL 17 con esa configuración, realizar dos solicitudes de rotación procesadas dentro del mismo segundo y consultar la ruta antes y después. Comprobar que puede mantenerse pese a que `pg_rotate_logfile()` acepte la solicitud. |

**Criterios de corrección**

- **U5-C04-01:** distinguir una respuesta de una consulta completada de una respuesta parcial fallida. Si se permite reintentar, preservar también la respuesta parcial anterior antes de liberar sus rutas públicas; no basta con quitar la condición que bloquea el reintento.
- **U5-C04-02:** conservar la comprobación de cambio de ruta, porque evita presentar un archivo activo como fuente cerrada. La mejora es volver a solicitar la rotación después de cruzar el límite de segundo, con un plazo acotado, no aceptar cualquier respuesta `t` como evidencia suficiente.

## Controles Y Límites

### `opencode_consulta.py`

**Controles existentes:** valida el prefijo, impide ubicar el directorio de eventos crudos dentro del repositorio identificado, usa `shell=False`, conserva snapshots y hashes de adjuntos, registra timeout y errores, y no declara aprobación humana ni ejecución SQL.

**Mejoras de robustez y dependencias:**

- La protección de `private_dir` depende de los permisos del directorio elegido: este programa lo crea con `mkdir`, pero no aplica una ACL privada como hace el preparador. **No demuestra exposición**, aunque la exclusión del repositorio no garantiza confidencialidad frente a otros usuarios locales.
- Se registran líneas no interpretables y eventos de herramientas, pero no intervienen en `successful` (`202`, `223–224`). Es una definición de éxito limitada, no una prueba autónoma de que todo el protocolo fue válido o de que no hubo uso de herramientas.
- La efectividad de `permission: deny`, `--pure` y el agente `plan` depende de la versión y configuración efectiva de OpenCode. No corresponde afirmar una evasión sin esa dependencia y sin evidencia de ejecución.

### `preparar_laboratorio.py`

**Controles existentes:** exige un runtime nuevo y externo al repositorio, aplica ACL antes de escribir secretos, utiliza creación exclusiva de archivos privados, comprueba PostgreSQL 17, configura autenticación SCRAM en `initdb`, limita la escucha a loopback y restaura sin propietarios ni privilegios del dump. También elimina el archivo temporal de contraseña y procura detener el clúster nuevo si falla la preparación.

Para `createdb` y `pg_restore`, elimina las variables heredadas cuyo nombre comienza por `PG`, fija destino y credenciales y evita incluir la contraseña en `argv`.

**Límites:**

- La cabecera `PGDMP` y el SHA-256 identifican el formato y los bytes, pero no convierten el respaldo en contenido confiable. Restaurar un dump requiere confiar en su procedencia, especialmente porque se utiliza el usuario bootstrap. Es una **precondición de seguridad**, no una prueba de que el respaldo recibido sea malicioso.
- Las ACL efectivas de Windows, la versión real de cada binario y el resultado de restauración necesitan comprobación local.
- El valor saneado de `password_encryption` **no es un defecto del original**.
- El script declara que no crea los roles U5 ni modifica los permisos de `public`; no corresponde exigirle esos efectos.

### `rotar_log.py`

**Control existente:** no confunde la aceptación de la solicitud con la observación del cambio de archivo. Ese control es correcto para el objetivo de capturar una fuente que ya no esté activa.

La conexión, el tipo devuelto por `scalar()` y el acceso a secretos dependen de `libpq_client.py`, no recibido aquí. La comparación con `'t'` solo sería un defecto si ese cliente devolviera otro tipo; **no lo afirmo**.

### `verificar_conservacion.py`

**Controles existentes:** usa una transacción `REPEATABLE READ READ ONLY`, fija zona horaria y formato de fechas, ordena el resumen por claves declaradas, compara conteos y hashes y evita sobrescribir una evidencia ya existente en el uso secuencial normal. No exporta filas completas.

**Limitaciones explícitas:**

- Comprueba las cinco tablas enumeradas, no secuencias, definiciones de objetos, funciones, ACL ni otras tablas.
- MD5 es una comprobación práctica de conservación, no una garantía criptográfica frente a manipulación deliberada.
- `string_agg` construye un agregado cuyo tamaño crece con el número de filas. La escala admisible depende del volumen y los recursos; no hay evidencia adjunta de que el laboratorio alcance ese límite.
- La evidencia anterior no identifica la instancia ni la base consultada. Asociar correctamente ambos archivos depende del procedimiento y de la configuración local.
- El `import Path` duplicado es inocuo; no lo considero hallazgo funcional.

### `verificar_matriz.py`

**Controles existentes:** distingue permisos de tabla y columna, incluye `PUBLIC`, compara la opción de concesión, incorpora `MAINTAIN` y verifica las opciones `ADMIN`, `INHERIT` y `SET` de las membresías seleccionadas. Devuelve error cuando la comparación no coincide.

**Límites de la certificación:**

- Compara ACL explícitas de relaciones y columnas en `public` y `datos_anon`, y membresías cuyo miembro pertenece a la lista fija.
- No comprueba atributos como `SUPERUSER` o `BYPASSRLS`, propietarios esperados, permisos de base y esquema, ACL de funciones, privilegios por defecto ni toda la red de membresías.
- Excluir entradas concedidas al propietario es coherente con su nota, pero significa que una propiedad incorrecta no queda detectada por esta comparación.
- Las lecturas de ACL y membresías no se agrupan aquí en un único snapshot transaccional. Si hubiera administración concurrente, podrían representar momentos distintos; en un laboratorio estable es una mejora de robustez.
- La salida de evidencia se sobrescribe en cada ejecución. Sirve como resultado actual, pero no conserva por sí sola el historial de verificaciones.

Estos límites **no prueban una configuración insegura**: delimitan lo que este helper puede demostrar. Las verificaciones complementarias pueden estar en los SQL y pruebas anteriores, que no están adjuntos en esta continuación.

## Dependencias

No se recibieron aquí `libpq_client.py`, las especificaciones finales de Kiro, los SQL revisados previamente, el respaldo ni las evidencias originales. Por ello:

- No puedo confirmar que la matriz codificada coincida con la especificación aprobada.
- No puedo certificar el aislamiento efectivo de los roles o la seguridad de las funciones `SECURITY DEFINER` mediante estos auxiliares solamente.
- No puedo confirmar que los dos hallazgos hayan ocurrido en las pruebas históricas.
- Los hashes declarados en el Markdown no fueron recalculados.

**Resultado:** dos hallazgos funcionales con condiciones concretas; los demás puntos son mejoras de robustez, dependencias o límites de alcance, no fallos históricos demostrados.

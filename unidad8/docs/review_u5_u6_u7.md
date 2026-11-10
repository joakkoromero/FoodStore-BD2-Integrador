# Revisión técnica propuesta: unidades 5, 6 y 7

Consolidación de consultas reales a OpenCode Plan, con herramientas denegadas. Las respuestas originales no se modificaron. Las decisiones siguientes son propuestas de Codex para la matriz final de Unidad 8; no acreditan aprobación humana ni pruebas pendientes.

## Cobertura

| Unidad | Fuentes revisadas completas | Estado |
|---|---:|---|
| 5 | 21 de 21 | Completa por unión: consulta inicial y cinco continuaciones sin truncamiento. |
| 6 | 8 de 8 | Completa por unión de consulta inicial y continuación. |
| 7 | 3 de 3 | Completa. |

Las referencias de línea corresponden a las copias saneadas según OpenCode. El helper de consolidación no ejecuta SQL ni conecta a los motores. La cobertura estática queda completa en 32 fuentes: 21 de U5, 8 de U6 y 3 de U7. Las pruebas nuevas propuestas se identifican aparte.

## Matriz de propuestas

| IDs originales conservados | Afirmación y alcance | Decisión propuesta | Fundamento y comprobación |
|---|---|---|---|
| review_u5/H-01 | Una cadena sensible escapada podría sobrevivir en un valor JSON aunque no exista como subcadena literal del texto serializado.<br>Alcance: Defecto algorítmico condicionado; no acredita exposición de las evidencias históricas U5. | aceptado | El recorrido de sanitize opera sobre texto serializado y la comprobación final repite la misma búsqueda literal. La consulta estática es evidencia del riesgo, no de que una credencial histórica haya aparecido. Se conserva el original y se propone una mejora probada por separado en U8.<br>Pendiente: Serializar un evento JSON con un marcador sintético que contenga comillas y barra inversa; sanearlo con el marcador decodificado en el inventario y comprobar el valor después de json.loads. No usar ni copiar secretos reales. |
| review_u6/U6-01 | La publicación de dos archivos no es atómica; puede quedar un dump huérfano. El selector no lo considera exitoso.<br>Alcance: Limitación operativa residual; no es un falso éxito del selector actual. | aceptado | La continuación review_u6_c01 revisó Read-BackupManifest y confirmó que enumera únicamente manifiestos SUCCESS, verifica el dump referenciado y su hash. Esa salvaguarda no vuelve atómica la publicación, pero evita seleccionar sólo un dump huérfano. No se descarta ni se tergiversa la observación original.<br>Pendiente: Presentar al selector únicamente un nombre .dump permitido sin manifiesto. Debe fallar con ausencia de manifiesto exitoso sin crear el destino. Una prueba de fallo al publicar manifiesto se limita a copias del flujo, sin tocar backups históricos. |
| review_u6/U6-02<br>review_u6_c01/U6-C01-02 | Dos capas del mismo problema diagnóstico: excepciones locales sin causa detallada y stderr nativo descartado. Los fallos sí producen salida no cero.<br>Alcance: Mejora de diagnóstico, sin afirmar éxito falso ni invalidar restauraciones históricas. | aceptado | Los códigos de salida se comprueban, se lanza excepción y los llamadores terminan en 1. Capturar la causa permitiría distinguir errores, pero su almacenamiento debe ser privado y no debe publicar credenciales o valores de filas. Se agrupan las observaciones conservando ambos IDs originales.<br>Pendiente: Simular un cliente que escriba un marcador no sensible en stderr y devuelva 1; comprobar código/aborto y ausencia del marcador en el log. Simular además una excepción local de archivo. Una corrección U8 deberá conservar diagnóstico únicamente en almacenamiento privado. |
| review_u6/U6-03 | La validación del generador no cubre uniformemente prosa y adjuntos; un literal accidental en un informe podría publicarse.<br>Alcance: Cobertura condicional del generador; no indica un secreto encontrado en el PDF U6 entregado. | aceptado | La observación distingue correctamente cobertura automática y contenido efectivo. Los controles finales de U6 incluyeron inspección y escaneo de valores privados conocidos sin coincidencias; esta revisión nueva no los reejecutó ni atribuye una exposición actual. Se propone comprobar la mejora con un marcador sintético, preservando el original.<br>Pendiente: Añadir a una copia descartable de un Markdown un patrón sintético que ya reconoce el filtro y comprobar si el generador lo rechaza. No añadir marcadores a la entrega histórica ni a informes finales. |
| review_u6_c01/U6-C01-01<br>review_u5_c04/U5-C04-01 | El reintento con igual prefijo sólo funciona si el fallo anterior no dejó respuesta parcial.<br>Alcance: Límite funcional del helper histórico; no afecta las consultas completadas conservadas. | aceptado | El bloqueo protege evidencia existente frente a sobreescritura, pero la opción de reintento no abarca todos los fallos. Para U8 puede mantenerse la regla explícita de usar un prefijo nuevo cuando hay respuesta parcial o implementarse archivado íntegro antes del reintento. No se afirma una corrección que todavía no se hizo. Se conserva la referencia independiente que revisó el wrapper U5 y se agrupa con el mismo defecto revisado en U6. Una solución futura debe preservar respuesta parcial y metadatos antes de autorizar el reintento.<br>Pendiente: El cliente simulado emite un evento text y devuelve 1. Comprobar metadatos failed, respuesta parcial guardada y rechazo de --retry-failed; comprobar también que un prefijo nuevo conserva el intento anterior. |
| review_u6_c01/U6-C01-03 | El contador de líneas no interpretadas se conserva, pero no condiciona el estado completed.<br>Alcance: Mejora de robustez condicionada; las consultas revisadas tienen contador cero. | aceptado | No toda línea no JSON demuestra pérdida de una respuesta. Conviene distinguir completed limpio y completed que requiere revisión, sin inventar fallos de las consultas actuales. Los metadatos de las cuatro consultas aquí consolidadas indican unparsed_line_count=0.<br>Pendiente: Emitir un evento text válido y una línea no JSON con salida 0. Comprobar estado y contador; definir una política explícita para ese caso antes de cambiarla. |
| review_u7/U7-01 | Un fallo del validador detiene la prueba y conserva el documento inesperado como residuo del laboratorio.<br>Alcance: Condición de reutilización ante una regresión; los cuatro casos actuales fueron rechazados. | aceptado | Las salidas originales y el cierre prueban cinco documentos y cero inválidos persistidos en esta ejecución. La observación no exige borrar automáticamente la evidencia de una regresión ni cambiar fuentes congeladas. Para futuras pruebas que debiliten el validador debe usarse una colección o copia separada.<br>Pendiente: Sólo en una copia separada, debilitar la validación del caso monetario y comprobar que se detecta la aceptación y queda el documento; no hacerlo sobre foodstore_u7.pedidos ni las fuentes congeladas. |
| review_u7/U7-02 | El generador no fuerza la limpieza de Git; los controles independientes sí acreditan la correspondencia de esta entrega congelada.<br>Alcance: Se descarta como discrepancia de la entrega U7 actual, conservando la mejora genérica como recomendación. | descartado | La condición de cambios sin confirmar no ocurre: working tree limpio y git diff contra 8178b01 sin diferencias. JS/SQL coinciden byte a byte con el commit; EJSON conserva el mismo contenido con CRLF en el archivo ejecutado y LF normalizado en Git. Los tres hashes de los bytes ejecutados sí coinciden exactamente con validacion.json y los adjuntos. HEAD posterior incorpora cierre documental. La prueba es local y no se presenta como una prueba de motor.<br>Realizada: [docs/evidencias/qa_u7_congelamiento.json](evidencias/qa_u7_congelamiento.json). git diff exit=0, working tree limpio, 3/3 archivos con el mismo contenido Git y SHA256 exactos de la ejecución; EJSON sólo cambia CRLF/LF frente al blob Git. |
| review_u5_c01/U5-C01-01 | El umbral fija una población concreta y podría divergir si se reutiliza el helper con otro conjunto de IDs.<br>Alcance: Propuesta de descarte como defecto del dataset histórico concreto, sujeta a corroboración agregada de IDs; el límite de reutilización se conserva. | descartado | La entrega histórica documenta 20.000 usuarios heredados y una cuenta sintética posterior. El umbral no es genérico, pero no se debe presentar como fallo ocurrido en esa población. Falta registrar aquí la comprobación agregada actual antes de cerrar definitivamente este descarte.<br>Pendiente: Verificar conteo y rango de los 20.000 usuarios heredados y que la cuenta sintética agregada por U5 está fuera del umbral; contrastar la huella heredada documentada. No publicar emails ni hashes de credenciales. |
| review_u5_c01/U5-C01-02<br>review_u5_c02/U5-C02-01<br>review_u5_c03/U5-C03-01 | Tres capas de precondiciones de logging parciales: ajuste de error, configuración por sesión y registro por duración.<br>Alcance: Robustez de seguridad condicionada; no demuestra una filtración histórica de U5. | aceptado | Se conservan los tres IDs y sus condiciones distintas. La parametrización impide interpolación SQL, pero no garantiza por sí sola que el servidor nunca registre valores. Las comprobaciones deberían incluir las vías y sesiones efectivamente usadas. Una prueba futura debe emplear exclusivamente centinelas sintéticos y guardar el diagnóstico privado.<br>Pendiente: Comparar pg_settings desde los logins usados antes de enviar parámetros; en una instancia descartable preparar los ajustes admitidos más logging de duración y registrar un centinela no secreto. Evaluar separadamente el control omitido de log_min_error_statement, sin tocar configuración de producción ni secretos. |
| review_u5_c01/U5-C01-03<br>review_u5_c05/U5-C05-01 | Una carpeta puede contener artefactos de una corrida fallida junto a un JSON anterior satisfactorio.<br>Alcance: Mejora de trazabilidad para reutilización; no invalida evidencias históricas con hashes y fechas comprobados. | aceptado | El fallo del proceso sí se comunica. El riesgo reside en consumir archivos aislados sin correlacionar la ejecución. Para procedimientos nuevos se propone una carpeta por corrida y un manifiesto final; no se altera ni se regenera retrospectivamente la evidencia U5. Se agrupa con U5-C01-03 por la vigencia de artefactos. El proceso sí rechaza coincidencias o errores, pero un consumidor no debe interpretar el JSON viejo como estado del intento nuevo. La mejora usa resultados por corrida y marcador final explícito.<br>Pendiente: Preparar una corrida sintética satisfactoria y una segunda que falle después de escribir un primer archivo; comprobar que los artefactos no deben tratarse como una unidad de éxito sólo por coexistir en el directorio. |
| review_u5_c02/U5-C02-02 | Una regresión de privilegios podría persistir la membresía justo cuando la prueba detecta el éxito indebido.<br>Alcance: Robustez de prueba negativa condicionada a permisos incorrectos; el intento histórico fue rechazado. | aceptado | Se debe distinguir el comportamiento correcto probado del catálogo actual de la contención ante una regresión. La comprobación detecta la anomalía, pero debería ensayarse con roles descartables y rollback para no dejar una concesión inesperada. No se propone conceder roles reales de negocio para probarlo.<br>Pendiente: En una transacción de prueba con roles sintéticos, permitir una operación equivalente y provocar el éxito que la prueba esperaba rechazar; comprobar desde otra conexión la persistencia o reversión. No cambiar membresías de los logins U5. |
| review_u5_c02/U5-C02-03 | Un helper de reset sin efecto podría superar esas aserciones positivas aunque conserve validaciones de entrada.<br>Alcance: Mejora de cobertura de pruebas; no afirma que la función real sea ineficaz. | aceptado | La función y los permisos originales tienen otras verificaciones, pero esas llamadas concretas no prueban el efecto de reset. La mejora propuesta es autenticar con el valor temporal dentro de la misma transacción y revertir todo, conservando únicamente el ID booleano de resultado.<br>Pendiente: Restablecer un valor aleatorio sintético válido y autenticar con él para verificar el ID esperado en límites de 12 y 72 bytes; terminar en rollback y no exportar contraseña ni hash. |
| review_u5_c03/U5-C03-02 | Un NOTICE con contenido sensible podría salir por una vía distinta del saneamiento de DatabaseError.<br>Alcance: Salida diagnóstica condicional; no se observó un NOTICE sensible en las evidencias históricas. | aceptado | El saneamiento de errores es un control presente y diferente. En helpers nuevos debe definirse una política explícita de avisos o capturarse su salida sólo en almacenamiento privado. No se atribuye una filtración real a partir de la mera ausencia del callback.<br>Pendiente: Con el cliente en un proceso controlado, emitir RAISE NOTICE con un marcador inocuo y capturar stderr; comprobar su presencia sin usar datos reales. Si se implementa callback ctypes, conservar su referencia durante toda la conexión. |
| review_u5_c03/U5-C03-03 | Determinadas entradas Markdown pueden perder asteriscos o sintaxis de enlaces en el PDF.<br>Alcance: Fidelidad condicionada a una entrada afectada; no acredita un defecto visual en el PDF U5 real. | aceptado | La mejora debe proteger primero los fragmentos de código y procesar el resto del marcado después. El informe histórico se conserva; no se necesita regenerarlo para aceptar una mejora del renderizador de uso futuro.<br>Pendiente: Renderizar una copia mínima con código en línea que contenga **literal** y [x](y); comparar el texto extraído y la imagen con la entrada literal, sin tocar el informe histórico. |
| review_u5_c03/U5-C03-04 | Un repositorio grande con muchos objetos pequeños puede superar un presupuesto razonable de memoria.<br>Alcance: Robustez ante repositorios mayores; no se demostró agotamiento en el ZIP U5 real. | aceptado | El empaquetador ya inspecciona objetos, credenciales, CRC, manifiesto y restauración Git. Esta observación propone un límite acumulado o procesamiento incremental, no niega esas garantías ni exige construir grandes archivos para validar un laboratorio pequeño.<br>Pendiente: Comprobar por inspección o inventario que no existe presupuesto acumulado antes de recuperar cuerpos; una prueba de mejora puede usar objetos sintéticos pequeños y un presupuesto de prueba reducido, evitando consumo excesivo. |
| review_u5_c04/U5-C04-02 | Puede notificarse un fallo aunque la solicitud de rotación haya sido procesada, porque el nombre tiene resolución de segundos.<br>Alcance: Robustez condicionada a colisión temporal; no acredita que haya sucedido en la captura histórica. | aceptado | El control de cambio de ruta es correcto para exigir una fuente cerrada. La mejora sería solicitar otra rotación al cruzar el segundo, dentro de un plazo acotado, no tomar pg_rotate_logfile()=true como prueba de cierre. Las evidencias originales se conservan.<br>Pendiente: Con el patrón de nombre por segundos, emitir rotaciones próximas y comparar pg_current_logfile; registrar por separado aceptación de solicitud y cambio real de ruta. No publicar contenido de los logs. |
| review_u5_c05/U5-C05-02 | La verificación se interrumpe ante ese estado del árbol de trabajo y no genera evidencia nueva.<br>Alcance: Diagnóstico de robustez para un árbol modificado; la entrega histórica se empaquetó con Git limpio. | aceptado | El proceso no produce un falso éxito. Puede rechazarse explícitamente ese estado con un diagnóstico claro, manteniendo el análisis del contenido todavía conservado en Git. No se interpreta como archivo perdido ni como defecto de la entrega U5 limpia.<br>Pendiente: Registrar un archivo sintético en Git y quitarlo sólo del directorio de trabajo; comprobar la interrupción controlada y no reutilizar un JSON anterior de éxito. No alterar repositorios o archivos históricos. |

## Trazabilidad por afirmación

### review_u5/H-01

Fuente: `tools/anonimizar_log.py`, líneas 165-166, 192-193; 239-250.

Afirmación de IA: Las sustituciones y comprobaciones literales de secretos no contemplan su representación escapada en JSON.

Respuesta original: [review_u5_respuesta.md](ia/review_u5_respuesta.md). Metadatos: [review_u5_metadatos.json](ia/review_u5_metadatos.json).

### review_u6/U6-01

Fuente: `backup_foodstore.ps1`, líneas 74-85.

Afirmación de IA: El dump se publica antes del manifiesto y un fallo posterior puede dejar un dump definitivo sin manifiesto.

Respuesta original: [review_u6_respuesta.md](ia/review_u6_respuesta.md). Metadatos: [review_u6_metadatos.json](ia/review_u6_metadatos.json).

### review_u6/U6-02

Fuente: `backup_foodstore.ps1; restore_test.ps1`, líneas 87-89; 124-127.

Afirmación de IA: Los catch conservan sólo la fase y descartan la causa de las excepciones locales.

Respuesta original: [review_u6_respuesta.md](ia/review_u6_respuesta.md). Metadatos: [review_u6_metadatos.json](ia/review_u6_metadatos.json).

### review_u6_c01/U6-C01-02

Fuente: `tools/ps_common.ps1`, líneas 34-38.

Afirmación de IA: Pg descarta stderr y registra únicamente el ejecutable y su código de error.

Respuesta original: [review_u6_c01_respuesta.md](ia/review_u6_c01_respuesta.md). Metadatos: [review_u6_c01_metadatos.json](ia/review_u6_c01_metadatos.json).

### review_u6/U6-03

Fuente: `tools/generar_informe_u6.py`, líneas 384-391, 406-409; contraste 293-307.

Afirmación de IA: La prosa Markdown se renderiza sin pasar por el mismo control de patrones sensibles usado para adjuntos.

Respuesta original: [review_u6_respuesta.md](ia/review_u6_respuesta.md). Metadatos: [review_u6_metadatos.json](ia/review_u6_metadatos.json).

### review_u6_c01/U6-C01-01

Fuente: `tools/opencode_consulta.py`, líneas 123-128, 202-204.

Afirmación de IA: Un fallo con respuesta parcial guarda answer_output, pero --retry-failed rechaza cualquier prefijo con ese archivo existente.

Respuesta original: [review_u6_c01_respuesta.md](ia/review_u6_c01_respuesta.md). Metadatos: [review_u6_c01_metadatos.json](ia/review_u6_c01_metadatos.json).

### review_u5_c04/U5-C04-01

Fuente: `tools/opencode_consulta.py`, líneas 123-128, 202-204.

Afirmación de IA: El reintento de una consulta fallida queda bloqueado si ya guardó una respuesta parcial.

Respuesta original: [review_u5_c04_respuesta.md](ia/review_u5_c04_respuesta.md). Metadatos: [review_u5_c04_metadatos.json](ia/review_u5_c04_metadatos.json).

### review_u6_c01/U6-C01-03

Fuente: `tools/opencode_consulta.py`, líneas 48-62, 197-202, 223-228.

Afirmación de IA: Una captura puede marcarse completed con texto válido, código cero y líneas no interpretables como JSON.

Respuesta original: [review_u6_c01_respuesta.md](ia/review_u6_c01_respuesta.md). Metadatos: [review_u6_c01_metadatos.json](ia/review_u6_c01_metadatos.json).

### review_u7/U7-01

Fuente: `consultas_mongodb.js`, líneas 78-94, especialmente 89-90.

Afirmación de IA: Si una inserción negativa fuese aceptada inesperadamente, el script falla pero deja esa escritura en la colección de laboratorio.

Respuesta original: [review_u7_respuesta.md](ia/review_u7_respuesta.md). Metadatos: [review_u7_metadatos.json](ia/review_u7_metadatos.json).

### review_u7/U7-02

Fuente: `tools/generar_informe.py`, líneas 186-188; 201-217.

Afirmación de IA: El generador toma HEAD como Commit de fuentes sin comprobar por sí mismo que los adjuntos coincidan con él.

Respuesta original: [review_u7_respuesta.md](ia/review_u7_respuesta.md). Metadatos: [review_u7_metadatos.json](ia/review_u7_metadatos.json).

### review_u5_c01/U5-C01-01

Fuente: `tools/ejecutar_anonimizacion.py`, líneas 75-76, 85-86, 94.

Afirmación de IA: La huella original abarca todos los usuarios heredados, pero la comprobación posterior usa id <= 20000.

Respuesta original: [review_u5_c01_respuesta.md](ia/review_u5_c01_respuesta.md). Metadatos: [review_u5_c01_metadatos.json](ia/review_u5_c01_metadatos.json).

### review_u5_c01/U5-C01-02

Fuente: `tools/crear_cuenta_prueba.py`, líneas 5-6, 17-18, 28-32.

Afirmación de IA: El helper sólo comprueba log_statement aunque su contrato también menciona log_min_error_statement.

Respuesta original: [review_u5_c01_respuesta.md](ia/review_u5_c01_respuesta.md). Metadatos: [review_u5_c01_metadatos.json](ia/review_u5_c01_metadatos.json).

### review_u5_c02/U5-C02-01

Fuente: `tools/ejecutar_pruebas.py`, líneas 116-138, 167, 229, 298, 332.

Afirmación de IA: Los ajustes de logging se comprueban desde bootstrap y no desde cada login que recibe parámetros sensibles.

Respuesta original: [review_u5_c02_respuesta.md](ia/review_u5_c02_respuesta.md). Metadatos: [review_u5_c02_metadatos.json](ia/review_u5_c02_metadatos.json).

### review_u5_c03/U5-C03-01

Fuente: `tools/instalar_seguridad.py`, líneas 22-26, 30-39.

Afirmación de IA: La precondición omite vías adicionales como log_min_duration_statement=0 con parámetros habilitados.

Respuesta original: [review_u5_c03_respuesta.md](ia/review_u5_c03_respuesta.md). Metadatos: [review_u5_c03_metadatos.json](ia/review_u5_c03_metadatos.json).

### review_u5_c01/U5-C01-03

Fuente: `tools/capturar_permisos.py; tools/ejecutar_anonimizacion.py`, líneas 82-101; 61-63, 85-89, 101-106.

Afirmación de IA: Las salidas con nombres reutilizados se publican por etapas y podrían mezclar intentos si una ejecución posterior falla.

Respuesta original: [review_u5_c01_respuesta.md](ia/review_u5_c01_respuesta.md). Metadatos: [review_u5_c01_metadatos.json](ia/review_u5_c01_metadatos.json).

### review_u5_c05/U5-C05-01

Fuente: `tools/verificar_privacidad.py`, líneas 25-65, especialmente 57-64.

Afirmación de IA: Si un intento falla antes de publicar el JSON nuevo, puede quedar el resultado passed:true de una ejecución anterior.

Respuesta original: [review_u5_c05_respuesta.md](ia/review_u5_c05_respuesta.md). Metadatos: [review_u5_c05_metadatos.json](ia/review_u5_c05_metadatos.json).

### review_u5_c02/U5-C02-02

Fuente: `tools/ejecutar_pruebas.py`, líneas 140-160, 256-259.

Afirmación de IA: El intento negativo de GRANT en phase_incident no tiene una contención transaccional explícita si inesperadamente tiene éxito.

Respuesta original: [review_u5_c02_respuesta.md](ia/review_u5_c02_respuesta.md). Metadatos: [review_u5_c02_metadatos.json](ia/review_u5_c02_metadatos.json).

### review_u5_c02/U5-C02-03

Fuente: `tools/ejecutar_pruebas.py`, líneas 344-345, 371-378.

Afirmación de IA: Las pruebas positivas de fn_resetear_password sólo verifican que la llamada devuelva una fila, no que la contraseña nueva autentique.

Respuesta original: [review_u5_c02_respuesta.md](ia/review_u5_c02_respuesta.md). Metadatos: [review_u5_c02_metadatos.json](ia/review_u5_c02_metadatos.json).

### review_u5_c03/U5-C03-02

Fuente: `tools/libpq_client.py`, líneas 115-167, 240-247, 253-301.

Afirmación de IA: El cliente no instala un receptor de NOTICE y libpq conserva su salida predeterminada a stderr.

Respuesta original: [review_u5_c03_respuesta.md](ia/review_u5_c03_respuesta.md). Metadatos: [review_u5_c03_metadatos.json](ia/review_u5_c03_metadatos.json).

### review_u5_c03/U5-C03-03

Fuente: `tools/generar_informe_pdf.py`, líneas 81-86.

Afirmación de IA: markup transforma negritas y enlaces antes de proteger código en línea y puede alterar literales dentro de backticks.

Respuesta original: [review_u5_c03_respuesta.md](ia/review_u5_c03_respuesta.md). Metadatos: [review_u5_c03_metadatos.json](ia/review_u5_c03_metadatos.json).

### review_u5_c03/U5-C03-04

Fuente: `tools/empaquetar_entrega.py`, líneas 84-101, 145-146.

Afirmación de IA: El límite se aplica por objeto Git, pero cat-file --batch acumula todos los objetos en memoria.

Respuesta original: [review_u5_c03_respuesta.md](ia/review_u5_c03_respuesta.md). Metadatos: [review_u5_c03_metadatos.json](ia/review_u5_c03_metadatos.json).

### review_u5_c04/U5-C04-02

Fuente: `tools/rotar_log.py; tools/preparar_laboratorio.py`, líneas 12-23; 200.

Afirmación de IA: Dos rotaciones procesadas dentro del mismo segundo pueden mantener la misma ruta de log y el helper sólo espera que cambie.

Respuesta original: [review_u5_c04_respuesta.md](ia/review_u5_c04_respuesta.md). Metadatos: [review_u5_c04_metadatos.json](ia/review_u5_c04_metadatos.json).

### review_u5_c05/U5-C05-02

Fuente: `tools/verificar_privacidad.py`, líneas 46-48.

Afirmación de IA: Un archivo rastreado eliminado sólo del directorio de trabajo sigue listado por git ls-files y read_bytes provoca FileNotFoundError.

Respuesta original: [review_u5_c05_respuesta.md](ia/review_u5_c05_respuesta.md). Metadatos: [review_u5_c05_metadatos.json](ia/review_u5_c05_metadatos.json).

## Límites del cierre actual

- Hay 23 IDs originales, agrupados en 18 filas por coincidencia de flujo o capas complementarias. Todos conservan su consulta/ID, afirmación y decisión propuesta; ninguno se pierde.
- Todas las filas tienen decisión técnica propuesta; 17 comprobaciones nuevas de regresión siguen pendientes en esta matriz técnica y se identifican como tales. La matriz final de U8 debe incorporar sus pruebas o delimitar lo aceptado como observación residual.
- La comprobación Git/SHA256 de U7 es real y local; no satisface por sí sola el requisito de desarrollar tres hallazgos comprobados en base de datos. La matriz final U8 debe incorporar esas pruebas de los motores.
- Los cambios preparatorios y pruebas futuras deben realizarse en copias; no se alteran scripts, bases ni evidencias históricas de U5/U6/U7.
- No se fuerza un descarte: U7-02 se descarta como discrepancia efectiva de esta entrega porque la condición no ocurre y se conserva prueba independiente. La recomendación genérica del generador sigue siendo válida.

La introducción de `review_u5_c04` dice seis archivos, pero su tabla y el adjunto contienen cinco. QA contrastó los cinco nombres contra el manifiesto y conservó esta observación sin alterar la respuesta original. No hay una sexta fuente ni material omitido.

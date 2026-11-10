## 1. Inventario Completo

El adjunto está completo: los tres archivos tienen cierre visible. Las referencias siguientes son **líneas relativas a cada archivo saneado**, incluidos sus dos comentarios iniciales, no líneas del Markdown contenedor.

| Archivo recibido | Alcance revisado | Estado |
|---|---|---|
| `tools/opencode_consulta.py` | Argumentos, rutas, conservación del prompt y adjuntos, invocación de OpenCode, timeout, extracción de respuesta, reintentos y metadatos. | Revisión estática completa. Un defecto en el reintento de consultas fallidas y una mejora de robustez en la clasificación del resultado. |
| `tools/ps_common.ps1` | Entorno PostgreSQL, logging, archivos exclusivos, controles de privacidad, ejecución nativa, validación de baseline, aislamiento, versiones y selección/verificación del respaldo. | Revisión estática completa. Se confirma descarte de stderr en el auxiliar `Pg`, con impacto diagnóstico. El selector no considera dumps huérfanos. |
| `validaciones.sql` | Restricción de base destino, transacción y snapshot, configuración de sesión, conteos, fingerprints, controles de valores inválidos y salida JSON. | Revisión estática completa. Sin defecto demostrable en el alcance recibido y bajo las restricciones del modelo indicadas. |

No ejecuté herramientas, comandos ni pruebas; tampoco modifiqué archivos.

## 2. Hallazgos

Prioridades: **P2**, problema funcional o diagnóstico relevante; **P3**, mejora de robustez.

| ID | Prioridad / tipo | Archivo y líneas relativas | Condición concreta | Consecuencia | Certeza | Prueba mínima propuesta |
|---|---|---|---|---|---|---|
| U6-C01-01 | P2 · Defecto demostrable | `tools/opencode_consulta.py:123-128, 202-204` | Una ejecución produce texto de respuesta, pero termina con código distinto de cero, un evento `error` o timeout. Se escribe `answer_output` aunque el estado sea `failed`. En la siguiente invocación, `--retry-failed` rechaza cualquier caso donde ya exista ese archivo. | Una consulta fallida con respuesta parcial no puede reintentarse bajo el mismo prefijo, aunque la opción se presenta como reintento de consultas fallidas. Solo funciona para fallos sin respuesta guardada. | Confirmado por el flujo del código; no requiere atribuir un comportamiento específico al servicio. | **Local:** usar un ejecutable simulado que responda correctamente a `--version` y, en la consulta, emita un evento `text` válido y termine con código 1. Verificar estado `failed`, archivo de respuesta existente y rechazo posterior con `--retry-failed`. |
| U6-C01-02 | P2 · Defecto diagnóstico demostrable | `tools/ps_common.ps1:34-38` | Un cliente ejecutado mediante `Pg` informa el motivo del fallo por stderr. La invocación usa `2>$null`; después solo registra nombre del ejecutable y código de salida. | Se pierde ese diagnóstico dentro de este flujo. Un fallo de autenticación, conexión o restauración puede quedar documentado únicamente mediante su código y la fase registrada por el llamador. No causa por sí mismo un falso éxito: el código no cero genera una excepción. | El descarte es confirmado. El efecto sobre cada script llamador depende de sus mecanismos adicionales de diagnóstico, no recibidos en esta continuación. | **Local:** simular un cliente que escriba un marcador no sensible en stderr y termine con código 1. Comprobar que se registra el código y se lanza excepción, pero no se conserva el marcador. Una corrección debería retener el diagnóstico únicamente en almacenamiento privado. |
| U6-C01-03 | P3 · Mejora de robustez | `tools/opencode_consulta.py:48-62, 197-202, 223-228` | La salida contiene una respuesta de texto válida, código cero y además líneas no interpretables como eventos JSON. `parse_events` las detecta, pero `successful` no considera `invalid`. | Los metadatos pueden indicar `completed` aunque el flujo capturado tenga líneas sin interpretar. El contador expone la anomalía, pero el estado no distingue ese caso de una captura completamente interpretable. | Conducta confirmada; que las líneas descartadas representen pérdida relevante de evidencia es condicionado. No toda línea no JSON implica una consulta fallida. | **Local:** simular una respuesta de texto válida más una línea no JSON y código cero. Verificar `completed` con `unparsed_line_count > 0`; definir si la política debe rechazarlo o marcarlo para revisión. |

### Controles Reconocidos

- **Los dumps huérfanos no producen éxito por sí solos.** `Read-BackupManifest`, líneas 95-126, enumera archivos `*.manifest.json`, filtra por estado `SUCCESS` y recién después localiza el dump referenciado. Publicar un dump antes del manifiesto no basta para que el selector lo acepte.
- El respaldo elegido se comprueba mediante nombre permitido, tamaño, SHA-256, baseline y lectura con `pg_restore --list`. Esta última verifica que se pueda leer el índice del archivo; no demuestra una restauración íntegra.
- Si el manifiesto exitoso más reciente resulta inválido, el selector falla: no sustituye silenciosamente ese respaldo por otro anterior. Es una política conservadora, no un falso éxito.
- `Pg` comprueba el código de salida y lanza una excepción. El hallazgo diagnóstico no implica que se ignoren fallos nativos.
- El wrapper conserva snapshots de adjuntos y rechaza contenido diferente en una ruta de snapshot existente. También registra errores, timeout, hashes y ausencia de aprobación humana.
- `validaciones.sql` usa una única transacción `REPEATABLE READ READ ONLY`, nombres de tablas calificados y configuración explícita de zona horaria y `DateStyle`. Advierte correctamente que esa transacción no sincroniza por sí sola el baseline con el snapshot del dump.

## 3. Límites y Dependencias

- **Continuación, no revisión integral independiente.** No están aquí los scripts principales de backup/restauración, health, maintenance ni el generador. Sus garantías deben evaluarse junto con la primera revisión; no doy por comprobada su integración.
- **Consistencia baseline/dump:** depende de que el orquestador impida escrituras durante el intervalo correspondiente o comparta un snapshot exportado. El SQL declara expresamente esa dependencia; no es un fallo confirmado de este archivo.
- **Aislamiento:** `Assert-Isolation` comprueba el límite de conexiones y privilegios efectivos de los roles indicados sobre base, esquemas y funciones de usuario. No acredita por sí solo ausencia de sesiones existentes ni contención de superusuarios. Su suficiencia depende de los roles y pasos del orquestador.
- **Modelo SQL:** se asumen las restricciones `NOT NULL` documentadas y claves que hagan determinista el orden de los fingerprints. Sin DDL no corresponde afirmar que esas condiciones falten.
- **Privacidad y entorno:** `Assert-Private` incorpora controles de ACL, reparse points y ancestros con `.git`. No equivale a una garantía universal frente a modificaciones concurrentes o frente a cualquier mecanismo posible de entrega. Se mantiene el requisito declarado de PowerShell 7.5+ para `-DateKind String`.
- **Alcance de la evidencia:** los checksums son controles de conservación, no anonimización ni firma; los resultados de RTO/RPO son pruebas de laboratorio, no SLA. Esta revisión estática no acredita ejecuciones históricas ni aprobación humana.

El último archivo completamente visible es `validaciones.sql`. No se identifican defectos atribuibles a placeholders de saneamiento.

**La revisión sólo puede ser parcial: el adjunto visible está truncado.** El contenido termina en la línea 1125 del Markdown, dentro de `tools/capturar_permisos.py`, con el aviso `Output capped at 50 KB`. Hay siete archivos completos y el comienzo de un octavo. No es posible inventariar ni revisar los archivos posteriores del bundle, incluidos los verificadores, el empaquetador, el generador de informe y la preparación del laboratorio que mencionás.

No ejecuté comandos, no utilicé herramientas y no modifiqué archivos. Las conclusiones siguientes corresponden exclusivamente al texto visible; no acreditan las pruebas históricas.

## 1. Inventario Disponible

Las rutas de esta sección son relativas a `outputs/Arancibia_Romero_U5/food-store-tp-u5/`. Las líneas indicadas más adelante son relativas a cada archivo, contando como línea 1 el primer comentario de la copia saneada.

| Archivo | Revisión realizada | Estado |
|---|---|---|
| `sql/auditoria_test.sql` | Revisé la parametrización, la secuencia de operaciones sobre pedido y detalle, la comprobación del total y el cierre por `ROLLBACK`; el archivo delega correctamente la ejecución y las comprobaciones de resultados al cliente. | **Sin hallazgo demostrable en el archivo completo visible.** No acredita por sí mismo que el cliente compruebe todas las condiciones. |
| `sql/configurar_auditoria.sql` | Revisé las opciones de registro, la supresión de parámetros y la recarga de configuración, considerando la verificación posterior implementada por `activar_auditoria.py`. | **Sin hallazgo demostrable.** La cobertura de privacidad tiene límites indicados abajo. |
| `sql/roles.sql` | Revisé precondiciones, roles y membresías, transferencia de ownership, limpieza de ACL de tabla y columna, funciones `SECURITY DEFINER`, permisos auxiliares y privilegios por defecto. | **Sin hallazgo demostrable con el contexto visible.** Algunas propiedades de los triggers heredados requieren las definiciones que aquí no aparecen. |
| `sql/simulacro_incidente.sql` | Revisé la separación entre conexión de prueba y verificadora, autenticación parametrizada, lectura masiva, intento de escalamiento y comprobación de membresía. | **Sin hallazgo demostrable.** La orquestación y las aserciones quedan pendientes de revisar en el cliente no visible. |
| `sql/usuario_anon.sql` | Revisé reconstrucción transaccional, rol creador efectivo, datos sintéticos, equivalencia agregada, comparación bidireccional y aborto ante diferencias. | **Sin hallazgo funcional demostrable.** Hay una limitación de desvinculación de identidades que se explica abajo. |
| `tools/activar_auditoria.py` | Revisé ejecución fuera de transacción, lectura del SQL estático, reintentos con conexiones nuevas y generación del registro de configuración. | **Sin hallazgo demostrable en este helper.** No pude revisar la implementación de `Connection`. |
| `tools/anonimizar_log.py` | Revisé interpretación de entradas, selección de sesiones, inventario de secretos, sustituciones, controles finales, restricciones de rutas, hashes y escritura del informe. | **Hallazgo H-01:** las sustituciones y comprobaciones de secretos no contemplan su representación escapada en JSON. |
| `tools/capturar_permisos.py` | Sólo son visibles las importaciones, los nombres de roles y el inicio de las consultas de atributos y permisos de tabla. | **No evaluable como archivo completo.** El fragmento no permite revisar captura, tratamiento de errores ni artefactos finales. |

**Archivos restantes:** su inventario, contenido y estado no son determinables con el adjunto visible. No asigno “sin hallazgo” a archivos que no pude revisar.

## 2. Hallazgos Reales

| ID | Prioridad | Archivo y líneas relativas | Fragmento o condición concreta | Consecuencia | Certeza | Prueba mínima propuesta, no ejecutada |
|---|---|---|---|---|---|---|
| H-01 | P2, media | `tools/anonimizar_log.py:165-166, 192-193`; entrada sin decodificar en `239-250` | Los secretos se eliminan con `text.replace(secret, ...)` y se verifican mediante `secret in text`. El saneamiento opera sobre el JSON serializado, aunque `_metadata()` sí reconoce ese formato. Un secreto con comillas, barras inversas o caracteres representados como escapes puede no aparecer literalmente en el texto, pero seguir íntegro en el valor JSON decodificado. | El archivo “saneado” puede conservar una credencial recuperable y el informe declarar `secret_scan_passed: True`. También pueden quedar en cero los conteos de secretos conocidos, ocultando esa presencia al revisor. | **Defecto demostrable del algoritmo.** Su ocurrencia en las evidencias históricas depende de los secretos y mensajes efectivamente registrados; no está acreditada aquí. | Construir un evento con `json.dumps({"message": 'diagnostic credential=AB"CD\\EF'})`; pasar a `sanitize()` el secreto exacto `AB"CD\EF`, representado correctamente como cadena de Python, y un mapa de redacciones vacío. Comprobar si el informe pasa y si `json.loads(resultado)["message"]` todavía contiene el secreto original. |

**Alcance de H-01.** No afirmo que PostgreSQL haya registrado contraseñas durante las pruebas. La supresión de parámetros reduce precisamente esa posibilidad. El problema afecta la garantía del saneador cuando un secreto conocido sí está presente en una representación escapada, por ejemplo dentro de un mensaje JSON.

La exigencia de revisión manual es un control adicional válido, pero no vuelve correcto el resultado automático `secret_scan_passed`. Una corrección posterior debería tratar los valores JSON decodificados y conservar una serialización válida, sin perder la correlación y el orden de los eventos. No corresponde alterar las evidencias históricas originales para corregir este helper.

## 3. Controles Y Condiciones

Los siguientes puntos **no son hallazgos confirmados adicionales**. Los separo para evitar convertir limitaciones expresas o dependencias no visibles en defectos.

### Roles Y Funciones

- **La separación de propietarios está implementada.** Las tablas quedan en `rol_propietario`; las cuatro funciones privilegiadas quedan en `rol_funciones`, sin conceder esas membresías a los logins de negocio.
- **Las membresías tienen restricciones explícitas.** `WITH INHERIT TRUE, SET FALSE, ADMIN FALSE` permite heredar los permisos de negocio sin habilitar su administración ni `SET ROLE` a esos grupos. No observo una escalada por esas concesiones.
- **Se limpian las dos capas de ACL.** El bloque de columnas complementa los `REVOKE` de tabla; no corresponde denunciar persistencia de privilegios por columna ignorando ese bloque.
- **El contexto de las funciones privilegiadas está protegido.** Usan `SET search_path = pg_catalog`, califican los objetos de negocio y restringen los permisos auxiliares. El `MAINTAIN` sobre la vista materializada es un privilegio disponible en PostgreSQL 17, no un error por ausencia de ownership.
- **Los privilegios por defecto contemplan el creador efectivo.** Se revoca globalmente el `EXECUTE` público de funciones y se incluyen revocaciones por esquema. `usuario_anon.sql` usa `SET LOCAL ROLE rol_propietario`, por lo que el default de lectura de `datos_anon` corresponde al creador real.
- **`u5_bootstrap` sigue siendo superusuario.** El propio SQL lo reconoce. Retirar sus entradas ACL no pretende limitar su capacidad efectiva; no es una vulnerabilidad adicional demostrada.
- **La integridad concurrente del total no puede resolverse aisladamente.** El recálculo mediante `SUM` exige considerar la serialización y el orden de los triggers. El bundle visible verifica la existencia de `u4_serializar_ventas()`, pero no muestra su cuerpo ni sus enlaces. Antes de atribuir una carrera habría que revisar ese control y proponer una prueba con dos conexiones modificando detalles del mismo pedido.
- **Las reglas de estados y stock dependen del esquema heredado.** Los permisos de escritura no bastan para demostrar que se pueden alterar pedidos confirmados o vulnerar el stock. Están referenciados validadores heredados cuyos cuerpos y enlaces no son visibles.

### Auditoría Y Pruebas

- **La recarga no se toma como prueba suficiente.** `activar_auditoria.py` abre conexiones nuevas y reintenta hasta observar los valores esperados. No hay base para denunciar que sólo se confía en `pg_reload_conf()`.
- **La supresión de parámetros no es una garantía universal de secreto.** `log_statement='all'` puede registrar credenciales escritas directamente como literales SQL. Los catálogos visibles exigen parámetros y el simulacro también verifica la configuración antes de enviarlos. Queda pendiente revisar que el cliente realmente respete ese contrato.
- **Los errores pueden incluir información fuera de los parámetros.** Un `DETAIL` de restricciones o un contexto de error puede contener valores. El saneador exige revisión manual y admite redacciones privadas; no demuestra ausencia de todos los datos personales.
- **El SQL de auditoría no es una prueba concurrente ni de rendimiento.** Su comprobación del total es válida para la transacción del escenario, pero no acredita invariantes ante intercalaciones entre sesiones. No exige esa capacidad ni afirma tenerla.
- **El simulacro distingue correctamente lectura de exfiltración.** Los comentarios no atribuyen al log nativo el conteo de filas recibidas ni una transferencia fuera del laboratorio.
- **La división por `;` en `activar_auditoria.py` es suficiente para el archivo visible.** Todas sus sentencias son simples y estáticas. Sería frágil si ese archivo incorporara bloques con punto y coma internos, pero esa condición no se presenta aquí.

### Copia Y Logs

- **La equivalencia agregada tiene una aserción efectiva.** No depende sólo de mostrar dos consultas: el `EXCEPT ALL` en ambos sentidos alimenta una tabla temporal y cualquier diferencia aborta la transacción.
- **El `folio` no garantiza desvinculación irreversible.** Se obtiene ordenando por el `id` original. Quien tenga acceso a la misma población original puede reconstruir esa correspondencia. Esto importa si después se pretende declarar anonimización irreversible; no demuestra incumplimiento del objetivo visible de copia académica con identificadores sintéticos.
- **Los grupos pequeños pueden facilitar inferencias.** Conservar mes de alta y estado de eliminación no garantiza anonimato frente a conocimiento auxiliar. No se ve un requisito de umbral mínimo de grupo, por lo que no lo convierto en defecto de esta entrega.
- **La correlación por PID está reconocida como más débil.** Sin identificadores de sesión, un log suficientemente largo puede incluir reutilización de PID. El informe lo declara y pide revisar la selección; sólo sería un problema efectivo si se comprobara esa reutilización en el archivo procesado.
- **El SHA-256 no autentica la evidencia histórica.** Permite identificar bytes y verificar la escritura; no acredita procedencia ni ausencia de alteraciones anteriores. El helper declara expresamente esa limitación.

## 4. Límites De La Revisión

1. **No se revisó todo el bundle.** La interrupción dentro de `capturar_permisos.py` impide cumplir el alcance exhaustivo solicitado. Ésta es una limitación material, no una conclusión favorable sobre los archivos ausentes.
2. **No hubo ejecución ni pruebas locales.** H-01 se deriva del tratamiento de cadenas; la prueba propuesta queda pendiente.
3. **No se inspeccionaron el motor, las ACL efectivas, los logs ni las evidencias históricas.** Los comentarios sobre resultados esperados no se trataron como resultados obtenidos.
4. **No están disponibles las implementaciones de `Connection`, la carga de secretos ni la orquestación de pruebas.** No puede concluirse sobre parametrización real, transacciones, cierre de conexiones, exposición de errores o restauración segura del entorno.
5. **Faltan las definiciones heredadas de tablas, vistas y triggers.** No puede confirmarse integridad concurrente, cobertura de validadores ni comportamiento de restauración únicamente a partir de sus nombres.
6. **Los placeholders no se interpretaron como defectos ni como credenciales reales.** Tampoco se equipararon las rutas y cuentas del laboratorio con producción.

**Resultado para decidir:** hay un defecto concreto identificado en el saneador y varios controles correctamente presentes en los siete archivos completos visibles. Esta revisión **no permite cerrar la revisión integral de Unidad 5 para Unidad 8**, porque no incluye el resto del adjunto. Para completarla se necesita únicamente la continuación saneada desde la línea 1126 del Markdown, no archivos privados.

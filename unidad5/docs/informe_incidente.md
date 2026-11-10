# Parte C. Simulacro y reconstrucción del incidente

**Ejecución técnica comprobada. Contraste automático con Codex y decisión de
contención del ejercicio documentada; conformidad de cierre expresada por el
usuario con el alcance registrado en [validacion_humana.md](validacion_humana.md).**

El simulacro se realizó únicamente contra la copia propia de Food Store en
PostgreSQL 17.11. La ejecución del cliente abarcó el 22/10/2026 entre
19:45:52.288 y 19:45:52.923 UTC. El log seleccionado corresponde a la sesión
`6ada67f0.ee4`, PID 3812, desde `127.0.0.1:60572`, entre
16:45:52.418 y 16:45:52.923 UTC−03.

## 1. Secuencia diseñada y ejecutada

`sql/simulacro_incidente.sql` define las consultas parametrizadas y
`tools/ejecutar_pruebas.py --phase incident` las ejecutó mediante conexiones
reales. La conexión de aplicación utilizó `app_web`; otra conexión verificadora
obtuvo conteos y membresías sin proporcionar sus resultados a la IA.

1. Se estableció una conexión PostgreSQL válida con SCRAM. Esta autenticación del
   motor es anterior y distinta de las llamadas a `fn_autenticar`.
2. Se llamó tres veces a `fn_autenticar` con el mismo usuario comercial sintético
   y contraseñas de prueba incorrectas, seguidas de una llamada con la credencial
   correcta. Los valores se enlazaron con `PQexecParams`; permanecieron fuera del
   SQL, el log entregado y el repositorio.
3. Se ejecutó realmente `SELECT id,nombre,apellido,eliminado,created_at FROM public.usuario ORDER BY id`.
   El cliente recibió 20.001 filas, verificó las
   cinco columnas y descartó sus valores. No se seleccionó `contrasena` ni se
   exportaron filas de usuarios.
4. Desde esa misma conexión de `app_web` se intentó
   `GRANT admin_datos TO app_web`. La conexión terminó después del rechazo.

La lectura está permitida por las ACL diseñadas para el laboratorio. El ejercicio
reproduce una secuencia que requiere investigación en un entorno real; por sí
sola no demuestra una vulneración de permisos ni una intención maliciosa.

## 2. Verificación del intento de escalamiento

El servidor rechazó el GRANT con SQLSTATE **42501**: `app_web` no posee la opción
ADMIN sobre `admin_datos`. El evento 16 del log conserva el error y la sentencia
asociada; el evento 15 conserva el intento.

La conexión separada `u5_verifier_incident` comprobó que la membresía en
`admin_datos` era falsa antes y después. El cliente también confirmó que
`session_user` y `current_user` seguían siendo `app_web` tras la autenticación de
negocio. Estas comprobaciones están en
[incident_resultados.json](evidencias/incident_resultados.json): once eventos,
estado `passed`. No se presenta un mensaje de éxito de `fn_autenticar` como una
elevación del rol PostgreSQL.

## 3. Extracción y anonimización del log real

Se seleccionó la aplicación exacta `u5_incident` dentro de la ventana UTC del
cliente, convirtiendo las marcas del log desde UTC−03. Luego se conservaron
**todos** los eventos de su sesión: `line_num` 1 a 17, incluida la conexión
inicial, que aún no contiene nombre de aplicación, y la desconexión final.

El archivo entregado es
[log_simulacro_anonimizado.txt](log_simulacro_anonimizado.txt), con un objeto JSON
válido por línea. Se sustituyeron el nombre de la base por `foodstore_lab` y el
usuario de las rutas Windows por `USR_LOCAL`; se conservaron horarios, PID,
sesión, roles, origen local y códigos de error. Los escaneos de secretos,
credenciales y correos y la inspección automática del contenido no detectaron
valores personales o contraseñas en el fragmento entregado.

Su SHA-256 es
`f30499043574aca7554877e118b1f21f8a804740cdbe2039c32f3f3a2b0d162b`.
La trazabilidad de la fuente privada, la selección y las transformaciones está en
[logs_procedencia.json](evidencias/logs_procedencia.json) y
[c_anonimizacion_scan.json](evidencias/c_anonimizacion_scan.json). El original
privado no integra el repositorio. Esta revisión automática no certifica
anonimización irreversible ni sustituye la revisión humana.

## 4. Consulta real a OpenCode sin contexto adicional

Se consultó OpenCode 1.18.23 con el modelo solicitado `openai/gpt-6.1-sol`, agente
`plan` y permisos de herramientas denegados. La consulta se realizó entre
19:49:50.902117 y 19:50:27.880495 UTC. Su único adjunto fue una copia exacta del
log anonimizado: no se adjuntaron el guion, los resultados del cliente, los
conteos, los controles de membresía ni este informe.

El [prompt conservado](ia/c_reconstruccion_prompt.txt) pidió reconstruir la
cronología, distinguir hechos de hipótesis y proponer una contención que una
persona evaluara antes de actuar. Los
[metadatos](ia/c_reconstruccion_metadatos.json) registran la consulta real y el
hash del único adjunto, idéntico al archivo entregado. OpenCode no ejecutó
herramientas ni SQL durante esta consulta.

## 5. Contraste de la reconstrucción con lo ejecutado

La reconstrucción no presentó errores factuales detectables en el contraste.
La IA separó lo visible en el log de las hipótesis y las comprobaciones
externas; la tabla siguiente identifica sus aciertos y las cuestiones que
únicamente resuelve la evidencia complementaria del cliente.

| Reconstrucción de OpenCode | Contraste con la evidencia y el cliente | Evaluación |
|---|---|---|
| Una sesión de `app_web`, origen local, SCRAM y aplicación declarada `u5_incident`. | Eventos 1–4; el cliente confirma rol de sesión y rol efectivo `app_web`. | Correcto; no atribuye una persona al rol. |
| Tres resultados `success=f` y luego uno `success=t`. | Eventos 6, 8, 10 y 12; el cliente obtiene NULL tres veces y el identificador esperado en la cuarta. | Correcto; la IA no puede saber por el log si se usó la misma cuenta. El guion sí lo confirma. |
| El SELECT solicita cinco columnas y no tiene WHERE; no prueba entrega ni cantidad de filas. | Evento 14; el cliente recibió y descartó 20.001 filas. | Correcto. No mencionar 20.001 es un límite del registro, no una omisión errónea. |
| La segunda consulta de identidades no muestra sus resultados. | Evento 13; el cliente confirma que los roles permanecieron iguales. | Correcto; la comprobación externa complementa el log. |
| GRANT rechazado con 42501; el fragmento no revela membresías anteriores. | Eventos 15–16; el verificador independiente obtuvo membresía falsa antes y después. | Correcto. Ese estado no fue adjuntado a la IA. |
| No demuestra fuerza bruta, exfiltración, compromiso ni intención maliciosa. | El guion era un laboratorio autorizado; no hubo exportación de filas ni contención automática. | Lectura prudente y coherente con el alcance disponible. |
| La conexión ya terminó y no corresponde terminar esa sesión cerrada. | Evento 17: duración informada de 0,511 segundos. | Correcto; la propuesta de restringir futuras conexiones es condicional. |

La hipótesis de exploración de datos e intento de obtener membresía es compatible
con la secuencia, pero no establece su intención. Tampoco se puede inferir un
origen externo a partir de `127.0.0.1`. Las correcciones reales de otras consultas
de IA se documentan donde ocurrieron; no se atribuye a esta reconstrucción un
error inexistente.

## 6. Decisión de contención del ejercicio

**La decisión del ejercicio es preservar la evidencia, verificar el alcance y
condicionar cualquier restricción a la confirmación de un incidente y a la
evaluación de impacto; ninguna medida de contención fue ejecutada.** Esta
conclusión se presentó al usuario junto con la explicación de A–E, tras lo cual
pidió «bien entonces enviame el zip listo para entregar asi lo subo a la
plataforma». Su pedido expresa conformidad con el cierre de la entrega, sin
establecer una revisión exhaustiva del PDF ni una corrección técnica humana;
el alcance se conserva en [validacion_humana.md](validacion_humana.md).

En un caso real, primero se preservarían los logs con acceso restringido y se
verificarían la autorización de la actividad, el componente que usa `app_web`,
el alcance de la lectura y el estado actual de sus privilegios y sesiones. La
conservación de evidencia precede a cambios que puedan dificultar reconstruir lo
ocurrido.

Solo si esa revisión confirma un incidente, la persona responsable evaluaría
suspender temporalmente la credencial de `app_web` y sus sesiones activas
relacionadas, considerando el impacto sobre los servicios. Se rotarían únicamente
los secretos comprometidos o cuya confidencialidad ya no pueda sostenerse, con
revisión posterior de acceso y monitoreo.

No se propone bloquear `127.0.0.1` como si fuera un atacante remoto ni revocar una
membresía en `admin_datos` que las pruebas comprobaron inexistente. La sesión del
fragmento ya estaba cerrada. El apagado posterior del servidor privado fue un
cierre rutinario del laboratorio realizado por su operador, separado de la
respuesta de OpenCode; no constituye ejecución de una contención sugerida por IA.

## Apéndice. Reconstrucción completa y evidencia enlazada

La [respuesta íntegra recibida de OpenCode](ia/c_reconstruccion_respuesta.md) se
entrega sin modificaciones en el repositorio; este informe solo la contrasta.
Se conservan también el [prompt](ia/c_reconstruccion_prompt.txt), los
[metadatos originales](ia/c_reconstruccion_metadatos.json) y la
[copia exacta del único adjunto enviado](ia/c_reconstruccion_adjuntos/01_log_simulacro_anonimizado.txt).
El [resultado del cliente](evidencias/incident_resultados.json) y la
[procedencia de los logs](evidencias/logs_procedencia.json) permiten reproducir la
validación externa y distinguirla del material que efectivamente vio la IA.

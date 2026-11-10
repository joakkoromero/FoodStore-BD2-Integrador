# Continuidad del proyecto y alcance de Unidad 5

## Base heredada

La resolución utiliza Food Store de Exequiel Arancibia y Joaquin Romero y conserva la continuidad de los trabajos anteriores. El laboratorio U5 utiliza PostgreSQL 17.11. Su copia privada tiene como punto de partida la base acumulativa U4, con las cinco tablas de negocio originales en `public` y estas cantidades anteriores al alta de la cuenta U5:

| Tabla | Filas heredadas de U4 |
| --- | ---: |
| `categoria` | 2 |
| `producto` | 50.000 |
| `usuario` | 20.000 |
| `pedido` | 225.000 |
| `detalle_pedido` | 499.997 |

La trazabilidad del modelo es la siguiente:

| Antecedente | Continuidad conservada |
| --- | --- |
| TP1 | Tablas, PK/FK, baja lógica, identificadores BIGINT, tipos de estado/pago, precio histórico y subtotal calculado. |
| TP2 | Transiciones de pedido y validación que permite editar detalles solo en pedidos PENDIENTE; recálculo del total. |
| TP3 y TP4 | Carga masiva, respaldo y optimizaciones del proyecto anterior. |
| TP5 | Índices y vistas, incluida la materializada mensual por categoría. |
| Unidad 4 | Descomposición FNBC del control de lotes, su vista compatible, guardia de unicidad y materializada diaria con sincronización transaccional. |

Los respaldos de la cadena de reconstrucción se identifican por hashes diferentes:

| Respaldo | SHA-256 verificado |
| --- | --- |
| Original pre-TP4 | `f53af18eac3da8de40114f63daaea8ccddae528db688b68e6740c8e31fc01871` |
| Copia acumulativa U4 usada para preparar U5 | `47e528484609b85dd3076eda5d7c36180218192c024ae00475b0219d4708251e` |

Los índices/vistas de TP4-TP5 y las incorporaciones U4 completaron el estado acumulativo desde el cual se preparó la copia U5. El hash identifica cada archivo sin publicar su contenido.

El respaldo privado de entrada U5 permanece en el espacio de ejecución externo al repositorio. No se lo incorpora al repositorio ni al ZIP, ni se publican rutas privadas del usuario. Quien reconstruya necesita disponer privadamente de una copia equivalente, indicarla mediante `--source-dump` y mantenerla fuera de Git.

## Alta sintética comprobada

Se ejecutó el alta de una cuenta comercial de laboratorio en la tabla `public.usuario` existente. No se recreó el maestro ni se convirtieron las contraseñas heredadas de demostración en nuevas claves. El alta usa un correo sintético y una clave aleatoria privada; `pgcrypto`, instalado en `crypto`, genera el hash para comprobar autenticaciones de esta cuenta.

Los resultados publicados en [continuidad_verificada.json](continuidad_verificada.json) son:

| Control | Resultado |
| --- | --- |
| Usuarios heredados | 20.000 |
| Cuenta sintética agregada | 1 |
| Usuarios totales posteriores | 20.001 |
| Huella de los usuarios heredados antes | `10d08c7a44644392c7cfd0f68827c270` |
| Huella de los usuarios heredados después | `10d08c7a44644392c7cfd0f68827c270` |

El control ordena los registros y compara una huella MD5 de sus filas completas, excluyendo del conjunto posterior la cuenta agregada. La coincidencia es la evidencia de conservación obtenida en este laboratorio; no constituye una técnica de anonimización. La evidencia pública no contiene filas personales, correo de la cuenta, contraseñas ni hashes de contraseñas.

## Parte D inicial y reconstrucción final bajo el propietario correcto

La primera ejecución de D se realizó el 21/10/2026 con el administrador técnico de bootstrap, durante la espera de Kiro. Se conserva como antecedente en [d_bootstrap_equivalencia.json](evidencias/d_bootstrap_equivalencia.json) y [d_bootstrap_ejecucion_psql.txt](evidencias/d_bootstrap_ejecucion_psql.txt). Ese resultado inicial no se usa para atribuir permisos a roles que todavía no se habían implementado.

Después de aplicar A se repitió D el **22/10/2026 a las 16:46:53, UTC-03**. El SQL final ejecuta `SET LOCAL ROLE rol_propietario` dentro de la transacción; la tabla reconstruida tiene ese propietario y el permiso SELECT efectivo de `rol_reportes` quedó comprobado. [d_equivalencia.json](d_equivalencia.json), [d_ejecucion_psql.txt](d_ejecucion_psql.txt) y [d_resultados_lado_a_lado.md](d_resultados_lado_a_lado.md) acreditan nuevamente **20.001 filas, dos grupos y diferencias 0/0**. La huella de los 20.000 usuarios heredados también permanece intacta.

La migración de propiedad y las concesiones sobre la copia preexistente se trataron explícitamente en A; los defaults no se consideraron retroactivos. La reconstrucción final, con `rol_propietario` como creador real, comprobó que la política futura de `datos_anon` permite SELECT a reportes. Para reproducir el orden de trabajo, la herramienta ofrece `--bootstrap` solo para la preparación anterior a A; después de A se utiliza su modo normal. [verificacion_equivalencia.md](verificacion_equivalencia.md) detalla ambos momentos y las huellas del SQL efectivamente ejecutado.

## Conservación final de las cinco tablas de negocio

Se compararon conteos y huellas MD5 ordenadas del contenido completo de cada tabla antes de aplicar A y después de las pruebas A/B/C y la reconstrucción final D. La comparación de [conservacion_after.json](evidencias/conservacion_after.json) contra [conservacion_before.json](evidencias/conservacion_before.json) registra `same_as_before = true`:

| Tabla | Filas antes y después | Huella de contenido coincidente |
| --- | ---: | --- |
| `categoria` | 2 | Sí |
| `producto` | 50.000 | Sí |
| `usuario` | 20.001 | Sí |
| `pedido` | 225.000 | Sí |
| `detalle_pedido` | 499.997 | Sí |

Este segundo control incluye la cuenta sintética U5 ya existente y complementa el control separado de los 20.000 usuarios originales. No se exportaron filas reales para obtener las huellas. Las inserciones y actualizaciones de prueba se revirtieron; el rollback no devuelve los valores consumidos de las secuencias identity ni borra los registros de auditoría.

## Compatibilidad conservada por la implementación U5

- `pedido.fecha` es TIMESTAMPTZ; los agrupamientos temporales usan la zona local del negocio.
- `detalle_pedido` tiene PK compuesta `(pedido_id, producto_id)`, sin ID sustituto ni columna `eliminado`.
- `subtotal` es GENERATED STORED; la aplicación modifica cantidad/precio unitario, no escribe el subtotal.
- Los pedidos nacen PENDIENTE y las reglas heredadas restringen la edición de sus detalles.
- La extensión FNBC se conserva y queda fuera de los permisos de aplicación de U5.
- Las materializadas mensual y diaria tienen finalidades distintas. El mantenimiento interno de la diaria se realiza mediante un puente SECURITY DEFINER acotado, sin conceder MAINTAIN a la aplicación ni escritura sobre totales derivados.

La especificación real de Kiro distingue cuatro grupos operativos, dos logins y dos roles técnicos NOLOGIN. Sus documentos finales y respuestas exportadas están en [kiro_roles_spec](kiro_roles_spec/estado.md), con la revisión automática de Codex identificada por separado. El commit `319cbaa` conserva esa especificación antes del commit `4262d81`, que incorpora `roles.sql`; no se presenta el contexto de entrada como si fuera una salida de Kiro.

La verificación efectiva de A finalizó con 52 eventos en [permissions_resultados.json](evidencias/permissions_resultados.json) y 71 eventos en [defaults_resultados.json](evidencias/defaults_resultados.json), ambas fases con estado `passed`. La comparación exacta de ACL identificó **44 concesiones explícitas de negocio previstas y 44 reales**, sin faltantes, sobrantes ni diferencias de membresías, según [a_comparacion_exacta.json](evidencias/a_comparacion_exacta.json). Estos conteos son eventos de los verificadores y entradas de ACL; no se los confunde con una validación humana.

## Alcance de seguridad y auditoría

U5 demuestra concesiones puntuales por objeto/columna, funciones de autenticación y restablecimiento, permisos futuros bajo el creador correcto, eventos de auditoría verificables, un escalamiento rechazado y agregaciones equivalentes sobre una copia desidentificada. El simulacro se limitó al clúster propio de desarrollo. Después de recibir el resumen A–E y la propuesta de revisión, la persona solicitante dio conformidad al cierre y pidió el ZIP para subirlo a la plataforma. El alcance de esa conformidad se registra en [validacion_humana.md](validacion_humana.md): no acredita lectura exhaustiva ni aprobación individual de ambos integrantes. No se ejecutó contención automática a partir de una respuesta de IA.

El laboratorio se configuró con SCRAM y escucha exclusiva en `127.0.0.1`; conserva secretos y logs en un runtime externo con ACL restringida. Durante la preparación se desactivó el registro de sentencias; antes de B/C se verificaron conexiones y desconexiones activadas, `log_statement=all`, `log_min_error_statement=error` y ambos límites de parámetros en cero. Los valores efectivos quedaron registrados en [configuracion_auditoria.json](configuracion_auditoria.json).

La prueba B completó 10 eventos y comprobó lectura, inserción, actualización, rollback y una conexión PostgreSQL rechazada por contraseña incorrecta. El simulacro C completó 11 eventos: tres autenticaciones comerciales fallidas, una exitosa, recepción de 20.001 filas autorizadas y escalamiento rechazado con SQLSTATE `42501`, sin nueva membresía. Los resultados están en [audit_resultados.json](evidencias/audit_resultados.json) e [incident_resultados.json](evidencias/incident_resultados.json). Las autenticaciones comerciales y la autenticación de la conexión PostgreSQL son controles diferentes.

`log_statement=all` permite registrar sentencias y metadatos; no equivale a un historial de los valores OLD/NEW de cada fila ni demuestra por sí solo cuántos registros recibió el cliente. En C, el conteo recibido se comprobó en el cliente y no se dedujo solamente del SELECT registrado. La documentación oficial describe los niveles de sentencias y el tratamiento de parámetros. [PostgreSQL 17: registro de errores y actividad](https://www.postgresql.org/docs/17/runtime-config-logging.html).

pgAudit puede agregar auditoría por sesión, clases de operación y objetos; su opción `log_rows` registra un número de filas, no los valores OLD/NEW de cada una. No se le atribuye automáticamente un historial fila por fila. Obtener ese historial requeriría otro mecanismo diseñado para ello. No se afirma que pgAudit esté instalado en este laboratorio. [pgAudit para PostgreSQL 17](https://github.com/pgaudit/pgaudit/blob/REL_17_STABLE/README.md).

Los logs son activos sensibles: pueden revelar identidades, orígenes, estructura y operaciones aun cuando los parámetros estén suprimidos. Los originales permanecen privados; para prompts y evidencias públicas se usa una copia anonimizada con controles técnicos de privacidad. No se publican credenciales ni filas personales. La copia determinista de usuarios se describe con sus límites de reidentificación, sin afirmar irreversibilidad universal.

## Estado honesto y forma de entrega

La especificación real de Kiro, la implementación A y las ejecuciones técnicas A/B/C/D tienen evidencias verificables. Las cinco tablas de negocio y los 20.000 usuarios originales conservan sus huellas de contenido. La persona solicitante autorizó el cierre con el pedido literal «bien entonces enviame el zip listo para entregar asi lo subo a la plataforma». Esa conformidad se distingue de la revisión automática de Codex y tiene el alcance documentado en [validacion_humana.md](validacion_humana.md), sin atribuir una revisión exhaustiva ni la validación separada de ambos autores.

El servidor privado de PostgreSQL quedó detenido mediante `pg_ctl` con modo `fast` y espera de finalización: el comando terminó con código 0 y confirmó `server stopped`. Sus archivos se conservan para una eventual reanudación; no se borró el clúster.

La entrega se prepara como repositorio Git, o su ZIP con `.git` e historial legible por partes, más un PDF complementario. El respaldo, el runtime, las claves y los logs sin anonimizar quedan excluidos. El cierre y la verificación del paquete están en proceso; no se afirma que la entrega ya haya sido publicada o enviada.

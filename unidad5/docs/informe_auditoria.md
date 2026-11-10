# Parte B. Configuración y prueba de auditoría de Food Store

**Ejecución técnica verificada sobre PostgreSQL 17.11 el 22/10/2026.**

La prueba B se ejecutó entre 19:45:41.715 y 19:45:43.743 UTC
(16:45:41.715–16:45:43.743, UTC−03). El cliente registró diez comprobaciones y
el fragmento nativo conserva catorce eventos de dos sesiones completas. La
revisión técnica y de privacidad aquí documentada es automática, realizada con
Codex. El alcance de la conformidad de cierre expresada por el usuario se
documenta en [validacion_humana.md](validacion_humana.md).
La propuesta real de OpenCode y sus correcciones técnicas están
conservadas en `ia/bc_respuesta.md` e `ia/bc_validacion_tecnica.md`.

| Dependencia o comprobación | Evidencia real |
|---|---|
| Parte A: especificación final de Kiro y contraste exacto de permisos | `evidencias/a_comparacion_exacta.json`: aprobado, 44 ACL explícitas previstas y observadas; sin faltantes ni extras |
| Parámetros efectivos en una conexión nueva | `configuracion_auditoria.json`: verificados a las 16:45:36.397328−03 |
| Lectura, inserción y actualización como `app_web` | `evidencias/audit_resultados.json`: estado `passed`, diez eventos cliente |
| Conexión con contraseña PostgreSQL incorrecta | FATAL real `28P01`, sesión `6ada67e7.5e60` |
| Captura, anonimización e integridad del fragmento | `log_auditoria_prueba.txt`: 14 JSON válidos; hashes y selección en `evidencias/logs_procedencia.json` |

## 1. Parámetros efectivos y su finalidad

El registro de sentencias estuvo desactivado durante la preparación de
credenciales. La conexión de verificación posterior a su activación observó los
siguientes valores para las pruebas B/C.

| Parámetro | Valor observado | Uso en el laboratorio |
|---|---|---|
| `logging_collector` | `on` | Recopilar archivos del servidor |
| `log_destination` | `stderr,jsonlog` | Formato legible y formato estructurado |
| `log_connections` | `on` | Registrar intentos y autorización de conexiones |
| `log_disconnections` | `on` | Registrar cierre de sesiones |
| `log_statement` | `all` | Incluir lectura y modificaciones |
| `log_min_error_statement` | `error` | Conservar la sentencia asociada al error |
| `log_parameter_max_length` | `0` | Omitir valores de parámetros en sentencias |
| `log_parameter_max_length_on_error` | `0` | Omitir valores de parámetros en errores |
| `log_timezone` | `America/Buenos_Aires` | Interpretar la hora del registro |

Prefijo efectivo para `stderr`:

```text
%m pid=%p session=%c user=%u db=%d app=%a client=%r sqlstate=%e
```

El prefijo relaciona hora, PID, usuario, base, aplicación, cliente, SQLSTATE y
sesión. JSON proporciona campos equivalentes, además de `line_num`; los valores
nulos pueden omitirse. `log_statement=all` amplía el mínimo de modificaciones de
la consigna para poder registrar también el SELECT de C. Los límites de parámetros
no ocultan contraseñas escritas como literales SQL. [PostgreSQL 17: registro de
eventos](https://www.postgresql.org/docs/17/runtime-config-logging.html).

## 2. Resolución paso a paso de la prueba

1. **Verificar la precondición de permisos.** Contrastar los roles y sus privilegios
   con la especificación final de Kiro. `app_web` debe poder realizar las
   operaciones concretas del catálogo de prueba sin recibir permisos
   administrativos ni acceso a hashes de contraseñas. Las salidas reales de
   permisos y la comparación exacta de la Parte A se conservaron en
   `docs/evidencias/a_*`.

2. **Activar la configuración de auditoría.** El archivo
   `sql/configurar_auditoria.sql` contiene los cambios de parámetros recargables.
   `logging_collector` y los destinos se preparan al crear el clúster; si fuera
   necesario cambiarlos, debe respetarse su requisito de reinicio. La herramienta
   `tools/activar_auditoria.py` verifica los parámetros en una conexión nueva y
   conservó la salida en `docs/configuracion_auditoria.json`.

3. **Comprobar la privacidad antes de enviar credenciales.** El cliente verifica
   primero que ambos límites de parámetros sean cero. Los valores sensibles se
   toman de un archivo privado externo al repositorio y se enlazan con
   `PQexecParams`; no se incorporan como literales al SQL ni se imprimen.

4. **Ejecutar las operaciones como una conexión real de `app_web`.** El catálogo
   `sql/auditoria_test.sql` se ejecuta con
   `python tools/ejecutar_pruebas.py --phase audit`. Es un catálogo de sentencias
   con marcadores y parámetros, por lo que no corresponde ejecutar el archivo
   completo directamente en psql.

   Dentro de `BEGIN`, el cliente lee productos activos con stock para dos
   unidades, elige uno y conserva su precio solo en memoria. Inserta un pedido,
   comprueba mediante `RETURNING` que existe una única fila inicialmente
   `PENDIENTE`, agrega un detalle de una unidad y actualiza su cantidad a dos.
   Luego verifica que el total del pedido coincida con la suma de subtotales y
   confirma el pedido mediante una transición condicionada a `PENDIENTE`.

5. **Revertir las filas de prueba.** El cliente ejecuta `ROLLBACK` también ante un
   error y compara los conteos de usuarios, pedidos y detalles antes y después.
   La prueba comprobó las filas devueltas y los valores esperados; un comando
   sin error no se contará por sí solo como una fila modificada. El rollback no
   recupera identidades consumidas ni elimina el registro de las operaciones
   intentadas.

6. **Probar el inicio de sesión PostgreSQL fallido.** En otra conexión se utiliza
   la identidad `app_web` con una contraseña deliberadamente incorrecta. El
   cliente debe distinguir un rechazo de contraseña de un problema de red; el
   código SQLSTATE `28P01` se comprobó en el evento real del servidor, porque
   un fallo durante el establecimiento de la conexión no entrega un `PGresult`
   al cliente. No se dará el intento por demostrado si solo falla la conexión
   por una causa distinta.

7. **Capturar y preparar la evidencia.** Se conservó el JSON nativo completo de
   las sesiones de prueba, incluido el intento fallido, en el área privada. Como
   este último evento no contiene `application_name`, se lo identificó por su
   SQLSTATE, usuario solicitado, hora, origen y `session_id`, sin inventar una
   etiqueta de aplicación. Se extrajeron las sesiones completas, se anonimizaron
   identificadores y se verificó el SHA-256 contra los bytes del archivo
   entregado. El original privado queda fuera de Git.

   La evidencia cliente está en `docs/evidencias/audit_resultados.json` y el
   fragmento anonimizado en `docs/log_auditoria_prueba.txt`.

## 3. Cómo responder quién, qué, cuándo y desde dónde

La sesión normal es `6ada67e6.80d4` (PID 32980, origen `127.0.0.1:60562`);
el intento fallido corresponde a `6ada67e7.5e60` (PID 24160, origen
`127.0.0.1:60563`). Las marcas de tiempo siguientes conservan UTC−03.

| Pregunta | Evidencia del fragmento | Interpretación y límite |
|---|---|---|
| ¿Quién? | `user=app_web`; sesión normal, eventos 2–3: SCRAM y autorización | Rol autenticado del motor; en el FATAL solo consta el usuario solicitado |
| ¿Qué? | Sesión normal: 5 SELECT, 6–7 INSERT, 8 y 10 UPDATE, 11 ROLLBACK | Operaciones solicitadas; las filas y el total se acreditan además por el cliente |
| ¿Cuándo? | Lectura 16:45:42.082; INSERT 16:45:42.087; UPDATE 16:45:42.914; FATAL 16:45:43.743 | Hora del servidor, convertida con UTC−03 al contrastarla con el cliente |
| ¿Desde dónde? | `remote_host=127.0.0.1`, puertos 60562 y 60563 | Conexiones locales; no hay evidencia de un origen remoto externo |
| ¿Qué conexión? | Sesión normal con `application_name=u5_audit_test`; intento fallido sin ese campo | PID y `session_id` preservan la correlación aun cuando falta la aplicación |

La numeración indicada es `line_num` **dentro de cada sesión**. El FATAL es el
evento 2 de la sesión fallida y la línea 14 del archivo entregado; su código es
`28P01` y el mensaje indica rechazo de contraseña de `app_web`. Los eventos 1–12
de la sesión normal incluyen desde la recepción de conexión hasta su desconexión.

Una sentencia registrada no demuestra por sí sola que se haya confirmado la
transacción ni cuántas filas recibió el cliente. Para B, los resultados de
`RETURNING`, la comprobación del total y el rollback se contrastaron con la
evidencia del cliente; no se infirieron solamente a partir del texto SQL.

## 4. Autenticación del motor y autenticación de Food Store

La conexión de PostgreSQL identifica al rol de servicio, por ejemplo `app_web`;
la función `fn_autenticar` valida por separado una cuenta de Food Store. La prueba
de contraseña PostgreSQL incorrecta de B y los intentos de contraseña de negocio
de C son sucesos diferentes. La primera corresponde al protocolo de conexión del
motor, aquí preparado con SCRAM. [PostgreSQL 17: autenticación por
contraseña](https://www.postgresql.org/docs/17/auth-password.html).

Invocar `fn_autenticar` correctamente como SQL no implica aceptar una contraseña
de negocio: la función puede devolver NULL. En C se observaron cuatro mensajes
`U5_AUTH success=f/f/f/t`, sin correo, contraseña ni identificador de usuario,
conservados en `log_simulacro_anonimizado.txt`. Esos resultados de negocio no se
etiquetan artificialmente como `28P01`: el FATAL de B corresponde a otra conexión.

## 5. Alcance nativo y nociones de pgAudit

La auditoría nativa preparada permite relacionar conexiones, sentencias y errores,
pero no proporciona automáticamente un historial de los valores anteriores y
posteriores de cada fila ni identifica a la persona detrás de una cuenta de
servicio compartida. Para un historial de cambios de valores se necesitaría un
mecanismo adicional diseñado para ese fin, como disparadores de auditoría
protegidos o captura de cambios.

pgAudit agrega auditoría de sesión y de objetos, permite identificar relaciones
consultadas o modificadas y puede incluir cantidades de filas mediante
`pgaudit.log_rows`. Ese contador no constituye una colección de los valores
`OLD` y `NEW` de todas las filas: la referencia de la consigna a «detalle fila por
fila» debe entenderse con esa precisión. Esta parte describe nociones; no afirma
que la extensión esté instalada ni configurada en el laboratorio. [Documentación
oficial de pgAudit para PostgreSQL
17](https://github.com/pgaudit/pgaudit/blob/REL_17_STABLE/README.md).

## 6. ¿El log es un activo sensible? Respuesta en tres oraciones

Sí: el log es un activo sensible porque puede revelar consultas, identidades,
horarios, estructura de la base y secretos incluidos accidentalmente en el SQL.
Deberían poder leerlo únicamente administradores y auditores autorizados, con
lectura restringida y escritura reservada al servicio y a quienes gestionan su
retención, mediante ACL de Windows en este laboratorio. Los roles de aplicación,
soporte e informes no deben recibir acceso general a archivos del servidor ni
`pg_read_server_files` para leerlo, ya que ese rol habilita un alcance mucho mayor
que el fragmento de auditoría necesario. [PostgreSQL 17: roles
predefinidos](https://www.postgresql.org/docs/17/predefined-roles.html).

## 7. Resultados y procedencia de la evidencia

El cliente recibió tres productos del catálogo, insertó un pedido y un detalle,
actualizó una línea y confirmó un pedido inicialmente pendiente. La comprobación
del total fue verdadera y el rollback dejó los mismos conteos: 20.001 usuarios,
225.000 pedidos y 499.997 detalles. No se exportaron los valores de las filas ni
se afirmó recuperar las identidades consumidas.

La captura partió del archivo JSON cerrado `u5-20261022-121336.json`, de 217
eventos. Se seleccionaron por ventana temporal y aplicación las sesiones reales
de B, agregando la sesión del FATAL; luego se conservaron todos sus eventos en
el orden original, incluidos los anteriores a la aparición de `application_name`.
No se incorporaron sesiones verificadoras ni eventos de C al fragmento de B.

| Elemento | SHA-256 de sus bytes |
|---|---|
| Fuente privada completa, excluida de Git | `de25e590ce9afdc75fef85cd19912e51463af9aae3981ee1df40a86916e45f9d` |
| Fragmento B anonimizado entregado | `9232abae2d5499f4a70e1997e701e81c0dfa55fbd36cb4ac2c7477dbe291b8d5` |

Se sustituyó el nombre de la base por `foodstore_lab` y el usuario de las rutas
Windows por `USR_LOCAL`. Los escaneos no detectaron secretos del inventario
privado, hashes de credenciales, correos ni contraseñas SQL literales en la
selección; la inspección automática con Codex tampoco identificó valores de
usuarios en el archivo entregado. Se preservaron los campos de tiempo, rol,
sesión, PID, origen y errores y se comprobó que los catorce objetos JSON siguen
siendo válidos. Estos controles reducen exposición y verifican la transformación;
no certifican anonimización irreversible ni autenticidad forense del origen.

Trazabilidad: `evidencias/logs_procedencia.json`; escaneo:
`evidencias/b_anonimizacion_scan.json`. La conformidad de cierre y su
alcance constan en `validacion_humana.md`.

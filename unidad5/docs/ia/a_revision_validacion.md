# Contraste técnico de la auditoría OpenCode: Parte A

Autor del contraste: Codex. La persona solicitante dio conformidad al cierre
y autorizó preparar el ZIP, con el alcance documentado en
[validacion_humana.md](../validacion_humana.md). No se atribuye lectura
exhaustiva ni aprobación individual a ambos integrantes. Las decisiones
siguientes siguen identificadas como contraste y correcciones técnicas de
Codex.

## Consulta real y alcance

Se utilizó OpenCode 1.18.23, modelo solicitado openai/gpt-6.1-sol, agente
plan y permisos de herramientas denegados. La consulta se inició el
22/10/2026 a las 19:41:35 UTC y terminó a las 19:43:21 UTC: estado completed,
returncode 0 y cero eventos de herramientas. Su respuesta fue una auditoría
estática; OpenCode no ejecutó SQL ni certificó las pruebas posteriores.

Se preservan [prompt](a_revision_prompt.txt),
[respuesta íntegra](a_revision_respuesta.md),
[metadatos](a_revision_metadatos.json) y los cuatro
[adjuntos exactos](a_revision_adjuntos/01_roles.sql). El SHA-256 del SQL
consultado y del actual coincide:
`916b8b4e9d9b59abc5bc6edef4d3d35d27007dcd7c875cc1ec62d791197f75f5`.
Las líneas citadas por el auditor corresponden al snapshot adjunto.

El dictamen no encontró un incumplimiento bloqueante demostrado de la
matriz final. Esto se interpreta como una conclusión estática limitada a
los adjuntos, no como una garantía general de seguridad. La ejecución y los
catálogos reales aportaron después la evidencia separada indicada abajo.

## Hallazgos contrastados

| Hallazgo de OpenCode | Contraste y decisión técnica |
|---|---|
| Confidencialidad de logs dependiente del cliente/configuración | Correcto. Un secreto literal queda dentro de la sentencia aunque log_parameter_max_length sea cero. Los clientes del laboratorio usan PQexecParams para autenticación/reset y verificaron ambos límites a cero antes de las llamadas. No se afirma que esos parámetros oculten literales ni que cualquier cliente futuro sea seguro. No requirió ampliar ACL ni cambiar roles.sql. |
| La limpieza no revoca ACL de todo posible rol ajeno | Correcto como condición general. El script está acotado al cluster privado preparado y no es un saneador universal de servidores existentes. La consulta real de ACL de relaciones/columnas abarcó todos los beneficiarios no propietarios y coincidió en 44 entradas, sin terceros ni permisos adicionales; el inventario de roles muestra los ocho U5 y bootstrap entre los roles propios. Esto no autoriza trasladar la misma conclusión a otra instancia sin inventario. |
| Canal temporal y ausencia de limitación de intentos en fn_autenticar | Riesgo residual aceptado como tal. Los caminos que evitan bcrypt pueden diferenciarse por tiempo y no hay limitación automática de intentos implementada en SQL. El trabajo no afirma mitigarlos; una política de aplicación o hash ficticio sería una decisión posterior, no un cambio aplicado ni un permiso adicional. |

La observación sobre PASSWORD NULL también es válida: por sí solo no
garantiza denegación con métodos como trust. El laboratorio usa SCRAM y el
instalador establece los secretos privados; no se generaliza esa protección
a configuraciones de autenticación ajenas.

Se conserva el matiz de search_path: PostgreSQL puede buscar pg_temp para
relaciones/tipos aunque no aparezca expresamente. Aquí los cuatro puentes
califican sus objetos y los logins no tienen TEMPORARY. Los INVOKER heredados
con referencias sin esquema conservan public en el path de los logins, que
no pueden crear objetos allí. No se presume que un path fijo por sí solo
proteja cualquier función futura con nombres sin calificar.

## Alternativas más amplias solicitadas y rechazadas

El prompt pidió expresamente una alternativa de mantenimiento y su acceso
adicional. Por ello, los dos candidatos siguientes **no son errores
espontáneos atribuidos al auditor**: OpenCode los separó de sus correcciones,
advirtió que excedían el diseño y recomendó mantener los permisos puntuales.
Quedan documentados como propuestas reales evaluadas críticamente.

### Heredar lectura desde soporte

El candidato fue conceder rol_app_lectura a rol_soporte con INHERIT TRUE,
SET FALSE y ADMIN FALSE. Aunque SET/ADMIN sigan restringidos, soporte y
admin_datos heredarían lectura de catálogo, pedidos, detalle,
usuario.created_at y futuras concesiones al grupo de lectura. Esos accesos
no responden al trabajo de contacto acordado.

**Decisión técnica:** no aplicar. Soporte conserva únicamente las seis
columnas de contacto y UPDATE telefono. La captura real tiene exactamente
las tres membresías del diseño y ninguna relación de soporte a lectura.
Se probaron 42501 para leer pedido/created_at y cambiar email/nombre.

### Lectura general de public para reportes

El candidato fue GRANT SELECT ON ALL TABLES IN SCHEMA public y un default
SELECT equivalente para futuras tablas del creador rol_propietario. Eso
incluye tablas, vistas y MVs, no sólo materializadas de reportes. Expondría
usuario.contrasena y contacto real, fuentes del negocio, FNBC y objetos
públicos futuros; no permite preservar la excepción del hash mediante un
REVOKE SELECT por columna, porque seguiría existiendo SELECT de tabla.

**Decisión técnica:** no aplicar. Reportes mantiene únicamente
datos_anon.usuario_anon y las dos MVs autorizadas, más el default del esquema
datos_anon bajo el creador correcto. La comparación exacta no detectó
SELECT adicional sobre public y el intento real de leer usuario dio 42501.

La evidencia de estas decisiones demuestra que las alternativas no se
incorporaron. La conformidad de cierre de la persona solicitante se conserva
con su alcance en [validacion_humana.md](../validacion_humana.md), sin
convertir este contraste técnico en una aprobación individual de ambos
integrantes ni en una declaración de lectura exhaustiva.

## Comprobación real posterior al dictamen

Los archivos de [evidencias](../evidencias/a_permisos.json) proceden de
consultas reales al catálogo y pruebas posteriores a la instalación:

| Aspecto | Resultado técnico observado |
|---|---|
| Matriz tabla/columna | 44 entradas previstas y actuales; cero faltantes/adicionales. No hubo ACL de otro beneficiario no propietario en las relaciones inventariadas. |
| Membresías | Exactamente tres; ADMIN=false, INHERIT=true, SET=false. Sin membresías de logins a propietarios o reportes. |
| Atributos peligrosos | Los ocho roles U5 tienen superuser, createdb, createrole, replication y bypassrls en falso. Sólo los dos logins tienen canlogin=true. |
| Cuatro DEFINER | Exclusivamente autenticación, reset, recálculo y refresh diario; dueño rol_funciones, prosecdef=true, search_path=pg_catalog. |
| EXECUTE público | No consta en las diez funciones públicas capturadas. app_web sólo recibe EXECUTE directo de autenticar; admin_datos sólo de reset. Los dos triggers DEFINER no se exponen con GRANT a logins. |
| Resto de funciones | Las otras seis funciones públicas son INVOKER de rol_propietario. |
| Propiedad de relaciones | Las 22 relaciones capturadas de public/datos_anon pertenecen a rol_propietario; ninguna pertenece a rol_funciones. Incluye las cuatro secuencias IDENTITY, vistas y ambas MVs. |
| Esquemas | Ningún rol de negocio tiene CREATE; rol_funciones usa public/crypto sin CREATE, reportes public/datos_anon sin CREATE. Los logins no usan crypto/datos_anon directamente. |
| Base | Los logins tienen CONNECT, sin CREATE/TEMP. TEMP sólo para rol_propietario entre los ocho roles, por la auditoría temporal D. |
| Puentes en uso | El flujo real app_web insertó pedido/detalle, actualizó cantidad, verificó total y confirmó pedido sin ampliar UPDATE total ni MAINTAIN; después ROLLBACK. |
| Defaults de funciones | Se crearon realmente funciones como cada uno de los tres creadores: cero PUBLIC EXECUTE y 42501 para los seis roles de negocio. El CREATE temporal de prueba a rol_funciones se revirtió. |
| Defaults de tablas | Nueva tabla public negó DML a los seis roles de negocio; nueva tabla datos_anon sólo concedió SELECT a reportes. No quedaron objetos de prueba. |
| Reconstrucción D | Creación efectiva como rol_propietario, SELECT automático de reportes, 20.001 filas y equivalencia agregada EXCEPT ALL 0/0. |
| Conservación | Las cinco tablas mantuvieron conteos y huellas completas; same_as_before=true. No se exportaron filas personales. |

La [comparación exacta](../evidencias/a_comparacion_exacta.json) y las fases
[permissions](../evidencias/permissions_resultados.json) y
[defaults](../evidencias/defaults_resultados.json) finalizaron PASSED con
52 y 71 eventos respectivamente para las dos fases. Los controles positivos
de negocio están en [audit_resultados.json](../evidencias/audit_resultados.json);
las huellas están en
[conservacion_after.json](../evidencias/conservacion_after.json).

La prueba de permisos incluye rechazo de hashes/SELECT *, escritura de
total/credenciales, DELETE pedido/usuario, secuencias, creación de roles y
SET ROLE no habilitado. El reset produjo P0002 para usuario ausente y 22023
para NULL/longitudes inválidas; aceptó 12 y 72 bytes. El UPDATE de teléfono
usó WHERE FALSE: probó autorización sin cambiar una fila. No se presenta
como una prueba exhaustiva de todas las combinaciones de operaciones.

La captura de ACL confirma la separación efectiva observada; no elimina las
facultades inherentes del propietario ni del bootstrap superusuario. La
autenticación no transforma a app_web en el usuario del negocio, y la matriz
permite consultar todas las filas de las columnas autorizadas: no hay RLS.
Los límites de logs, la confidencialidad del sistema operativo y las
políticas de intentos siguen requiriendo su control correspondiente.

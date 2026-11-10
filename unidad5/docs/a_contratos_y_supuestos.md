# Parte A: contratos y supuestos de implementación

Implementación SQL: Codex. Planificación previa: documentos reales de Kiro
`requirements.md` y `design.md`, conservados junto con su procedencia y la
revisión técnica automática en `docs/kiro_roles_spec`. El commit `319cbaa`
precede a la creación de `sql/roles.sql`. Esta nota no atribuye la
implementación a Kiro. La conformidad de cierre de la persona solicitante
está registrada con su alcance en
[validacion_humana.md](validacion_humana.md); no se atribuye lectura
exhaustiva ni aprobación individual de ambos integrantes.

El script se instaló y se auditó técnicamente. Los resultados reales se
conservan en evidencias separadas y se explican en
[informe_roles.md](informe_roles.md): la revisión estática no se usa como
sustituto de esas pruebas. Las decisiones técnicas continúan identificadas
como aportes de Codex, separados de la conformidad de cierre de la persona
solicitante.

## Entorno y primera ejecución

La implementación corresponde a PostgreSQL 17 y a la copia privada
`foodstore_u5_arancibia_romero`, restaurada por `u5_bootstrap`. Se inventarió
el DDL real de PostgreSQL 17.11 antes de programar. Deben existir los objetos
de U1-U4, la copia `datos_anon.usuario_anon` y pgcrypto instalado en `crypto`.
No se incluyen el dump fuente, credenciales, filas personales ni logs crudos.

Se ejecuta con `tools/instalar_seguridad.py`, durante el bootstrap privado
con `log_statement=none` y `log_min_error_statement=panic`. Los ocho roles
deben estar ausentes: el SQL aborta si encuentra cualquiera y no reemplaza
roles ajenos. La configuración se realiza en una transacción. Si falla una
sentencia, debe hacerse ROLLBACK; no continuar parcialmente.

Los dos logins nacen con `PASSWORD NULL`. El instalador establece sus claves
SCRAM mediante valores privados parametrizados, después de la transacción
de roles y antes de habilitar la auditoría. No hay contraseñas embebidas en
el SQL. No se abre ninguna membresía hacia los propietarios técnicos.

## Roles y superficie concedida

Los ocho roles carecen de SUPERUSER, CREATEDB, CREATEROLE, REPLICATION y
BYPASSRLS. Las tres membresías son `app_web` a lectura/escritura y
`admin_datos` a soporte, siempre INHERIT TRUE, SET FALSE y ADMIN FALSE.

| Rol | Privilegios de negocio |
|---|---|
| rol_app_lectura | SELECT de catálogo, pedidos y detalle; usuario sólo id, nombre, apellido, email, telefono, eliminado, created_at. |
| rol_app_escritura | INSERT de pedido(usuario_id,fecha,forma_pago); UPDATE de pedido(estado,forma_pago,eliminado); INSERT de cuatro entradas de detalle, UPDATE cantidad/precio_unitario y DELETE de detalle sujeto al validador heredado. |
| rol_soporte | Exactamente SELECT de usuario(id,nombre,apellido,email,telefono,eliminado) y UPDATE telefono. No recibe created_at, pedidos ni catálogo. |
| rol_reportes | SELECT de usuario_anon y de las dos MVs autorizadas. Sin tablas fuente. |
| app_web | Herencia de lectura/escritura y EXECUTE puntual de fn_autenticar. |
| admin_datos | Herencia de soporte y EXECUTE puntual de fn_resetear_password. |

`rol_propietario` posee public/datos_anon y sus tablas, vistas, MVs,
secuencias, enums y funciones heredadas INVOKER. `rol_funciones` posee
exclusivamente las cuatro funciones DEFINER y ninguna tabla. Sus ACL internas
se limitan a las columnas y a MAINTAIN de la MV diaria definidos por Kiro,
más USAGE de public/crypto y EXECUTE de crypt(text,text)/gen_salt(text,integer).

Se revocan permisos de PUBLIC y se limpian ACL de tabla y de columna antes
de conceder la matriz. Revocar sólo privilegios de tabla no elimina los
otorgamientos por columna. El retiro de entradas ACL de bootstrap no limita
sus facultades de superusuario; bootstrap conserva su carácter técnico.

PUBLIC no conserva CONNECT, CREATE o TEMP de la base ni permisos sobre los
esquemas de aplicación. CONNECT se concede a los dos logins; TEMP únicamente
a rol_propietario para la tabla temporal de equivalencia D. Los logins no
reciben CREATE en esquemas, acceso a secuencias ni permisos sobre FNBC.

## Contratos de funciones protegidas

Las cuatro funciones usan SECURITY DEFINER, propietario rol_funciones,
`search_path=pg_catalog`, nombres de objetos calificados y REVOKE EXECUTE
FROM PUBLIC explícito. No usan SQL dinámico ni cambian la identidad o las
membresías de la sesión.

| Función | Contrato |
|---|---|
| fn_autenticar(text,text) → bigint | Devuelve id para un usuario activo con bcrypt válido; NULL en los demás casos. Rechaza NULL, contraseña vacía o de más de 72 bytes. No acepta texto plano como alternativa. Los hashes demostrativos inválidos fallan de forma cerrada. |
| fn_resetear_password(bigint,text) → void | Sólo admin_datos. Valida 12..72 bytes con octet_length; NULL o longitud inválida da SQLSTATE 22023. Usuario ausente, incluido id NULL, da P0002. Bcrypt nuevo con coste 10. Primero valida longitud, luego busca/actualiza el usuario. |
| recalcular_total_pedido() → trigger | Conserva la suma heredada de subtotales y el recálculo del pedido anterior si cambia la referencia. Sólo la función puede escribir pedido.total en este flujo. |
| u4_refrescar_ventas() → trigger | Conserva el REFRESH de la MV diaria y la omisión del UPDATE anidado de pedido mediante pg_trigger_depth. No modifica la MV mensual TP5. |

Autenticación registra `U5_AUTH`, resultado booleano y timestamp mediante
RAISE LOG. Un reset exitoso registra sólo `U5_PASSWORD_RESET`, booleano y
timestamp. Nunca se agregan email, contraseña, hash o id al mensaje. Las
llamadas con credenciales deben usar parámetros; al auditar deben estar a
cero ambos límites de registro de parámetros, también el de errores.

Validar credenciales del negocio no aplica aislamiento por fila ni otorga
privilegios SQL al usuario devuelto. El SELECT masivo de columnas concedidas
sigue permitido por esta matriz; el simulacro registra el hecho sin guardar
filas personales. No se afirma protección RLS.

## Continuidad de reglas heredadas

Los triggers se conservan con sus enlaces originales, incluidos los U4 de
producto/categoria, el bloqueo por advisory lock y las guardas FNBC. Se
reemplaza el cuerpo de los dos puentes con CREATE OR REPLACE, conservando sus
OID y reglas. Se califica `public.pedido`/`public.detalle_pedido` en recálculo
para que el path fijo no cambie la resolución de objetos.

Las otras funciones siguen INVOKER de rol_propietario. Los validadores TP2
usan nombres sin esquema y el enum estado_pedido; por eso las sesiones de
app/admin mantienen `search_path=pg_catalog,public`. public sólo es
escribible por su propietario técnico. SELECT FOR UPDATE del validador no
requiere conceder UPDATE total: las columnas operativas ya proporcionan el
privilegio UPDATE necesario sobre pedido.

Los IDs heredados son BIGINT GENERATED ALWAYS AS IDENTITY. La generación
implícita del INSERT permitido no requiere habilitar nextval/setval
directos. detalle_pedido conserva su PK compuesta y subtotal GENERATED; no
se agrega una columna id ni se permite escribir subtotal.

Los permisos no modifican datos heredados. Las huellas anteriores y
posteriores deben compararse al ejecutar; un conteo igual no basta para
demostrar conservación del contenido. El dump sólo de esquema muestra MVs
WITH NO DATA por su formato de exportación y no demuestra el estado de las
MVs en la base activa.

## Objetos futuros y Parte D

Se revoca el EXECUTE público por defecto de funciones de forma GLOBAL para
los tres creadores efectivos: rol_propietario, rol_funciones y u5_bootstrap.
Un REVOKE sólo por esquema no elimina el default público global. También
se retiran defaults automáticos de tablas/secuencias para roles de negocio.

Sólo las tablas futuras de datos_anon creadas por rol_propietario reciben
SELECT automático para rol_reportes. Las tablas futuras de public quedan
sin acceso de aplicación. Los defaults no son retroactivos: usuario_anon ya
existente recibe cambio de propietario y GRANT explícitos en esta migración.
La reconstrucción D usó SET LOCAL ROLE rol_propietario y comprobó ownership,
SELECT de reportes y equivalencia bilateral 0/0. El mismo criterio de creador
efectivo debe mantenerse en posteriores reconstrucciones.

## Verificaciones ejecutadas y alcance

La captura real y comparación de ACL confirmaron tabla/columna, MAINTAIN,
esquemas, base, EXECUTE, propietarios y las tres opciones de membresía:
44 entradas previstas/actuales y diferencias 0/0. Las fases permissions y
defaults finalizaron PASSED, con 52 y 71 eventos respectivamente. Las pruebas
usan conexiones reales app_web/admin_datos y las distinguen de pruebas
técnicas SET LOCAL ROLE con bootstrap. Los cambios de prueba quedaron en
transacciones con ROLLBACK; los valores consumidos por IDENTITY no retroceden
por ese ROLLBACK.

Se comprobaron autenticación, reset y límites de bytes; el flujo real
pedido/detalle con total recalculado; denegaciones de hashes, total, columnas
generadas, DELETE de pedido/usuario, secuencias y SET ROLE; acceso de reportes
y defaults para cada creador. Las huellas posteriores de las cinco tablas
coincidieron con las previas. La evidencia de logs requiere auditoría
activada y sanitización. log_statement=all registra sentencias, no valores
OLD/NEW ni por sí solo la entrega de filas; no se afirma pgAudit instalado.

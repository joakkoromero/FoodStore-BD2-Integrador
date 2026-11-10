# Parte A. Roles y permisos de Food Store

Exequiel Arancibia — Joaquin Romero. Base de Datos II, Unidad 5, 2026.

**Estado: implementación instalada y verificación técnica de A ejecutada.**
La comparación exacta coincide en 44 entradas ACL; las fases permissions y
defaults finalizaron correctamente con 52 y 71 eventos registrados. Se
adjuntan capturas reales y auditoría OpenCode. El flujo positivo de
pedido/detalle, la reconstrucción D y la conservación posterior también
quedaron comprobados por sus evidencias separadas. La persona solicitante
dio conformidad al cierre y autorizó preparar el ZIP para entregar, con el
alcance registrado en [validacion_humana.md](validacion_humana.md). Esto no
acredita lectura exhaustiva ni aprobación individual de ambos integrantes;
las verificaciones y correcciones técnicas siguen identificadas como Codex.

## A.1. Planificación previa en Kiro

Primero se inventarió la base propia de desarrollo, continuando los trabajos
anteriores: tablas, claves, columnas GENERATED/IDENTITY, vistas, MVs y
triggers de TP2/U4. La copia de trabajo contiene 20.000 usuarios heredados y
una cuenta sintética de prueba; el dump con datos y sus secretos permanecen
fuera del repositorio. Se reconstruyeron los artefactos de roles y las
funciones de autenticación/reset para este entorno, dejando su procedencia
identificada, en lugar de atribuirles una existencia previa no comprobada.

Después se proporcionó ese inventario a Kiro y se revisaron sus propuestas.
Las respuestas reales finales de requirements y design se exportaron desde
la aplicación y se preservaron con sus marcas y hashes. El commit
`319cbaa` guardó ambos documentos y la revisión automática de Codex **antes**
de crear `sql/roles.sql`.

| Rol | Tipo | Operación habilitada y justificación |
|---|---|---|
| rol_app_lectura | NOLOGIN | Leer catálogo, pedidos, detalle y una proyección de usuario, porque la aplicación necesita consultar el negocio sin acceder a hashes. |
| rol_app_escritura | NOLOGIN | Escribir columnas operativas de pedido/detalle, porque los importes derivados y las credenciales tienen mecanismos específicos. |
| rol_soporte | NOLOGIN | Consultar contacto y cambiar teléfono, porque la atención al cliente no necesita pedidos, catálogo o contraseñas. |
| rol_reportes | NOLOGIN | Leer dos agregados materializados y usuario_anon, porque los informes no requieren datos personales fuente. |
| rol_propietario | NOLOGIN | Poseer infraestructura e invariantes heredadas, porque los logins de uso cotidiano no deben controlar objetos ni permisos. |
| rol_funciones | NOLOGIN | Poseer sólo cuatro funciones protegidas, porque ciertos cálculos y credenciales requieren privilegios internos limitados. |
| app_web | LOGIN | Heredar lectura/escritura y ejecutar autenticación, porque representa la conexión de la aplicación. |
| admin_datos | LOGIN | Heredar soporte y ejecutar reset, porque la administración de contacto/credenciales requiere una cuenta diferenciada. |

Las únicas membresías son app_web → lectura/escritura y admin_datos →
soporte. Las tres tienen INHERIT TRUE, SET FALSE y ADMIN FALSE: heredan las
ACL de sus grupos, no habilitan SET ROLE hacia ellos ni permiten conceder
membresías. Ningún login es miembro de los dos propietarios técnicos.
Ninguno de los ocho roles es superusuario, creador de bases/roles,
replicador ni BYPASSRLS.

Los documentos reales se conservan en
[requirements](kiro_roles_spec/requirements.md),
[design](kiro_roles_spec/design.md) y
[revisión automática](kiro_roles_spec/revision_automatica_codex.md).
La matriz final más estrecha de soporte tiene seis columnas, sin created_at.
La ampliación preliminar de Kiro a pedidos/detalles fue rechazada y consta
en su historial; se distingue de la auditoría OpenCode del punto A.4.

## A.2. Implementación de CREATE ROLE, REVOKE y GRANT

El archivo [roles.sql](../sql/roles.sql) comienza con una transacción y
precondiciones: PostgreSQL 17, base y bootstrap esperados, ausencia de los
ocho roles y existencia de los objetos heredados/pgcrypto. Si hay un rol U5
preexistente, aborta; no lo reemplaza silenciosamente. No contiene claves.
Los logins nacen con PASSWORD NULL y el instalador configura después sus
secretos privados.

La implementación sigue estos pasos:

1. Crea seis roles NOLOGIN y dos LOGIN; aplica sólo las tres membresías.
2. Transfiere esquemas, tablas, vistas, MVs, secuencias y enums a
   rol_propietario. La transferencia de las tablas mueve sus secuencias
   IDENTITY dependientes; no se intenta cambiarles dueño por separado.
3. Revoca permisos heredados de PUBLIC y limpia tanto ACL de tabla como
   de columna. Revocar una tabla no elimina por sí solo sus GRANT por columna.
4. Protege los dos puentes heredados y crea autenticación/reset con
   SECURITY DEFINER, dueño rol_funciones, search_path fijo y objetos
   calificados. Conserva las demás funciones como INVOKER.
5. Concede exactamente los permisos de la matriz, USAGE de esquemas donde
   hace falta y CONNECT a los dos logins. Quita CREATE/TEMP de PUBLIC;
   TEMP se reserva al propietario técnico para la auditoría de equivalencia D.
6. Establece defaults para los creadores efectivos y deja la comprobación
   de objetos futuros en transacciones reversibles.

| Beneficiario | Objeto | Privilegio y columnas |
|---|---|---|
| rol_app_lectura | categoria, producto, pedido, detalle_pedido | SELECT de tabla. |
| rol_app_lectura | usuario | SELECT(id,nombre,apellido,email,telefono,eliminado,created_at). |
| rol_app_escritura | pedido | INSERT(usuario_id,fecha,forma_pago); UPDATE(estado,forma_pago,eliminado). |
| rol_app_escritura | detalle_pedido | INSERT(pedido_id,producto_id,cantidad,precio_unitario); UPDATE(cantidad,precio_unitario); DELETE sujeto al trigger de PENDIENTE. |
| rol_soporte | usuario | SELECT(id,nombre,apellido,email,telefono,eliminado); UPDATE(telefono). |
| rol_reportes | datos_anon.usuario_anon | SELECT. |
| rol_reportes | mv_facturacion_categoria_mes, mv_u4_ventas_categoria_dia | SELECT. |
| app_web | fn_autenticar(text,text) | EXECUTE directo. |
| admin_datos | fn_resetear_password(bigint,text) | EXECUTE directo. |
| rol_funciones | usuario | SELECT(id,email,contrasena,eliminado); UPDATE(contrasena). |
| rol_funciones | detalle_pedido | SELECT(pedido_id,subtotal). |
| rol_funciones | pedido | SELECT(id); UPDATE(total). |
| rol_funciones | mv_u4_ventas_categoria_dia | Sólo MAINTAIN. |

El caso de permiso por columna es explícito. Por ejemplo:

```sql
GRANT SELECT (id,nombre,apellido,email,telefono,eliminado,created_at)
    ON public.usuario TO rol_app_lectura;
GRANT SELECT (id,nombre,apellido,email,telefono,eliminado), UPDATE (telefono)
    ON public.usuario TO rol_soporte;
```

No existe SELECT de tabla sobre usuario para esos roles, por lo que un
SELECT * que incluya contrasena queda denegado. Tampoco se conceden DELETE
de pedido/usuario, escritura de total/subtotal, cambios de catálogo,
MAINTAIN a logins, acceso a secuencias ni privilegios sobre la extensión FNBC.

Los cuatro contratos protegidos son:

| Función | Resultado y restricción |
|---|---|
| fn_autenticar(text,text) | id BIGINT para credenciales bcrypt válidas de usuario activo; NULL si inválidas/eliminado. No acepta los hashes demostrativos como texto plano. Registra sólo resultado y timestamp. |
| fn_resetear_password(bigint,text) | Retorna void. Sólo admin_datos; longitud 12..72 bytes o SQLSTATE 22023; usuario inexistente o id NULL, P0002. Bcrypt nuevo con coste 10; mensajes sin credenciales. |
| recalcular_total_pedido() | Conserva el recálculo de TP2 mediante UPDATE total reservado a la función; la aplicación no recibe ese UPDATE. |
| u4_refrescar_ventas() | Refresca sólo la MV diaria con MAINTAIN interno; conserva la omisión del UPDATE anidado de pedido. |

Todas tienen search_path=pg_catalog y REVOKE EXECUTE FROM PUBLIC. Los
auxiliares de pgcrypto sólo se conceden a rol_funciones. Autenticar no cambia
current_user ni otorga permisos SQL a la identidad del negocio devuelta.
Este diseño no implementa aislamiento por fila mediante RLS.

La política de objetos futuros es igualmente explícita:

```sql
ALTER DEFAULT PRIVILEGES FOR ROLE rol_propietario IN SCHEMA datos_anon
    GRANT SELECT ON TABLES TO rol_reportes;
```

En public no se concede acceso automático futuro. El SQL limpia defaults de
tablas/secuencias y revoca EXECUTE público por defecto de funciones de forma
global para rol_propietario, rol_funciones y u5_bootstrap. Un REVOKE de
funciones limitado a un esquema no revoca el default global de PUBLIC.
Los defaults no son retroactivos: usuario_anon existente recibe propietario
y GRANT explícitos; su reconstrucción D debe usar el creador correcto.

Los contratos y supuestos completos están en
[a_contratos_y_supuestos.md](a_contratos_y_supuestos.md).

## A.3. Verificación ejecutada y evidencia

La instalación se ejecutó en la copia privada y después se capturó su
estado real. El 22/10/2026 a las 19:47:13 UTC, la comparación exacta arrojó
44 ACL previstas y 44 actuales, cero faltantes y cero adicionales; también
cero membresías faltantes o adicionales. Esto verifica la matriz de
tablas/columnas y membresías, no constituye una certificación universal de
seguridad. Los privilegios implícitos del propietario se excluyen de esa
comparación y permanecen documentados.

El punto pide \du y information_schema.role_table_grants. El capturador
conserva ambas salidas y amplía su alcance a privilegios por columna,
propietarios, funciones, default ACL y catálogos de PostgreSQL 17. Esta
ampliación importa porque role_table_grants por sí sola no demuestra la
proyección de usuario ni el MAINTAIN de una MV.

```sql
-- En psql, como verificador técnico:
\du
\ddp

SELECT grantee,table_schema,table_name,privilege_type,is_grantable
FROM information_schema.role_table_grants
WHERE table_schema IN ('public','datos_anon')
  AND grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                  'rol_reportes','rol_funciones','app_web','admin_datos')
ORDER BY grantee,table_schema,table_name,privilege_type;

SELECT grantee,table_schema,table_name,column_name,privilege_type,is_grantable
FROM information_schema.role_column_grants
WHERE table_schema IN ('public','datos_anon')
  AND grantee IN ('rol_app_lectura','rol_app_escritura','rol_soporte',
                  'rol_reportes','rol_funciones','app_web','admin_datos')
ORDER BY grantee,table_schema,table_name,column_name,privilege_type;
```

Comandos técnicos empleados, desde la raíz del repositorio y con
U5_SECRET_FILE configurado hacia el JSON privado externo:

```powershell
python tools/instalar_seguridad.py
python tools/capturar_permisos.py
python tools/verificar_matriz.py
python tools/ejecutar_pruebas.py --phase permissions
python tools/ejecutar_pruebas.py --phase defaults
```

La comparación exacta usa ACL de tabla y columna por separado y excluye
privilegios implícitos del dueño. Comprueba también las tres membresías y
sus opciones. La captura complementaria inspecciona schemas/base, propietarios,
funciones y defaults; las pruebas de comportamiento usan conexiones reales
app_web/admin_datos y distinguen los grupos probados mediante SET LOCAL ROLE
con bootstrap.

| Evidencia real | Resultado observado |
|---|---|
| [a_psql_du.txt](evidencias/a_psql_du.txt) y [a_psql_ddp.txt](evidencias/a_psql_ddp.txt) | Ocho roles U5 y cuatro filas de defaults: tres funciones globales sin PUBLIC EXECUTE y SELECT de reportes en datos_anon para el creador propietario. |
| [a_permisos.json](evidencias/a_permisos.json) y archivos TSV | Captura real de atributos, tablas/columnas, funciones, propietarios, membresías y esquemas/base. |
| [a_comparacion_exacta.json](evidencias/a_comparacion_exacta.json) | PASSED; 44/44 ACL, diferencias 0/0 y diferencias de membresías 0/0. |
| [permissions_resultados.json](evidencias/permissions_resultados.json) | PASSED; 52 eventos entre 19:44:39.873 y 19:44:40.380 UTC. |
| [defaults_resultados.json](evidencias/defaults_resultados.json) | PASSED; 71 eventos entre 19:44:48.327 y 19:44:48.452 UTC; sin objetos de prueba remanentes. |
| [audit_resultados.json](evidencias/audit_resultados.json) | PASSED; 10 eventos: lectura, inserción de pedido/detalle, actualización, total correcto, transición y ROLLBACK; también login PostgreSQL fallido. |
| [incident_resultados.json](evidencias/incident_resultados.json) | PASSED; 11 eventos: tres autenticaciones fallidas y una válida; lectura autorizada de 20.001 filas sin exportarlas; GRANT denegado con 42501 y membresía administrativa ausente antes/después. |
| [d_equivalencia.json](d_equivalencia.json) | Reconstrucción bajo rol_propietario: 20.001 filas, dos grupos y diferencias EXCEPT ALL 0/0; reportes tiene SELECT automático. |
| [conservacion_before.json](evidencias/conservacion_before.json) y [conservacion_after.json](evidencias/conservacion_after.json) | Mismos conteos y huellas de contenido de las cinco tablas; same_as_before=true. |

El detalle de la comprobación permite distinguir lo siguiente:

- **Atributos y membresías:** únicamente app_web/admin_datos pueden iniciar
  sesión entre los ocho roles U5; los cinco atributos peligrosos están en
  falso para los ocho. Existen exactamente las tres membresías previstas,
  con ADMIN=false, INHERIT=true y SET=false. Ver
  [atributos](evidencias/a_atributos.tsv) y
  [membresías](evidencias/a_membresias.tsv).
- **Funciones:** exactamente fn_autenticar, fn_resetear_password,
  recalcular_total_pedido y u4_refrescar_ventas pertenecen a rol_funciones,
  tienen prosecdef=true y search_path=pg_catalog. Las otras seis funciones
  públicas pertenecen a rol_propietario y son INVOKER. La ACL autoriza
  autenticación sólo a app_web y reset sólo a admin_datos, además de su
  dueño; ningún EXECUTE público consta en esas funciones. Ver
  [funciones](evidencias/a_funciones.tsv).
- **Propiedad:** las 22 relaciones inventariadas de public/datos_anon
  —tablas, cuatro secuencias, vistas y dos MVs— pertenecen a rol_propietario;
  rol_funciones no posee ninguna. Ver
  [propietarios](evidencias/a_propietarios.tsv).
- **Esquemas/base:** los roles de negocio no tienen CREATE en los tres
  esquemas ni CREATE/TEMP de base. Los logins tienen CONNECT y USAGE de
  public, no de crypto/datos_anon. rol_funciones usa public/crypto sin CREATE;
  rol_reportes usa public/datos_anon sin CREATE. Sólo rol_propietario tiene
  TEMP entre los ocho roles. Ver
  [esquemas](evidencias/a_esquemas_efectivos.tsv) y
  [base](evidencias/a_base_efectivos.tsv).
- **Comportamiento:** app_web obtuvo SQLSTATE 42501 al leer hashes o
  SELECT * de usuario, escribir contrasena/total, eliminar pedido/usuario,
  asumir roles no habilitados, crear roles, usar nextval/setval o ejecutar
  reset. admin_datos leyó exactamente seis columnas y pudo ejecutar reset;
  se rechazaron created_at, hashes, DELETE de usuario, lectura de pedido y
  actualización de columnas ajenas a teléfono. El UPDATE de contacto se
  probó con WHERE FALSE: demuestra autorización, no modificación de una fila.
- **Contrato de reset:** usuario inexistente produjo P0002; NULL y
  longitudes 11/73 bytes y multibyte de 74 bytes produjeron 22023. Los
  límites válidos de 12 y 72 bytes se aceptaron. Los cambios se revirtieron.
- **Defaults:** una tabla nueva en public negó SELECT/INSERT/UPDATE/DELETE
  a los seis roles de negocio. En datos_anon, sólo reportes recibió SELECT.
  Las funciones creadas realmente por bootstrap, propietario y funciones
  tuvieron cero entradas PUBLIC EXECUTE y denegaron ejecución con 42501 a
  los seis roles. El CREATE concedido a rol_funciones sólo para esa prueba
  quedó dentro de la transacción: después del ROLLBACK volvió a false y no
  quedaron funciones ni tablas de prueba.
- **Puentes heredados en uso:** el flujo real app_web de la Parte B insertó
  un pedido PENDIENTE y su detalle, actualizó cantidad y comprobó total
  igual a la suma de subtotales; luego confirmó el pedido y revirtió las
  filas. El camino con triggers U4 completó correctamente sin conceder
  UPDATE total ni MAINTAIN a app_web. Esta prueba no se presenta como una
  comparación exhaustiva del contenido de ambas MVs.
- **Conservación y creador correcto:** la reconstrucción real de
  usuario_anon bajo rol_propietario obtuvo SELECT para reportes por default
  y equivalencia bilateral 0/0. La captura posterior conserva exactamente
  2 categorías, 50.000 productos, 20.001 usuarios, 225.000 pedidos y 499.997
  detalles, con iguales huellas completas a las anteriores. Los 20.000
  usuarios originales y la cuenta sintética de U5 permanecen intactos.

Los cambios de prueba se revierten; los valores consumidos por IDENTITY no
retroceden con ROLLBACK. Las huellas previas se calcularon sobre filas
completas ordenadas sin exportar las filas fuente. Ninguna prueba debe
ampliar la matriz para conseguir un resultado positivo.

## A.4. Auditoría de OpenCode y lectura crítica

Se solicitó una revisión estática real a OpenCode 1.18.23, modelo
openai/gpt-6.1-sol, agente plan y permisos de herramientas denegados. La
consulta terminó el 22/10/2026 a las 19:43:21 UTC sin ejecutar SQL ni otras
herramientas. Se conservan el [prompt](ia/a_revision_prompt.txt), los
[metadatos](ia/a_revision_metadatos.json), los adjuntos exactos y la
[respuesta completa](ia/a_revision_respuesta.md).

El auditor no identificó un incumplimiento bloqueante demostrado de la
matriz final. Señaló tres condiciones/riesgos: los literales SQL pueden
filtrar credenciales aunque se oculten parámetros; la limpieza no elimina
ACL de cualquier rol ajeno preexistente; y la autenticación conserva
diferencias temporales y no limita intentos. Se aceptó técnicamente esa
distinción: se verificaron clientes parametrizados y límites de logging,
se compararon las ACL reales del laboratorio y se dejaron documentadas las
limitaciones de autenticación sin inventar mitigaciones implementadas.

El prompt pidió además alternativas operativas para evaluarlas críticamente.
OpenCode propuso dos candidatos más amplios, advirtiendo expresamente que
excedían la matriz y recomendando conservar los GRANT puntuales:

| Propuesta real solicitada | Acceso adicional | Decisión técnica de Codex |
|---|---|---|
| Heredar rol_app_lectura desde rol_soporte | Soporte/admin_datos leerían catálogo, pedidos, detalles y usuario.created_at, además de futuras concesiones del grupo. | Rechazada: soporte sólo requiere seis columnas de contacto y UPDATE telefono. La captura conserva exactamente tres membresías, sin esta ampliación. |
| GRANT SELECT ON ALL TABLES de public a reportes y el default equivalente | Reportes leería usuario.contrasena, contacto real, fuentes del negocio, FNBC y futuros objetos públicos del creador indicado. | Rechazada: se mantienen sólo usuario_anon y las dos MVs. La comparación exacta no detectó ACL adicionales. |

Son alternativas solicitadas y candidatas inseguras para este alcance;
**no se presentan como errores espontáneos de OpenCode**. El auditor ya
explicó sus excesos. La decisión técnica fue no aplicarlas, demostrada por
la matriz actual. La conformidad de cierre de la persona solicitante consta
con su alcance en [validacion_humana.md](validacion_humana.md), sin atribuir
una aprobación individual a ambos integrantes. El contraste puntual está en
[a_revision_validacion.md](ia/a_revision_validacion.md); el registro
correspondiente debe conservarse también en BITACORA.md.

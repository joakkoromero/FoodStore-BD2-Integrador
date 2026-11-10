# Requirements: seguridad-roles-foodstore

## Introducción

Planificación del modelo de roles y permisos de Food Store (Trabajo Práctico
Unidad 5, Base de Datos II, PostgreSQL 17). Cubre ocho roles, la matriz de
privilegios por rol/objeto/columna, membresías, privilegios por defecto,
migración de propiedad de objetos existentes y pruebas previstas.

Documento generado por Kiro como planificación técnica. Ninguna prueba ha
sido ejecutada en el marco de esta especificación. La validación humana de
los integrantes queda pendiente para la entrega; no se atribuye aquí ninguna
aprobación real ocurrida.

---

## Glosario

| Término | Definición |
|---|---|
| NOLOGIN | Rol que no puede iniciar sesión; se usa como agrupador de privilegios. |
| LOGIN | Rol que puede iniciar sesión como cuenta de aplicación. |
| INHERIT TRUE | El rol hijo hereda automáticamente los privilegios del padre. |
| SET FALSE | Esa membresía NO habilita SET ROLE al padre; no es posible aunque el rol sea miembro. |
| ADMIN FALSE | No puede otorgar la membresía a otros roles. |
| SECURITY DEFINER | Función que se ejecuta con los privilegios de su propietario, no del invocador. |
| SECURITY INVOKER | Función que se ejecuta con los privilegios del invocador (comportamiento por defecto). |
| MAINTAIN | Privilegio de PostgreSQL 17 para ejecutar REFRESH MATERIALIZED VIEW. |
| datos_anon | Esquema separado que contiene únicamente datos desidentificados. |
| usuario_anon | Copia de usuario con datos sintéticos deterministas, sin credenciales ni id original. |
| bootstrap | Rol técnico transitorio usado para construir objetos antes de la Parte A; debe reemplazarse. |
| MV diaria | Vista materializada creada en U4, refrescada por trigger u4_refrescar_ventas. |
| FNBC | Extensión con tablas lote/depósito/responsable_depósito/lote_responsable y guardia técnica. |

---

## Contexto del sistema heredado

### Tablas base (esquema public)

| Tabla | Columnas |
|---|---|
| categoria | id (identity), nombre (UNIQUE), descripcion, eliminado, created_at |
| producto | id (identity), nombre, descripcion, precio, stock, categoria_id, eliminado, created_at |
| usuario | id (identity), nombre, apellido, email (UNIQUE), **contrasena**, telefono, eliminado, created_at |
| pedido | id (identity), usuario_id, fecha (TIMESTAMPTZ), forma_pago (enum), estado (enum), total, eliminado, created_at |
| detalle_pedido | PK (pedido_id, producto_id), cantidad, precio_unitario, subtotal (GENERATED: cantidad × precio_unitario) |

### Vistas y materializadas en esquema public

| Objeto | Tipo | Notas |
|---|---|---|
| Vistas TP5 | VIEW | Sin cambios en este trabajo. |
| mv_facturacion_categoria_mes | MATERIALIZED VIEW | Mensual TP5; no cambia en este trabajo. |
| mv_u4_ventas_categoria_dia | MATERIALIZED VIEW | Diaria U4; sujeta a MAINTAIN. |

### Volumen de datos

- 20.001 usuarios: 20.000 heredados intactos + 1 cuenta de prueba U5.
- 50.000 productos, 225.000 pedidos, 499.997 detalles, 2 categorías.

### Objetos adicionales

- **FNBC**: tablas lote, deposito, responsable_deposito, lote_responsable; vista control_lote_almacen y guardia técnica. No se expone a la aplicación.
- **Triggers heredados** (deben conservarse sin modificación):
  - `validar_detalle_pendiente`: solo permite editar líneas de pedidos PENDIENTE.
  - `recalcular_total_pedido`: función SECURITY INVOKER, actualiza pedido.total; propietario rol_propietario.
  - `u4_refrescar_ventas`: función SECURITY DEFINER, refresca MV diaria, omite refresco anidado; propietario rol_funciones.

### Esquema datos_anon

- `datos_anon.usuario_anon`: datos sintéticos deterministas; excluye credenciales, id original, teléfono real; conserva mes de alta local y eliminado.
- Equivalencia agregada verificada por un proceso técnico externo a Kiro.
- La tabla fue creada por el rol técnico `bootstrap` (antes de la Parte A).
- **Acción planificada**: migrar propietario a `rol_propietario` con REVOKE/GRANT explícitos. Después reconstruir bajo `SET LOCAL ROLE rol_propietario` para verificar defaults del creador correcto.

---

## Requisitos

### Requirement 1: Definición y atributos de los ocho roles

**User Story:** Como equipo técnico, quiero que todos los roles queden
definidos con atributos precisos antes de cualquier implementación SQL.

#### Justificación por rol

| Rol | Tipo | Justificación |
|---|---|---|
| rol_app_lectura | NOLOGIN | Agrupa permisos de lectura sobre catálogo y pedidos. Separa la superficie de lectura de la de escritura. |
| rol_app_escritura | NOLOGIN | Agrupa permisos de escritura acotados a columnas de negocio. Nunca incluye columnas derivadas ni credenciales. |
| rol_soporte | NOLOGIN | Agrupa permisos mínimos de atención al cliente: lectura de datos de contacto y cambio de teléfono. Sin acceso a credenciales ni capacidad de eliminar registros. |
| rol_reportes | NOLOGIN | Agrupa acceso a agregados aprobados y a la copia desidentificada. Nunca recibe acceso a tablas fuente ni permisos amplios. |
| rol_propietario | NOLOGIN | Posee esquemas, tablas, vistas, MVs, extensión FNBC y funciones SECURITY INVOKER heredadas. No se otorga como membresía a ningún login de aplicación; aísla la propiedad de objetos del acceso operativo. |
| rol_funciones | NOLOGIN | Posee exclusivamente las cuatro funciones SECURITY DEFINER (fn_autenticar, fn_resetear_password, recalcular_total_pedido, u4_refrescar_ventas). Recibe solo los permisos internos mínimos que esas funciones necesitan. No se otorga como membresía a ningún login. No posee tablas. |
| app_web | LOGIN | Cuenta de aplicación web. Hereda lectura y escritura acotadas a través de rol_app_lectura y rol_app_escritura. |
| admin_datos | LOGIN | Cuenta de administración de datos. Hereda soporte a través de rol_soporte y tiene permiso puntual propio para ejecutar fn_resetear_password. |

#### Acceptance Criteria

1. WHEN se definen los ocho roles, THEN cada uno debe tener exactamente los atributos de la tabla anterior: NOLOGIN o LOGIN según corresponda, sin SUPERUSER, CREATEDB, CREATEROLE, REPLICATION, BYPASSRLS, y nunca con ADMIN OPTION.
2. IF se intentara otorgar membresía de rol_propietario o rol_funciones a cualquier login de aplicación, THEN la operación no está planificada y requiere revisión explícita del equipo.

---

### Requirement 2: Membresías de roles LOGIN

**User Story:** Como arquitecto de seguridad, quiero que los roles de login
reciban exactamente las membresías planificadas con los flags correctos.

#### Tabla de membresías

| Login | Miembro de | INHERIT | SET | ADMIN |
|---|---|---|---|---|
| app_web | rol_app_lectura | TRUE | FALSE | FALSE |
| app_web | rol_app_escritura | TRUE | FALSE | FALSE |
| admin_datos | rol_soporte | TRUE | FALSE | FALSE |

> SET FALSE significa que esa membresía NO habilita SET ROLE al padre; no es
> posible hacer SET ROLE rol_app_lectura desde una sesión de app_web aunque
> sea miembro. INHERIT TRUE activa la herencia automática de privilegios.

#### Acceptance Criteria

1. WHEN se configura app_web, THEN recibe membresía de rol_app_lectura con INHERIT TRUE, SET FALSE, ADMIN FALSE.
2. WHEN se configura app_web, THEN recibe membresía de rol_app_escritura con INHERIT TRUE, SET FALSE, ADMIN FALSE.
3. WHEN se configura admin_datos, THEN recibe membresía de rol_soporte con INHERIT TRUE, SET FALSE, ADMIN FALSE.
4. IF desde cualquier sesión de login se intenta SET ROLE a rol_propietario o rol_funciones, THEN la operación debe ser denegada (no existe membresía planificada hacia esos roles).

---

### Requirement 3: Matriz de privilegios — rol_app_lectura

**User Story:** Como desarrollador de la aplicación web, quiero que el rol
de lectura acceda exactamente a las columnas públicas sin exponer columnas
sensibles.

#### Matriz

| Objeto | Operación | Columnas autorizadas |
|---|---|---|
| categoria | SELECT | todas |
| producto | SELECT | todas |
| usuario | SELECT | id, nombre, apellido, email, telefono, eliminado, created_at |
| pedido | SELECT | todas |
| detalle_pedido | SELECT | todas |

#### Acceptance Criteria

1. WHEN rol_app_lectura accede a usuario, THEN puede SELECT únicamente las columnas listadas; la columna contrasena NUNCA está incluida.
2. IF rol_app_lectura intenta SELECT contrasena, THEN la operación debe ser denegada.
3. WHEN rol_app_lectura accede a categoria, producto, pedido y detalle_pedido, THEN puede SELECT todas sus columnas.

---

### Requirement 4: Matriz de privilegios — rol_app_escritura

**User Story:** Como desarrollador de la aplicación web, quiero que el rol
de escritura opere únicamente sobre columnas de negocio necesarias.

#### Matriz

| Objeto | Operación | Columnas autorizadas | Notas |
|---|---|---|---|
| pedido | INSERT | usuario_id, fecha, forma_pago | estado nace DEFAULT PENDIENTE; nunca escribir total |
| pedido | UPDATE | estado, forma_pago, eliminado | baja lógica via eliminado |
| pedido | DELETE | — | DENEGADO |
| detalle_pedido | INSERT | pedido_id, producto_id, cantidad, precio_unitario | subtotal es GENERATED, nunca se escribe |
| detalle_pedido | UPDATE | cantidad, precio_unitario | — |
| detalle_pedido | DELETE | — | solo en pedidos PENDIENTE, controlado por trigger |
| usuario | DELETE | — | DENEGADO |
| usuario | UPDATE (contrasena) | — | DENEGADO |
| secuencias identity | nextval / setval | — | DENEGADO; el INSERT implícito es suficiente |

#### Acceptance Criteria

1. WHEN rol_app_escritura inserta un pedido, THEN solo puede especificar (usuario_id, fecha, forma_pago); estado nace PENDIENTE por DEFAULT sin que la aplicación lo escriba; total nunca se incluye en el INSERT.
2. WHEN rol_app_escritura actualiza un pedido, THEN solo puede modificar (estado, forma_pago, eliminado).
3. IF rol_app_escritura intenta DELETE sobre pedido, THEN la operación debe ser denegada.
4. WHEN rol_app_escritura inserta una línea de detalle_pedido, THEN solo puede especificar (pedido_id, producto_id, cantidad, precio_unitario); subtotal es GENERATED y nunca se escribe.
5. WHEN rol_app_escritura actualiza una línea de detalle_pedido, THEN solo puede modificar (cantidad, precio_unitario).
6. WHEN rol_app_escritura elimina una línea de detalle_pedido, THEN el trigger validar_detalle_pendiente garantiza que solo aplica a pedidos en estado PENDIENTE.
7. IF rol_app_escritura intenta nextval o setval sobre cualquier secuencia identity, THEN la operación debe ser denegada.
8. IF rol_app_escritura intenta UPDATE de contrasena o DELETE sobre usuario, THEN la operación debe ser denegada.

---

### Requirement 5: Matriz de privilegios — rol_soporte

**User Story:** Como agente de soporte, quiero poder consultar y actualizar
datos de contacto de usuarios sin acceso a credenciales ni a otras tablas.

#### Matriz

| Objeto | Operación | Columnas autorizadas | Notas |
|---|---|---|---|
| usuario | SELECT | id, nombre, apellido, email, telefono, eliminado | sin contrasena |
| usuario | UPDATE | telefono | solo dato de contacto |
| usuario | UPDATE (contrasena) | — | DENEGADO |
| usuario | DELETE | — | DENEGADO |
| pedido | SELECT | — | DENEGADO (fuera de alcance de soporte) |
| detalle_pedido | SELECT | — | DENEGADO (fuera de alcance de soporte) |
| catalogo / FNBC | cualquiera | — | DENEGADO |

#### Acceptance Criteria

1. WHEN rol_soporte accede a usuario, THEN puede SELECT únicamente (id, nombre, apellido, email, telefono, eliminado); contrasena NUNCA está incluida.
2. WHEN rol_soporte actualiza usuario, THEN solo puede modificar la columna telefono.
3. IF rol_soporte intenta SELECT contrasena, UPDATE de cualquier columna distinta de telefono, o DELETE sobre usuario, THEN la operación debe ser denegada.
4. IF rol_soporte intenta acceder a pedido, detalle_pedido, catalogo o cualquier objeto FNBC, THEN la operación debe ser denegada.

> admin_datos tiene permiso puntual propio para ejecutar fn_resetear_password;
> ese permiso no proviene de rol_soporte sino de un GRANT directo sobre la función.

---

### Requirement 6: Matriz de privilegios — rol_reportes

**User Story:** Como analista de reportes, quiero acceder únicamente a datos
desidentificados y a los agregados aprobados, sin poder consultar tablas
fuente ni datos de contacto.

#### Objetos autorizados para rol_reportes

| Objeto | Esquema | Operación |
|---|---|---|
| usuario_anon | datos_anon | SELECT (todas las columnas disponibles) |
| mv_facturacion_categoria_mes | public | SELECT |
| mv_u4_ventas_categoria_dia | public | SELECT |

#### Acceptance Criteria

1. WHEN rol_reportes accede a datos_anon.usuario_anon, THEN puede SELECT todas las columnas disponibles.
2. WHEN rol_reportes accede a mv_facturacion_categoria_mes, THEN puede SELECT.
3. WHEN rol_reportes accede a mv_u4_ventas_categoria_dia, THEN puede SELECT.
4. IF rol_reportes intenta SELECT sobre cualquier tabla fuente del esquema public (categoria, producto, usuario, pedido, detalle_pedido), THEN la operación debe ser denegada.
5. IF rol_reportes intenta acceder a datos de contacto reales o a objetos FNBC, THEN la operación debe ser denegada.
6. IF se intentara otorgar ALL PRIVILEGES o acceso en bloque a rol_reportes, THEN la operación no está planificada.
7. WHEN se aplican default privileges bajo rol_propietario en datos_anon, THEN rol_reportes recibe SELECT automáticamente sobre objetos nuevos creados por rol_propietario en ese esquema.

---

### Requirement 7: Propiedad de objetos — rol_propietario

**User Story:** Como arquitecto de seguridad, quiero que rol_propietario sea
el dueño aislado de todos los objetos de infraestructura, con un único permiso
técnico temporal justificado.

#### Objetos bajo propiedad de rol_propietario

| Categoría | Objetos |
|---|---|
| Esquemas | public, datos_anon |
| Tablas | todas las tablas del esquema public |
| Extensión FNBC | lote, deposito, responsable_deposito, lote_responsable, control_lote_almacen, guardia técnica |
| Vistas TP5 | todas las vistas del grupo TP5 |
| Materializadas | mv_facturacion_categoria_mes, mv_u4_ventas_categoria_dia |
| Funciones SECURITY INVOKER | recalcular_total_pedido (trigger), demás funciones heredadas que no sean SECURITY DEFINER |
| datos_anon.usuario_anon | después de migración desde bootstrap |

#### Acceptance Criteria

1. WHEN se transfiere propiedad, THEN rol_propietario debe ser propietario de todos los objetos listados en la tabla anterior.
2. WHEN se planifica la migración de datos_anon.usuario_anon, THEN el propietario debe cambiar de bootstrap a rol_propietario con REVOKE/GRANT explícitos aplicados; no basta con defaults heredados.
3. WHEN se reconstruye datos_anon.usuario_anon en el paso de verificación, THEN la construcción debe ejecutarse bajo SET LOCAL ROLE rol_propietario para confirmar defaults del creador correcto.
4. WHEN se requiere soporte para la auditoría temporal de Parte D, THEN rol_propietario puede tener el privilegio TEMPORARY únicamente en la base de datos actual; justificación exclusivamente técnica, independiente de privilegios de negocio.
5. IF se intentara otorgar TEMPORARY a app_web, admin_datos, rol_soporte o rol_reportes, THEN la operación debe ser denegada.
6. WHEN se aplican default privileges bajo rol_propietario en el esquema public, THEN ningún rol recibe acceso automático sobre objetos futuros en public.
7. WHEN se aplican default privileges bajo rol_propietario en el esquema datos_anon, THEN rol_reportes recibe SELECT automáticamente sobre objetos nuevos en ese esquema.

---

### Requirement 8: Propiedad y permisos internos — rol_funciones

**User Story:** Como arquitecto de seguridad, quiero que las cuatro funciones
SECURITY DEFINER estén aisladas en un rol propietario dedicado con permisos
internos mínimos, sin exposición a logins.

#### Funciones SECURITY DEFINER bajo propiedad de rol_funciones

| Función | Propósito |
|---|---|
| fn_autenticar | Valida bcrypt con pgcrypto; devuelve id o NULL; registra intento sin email/password/hash. |
| fn_resetear_password | Restablece contraseña; solo ejecutable por admin_datos. |
| recalcular_total_pedido | Función trigger que actualiza pedido.total. |
| u4_refrescar_ventas | Función trigger que refresca MV diaria; omite refresco anidado. |

> rol_funciones NO posee tablas. Posee ÚNICAMENTE estas cuatro funciones.

#### Permisos internos acotados de rol_funciones

| Objeto | Operación | Columnas autorizadas |
|---|---|---|
| usuario | SELECT | id, email, contrasena, eliminado |
| usuario | UPDATE | contrasena |
| detalle_pedido | SELECT | pedido_id, subtotal |
| pedido | SELECT | id |
| pedido | UPDATE | total |
| mv_u4_ventas_categoria_dia | MAINTAIN | — |

#### Acceptance Criteria

1. WHEN se define rol_funciones, THEN es NOLOGIN y no recibe membresía de ningún login ni de ningún otro rol de la jerarquía de aplicación.
2. WHEN rol_funciones posee funciones, THEN posee ÚNICAMENTE las cuatro funciones SECURITY DEFINER listadas; ninguna tabla le pertenece.
3. WHEN rol_funciones recibe permisos internos, THEN son exactamente los de la tabla anterior; ninguna columna adicional de ninguna tabla.
4. WHEN se crean o recrean las cuatro funciones, THEN cada una debe declarar search_path = pg_catalog, usar referencias de nombres calificadas, y tener REVOKE EXECUTE FROM PUBLIC aplicado.
5. IF PUBLIC intenta ejecutar fn_autenticar o fn_resetear_password directamente, THEN la operación debe ser denegada.
6. WHEN admin_datos ejecuta fn_resetear_password, THEN la operación debe ser permitida por GRANT directo sobre esa función; ningún otro login de aplicación puede ejecutarla.
7. WHEN app_web invoca fn_autenticar, THEN la función valida bcrypt con pgcrypto, devuelve id o NULL, y registra el resultado sin incluir email, password ni hash en el registro.
8. WHEN rol_funciones opera sobre la MV diaria, THEN recibe únicamente MAINTAIN; no recibe INSERT, UPDATE, DELETE ni SELECT sobre la MV.

---

### Requirement 9: Privilegios de esquema, secuencias y defaults

**User Story:** Como arquitecto de seguridad, quiero que los esquemas y los
defaults queden configurados explícitamente para que objetos futuros no
hereden accesos inadvertidos.

#### Acceptance Criteria

1. WHEN se configura el esquema public, THEN se revoca CREATE en ese esquema a todos los roles de aplicación y soporte.
2. WHEN se configuran default privileges bajo rol_propietario en public, THEN ningún rol recibe permisos automáticos sobre objetos nuevos creados por rol_propietario en public.
3. WHEN se configuran default privileges bajo rol_propietario en datos_anon, THEN rol_reportes recibe SELECT automáticamente sobre objetos nuevos en ese esquema.
4. IF se intentara conceder USAGE de secuencias identity en bloque, THEN la operación no está planificada; los grants son explícitos por tabla.
5. WHEN se revocan permisos de ejecución pública, THEN REVOKE EXECUTE FROM PUBLIC se aplica individualmente a cada una de las cuatro funciones SECURITY DEFINER.

---

### Requirement 10: Pruebas previstas de privilegios

**User Story:** Como equipo de calidad, queremos que existan pruebas
planificadas que cubran privilegios esperados (positivos) y denegados
(negativos), para verificar el modelo después de implementar el SQL.

> Estas pruebas son PREVISTAS para ejecutar tras la implementación SQL.
> No han sido ejecutadas en el marco de esta especificación.

#### Pruebas positivas previstas

| Sujeto | Operación prevista a confirmar |
|---|---|
| app_web | SELECT columnas autorizadas de usuario (sin contrasena) |
| app_web | INSERT pedido con (usuario_id, fecha, forma_pago); estado = PENDIENTE |
| app_web | UPDATE pedido con (estado, forma_pago, eliminado) |
| app_web | INSERT detalle_pedido con (pedido_id, producto_id, cantidad, precio_unitario) |
| app_web | UPDATE detalle_pedido (cantidad, precio_unitario) |
| app_web | DELETE línea de detalle en pedido PENDIENTE |
| admin_datos | SELECT columnas autorizadas de usuario |
| admin_datos | UPDATE usuario(telefono) |
| admin_datos | EXECUTE fn_resetear_password |
| rol_reportes | SELECT datos_anon.usuario_anon |
| rol_reportes | SELECT mv_facturacion_categoria_mes |
| rol_reportes | SELECT mv_u4_ventas_categoria_dia |

#### Pruebas negativas previstas

| Sujeto | Operación prevista a denegar |
|---|---|
| app_web | SELECT contrasena de usuario |
| app_web | INSERT total en pedido |
| app_web | DELETE pedido |
| app_web | DELETE usuario |
| app_web | nextval / setval en secuencias identity |
| app_web | UPDATE contrasena de usuario |
| admin_datos | SELECT contrasena de usuario |
| admin_datos | DELETE usuario |
| admin_datos | SET ROLE rol_propietario |
| admin_datos | SET ROLE rol_funciones |
| app_web | SET ROLE rol_propietario |
| app_web | SET ROLE rol_funciones |
| rol_reportes | SELECT tabla fuente (usuario, pedido, producto, etc.) en public |
| rol_reportes | SELECT datos de contacto reales |

#### Prueba de auditoría prevista

| Escenario | Descripción |
|---|---|
| 3 fallos fn_autenticar | Tres intentos de autenticación fallidos; registrados sin credenciales. |
| 1 éxito fn_autenticar | Un intento exitoso; registrado sin credenciales. |
| SELECT masivo autorizado | SELECT sobre columnas autorizadas de usuario (sin contrasena). |
| GRANT denegado | Intento de GRANT admin_datos TO app_web; denegado. |

#### Acceptance Criteria

1. WHEN se ejecuten las pruebas positivas previstas, THEN cada operación de la tabla anterior debe completarse sin error.
2. WHEN se ejecuten las pruebas negativas previstas, THEN cada operación de la tabla anterior debe producir un error de permisos.
3. WHEN se ejecuten las pruebas de defaults, THEN un objeto nuevo creado por rol_propietario en public no debe ser accesible por ningún rol de aplicación sin GRANT explícito; un objeto nuevo en datos_anon debe ser accesible por SELECT para rol_reportes.
4. IF cualquier prueba negativa produce éxito inesperado, THEN el resultado debe registrarse como fallo del modelo y requerir corrección antes de continuar.

---

### Requirement 11: Conservación de invariantes heredadas

**User Story:** Como equipo técnico, quiero garantizar que el nuevo modelo
de roles no rompa ninguna invariante de las unidades anteriores.

#### Acceptance Criteria

1. WHEN se aplica el modelo de roles, THEN los tres triggers heredados (validar_detalle_pendiente, recalcular_total_pedido, u4_refrescar_ventas) deben seguir operando correctamente.
2. WHEN se aplica el modelo de roles, THEN las vistas TP5, mv_facturacion_categoria_mes y mv_u4_ventas_categoria_dia deben seguir siendo accesibles para los roles que las usen internamente.
3. WHEN se aplica el modelo de roles, THEN los 20.000 usuarios heredados y sus pedidos asociados no deben ser modificados ni afectados por las operaciones de configuración de roles.
4. WHEN se configura la extensión FNBC, THEN sus tablas y vista de guardia no reciben ningún privilegio de los roles de aplicación; permanecen bajo el dominio exclusivo de rol_propietario.
5. WHEN se recrean fn_autenticar y fn_resetear_password con SECURITY DEFINER, THEN su comportamiento funcional (validación bcrypt, devolución de id o NULL, registro sin credenciales) no debe cambiar.

---

## Restricciones globales

| Restricción | Descripción |
|---|---|
| Sin SQL en esta especificación | Este documento no contiene ni genera código SQL. |
| Sin implementación automática | Kiro no ejecuta comandos, no se conecta a bases de datos y no crea archivos SQL. |
| Validación humana pendiente | Toda implementación requiere revisión y aprobación explícita de los integrantes. |
| Mínimo privilegio | Ningún rol recibe más permisos de los estrictamente necesarios. |
| Sin ALL PRIVILEGES | No se planifica ALL PRIVILEGES ni permisos en bloque para ningún rol. |
| Sin blanket USAGE en secuencias | Grants sobre secuencias identity son explícitos; no se concede USAGE global. |
| Sin TEMPORARY para roles de negocio | app_web, admin_datos, rol_soporte y rol_reportes no reciben TEMPORARY. Solo rol_propietario, con justificación técnica acotada a Parte D. |
| contrasena siempre excluida de aplicación | Ningún rol de aplicación, soporte ni reportes puede leer la columna contrasena. Solo rol_funciones la accede internamente para bcrypt. |
| Datos heredados intactos | Los 20.000 usuarios heredados no se modifican. La única adición es la cuenta de prueba U5. |
| rol_funciones sin tablas propias | rol_funciones posee únicamente las cuatro funciones SECURITY DEFINER; ninguna tabla le pertenece. |
| Propiedad sin superposición | rol_propietario posee objetos de infraestructura y funciones SECURITY INVOKER. rol_funciones posee únicamente las cuatro funciones SECURITY DEFINER. No hay superposición. |

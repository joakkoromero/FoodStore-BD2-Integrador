# Requirements: seguridad-roles-foodstore

## Introducción

Este documento especifica los requisitos funcionales y de seguridad para la
planificación del modelo de roles y permisos de Food Store (Trabajo Práctico
Unidad 5, Base de Datos II, PostgreSQL 17). Cubre la definición de ocho roles,
la matriz explícita de privilegios por rol/objeto/columna, las membresías, los
privilegios por defecto, la migración de propiedad de objetos ya existentes y
las pruebas previstas.

Esta es una planificación técnica generada por Kiro. Ninguna prueba ha sido
ejecutada en el marco de esta especificación, y ninguna decisión de los
integrantes ha sido validada ni atribuida a este proceso automatizado.

---

## Glosario

| Término | Definición |
|---|---|
| NOLOGIN | Rol de PostgreSQL que no puede iniciar sesión directamente; se usa como agrupador de privilegios. |
| LOGIN | Rol de PostgreSQL que puede iniciar sesión como cuenta de aplicación. |
| INHERIT TRUE | El rol hijo hereda automáticamente los privilegios del rol padre. |
| SET FALSE | No permite hacer SET ROLE al padre sin una acción explícita. |
| ADMIN FALSE | No puede otorgar la membresía a otros roles. |
| SECURITY DEFINER | Función que se ejecuta con los privilegios de su propietario, no del invocador. |
| MAINTAIN | Privilegio de PostgreSQL 17 que permite ejecutar REFRESH MATERIALIZED VIEW. |
| datos_anon | Esquema separado que contiene únicamente datos desidentificados. |
| usuario_anon | Copia de la tabla usuario con datos sintéticos deterministas, sin credenciales ni id original. |
| bootstrap | Rol técnico transitorio usado para construir objetos antes de la Parte A; debe ser reemplazado. |
| MV diaria | Vista materializada creada en U4, refrescada por trigger. |
| FNBC | Extensión de tablas lote/depósito/responsable_depósito/lote_responsable con guardia técnica propia. |

---

## Contexto del sistema heredado

### Esquema public — tablas base

| Tabla | Columnas |
|---|---|
| categoria | id (identity), nombre (UNIQUE), descripcion, eliminado, created_at |
| producto | id (identity), nombre, descripcion, precio, stock, categoria_id, eliminado, created_at |
| usuario | id (identity), nombre, apellido, email (UNIQUE), **contrasena**, telefono, eliminado, created_at |
| pedido | id (identity), usuario_id, fecha (TIMESTAMPTZ), forma_pago (enum), estado (enum), total, eliminado, created_at |
| detalle_pedido | PK (pedido_id, producto_id), cantidad, precio_unitario, subtotal (GENERATED: cantidad × precio_unitario) |

### Volumen de datos

- 20.001 usuarios: 20.000 heredados (intactos, no se modifican) + 1 cuenta de prueba U5.
- 50.000 productos, 225.000 pedidos, 499.997 detalles, 2 categorías.

### Objetos adicionales heredados

- **Extensión FNBC**: tablas lote, deposito, responsable_deposito, lote_responsable; vista control_lote_almacen y guardia técnica. No se expone a la aplicación.
- **Vistas TP5**: sin cambios en este trabajo.
- **Materializada mensual TP5**: no cambia en este trabajo.
- **Materializada diaria U4**: refrescada por trigger; sujeta a privilegio MAINTAIN.
- **Triggers heredados**:
  - `validar_detalle_pendiente`: solo permite editar líneas de pedidos en estado PENDIENTE.
  - `recalcular_total_pedido`: actualiza pedido.total automáticamente.
  - `u4_refrescar_ventas`: refresca MV diaria; omite refresco anidado de pedido.

Todos los triggers y reglas heredados deben conservarse sin modificación.

### Esquema datos_anon

- Contiene `datos_anon.usuario_anon`: copia con datos sintéticos deterministas.
- Excluye: credenciales, id original, teléfono real.
- Conserva: mes de alta local y columna eliminado.
- Equivalencia agregada verificada por un proceso técnico externo a Kiro.
- La tabla fue creada por el rol técnico `bootstrap` (antes de la Parte A).
- **Acción planificada**: migrar propietario a `rol_propietario` y aplicar REVOKE/GRANT explícitos; no es suficiente depender de defaults heredados. Después se repetirá la construcción bajo `SET LOCAL ROLE rol_propietario` para verificar que los defaults del creador correcto se aplican.

---

## Requisitos de roles

### Requirement 1: Definición de los ocho roles

**User Story:** Como equipo técnico, queremos que el sistema de roles quede
completamente definido antes de cualquier implementación SQL, para que la
planificación sea revisable y aprobable por los integrantes.

#### Justificación por rol

| Rol | Tipo | Justificación |
|---|---|---|
| rol_app_lectura | NOLOGIN | Agrupa los permisos de solo lectura que la aplicación web necesita sobre el catálogo y los pedidos. Separa la superficie de lectura de la de escritura para aplicar mínimo privilegio. |
| rol_app_escritura | NOLOGIN | Agrupa los permisos de escritura acotados a las columnas de negocio estrictamente necesarias. Nunca incluye columnas derivadas ni credenciales. |
| rol_soporte | NOLOGIN | Agrupa los permisos mínimos para atención al cliente: lectura de datos de contacto y cambio de teléfono. No puede acceder a credenciales ni eliminar registros. |
| rol_reportes | NOLOGIN | Agrupa el acceso exclusivo al esquema datos_anon. Nunca recibe acceso a tablas fuente ni permisos amplios. |
| rol_propietario | NOLOGIN | Posee todos los objetos del esquema public, la extensión FNBC, las vistas y las funciones protegidas. No se otorga como membresía a ningún login de aplicación, para aislar la propiedad de los objetos del acceso operativo. |
| rol_funciones | NOLOGIN | Es propietario exclusivo de las funciones SECURITY DEFINER (puentes de seguridad). Recibe únicamente los permisos internos mínimos que cada función necesita para operar. No se otorga como membresía a ningún login. |
| app_web | LOGIN | Cuenta de aplicación web. Hereda lectura y escritura acotadas a través de rol_app_lectura y rol_app_escritura. |
| admin_datos | LOGIN | Cuenta de administración de datos. Hereda soporte a través de rol_soporte y es el único login autorizado a ejecutar fn_resetear_password. |

#### Acceptance Criteria

1. WHEN se define el modelo de roles, THEN los ocho roles deben existir con exactamente los atributos especificados: NOLOGIN o LOGIN según corresponda, sin SUPERUSER, sin CREATEDB, sin CREATEROLE, sin REPLICATION, sin BYPASSRLS, y nunca con ADMIN OPTION.
2. WHEN se asignan membresías, THEN todas deben declararse con INHERIT TRUE, SET FALSE, ADMIN FALSE.
3. WHEN rol_propietario o rol_funciones son referenciados, THEN ningún rol LOGIN de aplicación (app_web, admin_datos) debe recibir membresía a ninguno de esos dos roles.

---

### Requirement 2: Membresías de roles LOGIN

**User Story:** Como arquitecto de seguridad, quiero que los roles de login
reciban exactamente las membresías planificadas, para que el principio de
mínimo privilegio se verifique sin ambigüedad.

#### Acceptance Criteria

1. WHEN se configura app_web, THEN debe recibir membresía de rol_app_lectura con INHERIT TRUE, SET FALSE, ADMIN FALSE.
2. WHEN se configura app_web, THEN debe recibir membresía de rol_app_escritura con INHERIT TRUE, SET FALSE, ADMIN FALSE.
3. WHEN se configura admin_datos, THEN debe recibir membresía de rol_soporte con INHERIT TRUE, SET FALSE, ADMIN FALSE.
4. IF se intentara otorgar membresía de rol_propietario o rol_funciones a cualquier login, THEN la operación debe ser rechazada por política (no planificada y no ejecutable sin revisión explícita del equipo).

---

### Requirement 3: Matriz de privilegios — rol_app_lectura

**User Story:** Como desarrollador de la aplicación web, quiero que el rol de
lectura acceda exactamente a las columnas públicas del catálogo y los pedidos,
sin exponer ninguna columna sensible.

#### Acceptance Criteria

1. WHEN rol_app_lectura accede a categoria, THEN puede SELECT todas sus columnas.
2. WHEN rol_app_lectura accede a producto, THEN puede SELECT todas sus columnas.
3. WHEN rol_app_lectura accede a usuario, THEN puede SELECT únicamente (id, nombre, apellido, email, telefono, eliminado, created_at); la columna contrasena NUNCA debe estar incluida.
4. WHEN rol_app_lectura accede a pedido, THEN puede SELECT todas sus columnas.
5. WHEN rol_app_lectura accede a detalle_pedido, THEN puede SELECT todas sus columnas.
6. IF rol_app_lectura intenta leer contrasena de usuario, THEN la operación debe ser denegada.

---

### Requirement 4: Matriz de privilegios — rol_app_escritura

**User Story:** Como desarrollador de la aplicación web, quiero que el rol de
escritura opere únicamente sobre las columnas de negocio necesarias, sin poder
afectar columnas derivadas, credenciales ni registros eliminados permanentemente.

#### Acceptance Criteria

1. WHEN rol_app_escritura inserta un pedido, THEN solo puede especificar las columnas (usuario_id, fecha, forma_pago); la columna estado debe nacer con el valor DEFAULT PENDIENTE sin que la aplicación lo escriba explícitamente.
2. WHEN rol_app_escritura inserta un pedido, THEN no puede incluir la columna total en el INSERT.
3. WHEN rol_app_escritura actualiza un pedido, THEN solo puede modificar las columnas (estado, forma_pago, eliminado).
4. IF rol_app_escritura intenta DELETE sobre pedido, THEN la operación debe ser denegada; la baja lógica se realiza mediante UPDATE eliminado.
5. WHEN rol_app_escritura inserta una línea de detalle_pedido, THEN solo puede especificar las columnas (pedido_id, producto_id, cantidad, precio_unitario); la columna subtotal es GENERATED y nunca se escribe directamente.
6. WHEN rol_app_escritura actualiza una línea de detalle_pedido, THEN solo puede modificar las columnas (cantidad, precio_unitario).
7. WHEN rol_app_escritura elimina una línea de detalle_pedido, THEN puede usar DELETE solo sobre líneas de pedidos en estado PENDIENTE (controlado por el trigger validar_detalle_pendiente heredado).
8. IF rol_app_escritura intenta nextval o setval directamente sobre cualquier secuencia identity, THEN la operación debe ser denegada; el INSERT implícito es suficiente.
9. IF rol_app_escritura intenta UPDATE de contrasena o de cualquier columna de credenciales, THEN la operación debe ser denegada.
10. IF rol_app_escritura intenta DELETE sobre usuario, THEN la operación debe ser denegada.

---

### Requirement 5: Matriz de privilegios — rol_soporte

**User Story:** Como agente de soporte, quiero poder consultar y actualizar
datos de contacto de usuarios sin tener acceso a credenciales ni poder
eliminar registros.

#### Acceptance Criteria

1. WHEN rol_soporte accede a usuario, THEN puede SELECT únicamente (id, nombre, apellido, email, telefono, eliminado); la columna contrasena NUNCA debe estar incluida.
2. WHEN rol_soporte actualiza usuario, THEN solo puede modificar la columna telefono.
3. IF rol_soporte intenta UPDATE de contrasena u otra columna de credenciales, THEN la operación debe ser denegada.
4. IF rol_soporte intenta DELETE sobre usuario, THEN la operación debe ser denegada.
5. WHEN rol_soporte accede a pedido, THEN puede SELECT todas sus columnas (lectura para atención al cliente).
6. WHEN rol_soporte accede a detalle_pedido, THEN puede SELECT todas sus columnas.

---

### Requirement 6: Matriz de privilegios — rol_reportes

**User Story:** Como analista de reportes, quiero acceder únicamente a datos
desidentificados aprobados, sin poder consultar las tablas fuente ni recibir
permisos amplios.

#### Acceptance Criteria

1. WHEN rol_reportes accede al esquema datos_anon, THEN puede SELECT todas las columnas disponibles de datos_anon.usuario_anon.
2. IF rol_reportes intenta acceder a cualquier tabla del esquema public (categoria, producto, usuario, pedido, detalle_pedido), THEN la operación debe ser denegada.
3. IF se intentara otorgar ALL PRIVILEGES o permisos en bloque a rol_reportes, THEN la operación no está planificada y debe requerir revisión explícita.
4. WHEN se aplican default privileges bajo rol_propietario en el esquema datos_anon, THEN rol_reportes recibe SELECT automáticamente sobre objetos nuevos creados por rol_propietario en ese esquema.

---

### Requirement 7: Privilegios de rol_propietario

**User Story:** Como arquitecto de seguridad, quiero que rol_propietario sea
el dueño aislado de todos los objetos críticos, con un permiso temporal
técnico justificado, sin actuar como cuenta de aplicación.

#### Acceptance Criteria

1. WHEN se transfiere propiedad de objetos, THEN rol_propietario debe ser propietario de: todas las tablas del esquema public, la extensión FNBC y sus objetos asociados, las vistas TP5, las materializadas mensual y diaria.
2. WHEN se transfiere propiedad de funciones, THEN rol_propietario debe ser propietario de las funciones fn_autenticar, fn_resetear_password, y las funciones trigger de recalcular total y refrescar MV diaria.
3. WHEN se planifica la migración de datos_anon.usuario_anon, THEN el propietario de esa tabla debe cambiar de bootstrap a rol_propietario, con REVOKE/GRANT explícitos aplicados.
4. WHEN se reconstruye datos_anon.usuario_anon en el paso de verificación, THEN la construcción debe ejecutarse bajo SET LOCAL ROLE rol_propietario para confirmar que los defaults del creador correcto se aplican.
5. WHEN se requiere soporte para la auditoría temporal de Parte D, THEN rol_propietario puede tener el privilegio TEMPORARY únicamente en la base de datos actual; este permiso tiene justificación exclusivamente técnica (tablas temporales para auditoría) y es independiente de los privilegios de negocio.
6. IF se intentara otorgar TEMPORARY a app_web, admin_datos, rol_soporte o rol_reportes, THEN la operación debe ser denegada; ese privilegio no está planificado para roles de negocio.
7. WHEN se aplican default privileges bajo rol_propietario en el esquema public, THEN ningún rol recibe acceso automático sobre objetos futuros creados por rol_propietario en public (acceso futuro denegado por defecto).

---

### Requirement 8: Privilegios de rol_funciones y funciones SECURITY DEFINER

**User Story:** Como arquitecto de seguridad, quiero que las funciones críticas
estén aisladas en un rol propietario dedicado con permisos internos mínimos,
para que ningún login pueda invocarlas sin autorización explícita.

#### Acceptance Criteria

1. WHEN se define rol_funciones, THEN es NOLOGIN y no recibe membresía de ningún login ni de ningún otro rol de la jerarquía de aplicación.
2. WHEN rol_funciones posee funciones, THEN posee únicamente los puentes SECURITY DEFINER: fn_autenticar, fn_resetear_password, la función trigger de recalcular pedido.total y la función trigger de refrescar MV diaria.
3. WHEN rol_funciones necesita permisos internos sobre usuario, THEN recibe SELECT (id, email, contrasena, eliminado) y UPDATE (contrasena); ninguna otra columna de usuario.
4. WHEN rol_funciones necesita permisos internos sobre detalle_pedido, THEN recibe SELECT (pedido_id, subtotal); ninguna otra columna de detalle_pedido.
5. WHEN rol_funciones necesita permisos internos sobre pedido, THEN recibe SELECT (id) y UPDATE (total); ninguna otra columna de pedido.
6. WHEN rol_funciones necesita operar sobre la MV diaria, THEN recibe únicamente MAINTAIN (PostgreSQL 17); no recibe INSERT, UPDATE ni DELETE sobre la MV.
7. WHEN se crean o recrían las funciones SECURITY DEFINER, THEN cada función debe declarar search_path igual a pg_catalog, usar referencias de nombres calificadas y tener REVOKE EXECUTE FROM PUBLIC aplicado.
8. IF PUBLIC intenta ejecutar fn_autenticar o fn_resetear_password directamente, THEN la operación debe ser denegada.
9. WHEN admin_datos ejecuta fn_resetear_password, THEN la operación debe ser permitida; ningún otro login de aplicación puede ejecutar esa función.
10. WHEN app_web invoca fn_autenticar, THEN la función valida bcrypt con pgcrypto, devuelve id o NULL, y registra el resultado del intento sin incluir email, password ni hash en el registro.

---

### Requirement 9: Privilegios de esquema y defaults

**User Story:** Como arquitecto de seguridad, quiero que el esquema public
y el esquema datos_anon tengan permisos de esquema y defaults configurados
explícitamente, para que objetos futuros no hereden accesos inadvertidos.

#### Acceptance Criteria

1. WHEN se configura el esquema public, THEN se debe revocar CREATE en ese esquema a todos los roles de aplicación (rol_app_lectura, rol_app_escritura, rol_soporte, rol_reportes, app_web, admin_datos).
2. WHEN se configuran default privileges bajo rol_propietario en el esquema public, THEN ningún rol recibe permisos automáticos sobre objetos nuevos; el acceso futuro queda denegado por defecto.
3. WHEN se configuran default privileges bajo rol_propietario en el esquema datos_anon, THEN rol_reportes recibe SELECT automáticamente sobre objetos nuevos creados por rol_propietario en ese esquema.
4. IF se intentara conceder USAGE de secuencias identity en bloque (blanket USAGE), THEN la operación no está planificada; los grants deben ser explícitos por tabla.
5. WHEN se revocan permisos de ejecución pública, THEN REVOKE EXECUTE FROM PUBLIC se aplica a cada función SECURITY DEFINER individualmente.

---

### Requirement 10: Pruebas previstas de privilegios

**User Story:** Como equipo de calidad, queremos que existan pruebas
planificadas que cubran tanto los privilegios que deben funcionar (positivos)
como los que deben ser denegados (negativos), para verificar el modelo antes
de ponerlo en producción.

#### Acceptance Criteria

1. WHEN se ejecuten pruebas positivas de app_web, THEN deben confirmar: SELECT de columnas autorizadas de usuario (sin contrasena), INSERT de pedido con columnas (usuario_id, fecha, forma_pago), UPDATE de estado de pedido, INSERT de detalle_pedido con columnas (pedido_id, producto_id, cantidad, precio_unitario), UPDATE y DELETE de línea de detalle en pedido PENDIENTE.
2. WHEN se ejecuten pruebas negativas de app_web, THEN deben confirmar denegación de: SELECT contrasena, INSERT total en pedido, DELETE pedido, DELETE usuario, nextval/setval directo en secuencias, UPDATE contrasena.
3. WHEN se ejecuten pruebas positivas de admin_datos, THEN deben confirmar: SELECT columnas autorizadas de usuario, UPDATE telefono, EXECUTE fn_resetear_password.
4. WHEN se ejecuten pruebas negativas de admin_datos, THEN deben confirmar denegación de: SELECT contrasena, DELETE usuario, EXECUTE fn_autenticar directamente (si no está planificado).
5. WHEN se ejecuten pruebas positivas de rol_reportes, THEN deben confirmar: SELECT sobre datos_anon.usuario_anon.
6. WHEN se ejecuten pruebas negativas de rol_reportes, THEN deben confirmar denegación de: SELECT sobre cualquier tabla del esquema public.
7. WHEN se ejecuten pruebas de membresía, THEN deben confirmar que SET ROLE a rol_propietario o rol_funciones desde cualquier login produce error (SET FALSE).
8. WHEN se ejecuten pruebas de defaults, THEN deben confirmar que un objeto nuevo creado por rol_propietario en public no es accesible por defecto para ningún rol de aplicación, y que un objeto nuevo en datos_anon sí es accesible por SELECT para rol_reportes.
9. WHEN se simule el escenario de auditoría, THEN deben registrarse: 3 fallos de fn_autenticar, 1 éxito, 1 SELECT masivo de columnas autorizadas de usuario, 1 intento de GRANT admin_datos TO app_web (denegado).
10. IF cualquier prueba negativa produce éxito inesperado, THEN el resultado debe registrarse como fallo del modelo de permisos y requerir corrección antes de proceder con design.md.

---

### Requirement 11: Conservación de invariantes heredadas

**User Story:** Como equipo técnico, queremos garantizar que el nuevo modelo
de roles no rompa ninguna invariante de las unidades anteriores.

#### Acceptance Criteria

1. WHEN se aplica el modelo de roles, THEN los triggers validar_detalle_pendiente, recalcular_total_pedido y u4_refrescar_ventas deben seguir operando correctamente.
2. WHEN se aplica el modelo de roles, THEN las vistas TP5, la materializada mensual y la materializada diaria deben seguir siendo accesibles para los roles que las usen internamente.
3. WHEN se aplica el modelo de roles, THEN los 20.000 usuarios heredados y sus pedidos asociados no deben ser modificados ni afectados por las operaciones de configuración de roles.
4. WHEN se configura la extensión FNBC, THEN sus tablas y vista de guardia no reciben ningún privilegio de los roles de aplicación; permanecen bajo el dominio exclusivo de rol_propietario.
5. WHEN se reconstruyen fn_autenticar y fn_resetear_password con SECURITY DEFINER, THEN su comportamiento funcional (validación bcrypt, devolución de id o NULL, registro de resultado) no debe cambiar respecto a la especificación original.

---

## Restricciones globales

| Restricción | Descripción |
|---|---|
| No SQL en esta especificación | Este documento no contiene ni genera código SQL. La implementación requiere revisión técnica y aprobación del equipo. |
| No implementación automática | Kiro no ejecuta comandos, no se conecta a ninguna base de datos y no crea archivos SQL. |
| Validación humana pendiente | Toda implementación derivada de este documento requiere revisión y aprobación explícita de los integrantes del trabajo. |
| Mínimo privilegio | Ningún rol recibe más permisos de los estrictamente necesarios para su función. |
| Sin ALL PRIVILEGES | No se planifica conceder ALL PRIVILEGES ni permisos en bloque a ningún rol. |
| Sin blanket USAGE en secuencias | Los grants sobre secuencias identity son explícitos; no se concede USAGE global. |
| Sin TEMP para roles de negocio | app_web, admin_datos, rol_soporte y rol_reportes no reciben TEMPORARY. Solo rol_propietario tiene TEMPORARY con justificación técnica acotada. |
| Columna contrasena siempre excluida | Ningún rol de aplicación ni de soporte puede leer la columna contrasena de usuario. Solo rol_funciones la lee internamente para bcrypt. |
| Datos heredados intactos | Los 20.000 usuarios heredados no se modifican. La cuenta de prueba U5 es la única adición. |

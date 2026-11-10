# Requirements: seguridad-roles-foodstore

## Introducción

Planificación del modelo de roles y permisos de Food Store (TP Unidad 5,
Base de Datos II, PostgreSQL 17). Cubre ocho roles, matriz de privilegios
por rol/objeto/columna, membresías, defaults, migración de propiedad y
pruebas previstas. Documento generado por Kiro como planificación técnica;
ninguna prueba ha sido ejecutada. Validación humana de los integrantes
pendiente para la entrega; la revisión automática de Codex no la sustituye.

---

## Glosario

| Término | Definición |
|---|---|
| NOLOGIN | Rol sin capacidad de sesión directa; agrupador de privilegios. |
| LOGIN | Rol con capacidad de sesión como cuenta de aplicación. |
| INHERIT TRUE | El miembro hereda automáticamente los privilegios del padre. |
| SET FALSE | Esa membresía NO habilita SET ROLE al padre; imposible por diseño. |
| ADMIN FALSE | No puede otorgar la membresía a otros roles. |
| SECURITY DEFINER | Función ejecutada con privilegios de su propietario. |
| SECURITY INVOKER | Función ejecutada con privilegios del invocador (por defecto). |
| MAINTAIN | Privilegio PG17 para REFRESH MATERIALIZED VIEW. |
| bootstrap | Rol técnico transitorio pre-Parte A; debe reemplazarse como propietario. |

---

## Contexto del sistema heredado

### Tablas base (esquema public)

| Tabla | Columnas relevantes |
|---|---|
| categoria | id (identity), nombre, descripcion, eliminado, created_at |
| producto | id (identity), nombre, descripcion, precio, stock, categoria_id, eliminado, created_at |
| usuario | id (identity), nombre, apellido, email, **contrasena**, telefono, eliminado, created_at |
| pedido | id (identity), usuario_id, fecha, forma_pago, estado, total, eliminado, created_at |
| detalle_pedido | PK(pedido_id, producto_id), cantidad, precio_unitario, subtotal (GENERATED) |

### Vistas y materializadas (esquema public)

| Objeto | Tipo |
|---|---|
| Vistas TP5 | VIEW — sin cambios en este trabajo |
| mv_facturacion_categoria_mes | MATERIALIZED VIEW mensual — sin cambios |
| mv_u4_ventas_categoria_dia | MATERIALIZED VIEW diaria U4 |

### Volumen: 20.001 usuarios (20.000 heredados intactos + 1 prueba U5), 50.000 productos, 225.000 pedidos, 499.997 detalles.

### Triggers heredados (deben conservarse sin modificación)

| Trigger / Función | Tipo | Propietario |
|---|---|---|
| validar_detalle_pendiente | SECURITY INVOKER | rol_propietario |
| recalcular_total_pedido | **SECURITY DEFINER** | **rol_funciones** |
| u4_refrescar_ventas | **SECURITY DEFINER** | **rol_funciones** |

### Esquema datos_anon
`datos_anon.usuario_anon`: datos sintéticos deterministas; excluye credenciales,
id original, teléfono real; conserva mes de alta y eliminado. Equivalencia
agregada verificada por proceso técnico externo a Kiro. Creada por bootstrap;
se planifica migrar propietario a rol_propietario con REVOKE/GRANT explícitos
y reconstruir bajo SET LOCAL ROLE rol_propietario para verificar defaults.

**FNBC**: tablas lote/deposito/responsable_deposito/lote_responsable, vista
control_lote_almacen y guardia técnica. No se expone a roles de aplicación.

---

## Requisitos

### Requirement 1: Definición y atributos de los ocho roles

**User Story:** Como equipo técnico, quiero todos los roles definidos con
atributos precisos antes de cualquier SQL.

#### Justificación por rol

| Rol | Tipo | Justificación |
|---|---|---|
| rol_app_lectura | NOLOGIN | Agrupa lectura de catálogo y pedidos; separa superficie de lectura de escritura. |
| rol_app_escritura | NOLOGIN | Agrupa escritura acotada a columnas de negocio; excluye columnas derivadas y credenciales. |
| rol_soporte | NOLOGIN | Permisos mínimos de atención al cliente: datos de contacto y cambio de teléfono únicamente. |
| rol_reportes | NOLOGIN | Acceso a agregados aprobados y copia desidentificada; nunca tablas fuente ni permisos amplios. |
| rol_propietario | NOLOGIN | Posee esquemas, tablas, vistas, MVs, FNBC y funciones SECURITY INVOKER. No se otorga a ningún login. |
| rol_funciones | NOLOGIN | Posee exclusivamente las cuatro funciones SECURITY DEFINER. Permisos internos mínimos. No posee tablas. No se otorga a ningún login. |
| app_web | LOGIN | Hereda lectura y escritura acotadas vía rol_app_lectura y rol_app_escritura. |
| admin_datos | LOGIN | Hereda soporte vía rol_soporte; tiene GRANT puntual propio sobre fn_resetear_password. |

**Todos sin** SUPERUSER, CREATEDB, CREATEROLE, REPLICATION, BYPASSRLS, ADMIN OPTION.

#### Acceptance Criteria
1. WHEN se definen los ocho roles, THEN cada uno tiene exactamente los atributos de la tabla anterior.
2. IF se intentara otorgar membresía de rol_propietario o rol_funciones a cualquier login, THEN la operación no está planificada y requiere revisión explícita.

---

### Requirement 2: Membresías de roles LOGIN

| Login | Miembro de | INHERIT | SET | ADMIN |
|---|---|---|---|---|
| app_web | rol_app_lectura | TRUE | FALSE | FALSE |
| app_web | rol_app_escritura | TRUE | FALSE | FALSE |
| admin_datos | rol_soporte | TRUE | FALSE | FALSE |

#### Acceptance Criteria
1. WHEN se configuran los logins, THEN las membresías coinciden exactamente con la tabla.
2. IF desde cualquier sesión de login se intenta SET ROLE a rol_propietario o rol_funciones, THEN la operación es denegada (no existe membresía planificada).

---

### Requirement 3: Matriz — rol_app_lectura

| Objeto | Op | Columnas autorizadas |
|---|---|---|
| categoria | SELECT | todas |
| producto | SELECT | todas |
| usuario | SELECT | id, nombre, apellido, email, telefono, eliminado, created_at |
| pedido | SELECT | todas |
| detalle_pedido | SELECT | todas |

#### Acceptance Criteria
1. WHEN rol_app_lectura accede a usuario, THEN contrasena NUNCA está incluida.
2. IF rol_app_lectura intenta SELECT contrasena, THEN denegado.

---

### Requirement 4: Matriz — rol_app_escritura

| Objeto | Op | Columnas autorizadas | Notas |
|---|---|---|---|
| pedido | INSERT | usuario_id, fecha, forma_pago | estado = DEFAULT PENDIENTE; total excluido |
| pedido | UPDATE | estado, forma_pago, eliminado | baja lógica vía eliminado |
| pedido | DELETE | — | DENEGADO |
| detalle_pedido | INSERT | pedido_id, producto_id, cantidad, precio_unitario | subtotal GENERATED, nunca se escribe |
| detalle_pedido | UPDATE | cantidad, precio_unitario | — |
| detalle_pedido | DELETE | — | solo en PENDIENTE (trigger) |
| usuario | DELETE | — | DENEGADO |
| usuario | UPDATE contrasena | — | DENEGADO |
| secuencias identity | nextval/setval | — | DENEGADO |

#### Acceptance Criteria
1. WHEN INSERT pedido, THEN solo (usuario_id, fecha, forma_pago); estado nace PENDIENTE; total no se incluye.
2. WHEN UPDATE pedido, THEN solo (estado, forma_pago, eliminado).
3. IF DELETE pedido o DELETE usuario o UPDATE contrasena o nextval/setval, THEN denegado.
4. WHEN INSERT detalle, THEN solo (pedido_id, producto_id, cantidad, precio_unitario); subtotal excluido.
5. WHEN DELETE detalle, THEN trigger validar_detalle_pendiente garantiza pedido en PENDIENTE.

---

### Requirement 5: Matriz — rol_soporte

| Objeto | Op | Columnas autorizadas | Notas |
|---|---|---|---|
| usuario | SELECT | id, nombre, apellido, email, telefono, eliminado | sin contrasena |
| usuario | UPDATE | telefono | solo contacto |
| usuario | UPDATE otras cols | — | DENEGADO |
| usuario | DELETE | — | DENEGADO |
| pedido / detalle / catálogo / FNBC | cualquiera | — | DENEGADO |

> admin_datos ejecuta fn_resetear_password por GRANT puntual directo, no por rol_soporte.

#### Acceptance Criteria
1. WHEN rol_soporte accede a usuario, THEN SELECT solo columnas listadas; contrasena NUNCA incluida.
2. WHEN rol_soporte actualiza usuario, THEN solo telefono.
3. IF rol_soporte intenta cualquier operación sobre pedido, detalle, catálogo o FNBC, THEN denegado.

---

### Requirement 6: Matriz — rol_reportes

| Objeto | Esquema | Op |
|---|---|---|
| usuario_anon | datos_anon | SELECT (todas las columnas) |
| mv_facturacion_categoria_mes | public | SELECT |
| mv_u4_ventas_categoria_dia | public | SELECT |

#### Acceptance Criteria
1. WHEN rol_reportes accede a los tres objetos autorizados, THEN SELECT permitido.
2. IF rol_reportes intenta acceder a cualquier tabla fuente de public o a datos de contacto reales, THEN denegado.
3. IF se intentara ALL PRIVILEGES o acceso en bloque a rol_reportes, THEN no está planificado.
4. WHEN defaults bajo rol_propietario en datos_anon, THEN rol_reportes recibe SELECT sobre objetos nuevos en ese esquema.

---

### Requirement 7: Propiedad — rol_propietario

#### Objetos bajo propiedad de rol_propietario

| Categoría | Objetos |
|---|---|
| Esquemas | public, datos_anon |
| Tablas public | todas |
| FNBC | lote, deposito, responsable_deposito, lote_responsable, control_lote_almacen, guardia |
| Vistas | todas las vistas TP5 |
| Materializadas | mv_facturacion_categoria_mes, mv_u4_ventas_categoria_dia |
| Funciones SECURITY INVOKER | validar_detalle_pendiente y demás funciones heredadas no SECURITY DEFINER |
| datos_anon.usuario_anon | tras migración desde bootstrap |

#### Acceptance Criteria
1. WHEN se transfiere propiedad, THEN rol_propietario es dueño de todos los objetos de la tabla anterior. Las cuatro funciones SECURITY DEFINER NO están aquí; pertenecen a rol_funciones.
2. WHEN migración de usuario_anon, THEN propietario cambia de bootstrap a rol_propietario con REVOKE/GRANT explícitos; reconstruir bajo SET LOCAL ROLE rol_propietario para verificar defaults.
3. WHEN auditoría Parte D, THEN rol_propietario puede tener TEMPORARY únicamente en la base actual; justificación técnica exclusiva, independiente de privilegios de negocio.
4. IF se intenta TEMPORARY para app_web, admin_datos, rol_soporte o rol_reportes, THEN denegado.
5. WHEN defaults bajo rol_propietario en public, THEN ningún rol recibe acceso automático sobre objetos futuros.
6. WHEN defaults bajo rol_propietario en datos_anon, THEN rol_reportes recibe SELECT sobre objetos nuevos.

---

### Requirement 8: Propiedad y permisos internos — rol_funciones

#### Cuatro funciones SECURITY DEFINER (única propiedad de rol_funciones)

| Función | Propósito |
|---|---|
| fn_autenticar | Valida bcrypt con pgcrypto; devuelve id o NULL; registra intento sin email/password/hash. |
| fn_resetear_password | Restablece credencial; ejecutable solo por admin_datos; comportamiento de retorno se define en design. |
| recalcular_total_pedido | Función trigger; actualiza pedido.total. |
| u4_refrescar_ventas | Función trigger; refresca mv_u4_ventas_categoria_dia; omite refresco anidado. |

> rol_funciones NO posee tablas. Posee ÚNICAMENTE estas cuatro funciones.

#### Permisos internos acotados

| Objeto | Op | Columnas |
|---|---|---|
| usuario | SELECT | id, email, contrasena, eliminado |
| usuario | UPDATE | contrasena |
| detalle_pedido | SELECT | pedido_id, subtotal |
| pedido | SELECT | id |
| pedido | UPDATE | total |
| mv_u4_ventas_categoria_dia | MAINTAIN | — |

#### Acceptance Criteria
1. WHEN se define rol_funciones, THEN NOLOGIN; sin membresía de/a ningún login; sin tablas propias.
2. WHEN rol_funciones posee funciones, THEN ÚNICAMENTE las cuatro listadas.
3. WHEN permisos internos, THEN exactamente los de la tabla; ninguna columna adicional.
4. WHEN se crean las funciones, THEN search_path = pg_catalog, referencias calificadas, REVOKE EXECUTE FROM PUBLIC en cada una.
5. IF PUBLIC intenta EXECUTE fn_autenticar o fn_resetear_password, THEN denegado.
6. WHEN admin_datos ejecuta fn_resetear_password, THEN permitido por GRANT directo; ningún otro login puede ejecutarla.
7. WHEN rol_funciones opera sobre MV diaria, THEN solo MAINTAIN; sin INSERT/UPDATE/DELETE/SELECT sobre la MV.

---

### Requirement 9: Esquema, secuencias y defaults

#### Acceptance Criteria
1. WHEN se configura public, THEN se revoca CREATE a todos los roles de aplicación y soporte.
2. WHEN defaults bajo rol_propietario en public, THEN ningún acceso automático sobre objetos futuros.
3. WHEN defaults bajo rol_propietario en datos_anon, THEN rol_reportes recibe SELECT sobre objetos nuevos.
4. IF USAGE de secuencias en bloque, THEN no planificado; grants explícitos por tabla.
5. WHEN se revocan permisos de ejecución pública, THEN REVOKE EXECUTE FROM PUBLIC aplicado individualmente a cada una de las cuatro funciones.

---

### Requirement 10: Pruebas previstas de privilegios

> Pruebas PREVISTAS para ejecutar tras implementar SQL. No ejecutadas en
> esta especificación.

#### Positivas

| Sujeto | Operación |
|---|---|
| app_web | SELECT columnas autorizadas usuario (sin contrasena) |
| app_web | INSERT pedido (usuario_id, fecha, forma_pago) → estado PENDIENTE |
| app_web | UPDATE pedido (estado, forma_pago, eliminado) |
| app_web | INSERT detalle (pedido_id, producto_id, cantidad, precio_unitario) |
| app_web | UPDATE detalle (cantidad, precio_unitario); DELETE detalle en PENDIENTE |
| admin_datos | SELECT columnas autorizadas usuario; UPDATE telefono |
| admin_datos | EXECUTE fn_resetear_password |
| rol_reportes | SELECT usuario_anon, mv_facturacion_categoria_mes, mv_u4_ventas_categoria_dia |

#### Negativas

| Sujeto | Operación denegada |
|---|---|
| app_web | SELECT contrasena; INSERT total; DELETE pedido; DELETE usuario |
| app_web | nextval/setval en secuencias; UPDATE contrasena |
| app_web | SET ROLE rol_propietario / rol_funciones |
| admin_datos | SELECT contrasena; DELETE usuario |
| admin_datos | SET ROLE rol_propietario / rol_funciones |
| rol_reportes | SELECT tabla fuente public; SELECT datos de contacto reales |

#### Auditoría prevista

| Escenario | Descripción |
|---|---|
| 3 fallos fn_autenticar | Registrados sin credenciales. |
| 1 éxito fn_autenticar | Registrado sin credenciales. |
| SELECT masivo autorizado | Columnas autorizadas de usuario, sin contrasena. |
| GRANT denegado | GRANT admin_datos TO app_web → denegado. |

#### Acceptance Criteria
1. WHEN pruebas positivas, THEN cada operación listada completa sin error.
2. WHEN pruebas negativas, THEN cada operación produce error de permisos.
3. WHEN prueba de defaults, THEN objeto nuevo en public inaccesible sin GRANT explícito; objeto nuevo en datos_anon accesible por SELECT para rol_reportes.
4. IF prueba negativa produce éxito inesperado, THEN fallo del modelo; requiere corrección antes de continuar.

---

### Requirement 11: Conservación de invariantes heredadas

#### Acceptance Criteria
1. WHEN se aplica el modelo, THEN los tres triggers (validar_detalle_pendiente, recalcular_total_pedido, u4_refrescar_ventas) siguen operando correctamente.
2. WHEN se aplica el modelo, THEN vistas TP5, mv_facturacion_categoria_mes y mv_u4_ventas_categoria_dia siguen accesibles para sus roles internos.
3. WHEN se aplica el modelo, THEN los 20.000 usuarios heredados y sus pedidos no son modificados.
4. WHEN se configura FNBC, THEN sus objetos no reciben privilegios de roles de aplicación; dominio exclusivo de rol_propietario.
5. WHEN se recrea fn_autenticar, THEN: valida bcrypt con pgcrypto, devuelve id o NULL, registra resultado sin email/password/hash.
6. WHEN se recrea fn_resetear_password, THEN: restablece credencial solo para admin_datos; comportamiento de retorno se define en design.

---

## Restricciones globales

| Restricción | Descripción |
|---|---|
| Sin SQL en esta especificación | No contiene ni genera código SQL. |
| Sin implementación automática | Kiro no ejecuta comandos ni se conecta a bases de datos. |
| Validación humana pendiente | Validación de los integrantes pendiente para la entrega; la revisión automática de Codex no la sustituye. |
| Mínimo privilegio | Ningún rol recibe más permisos de los estrictamente necesarios. |
| Sin ALL PRIVILEGES | No se planifica ALL PRIVILEGES ni permisos en bloque. |
| Sin blanket USAGE en secuencias | Grants explícitos por tabla; sin USAGE global. |
| Sin TEMPORARY para roles de negocio | Solo rol_propietario, con justificación técnica acotada a Parte D. |
| contrasena excluida de aplicación | Solo rol_funciones la accede internamente para bcrypt. |
| Datos heredados intactos | 20.000 usuarios heredados sin modificar. |
| Propiedad sin superposición | rol_propietario: infraestructura y SECURITY INVOKER. rol_funciones: solo las cuatro SECURITY DEFINER. Sin superposición. |

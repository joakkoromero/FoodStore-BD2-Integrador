```markdown
# Design: seguridad-roles-foodstore

## Introducción

Diseño técnico derivado de requirements.md (versión final corregida).
Establece la arquitectura de roles, la matriz de privilegios, los contratos
de las cuatro funciones SECURITY DEFINER, el plan de migración de objetos
existentes y las pruebas previstas. No contiene SQL ejecutable ni implementación.
Validación humana de los integrantes pendiente para la entrega.

---

## 1. Arquitectura de roles y membresías

### 1.1 Jerarquía

```
rol_app_lectura  ←─ app_web
rol_app_escritura ←─ app_web
rol_soporte      ←─ admin_datos
rol_reportes     (sin logins)
rol_propietario  (sin logins — dueño de infraestructura)
rol_funciones    (sin logins — dueño de los cuatro puentes SECURITY DEFINER)
```

Ningún login recibe membresía de `rol_propietario` ni de `rol_funciones`.
`rol_reportes` es NOLOGIN; no se convierte en cuenta de sesión.

### 1.2 Tabla de membresías

| Login | Miembro de | INHERIT | SET | ADMIN |
|---|---|---|---|---|
| app_web | rol_app_lectura | TRUE | FALSE | FALSE |
| app_web | rol_app_escritura | TRUE | FALSE | FALSE |
| admin_datos | rol_soporte | TRUE | FALSE | FALSE |

SET FALSE: esa membresía **no habilita SET ROLE al padre**. Imposible por
diseño, no por falta de permisos adicionales.

Todos los roles: sin SUPERUSER, CREATEDB, CREATEROLE, REPLICATION,
BYPASSRLS, ADMIN OPTION.

---

## 2. Matriz de privilegios por objeto

### 2.1 Lectura — rol_app_lectura

| Objeto | Op | Columnas autorizadas |
|---|---|---|
| categoria | SELECT | todas |
| producto | SELECT | todas |
| usuario | SELECT | id, nombre, apellido, email, telefono, eliminado, created_at |
| pedido | SELECT | todas |
| detalle_pedido | SELECT | todas |

`contrasena` excluida explícitamente; requiere GRANT por columna, no por tabla.

### 2.2 Escritura — rol_app_escritura

| Objeto | Op | Columnas autorizadas | Notas |
|---|---|---|---|
| pedido | INSERT | usuario_id, fecha, forma_pago | estado = DEFAULT PENDIENTE; total excluido |
| pedido | UPDATE | estado, forma_pago, eliminado | baja lógica vía eliminado |
| pedido | DELETE | — | DENEGADO |
| detalle_pedido | INSERT | pedido_id, producto_id, cantidad, precio_unitario | subtotal GENERATED, nunca se escribe |
| detalle_pedido | UPDATE | cantidad, precio_unitario | — |
| detalle_pedido | DELETE | — | solo en PENDIENTE (trigger validar_detalle_pendiente) |
| usuario | DELETE/UPDATE contrasena | — | DENEGADO |
| secuencias identity | nextval/setval | — | DENEGADO; INSERT implícito suficiente |

No se concede USAGE en bloque sobre secuencias. El INSERT sobre la tabla
implica el avance de la secuencia sin exponer nextval/setval directos.

### 2.3 Soporte — rol_soporte

| Objeto | Op | Columnas autorizadas |
|---|---|---|
| usuario | SELECT | id, nombre, apellido, email, telefono, eliminado |
| usuario | UPDATE | telefono |
| pedido / detalle / catálogo / FNBC | cualquiera | DENEGADO |

`contrasena` excluida. Sin acceso a pedido, detalle, catálogo ni FNBC.
`admin_datos` ejecuta `fn_resetear_password` por GRANT puntual directo,
no derivado de rol_soporte.

### 2.4 Reportes — rol_reportes

| Objeto | Esquema | Op |
|---|---|---|
| usuario_anon | datos_anon | SELECT (todas las columnas) |
| mv_facturacion_categoria_mes | public | SELECT |
| mv_u4_ventas_categoria_dia | public | SELECT |

Acceso restringido a los tres objetos listados. Ninguna tabla fuente de
public. Las denegaciones sobre tablas fuente requieren ausencia de GRANT
y revocación de cualquier privilegio heredado de PUBLIC.

### 2.5 Permisos internos — rol_funciones

| Objeto | Op | Columnas |
|---|---|---|
| usuario | SELECT | id, email, contrasena, eliminado |
| usuario | UPDATE | contrasena |
| detalle_pedido | SELECT | pedido_id, subtotal |
| pedido | SELECT | id |
| pedido | UPDATE | total |
| mv_u4_ventas_categoria_dia | MAINTAIN | — |

`mv_facturacion_categoria_mes` (mensual TP5) no recibe MAINTAIN ni ningún
privilegio de rol_funciones; conserva su comportamiento previo intacto.

---

## 3. Propiedad de objetos

### 3.1 rol_propietario

| Categoría | Objetos |
|---|---|
| Esquemas | public, datos_anon |
| Tablas public | todas (categoria, producto, usuario, pedido, detalle_pedido) |
| FNBC | lote, deposito, responsable_deposito, lote_responsable, control_lote_almacen, guardia |
| Vistas TP5 | todas |
| Materializadas | mv_facturacion_categoria_mes, mv_u4_ventas_categoria_dia |
| Funciones SECURITY INVOKER | validar_detalle_pendiente y demás heredadas no SECURITY DEFINER |
| datos_anon.usuario_anon | tras migración desde bootstrap |

### 3.2 rol_funciones — los cuatro puentes SECURITY DEFINER

| Función | Propietario | Tipo |
|---|---|---|
| fn_autenticar | rol_funciones | SECURITY DEFINER |
| fn_resetear_password | rol_funciones | SECURITY DEFINER |
| recalcular_total_pedido | rol_funciones | SECURITY DEFINER |
| u4_refrescar_ventas | rol_funciones | SECURITY DEFINER |

`rol_funciones` no posee tablas. Ninguna otra función le pertenece.
Las demás funciones heredadas (incluido `validar_detalle_pendiente`) son
SECURITY INVOKER y pertenecen a `rol_propietario`.

---

## 4. Contratos de las cuatro funciones SECURITY DEFINER

Propiedades comunes a las cuatro:
- `search_path = pg_catalog`
- Referencias de nombres calificadas (esquema.objeto)
- `REVOKE EXECUTE FROM PUBLIC` aplicado individualmente

### fn_autenticar
- **Entrada**: credenciales de sesión (parametrizadas, no en texto de log)
- **Proceso**: valida bcrypt contra `usuario.contrasena` usando pgcrypto
- **Salida**: `id` del usuario si válido, `NULL` si inválido o eliminado
- **Registro**: guarda resultado del intento (éxito/fallo + timestamp) sin email, password ni hash
- **Ejecutores autorizados**: app_web (GRANT EXECUTE directo)

### fn_resetear_password
- **Proceso**: restablece `usuario.contrasena` con hash bcrypt nuevo
- **Salida y errores**: comportamiento de retorno se define en tasks
- **Ejecutores autorizados**: admin_datos únicamente (GRANT EXECUTE directo)
- **Restricción**: PUBLIC y app_web denegados

### recalcular_total_pedido (función trigger)
- **Disparo**: trigger `recalcular_total_pedido` en detalle_pedido
- **Proceso**: suma subtotales del pedido y escribe `pedido.total` usando los permisos internos de rol_funciones
- **Restricción de diseño**: app_web nunca recibe UPDATE total; el recálculo ocurre exclusivamente por este puente

### u4_refrescar_ventas (función trigger)
- **Disparo**: trigger `u4_refrescar_ventas` en pedido/detalle según herencia U4
- **Proceso**: ejecuta REFRESH sobre mv_u4_ventas_categoria_dia usando MAINTAIN de rol_funciones; omite refresco anidado
- **Restricción de diseño**: app_web nunca recibe MAINTAIN sobre ninguna MV; mv_facturacion_categoria_mes no se toca

Decisión de diseño: los puentes de trigger mantienen las reglas heredadas
y no abren UPDATE total, columnas GENERATED ni MAINTAIN de MVs a la aplicación.
Si se detecta una limitación técnica durante la implementación (ej. versión
de pgcrypto), se documenta como decisión de diseño y prueba pendiente sin
ampliar privilegios.

---

## 5. Plan de migración de objetos existentes

### Orden de operaciones

1. **Crear los seis roles NOLOGIN** antes de transferir propiedad.
2. **Crear los dos roles LOGIN** (app_web, admin_datos) y asignar membresías.
3. **Transferir propiedad** de todos los objetos a rol_propietario con `ALTER … OWNER TO rol_propietario`.
4. **Migrar datos_anon.usuario_anon**: tabla ya existente creada por bootstrap.
   - `ALTER TABLE datos_anon.usuario_anon OWNER TO rol_propietario`
   - REVOKE privilegios heredados de bootstrap y PUBLIC
   - GRANT explícitos según matriz
5. **Recrear las cuatro funciones SECURITY DEFINER** con propietario rol_funciones, search_path pg_catalog, nombres calificados y REVOKE EXECUTE FROM PUBLIC.
6. **Aplicar GRANTs por columna** según matrices 2.1–2.4.
7. **GRANT puntual** EXECUTE fn_resetear_password a admin_datos; EXECUTE fn_autenticar a app_web.
8. **REVOKE CREATE en public** a todos los roles de aplicación y soporte.
9. **Aplicar default privileges bajo rol_propietario**:
   - En public: sin acceso automático futuro para ningún rol
   - En datos_anon: SELECT automático para rol_reportes sobre objetos nuevos
10. **TEMPORARY para rol_propietario** únicamente en la base actual (auditoría Parte D); no conceder a logins ni agrupadores de negocio.
11. **Verificación de defaults**: reconstruir datos_anon.usuario_anon bajo `SET LOCAL ROLE rol_propietario` y comprobar que los defaults del creador correcto se aplican.

---

## 6. Auditoría del laboratorio

- **Autenticación**: SCRAM en cluster de desarrollo aislado
- **Logging**: `log_connections on`, `log_disconnections on`, `log_statement all`
- **Prefijo de log**: timestamp, pid, session, rol, db, application_name, origen
- **Parámetros con secretos**: `log_parameter_max_length = 0` y `log_parameter_max_length_on_error = 0` (no se incrustan en el texto registrado)
- **Simulacro previsto**: 3 fallos fn_autenticar, 1 éxito, SELECT masivo columnas autorizadas usuario, intento GRANT admin_datos TO app_web (denegado)
- **Sanitización**: logs anonimizados antes de usar en herramientas de IA
- **Restricción**: sin contención automática; intervención manual requerida ante incidentes

---

## 7. Pruebas previstas

> Previstas para después de implementar SQL. No ejecutadas ni aprobadas
> en esta especificación.

### Positivas

| Sujeto | Verificación |
|---|---|
| app_web | INSERT pedido → estado PENDIENTE automático; SELECT columnas autorizadas usuario |
| app_web | UPDATE pedido (estado/forma_pago/eliminado); INSERT/UPDATE/DELETE detalle en PENDIENTE |
| admin_datos | UPDATE usuario(telefono); EXECUTE fn_resetear_password |
| rol_reportes | SELECT usuario_anon, mv_facturacion_categoria_mes, mv_u4_ventas_categoria_dia |
| Triggers | recalcular_total_pedido actualiza total; u4_refrescar_ventas refresca MV diaria |
| Defaults | objeto nuevo en datos_anon → SELECT para rol_reportes sin GRANT adicional |
| Ownership | datos_anon.usuario_anon propietario = rol_propietario tras migración |

### Negativas

| Sujeto | Denegación esperada |
|---|---|
| app_web | SELECT contrasena; INSERT total; DELETE pedido/usuario; nextval/setval |
| app_web | UPDATE contrasena; SET ROLE rol_propietario/rol_funciones |
| admin_datos | SELECT contrasena; DELETE usuario; SET ROLE rol_propietario/rol_funciones |
| rol_reportes | SELECT tabla fuente public; SELECT datos de contacto reales |
| Cualquier login | EXECUTE fn_resetear_password (excepto admin_datos) |
| Cualquier login | MAINTAIN sobre cualquier MV directamente |
| Defaults | objeto nuevo en public → sin acceso para ningún rol de aplicación sin GRANT explícito |

### Límites reconocidos

- Los grants son por columna/objeto; no proveen aislamiento por fila ni
  por usuario del negocio. Las invariantes de negocio (solo PENDIENTE,
  no DELETE lógico) las garantizan los triggers heredados, no los permisos.
- La equivalencia de datos_anon se verificó por proceso técnico externo;
  no se repite aquí. La prueba de reconstrucción bajo SET LOCAL ROLE
  rol_propietario confirma defaults, no equivalencia de contenido.
- Los 20.000 usuarios heredados no deben ser modificados por ninguna
  operación de configuración de roles; se verifica por snapshot de conteo.
```

---

El diseño aplica exactamente las correcciones del requirements final:

- `recalcular_total_pedido` y `u4_refrescar_ventas` aparecen como SECURITY DEFINER / rol_funciones en **todas** las secciones (tabla de propiedad §3.2, contratos §4, plan de migración §5). No figuran en ningún lugar como SECURITY INVOKER.
- `validar_detalle_pendiente` aparece como SECURITY INVOKER / rol_propietario en §3.1, coherente con los requisitos.
- `mv_facturacion_categoria_mes` no recibe MAINTAIN ni ningún privilegio de rol_funciones; queda intacta.
- SET FALSE explicado como imposibilidad de diseño, no como restricción operativa.
- Pruebas marcadas explícitamente como previstas; ningún resultado atribuido a Kiro.

**Kiro se detiene aquí. Listo para continuar con `tasks.md` cuando lo indiques.**

## Dictamen

**La revisión estática no identifica un incumplimiento bloqueante demostrado de la matriz final de Kiro y las precisiones de integración.** El script aplica separación de propietarios, permisos por columna y cuatro puentes `SECURITY DEFINER` sin conceder privilegios administrativos a los logins.

Esto **no equivale a certificar su ejecución ni su seguridad operativa**. Hay riesgos residuales y condiciones externas que el SQL no demuestra, especialmente el tratamiento de logs y la ausencia de concesiones previas a otros roles.

La auditoría se limita a los cuatro adjuntos. No ejecuté herramientas ni SQL, no modifiqué archivos y no atribuyo pruebas ejecutadas ni aprobación humana.

## Hallazgos

### 1. Media: La Confidencialidad De Los Logs Depende De Configuración Externa

**Referencias:** `01_roles.sql:198–250`; `02_design.md:205–213`; `03_revision_automatica_codex.md:72–74`.

Los mensajes explícitos de las funciones son adecuados: registran resultado y timestamp, no correo, contraseña ni hash. Sin embargo, eso **no garantiza que PostgreSQL no registre los argumentos de la llamada**.

Con `log_statement = all`, una llamada como:

```sql
SELECT public.fn_autenticar('correo@ejemplo.test', 'una-clave-literal');
```

incluye el secreto en el texto SQL registrado. `log_parameter_max_length = 0` no oculta literales escritos dentro de la sentencia: protege los parámetros del protocolo cuando se usan como tales.

**Corrección necesaria si el cliente utiliza literales:** pasar correo y contraseña como parámetros enlazados, también en `fn_resetear_password`, y aplicar la configuración de logs definida en el diseño. No se corrige ampliando o reduciendo los `GRANT` del archivo.

El adjunto no permite verificar el instalador ni los clientes. Es una **condición de integración pendiente**, no una filtración demostrada.

### 2. Baja, Condicional: La Limpieza De ACL No Es Universal

**Referencias:** `01_roles.sql:26–33, 100–105, 165–194, 339–352`.

La limpieza contempla `PUBLIC`, bootstrap y los roles del proyecto. Eso es coherente con un laboratorio aislado, pero **no elimina permisos concedidos previamente a otros roles no enumerados**.

La precondición comprueba propietarios de relaciones, no que sus ACL carezcan de otros beneficiarios. Además, el dump sin propietarios ni ACL no demuestra el estado real de esas concesiones.

Si existiera un rol ajeno con acceso a `usuario.contrasena`, ese acceso podría sobrevivir. Lo mismo vale para permisos previos de base o esquema concedidos directamente a terceros.

**Corrección si se detecta un beneficiario no autorizado:** revocar sus permisos concretos, incluidas concesiones por columna. No recomiendo un barrido indiscriminado sin inventario, porque podría eliminar accesos legítimos ajenos al alcance.

Ejemplo ilustrativo, únicamente si ese rol existiera y su acceso fuera indebido:

```sql
REVOKE ALL PRIVILEGES ON TABLE public.usuario FROM rol_ajeno;
REVOKE ALL PRIVILEGES
    (id, nombre, apellido, email, contrasena, telefono, eliminado, created_at)
    ON TABLE public.usuario FROM rol_ajeno;
```

Revocar privilegios de tabla **no sustituye** la revocación de concesiones independientes por columna.

### 3. Baja: La Autenticación Conserva Un Canal Temporal Y No Limita Intentos

**Referencias:** `01_roles.sql:208–221, 327`.

Una cuenta inexistente, eliminada o con hash no reconocido evita el cálculo bcrypt. Una cuenta activa con hash reconocido lo realiza. Esa diferencia puede facilitar enumeración por tiempo de respuesta.

Además, el login `app_web` puede llamar reiteradamente a la función; el SQL no implementa limitación de intentos.

Son **riesgos residuales**, no incumplimientos de la matriz solicitada. Si se exige mitigarlos, conviene limitar intentos en la aplicación y evaluar una comparación con hash ficticio para los caminos negativos. Esto requiere una decisión adicional y no justifica otorgar más permisos.

## Comprobaciones Estáticas

### Roles Y Membresías

**Referencias:** `01_roles.sql:71–84`.

- Los seis agrupadores y propietarios son `NOLOGIN`; solamente `app_web` y `admin_datos` tienen `LOGIN`.
- Todos se crean sin `SUPERUSER`, `CREATEDB`, `CREATEROLE`, `REPLICATION` ni `BYPASSRLS`.
- Las membresías usan explícitamente `INHERIT TRUE`, `SET FALSE`, `ADMIN FALSE`, sintaxis válida para PostgreSQL 17.
- Los logins heredan los permisos operativos sin poder usar esas membresías para asumir el rol padre o administrarlas.
- Ningún login recibe membresía de `rol_propietario`, `rol_funciones` o `rol_reportes`.
- `NOINHERIT` en los propietarios no es la barrera principal: la barrera es que no se otorgan sus membresías.

`PASSWORD NULL` es consistente con el instalador posterior. **No demuestra por sí solo que el login no pueda conectarse:** otros métodos de autenticación podrían permitirlo. La exigencia de SCRAM pertenece a la configuración externa del laboratorio.

### Tabla Y Columna

**Referencias:** `01_roles.sql:162–190, 313–328`.

La implementación distingue correctamente las dos capas de ACL:

- Revoca permisos de tabla y también permisos por columna.
- `rol_app_lectura` obtiene siete columnas de `usuario`, sin `contrasena`.
- `rol_soporte` obtiene exactamente las seis columnas finales, sin `created_at` ni `contrasena`, y solamente puede actualizar `telefono`.
- La aplicación no recibe escritura directa de `pedido.total`, `detalle_pedido.subtotal` ni `usuario.contrasena`.
- No recibe `DELETE` sobre `pedido` o `usuario`.
- Las concesiones de escritura excluyen identificadores y columnas derivadas.

**No corresponde añadir `USAGE` sobre las secuencias identity:** los identificadores implícitos de estas tablas no requieren conceder acceso directo a `nextval` o `setval`. Esto depende de que se conserve `IDENTITY`, como muestra el esquema, y no se sustituya por un `DEFAULT nextval(...)`.

### `SECURITY DEFINER` Y Triggers Heredados

**Referencias:** `01_roles.sql:150–158, 198–311`; `04_esquema_heredado_sin_datos.sql:173–255, 808–881`.

Los cuatro puentes coinciden con la especificación: propietario `rol_funciones`, contexto protegido y referencias calificadas. Las demás funciones públicas quedan `SECURITY INVOKER` de `rol_propietario`.

Los permisos internos presentan una correspondencia razonable con sus cuerpos:

| Función | Permisos relevantes |
|---|---|
| `fn_autenticar` | Lectura de `id,email,contrasena,eliminado`; ejecución de `crypto.crypt` |
| `fn_resetear_password` | Lectura de `id`; actualización de `contrasena`; ejecución de `crypt` y `gen_salt` |
| `recalcular_total_pedido` | Lectura de `detalle_pedido(pedido_id,subtotal)`; lectura de `pedido.id`; actualización de `pedido.total` |
| `u4_refrescar_ventas` | `MAINTAIN` sobre la MV diaria |

Tres puntos importantes:

1. **`validar_detalle_pendiente` usa `SELECT ... FOR UPDATE`.** La aplicación tiene lectura de `pedido` y permisos de actualización sobre algunas de sus columnas. No necesita recibir `UPDATE(total)` para satisfacer el requisito de bloqueo de filas.
2. **El recálculo de total no dispara el validador de estado mostrado.** Este es `BEFORE UPDATE OF estado`; el puente actualiza solamente `total`. Por ello, ese camino no justifica añadir a `rol_funciones` lectura de `estado` ni de columnas adicionales del detalle.
3. **En PostgreSQL 17, `MAINTAIN` habilita el refresco de la MV.** La consulta de refresco se ejecuta bajo el propietario de la vista materializada. No corresponde conceder al rol de funciones lectura general de todas las tablas fuente.

La revocación de `EXECUTE` sobre funciones trigger tampoco implica por sí sola que los triggers existentes dejen de funcionar: PostgreSQL comprueba ese permiso al crear el trigger, no nuevamente en cada disparo.

Se conservan los enlaces heredados, incluidos los disparadores de `producto` y `categoria`. No aparecen cambios de las reglas de transición, edición de detalle o serialización.

### `search_path`

**Referencias:** `01_roles.sql:86–91, 200–201, 236–237, 260–261, 287–288`.

Los puentes usan `search_path = pg_catalog` y nombres de relaciones calificados. Es una protección adecuada para los cuerpos mostrados.

**Matiz:** omitir `pg_temp` no significa que PostgreSQL nunca lo busque para relaciones o tipos. Aquí no se observa una explotación concreta: las relaciones de los puentes están calificadas y los logins no reciben `TEMPORARY`.

Los validadores invoker heredados sí necesitan `public` por sus referencias no calificadas. Mantenerlo en el `search_path` de los logins es coherente, dado que estos no pueden crear allí.

### Propiedad Y Defaults

**Referencias:** `01_roles.sql:98–160, 330–358`.

- La transferencia contempla tablas, vistas, MVs, secuencias y enums públicos.
- Las secuencias identity dependientes acompañan el cambio de propietario de sus tablas.
- `rol_funciones` no recibe propiedad de tablas ni secuencias.
- La propiedad de `crypto` y de la extensión no se transfiere; no hay un requisito adjunto que obligue a hacerlo.
- Los defaults se configuran para los **creadores efectivos**: `rol_propietario`, `rol_funciones` y `u5_bootstrap`.
- La revocación global de ejecución pública de funciones evita el error de intentar eliminar ese default global mediante una revocación solamente por esquema.
- El `SELECT` automático de `datos_anon` se concede únicamente para objetos creados por `rol_propietario`.

**Consecuencia operativa:** transferir después la propiedad de una tabla creada por bootstrap no recalcula sus ACL usando los defaults de `rol_propietario`. Para obtener el acceso automático previsto, la reconstrucción debe crearla efectivamente bajo ese rol, como exige la precisión de integración.

## Permisos Residuales

Estos accesos permanecen y no deben confundirse con aislamiento más fuerte:

- `app_web` puede leer las columnas autorizadas de **todos** los usuarios y todos los pedidos y detalles. No hay aislamiento por cliente mediante RLS.
- `admin_datos` puede actualizar teléfonos y restablecer contraseñas de cualquier usuario alcanzado por las funciones. El reset no excluye usuarios eliminados.
- `rol_reportes` puede leer todas las columnas y filas de los tres objetos autorizados; también recibe automáticamente lectura de futuras tablas de `datos_anon` creadas por `rol_propietario`.
- `rol_propietario` mantiene las facultades inherentes a la propiedad, aunque no sea login.
- `u5_bootstrap` conserva sus facultades de superusuario. Sus revocaciones de ACL no lo restringen efectivamente.
- Los permisos ordinarios que PostgreSQL concede a `PUBLIC` sobre tipos, catálogos y funciones de otros esquemas no se eliminan globalmente con este script.

## Alternativa Operativa Solicitada

**Esta sección es una propuesta separada, no una corrección necesaria ni una alternativa aplicada. Ambas simplificaciones siguientes exceden la matriz actual.**

### Soporte Mediante Herencia De Lectura

Podría evitarse mantener por separado buena parte de la lectura de soporte mediante:

```sql
GRANT rol_app_lectura TO rol_soporte
    WITH INHERIT TRUE, SET FALSE, ADMIN FALSE;
```

Esto conservaría la prohibición de asumir o administrar el padre mediante esa membresía, pero **ampliaría el acceso efectivo de `admin_datos`**:

- `SELECT` de todas las columnas de `categoria`, `producto`, `pedido` y `detalle_pedido`.
- `SELECT` adicional de `usuario.created_at`.
- Herencia automática de futuras concesiones a `rol_app_lectura`.

No concedería, con las ACL actuales, lectura de `contrasena`, escritura de pedidos o acceso a FNBC. Aun así, **contradice expresamente la corrección de alcance que excluyó pedidos, detalle y catálogo de soporte**. Mantener los grants actuales es la opción de mínimo privilegio.

### Reportes Mediante Lectura General De `public`

Una simplificación más amplia sería:

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rol_reportes;

ALTER DEFAULT PRIVILEGES FOR ROLE rol_propietario IN SCHEMA public
    GRANT SELECT ON TABLES TO rol_reportes;
```

El primer comando alcanza tablas, vistas y materializadas existentes; no concede acceso a las secuencias. El segundo alcanza futuros objetos de esas clases creados por `rol_propietario`, no por cualquier creador.

**Acceso adicional concreto:**

- Lectura completa de `usuario`, incluida **`contrasena`**, correo, teléfono y demás datos reales.
- Lectura de catálogo, pedidos y detalles.
- Lectura de las tablas FNBC, la guardia y `control_lote_almacen_original`.
- Lectura de las vistas TP5 y de futuras tablas, vistas y MVs públicas del creador indicado, incluidas futuras columnas sensibles.

No concede escritura, ejecución de funciones ni `MAINTAIN`. Pero **viola la exclusión de credenciales, contactos reales y tablas fuente**.

No existe un default de `ON TABLES` que signifique “solamente futuras materializadas de reportes”: también abarca tablas ordinarias y vistas. Por eso, esta simplificación no es equivalente al esquema puntual.

**Recomendación:** conservar los grants explícitos de `public` y el default ya acotado de `datos_anon`. Si se busca simplificar el proceso sin ampliar acceso, automatizar las migraciones para emitir los grants de la matriz bajo el creador correcto, en lugar de ampliar las ACL.

### FILE: requirements.md

```markdown
# Requisitos U8 – Food Store SQLite (Arancibia / Romero)

## Alcance

Tablet SQLite 3.37+ que opera sin conexión a PostgreSQL, usando una copia nueva
`foodstore_u8_arancibia_romero`. La fuente oficial `foodstore` nunca se modifica.
Ningún SIMULADO_APROBADO equivale a una venta real.

---

## REQ-01 — Integridad y atomicidad offline

**WHEN** la tablet funciona sin conexión o el operador registra un borrador,
**THE SYSTEM SHALL** consultar el catálogo local y persistir borrador, ítems y
solicitud inicial de forma atómica en las cuatro tablas STRICT de SQLite, con
`PRAGMA foreign_keys = ON` activado y verificado en cada conexión, centavos como
`INTEGER` no negativo (`BIGINT` equivalente a `NUMERIC(12,2) × 100`), forma de
pago `CHECK IN ('EFECTIVO','TARJETA','TRANSFERENCIA')`, cantidades positivas y
`solicitud_uuid TEXT PRIMARY KEY` como identificador único; y, si cualquier
sentencia dentro de la transacción falla o se cancela, deberá ejecutar `ROLLBACK`
completo sin dejar filas parciales en ninguna tabla.

### Casos de prueba

| ID | Descripción | Resultado esperado |
|----|-------------|-------------------|
| C1-COMMIT | Insertar borrador con dos ítems válidos y solicitud PENDIENTE dentro de un `BEGIN` / `COMMIT` | Tres tablas muestran las filas nuevas; `PRAGMA integrity_check` = ok |
| C1-ROLLBACK | Mismo flujo pero con `ROLLBACK` explícito antes del `COMMIT` | Ninguna fila nueva persiste en ninguna tabla |
| C7 | Intentar insertar un ítem con `precio_centavos = -1` o `cantidad = 0` (viola `CHECK`) o con `producto_id` inexistente (viola `FK`) dentro de una transacción que ya insertó el borrador | `ROLLBACK` completo; el borrador tampoco queda; `SELECT` posterior devuelve cero filas nuevas |

---

## REQ-02 — Semáforo de simulación con prioridad rojo > amarillo

**WHEN** se ejecuta la simulación de una solicitud PENDIENTE contra una
instantánea vigente,
**THE SYSTEM SHALL** evaluar cada ítem mediante `LEFT JOIN` a `producto_cache`,
marcar `RECHAZADO` (rojo) si algún producto no existe en la instantánea, está
dado de baja (`eliminado = 1`), no está disponible (`stock_visto = 0`) o si el
borrador no contiene ítems; marcar `CONFLICTO` (amarillo) únicamente si no hay
ningún rojo y al menos un precio difiere del visto al momento del borrador; y
marcar `SIMULADO_APROBADO` solo si no hay rojo ni amarillo; con la condición de
que un ítem con rojo y precio distinto simultáneamente se registre siempre como
`RECHAZADO`, no como `CONFLICTO`; y, cuando el operador acepta explícitamente un
precio nuevo tras un `CONFLICTO`, actualizar `precio_centavos_visto` en
`item_borrador`, crear una nueva fila en `cola_sync` con `solicitud_uuid` nuevo y
conservar la fila anterior con su resultado `CONFLICTO` sin modificarla.

### Casos de prueba

| ID | Descripción | Resultado esperado |
|----|-------------|-------------------|
| C2 | Snapshot con precio modificado de un producto del borrador; re-simular | Estado = `CONFLICTO`; motivo incluye producto_id y precios; fila anterior intacta |
| C2-aceptar | Operador acepta precio; re-simular con UUID nuevo | Estado = `SIMULADO_APROBADO`; fila C2 permanece `CONFLICTO`; precio actualizado en `item_borrador` |
| C3 | Snapshot sin stock suficiente (`stock_visto < cantidad`) | Estado = `RECHAZADO`; motivo indica stock insuficiente |
| C5 | Snapshot sin cambios respecto al borrador | Estado = `SIMULADO_APROBADO` |
| Mixto rojo/amarillo | Borrador con un producto sin stock y otro con precio distinto | Estado = `RECHAZADO`; motivo menciona el producto sin stock (rojo tiene prioridad) |
| Borrador vacío | Borrador sin ítems | Estado = `RECHAZADO`; motivo indica borrador vacío |

---

## REQ-03 — Idempotencia UUID y una sola solicitud PENDIENTE por borrador

**WHEN** se reenvía o duplica una solicitud ya evaluada,
**THE SYSTEM SHALL** rechazar el `INSERT` de un `solicitud_uuid` repetido
mediante la clave primaria de `cola_sync` y conservar el estado y motivo
originales sin reevaluar; y, además, garantizar que un borrador tenga como
máximo una solicitud con `estado = 'PENDIENTE'` simultánea mediante un índice
`UNIQUE` parcial `ON cola_sync(id_local) WHERE estado = 'PENDIENTE'`, sin
imponer `UNIQUE` global sobre `id_local` (un borrador puede tener múltiples
entradas históricas con estados distintos).

### Casos de prueba

| ID | Descripción | Resultado esperado |
|----|-------------|-------------------|
| C6-PK | Re-insertar en `cola_sync` el mismo `solicitud_uuid` de C2 | Error de `UNIQUE constraint failed`; fila original inalterada |
| C6-PENDIENTE | Intentar insertar segunda solicitud `PENDIENTE` para el mismo `id_local` | Error de índice parcial; primera solicitud `PENDIENTE` inalterada |
| C6-histórico | Insertar segunda solicitud con estado `CONFLICTO` para el mismo `id_local` que ya tiene un `CONFLICTO` previo | Inserción exitosa; `id_local` aparece dos veces en `cola_sync` |

---

## REQ-04 — Snapshot con lápidas y autoridad exclusiva de PostgreSQL

**WHEN** se descarga o recarga el catálogo desde PostgreSQL,
**THE SYSTEM SHALL** importar la instantánea fechada desde CSV producido por
`psql \copy` sobre la vista `v_snapshot_movil` de la copia `foodstore_u8_arancibia_romero`,
actualizar e insertar filas en `producto_cache` sin borrar productos referenciados
por borradores, conservar los productos dados de baja como lápidas
(`eliminado = 1`) ocultos en `v_catalogo_disponible` pero visibles en
`producto_cache`, tomar la fecha de `capturado_en` del servidor PostgreSQL, y
no emitir ningún `UPDATE`, `INSERT` ni `DELETE` sobre tablas de PostgreSQL
durante la simulación; y, al finalizar todas las pruebas, comparar la cantidad
de pedidos y el stock de los productos fixture en la copia antes y después, y
verificar que las huellas (`md5` o `sha256`) de los objetos de `foodstore` no
cambiaron.

### Casos de prueba

| ID | Descripción | Resultado esperado |
|----|-------------|-------------------|
| C4-importar | Importar CSV con un producto nuevo y uno marcado `eliminado = t` | `producto_cache` contiene ambos; `v_catalogo_disponible` oculta el eliminado |
| C4-baja | Simular borrador que incluye el producto con `eliminado = 1` | Estado = `RECHAZADO`; motivo indica producto dado de baja |
| C4-lápida | Consultar `producto_cache` directamente | Fila con `eliminado = 1` presente; `v_catalogo_disponible` no la muestra |
| Conservación | Comparar conteo de `pedido` y stock fixture en la copia antes y después de todas las pruebas | Valores idénticos |
| Huella `foodstore` | Hash de tablas clave de `foodstore` antes y después | Hashes idénticos; ninguna escritura ocurrió |
```

---

### FILE: design.md

```markdown
# Diseño U8 – Food Store SQLite (Arancibia / Romero)

## Componentes

### 1. Copia PostgreSQL `foodstore_u8_arancibia_romero`

- Creada con `CREATE DATABASE foodstore_u8_arancibia_romero TEMPLATE foodstore`.
- Respaldo previo con `pg_dump` antes de cualquier cambio.
- Fixture inventado: productos de feria con nombres identificables como "U8-FERIA-*",
  categoría propia, precios en `NUMERIC(12,2)`. Stock asignado manualmente.
- Vista de exportación:

```sql
CREATE VIEW v_snapshot_movil AS
SELECT
  p.producto_id,
  p.nombre,
  (p.precio * 100)::BIGINT  AS precio_centavos,
  p.stock,
  (p.stock > 0)             AS disponible,
  (p.eliminado OR c.eliminado) AS eliminado,
  now()                     AS capturado_en
FROM producto p
JOIN categoria c USING (categoria_id)
WHERE p.categoria_id IN (<ids fixture>);
```

- Exportación: `\copy (SELECT * FROM v_snapshot_movil) TO 'snapshot.csv' CSV HEADER`
- Verificación de conservación: `md5` / `sha256` sobre tablas de `foodstore` antes y después.

### 2. Esquema SQLite (`schema_sqlite.sql`)

```sql
PRAGMA foreign_keys = ON;   -- repetir en cada conexión y verificar con PRAGMA foreign_keys

CREATE TABLE producto_cache (
  producto_id    INTEGER PRIMARY KEY,
  nombre         TEXT    NOT NULL,
  precio_centavos INTEGER NOT NULL CHECK (precio_centavos >= 0),
  stock_visto    INTEGER NOT NULL CHECK (stock_visto >= 0),
  disponible_visto INTEGER NOT NULL CHECK (disponible_visto IN (0,1)),
  eliminado      INTEGER NOT NULL CHECK (eliminado IN (0,1)),
  capturado_en   TEXT    NOT NULL
) STRICT;

CREATE TABLE pedido_borrador (
  id_local       TEXT PRIMARY KEY,
  usuario_id_servidor INTEGER NOT NULL,
  forma_pago     TEXT NOT NULL CHECK (forma_pago IN ('EFECTIVO','TARJETA','TRANSFERENCIA')),
  creado_en      TEXT NOT NULL
) STRICT;

CREATE TABLE item_borrador (
  id_local         TEXT NOT NULL REFERENCES pedido_borrador(id_local),
  producto_id      INTEGER NOT NULL REFERENCES producto_cache(producto_id),
  cantidad         INTEGER NOT NULL CHECK (cantidad > 0),
  precio_centavos_visto INTEGER NOT NULL CHECK (precio_centavos_visto >= 0),
  PRIMARY KEY (id_local, producto_id)
) STRICT;

CREATE TABLE cola_sync (
  solicitud_uuid TEXT PRIMARY KEY,
  id_local       TEXT NOT NULL REFERENCES pedido_borrador(id_local),
  estado         TEXT NOT NULL CHECK (estado IN
                   ('PENDIENTE','CONFLICTO','RECHAZADO','SIMULADO_APROBADO')),
  motivo         TEXT,
  evaluado_en    TEXT
) STRICT;

-- Una sola solicitud PENDIENTE por borrador (índice parcial)
CREATE UNIQUE INDEX uq_pendiente_por_borrador
  ON cola_sync(id_local) WHERE estado = 'PENDIENTE';

-- Tabla auxiliar de importación (no STRICT, carga CSV crudo)
CREATE TABLE snapshot_servidor (
  producto_id     INTEGER,
  nombre          TEXT,
  precio_centavos INTEGER,
  stock           INTEGER,
  disponible      TEXT,   -- 't'/'f' del CSV; normalizar a 1/0 al pasar a producto_cache
  eliminado       TEXT,
  capturado_en    TEXT
);
```

### 3. Lógica del semáforo (`semaforo.sql`)

Ejecutado dentro de una transacción SQLite local; no abre conexión a PostgreSQL.

```
Pasos para cada solicitud PENDIENTE:
  1. Verificar que el borrador tenga al menos un ítem → si no, RECHAZADO "borrador vacío".
  2. LEFT JOIN item_borrador → producto_cache por producto_id.
     Rojo si: producto_cache.producto_id IS NULL
              OR eliminado = 1
              OR stock_visto = 0
              OR stock_visto < item_borrador.cantidad
  3. Si COUNT(rojo) > 0 → estado = RECHAZADO; motivo lista producto_ids con causa.
  4. Si COUNT(rojo) = 0 y algún precio_centavos ≠ precio_centavos_visto → CONFLICTO.
  5. Si no hay rojo ni amarillo → SIMULADO_APROBADO.
  6. UPDATE cola_sync SET estado = <resultado>, motivo = <texto>, evaluado_en = datetime('now')
     WHERE solicitud_uuid = <uuid>.
```

Aceptación de precio (C2-aceptar):
- `UPDATE item_borrador SET precio_centavos_visto = <nuevo> WHERE ...`
- `INSERT INTO cola_sync VALUES (<uuid_nuevo>, id_local, 'PENDIENTE', NULL, NULL)`
- Re-ejecutar semáforo con el UUID nuevo.

### 4. Flujo de importación de snapshot

```
psql \copy → snapshot.csv
  → Python: leer CSV, convertir 't'→1 / 'f'→0
  → INSERT OR REPLACE INTO producto_cache (no borra filas referenciadas)
  → Verificar PRAGMA integrity_check = 'ok'
  → Verificar PRAGMA foreign_keys = ON
```

### 5. Restricciones de diseño

| Restricción | Decisión |
|-------------|----------|
| `disponible` en PostgreSQL | Derivado como `(stock > 0)`; no existe columna real |
| Baja de producto o categoría | `(p.eliminado OR c.eliminado)` en la vista |
| Centavos | `(precio * 100)::BIGINT`; SQLite `INTEGER` 64-bit |
| Sin datos personales en SQLite | `usuario_id_servidor` = entero de prueba |
| Sin escritura a PostgreSQL en simulación | Semáforo es SQL local puro |
| `SIMULADO_APROBADO` ≠ venta | Etiqueta explícita en motivo y documentación |
```

---

### FILE: tasks.md

```markdown
# Tareas U8 – Food Store SQLite (Arancibia / Romero)

> Las tareas 1-3 son de preparación. Las tareas 4-8 generan código con
> **OpenCode Build** y lo revisan con **OpenCode Plan**. Ninguna tarea implementa
> código directamente desde esta especificación.

---

**Task 1: Congelar especificaciones y registrar origen**

- Guardar `requirements.md`, `design.md` y `tasks.md` en `docs/kiro/`.
- Registrar hash (`sha256`) y fecha de cada archivo.
- Anotar en la bitácora de IA que estos archivos son autoría de Codex/Kiro
  y aún no constituyen evidencia de ejecución.
- **Demo:** tres archivos presentes en `docs/kiro/`, hashes verificables,
  bitácora con entrada inicial.

---

**Task 2: Preparar copia PostgreSQL y fixture**

- Respaldar con `pg_dump foodstore > foodstore_backup_<fecha>.sql`.
- Crear `foodstore_u8_arancibia_romero` desde template.
- Verificar que `foodstore` sigue intacto (hash pre/post).
- Insertar productos fixture "U8-FERIA-*" con categoría propia.
- Crear vista `v_snapshot_movil` según diseño.
- Exportar `snapshot_inicial.csv` con `\copy`.
- **Demo:** `\dt`, `SELECT COUNT(*) FROM producto WHERE nombre LIKE 'U8-FERIA-%'`,
  CSV generado con cabecera correcta, hash de `foodstore` sin cambios.

---

**Task 3: Crear esquema SQLite y verificar invariantes**

- Usar **OpenCode Build** para generar `movil/schema_sqlite.sql`.
- Ejecutar script; verificar con:
  - `PRAGMA integrity_check` = `ok`
  - `PRAGMA foreign_keys` = `1`
  - `.tables` muestra las cinco tablas
  - `.schema cola_sync` incluye el índice parcial
- **Demo:** salida de verificaciones sin errores; esquema vacío listo para datos.

---

**Task 4: Importar snapshot e integrar con producto_cache**

- Usar **OpenCode Build** para generar el script de importación Python/SQL.
- Leer el script antes de ejecutarlo.
- Importar `snapshot_inicial.csv` → `snapshot_servidor` → `producto_cache`
  (normalizar `t`/`f` → `1`/`0`).
- Verificar que `v_catalogo_disponible` oculta eliminados y muestra disponibles.
- **Demo:** `SELECT COUNT(*) FROM producto_cache`, muestra de filas con
  `eliminado = 1` en cache pero ausentes de la vista.

---

**Task 5: Pruebas de atomicidad C1-COMMIT, C1-ROLLBACK y C7**

- Usar **OpenCode Build** para generar `movil/pruebas_sqlite.sql`.
- Ejecutar C1-COMMIT: borrador + ítems + solicitud PENDIENTE → verificar filas.
- Ejecutar C1-ROLLBACK: mismo flujo con `ROLLBACK` → verificar cero filas nuevas.
- Ejecutar C7: ítem con `precio_centavos = -1` y con `producto_id` inexistente →
  verificar `ROLLBACK` completo (borrador tampoco persiste).
- **Demo:** salidas de `SELECT` antes/después de cada transacción documentadas.

---

**Task 6: Semáforo — casos C2 a C6 y controles de borde**

- Usar **OpenCode Build** para generar `movil/semaforo.sql`.
- Revisar con **OpenCode Plan** antes de ejecutar.
- Ejecutar en orden: C3 (sin stock), C4 (baja / lápida), C5 (sin cambios),
  C2 (precio), C2-aceptar (UUID nuevo, precio aceptado), mixto rojo/amarillo,
  borrador vacío.
- Ejecutar C6: re-insertar UUID duplicado → error PK; segunda PENDIENTE para
  mismo `id_local` → error índice parcial; segunda entrada histórica con estado
  distinto → éxito.
- **Demo:** tabla `cola_sync` con todas las filas; estados y motivos visibles;
  ningún cambio en PostgreSQL.

---

**Task 7: Verificar conservación de PostgreSQL**

- Comparar `COUNT(*)` de `pedido` y stock fixture en la copia antes y después.
- Calcular hash de tablas clave de `foodstore` antes y después de todas las pruebas.
- Documentar que el semáforo no emitió escrituras a PostgreSQL.
- **Demo:** tabla comparativa de conteos y hashes; afirmación explícita
  "SIMULADO_APROBADO ≠ venta".

---

**Task 8: Review OpenCode Plan, correcciones y segunda ejecución**

- Congelar trabajo en rama `review-final`.
- Solicitar review de scripts con **OpenCode Plan** (mínimo dos unidades,
  mínimo tres hallazgos desarrollados, uno descartado con prueba).
- Registrar cada hallazgo: aceptado / corregido / descartado.
- Corregir en commits separados.
- Reproducir desde SQLite vacío y comparar evidencia de segunda ejecución.
- **Demo:** rama `review-final`, log de commits de corrección, dos salidas
  comparadas (primera y segunda ejecución).

---

**Task 9: Artefactos finales**

- Mapa PostgreSQL / MongoDB / SQLite.
- Extensión del plan U6: backups, resincronización, revisión de conflictos.
- Bitácora de IA con al menos tres entradas con fecha, herramienta y resultado.
- DUIA de la cátedra completada.
- README con estructura del proyecto.
- Informe de máximo seis páginas.
- ZIP `food-store/` con base SQLite y archivos requeridos; sin datos personales
  ni secretos.
- Guion de defensa de diez minutos (el ensayo en clase lo realiza el equipo,
  no se simula aquí).
- **Demo:** ZIP verificado, `grep` sobre ZIP confirma ausencia de contraseñas
  y mails, hashes del ZIP documentados.
```

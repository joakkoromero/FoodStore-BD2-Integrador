### FILE: requirements.md

```markdown
# requirements.md — Complemento FNBC Food Store
**Fecha:** 10/11/2026 | **Alcance:** nueva spec previa a implementación

## Contexto
Complemento nuevo del TPI Food Store. La migración U4 histórica (20/10/2026) no conservó specs Kiro ni prueba de reversión post-COMMIT de FNBC. Estas tres specs son originales del 10/11/2026 y deben archivarse antes de generar o ejecutar código nuevo.

## Dependencias de entorno
- PostgreSQL 17.x (compatible 16+), PL/pgSQL.
- Base de trabajo exclusiva: `foodstore_tpi_migracion_nov10`.
- Esquema nuevo: `tpi_migracion` (inexistente antes de la preparación).
- `public.*` y la fuente oficial: solo lectura. Sin modificar roles, permisos ni entregables anteriores.

## Modelo relacional de partida
Tabla fuente: `public.control_lote_almacen_original`
Columnas: `(lote_id L, deposito_id D, responsable_control_id R)`
Datos iniciales: 3 filas — `(501,30,801),(502,30,801),(503,31,802)`.
Claves candidatas: **LD** y **LR**.
Dependencias funcionales: `LD→R` y `R→D`.
Violación FNBC: `R→D` porque R no es superclave.
Descomposición sin pérdida: **RD** (PK: R) y **LR** (PK: LR).
`LD→R` no es preservable por PK/FK locales; requiere guardia compartida + validación del JOIN.

## Requisitos funcionales (EARS)

**RF-01** WHEN `current_database()` o el esquema destino no coincidan con los previstos, THEN el script aborta antes de escribir nada.

**RF-02** WHEN la fuente tenga filas que violen `R→D` (mismo R, distintos D), THEN rechazar la migración con SQLSTATE 23514, sin instalación parcial ni selección arbitraria de deposito.

**RF-03** WHEN la migración se revierte antes de COMMIT, THEN el esquema y los datos retornan al estado exacto anterior; ningún objeto de `tpi_migracion` persiste.

**RF-04** WHEN la migración se confirma con COMMIT, THEN la reunión de `responsable_deposito ⋈ lote_responsable` es equivalente a la fuente en ambos sentidos (EXCEPT ALL bilateral = 0).

**RF-05** WHEN dos sesiones intentan confirmar el mismo par `(L,D)` con distinto R, THEN exactamente una confirma y la otra recibe SQLSTATE 23505; `LD→R` no se viola.

**RF-06** WHEN se ejecuta la reversión post-COMMIT tras cambios válidos confirmados, THEN la tabla reconstruida refleja el JOIN actual (4 filas), no el checkpoint de 3 filas; los cambios no se pierden.

**RF-07** WHEN ocurre cualquier error durante la reversión post-COMMIT, THEN el ROLLBACK preserva la versión normalizada operativa completa; no queda estado intermedio visible.

**RF-08** WHEN concluye cualquier ensayo, THEN las tablas de `public` y la fuente oficial conservan sus huellas y recuentos originales, sin excepción.

## Requisitos no funcionales

**RNF-01** Mismo código de migración para ensayo ROLLBACK y ejecución COMMIT; no dos variantes divergentes.

**RNF-02** Respaldo custom con manifiesto y hash verificado antes de cada fase destructiva; sin dumps de filas personales ni credenciales en artefactos.

**RNF-03** BIGINT sin secuencias en `tpi_migracion`; evitar confusión entre reversibilidad de tablas y no-transaccionalidad de sequences.

**RNF-04** Funciones con `search_path` seguro y referencias totalmente calificadas.

**RNF-05** Reversión sin CASCADE fuera del esquema nuevo; sin DROP sobre `public.*`.

**RNF-06** Toda fuente nueva revisada con OpenCodePlan antes de ejecutarse.

**RNF-07** Pruebas negativas con ROLLBACK o SAVEPOINT específico por caso; sin captura genérica que oculte fallos.

**RNF-08** Prueba de concurrencia real con dos sesiones; no sustituible por un sleep fijo.
```

---

### FILE: design.md

```markdown
# design.md — Diseño técnico FNBC Food Store
**Fecha:** 10/11/2026

## Arquitectura de esquema

```
tpi_migracion
├── control_legacy_checkpoint   -- copia inmutable 3 filas (L,D,R), PK(L,D)
├── control_legacy              -- interfaz operativa (tabla o vista según fase)
├── responsable_deposito        -- RD normalizada, PK(R), FK→public.deposito, public.usuario
├── lote_responsable            -- LR normalizada, PK(L,R), FK→public.lote, FK→responsable_deposito(R)
├── _migration_guard            -- fila única de guardia transaccional
├── fn_validate_fd_ld_r()       -- valida LD→R vía JOIN antes de confirmar escritura
├── trg_before_lote_resp        -- BEFORE STATEMENT: bloquea guardia; llama fn_validate_fd_ld_r
├── trg_after_lote_resp         -- AFTER STATEMENT: revalida JOIN post-escritura
└── trg_before_resp_dep         -- BEFORE STATEMENT análogo para responsable_deposito
```

## Flujo transaccional

### Fase 1 — Preparación y checkpoint
1. Validar `current_database()` y ausencia previa de `tpi_migracion`; abortar si difieren.
2. Verificar 3 filas fuente, FKs a maestros y ausencia de violación `R→D`.
3. Crear esquema `tpi_migracion`.
4. Crear `control_legacy_checkpoint` con PK(L,D), FKs; copiar 3 filas.
5. Registrar hash SHA-256 del contenido y manifiesto inicial.

### Fase 2 — Precondición negativa
Dentro de BEGIN: insertar `(501,31,801)` en `control_legacy_checkpoint` (viola `R→D`).
Intentar migrar: la validación previa detecta la violación → RAISE SQLSTATE 23514.
ROLLBACK explícito. Verificar que nada de la migración instaló objetos.

### Fase 3 — Ensayo ROLLBACK
```
BEGIN;
  -- Renombrar control_legacy_checkpoint → control_legacy_checkpoint_bak (salvaguarda)
  -- Crear responsable_deposito, lote_responsable, _migration_guard
  -- Crear funciones y triggers
  -- Migrar proyecciones desde fuente
  -- Crear vista control_legacy(L,D,R)
  -- Verificar conteos, PK/FK, EXCEPT ALL bilateral
ROLLBACK;
```
Post-ROLLBACK: desde segunda conexión confirmar que `control_legacy_checkpoint` tiene 3 filas y no existen `responsable_deposito` ni `lote_responsable`.

### Fase 4 — Migración confirmada
Repetir exactamente la misma secuencia de Fase 3. COMMIT solo tras todas las verificaciones.
`control_legacy_checkpoint` permanece como archivo histórico. `control_legacy` es la vista operativa.

### Fase 5 — Restricciones
- `R→D` local: intentar `UPDATE responsable_deposito SET deposito_id=X` donde X≠D asignado → 23514.
- Duplicado `(L,R)`: intentar insertar par existente en `lote_responsable` → 23505.
- FK inexistente: lote o responsable fuera de maestros → 23503.
- Dos R del mismo D: insertar par `(L,R2)` donde R2 comparte D con R1 ya asignado a L → validación JOIN → 23505.
Cada caso con SAVEPOINT específico y verificación de SQLSTATE exacto.

### Fase 6 — Concurrencia
Sesión A y Sesión B proponen insertar mismo par `(L,D)` con diferente R.
Mecanismo:
- `trg_before_lote_resp` hace `SELECT ... FOR UPDATE` sobre `_migration_guard`.
- B queda bloqueada (pg_locks observable) hasta que A confirma o revierte.
- Si A confirma: `fn_validate_fd_ld_r` de B detecta violación → 23505.
- Verificar que B estaba realmente bloqueada (pg_locks, no solo timing).
Limpiar solo filas auxiliares insertadas en la prueba.

### Fase 7 — Cambios válidos post-COMMIT
En `tpi_migracion`:
- `UPDATE responsable_deposito SET deposito_id=31 WHERE responsable_id=801`.
- `INSERT INTO responsable_deposito VALUES (803,30)`.
- `INSERT INTO lote_responsable VALUES (501,803)`.
Resultado esperado JOIN: 4 filas `(501,31,801),(502,31,801),(503,31,802),(501,30,803)`.
Guardar snapshot y hash de la reunión actual.

### Fase 8 — Reversión post-COMMIT
```
BEGIN;
  LOCK TABLE responsable_deposito, lote_responsable IN SHARE ROW EXCLUSIVE MODE;
  -- Capturar JOIN actual → tabla temporal t_reunion_actual
  -- Validar FD/PK/FK sobre t_reunion_actual
  -- Crear control_legacy_new(L,D,R) con 4 filas desde t_reunion_actual
  -- EXCEPT ALL bilateral: control_legacy_new vs snapshot fase 7 → debe ser 0
  -- Verificar hash
  -- DROP VIEW control_legacy; renombrar control_legacy_new → control_legacy (tabla)
  -- DROP TABLE responsable_deposito, lote_responsable, _migration_guard CASCADE (solo dentro de tpi_migracion)
  -- DROP funciones y triggers dentro de tpi_migracion
  -- control_legacy_checkpoint permanece intacto (3 filas)
COMMIT;  -- solo si todo verificado; ROLLBACK deja versión normalizada operativa
```

### Fase 9 — Validación final
Desde conexión nueva: `control_legacy` es tabla, 4 filas, hash coincide con snapshot fase 7.
`control_legacy_checkpoint` tiene 3 filas, hash igual al manifiesto inicial.
Huellas de `public.*` inalteradas.

## Guardia de concurrencia — detalle

```
_migration_guard(id BIGINT PK, locked_by TEXT, ts TIMESTAMPTZ)
-- una sola fila; SELECT FOR UPDATE en BEFORE STATEMENT
-- asegura serialización de escrituras sobre lote_responsable
-- AFTER STATEMENT re-ejecuta fn_validate_fd_ld_r para detectar interleaving en READ COMMITTED
```

Nivel de aislamiento y comportamiento:
- READ COMMITTED: consulta VOLATILE post-bloqueo ve commit anterior; segundo escritor recibe 23505.
- REPEATABLE READ / SERIALIZABLE: colisión puede producir 40001; exige reintento completo del script.
```

---

### FILE: tasks.md

```markdown
# tasks.md — Plan de tareas FNBC Food Store
**Fecha:** 10/11/2026 | Revisión OpenCodePlan requerida antes de ejecutar cada fuente nueva.

---

**Task 1:** Preparación del entorno y checkpoint inicial

Objetivo: crear la base aislada `foodstore_tpi_migracion_nov10`, el esquema `tpi_migracion`, copiar las 3 filas fuente en `control_legacy_checkpoint` y generar manifiesto/hash inicial.

Guía: script `01_prepare.sql` con guard `current_database()`. Crear `control_legacy_checkpoint(lote_id BIGINT, deposito_id BIGINT, responsable_control_id BIGINT, PK(lote_id,deposito_id))` con FKs a maestros de `public`. Copiar filas mediante INSERT SELECT verificando recuento exacto = 3. Generar hash SHA-256 del contenido y escribir manifiesto en tabla de auditoría `tpi_migracion.migration_manifest`.

Tests: recuento = 3; hash almacenado ≠ NULL; `current_database()` = nombre previsto; `public.*` sin cambios (EXCEPT ALL = 0 contra snapshot previo).

Demo: `SELECT * FROM tpi_migracion.control_legacy_checkpoint` retorna exactamente las 3 filas fuente; manifiesto visible.

---

**Task 2:** Validación de precondiciones y prueba negativa

Objetivo: demostrar que la migración rechaza una fuente con violación `R→D` sin dejar instalación parcial.

Guía: script `02_negative_precheck.sql`. En BEGIN: insertar `(501,31,801)` en `control_legacy_checkpoint`; invocar la función de validación `fn_check_fd_rd()`. Capturar SQLSTATE 23514. ROLLBACK explícito. Verificar ausencia de objetos normalizados.

Tests: SQLSTATE recibido = 23514; recuento post-ROLLBACK = 3; `tpi_migracion` no contiene `responsable_deposito` ni `lote_responsable`; ningún trigger instalado.

Demo: log del runner muestra "SQLSTATE 23514 capturado" y recuento 3 en checkpoint.

---

**Task 3:** Implementación de tablas normalizadas, guardia y funciones

Objetivo: crear `responsable_deposito`, `lote_responsable`, `_migration_guard`, `fn_validate_fd_ld_r()` y triggers dentro de `tpi_migracion`.

Guía: script `03_schema_normalized.sql`. BIGINT sin secuencias. `search_path` = `tpi_migracion,public`. Triggers BEFORE STATEMENT con `SELECT FOR UPDATE` sobre `_migration_guard`; AFTER STATEMENT con revalidación. FK explícitas. Revisar con OpenCodePlan antes de ejecutar.

Tests: DDL crea objetos sin error; `fn_validate_fd_ld_r()` retorna TRUE con datos válidos y FALSE/excepción con violación; triggers registrados en `pg_trigger`.

Demo: `\d tpi_migracion.responsable_deposito` muestra PK y FKs; función invocable manualmente.

---

**Task 4:** Ensayo de migración con ROLLBACK

Objetivo: ejecutar la migración completa dentro de una transacción y revertirla; verificar desde segunda sesión que el estado es el inicial.

Guía: script `04_migration_rollback.sql` reutiliza la misma lógica de migración de Task 3-5. BEGIN → renombrar checkpoint bak → migrar proyecciones → crear vista `control_legacy` → verificar EXCEPT ALL bilateral → ROLLBACK. Segunda sesión corre `04b_verify_rollback.sql`.

Tests: post-ROLLBACK: `control_legacy_checkpoint` = 3 filas, hash igual; `responsable_deposito` inexistente; vista `control_legacy` inexistente. EXCEPT ALL bilateral = 0 dentro de la transacción antes del ROLLBACK.

Demo: runner muestra dos sesiones; sesión B confirma estado limpio post-ROLLBACK.

---

**Task 5:** Migración confirmada (COMMIT)

Objetivo: ejecutar exactamente la misma secuencia de Task 4 y confirmar con COMMIT.

Guía: script `05_migration_commit.sql` — mismo wrapper, mismo cuerpo. COMMIT solo tras verificación completa. `control_legacy_checkpoint` permanece. `control_legacy` es la vista operativa.

Tests: `SELECT COUNT(*) FROM tpi_migracion.control_legacy` = 3; EXCEPT ALL bilateral = 0; PK/FK de ambas tablas normalizadas verificadas; huellas `public.*` inalteradas.

Demo: `SELECT * FROM tpi_migracion.control_legacy` retorna 3 filas; tablas normalizadas consultables.

---

**Task 6:** Pruebas de restricciones

Objetivo: verificar que cada violación de integridad produce el SQLSTATE correcto y sin efectos secundarios.

Guía: script `06_constraints.sql`. Un SAVEPOINT por caso: (a) `R→D` local → 23514; (b) duplicado `(L,R)` → 23505; (c) FK inexistente → 23503; (d) dos R del mismo D para un L → 23505 vía JOIN. ROLLBACK TO SAVEPOINT tras cada caso.

Tests: cada caso captura el SQLSTATE esperado; recuentos en `responsable_deposito` y `lote_responsable` inalterados al final.

Demo: runner imprime tabla: caso / SQLSTATE esperado / SQLSTATE recibido / pass.

---

**Task 7:** Prueba de concurrencia real

Objetivo: demostrar que dos sesiones que compiten por el mismo `(L,D)` no pueden ambas confirmar, preservando `LD→R`.

Guía: script `07_concurrency.sql` lanza dos sesiones psql o `\connect`. Sesión A: BEGIN, INSERT `(L,R1)` en `lote_responsable`. Sesión B: BEGIN, INSERT mismo `(L,R2)`. Verificar `pg_locks` que B está bloqueada (no solo timing). A hace COMMIT. B recibe 23505. Limpiar solo filas de prueba con SAVEPOINT/ROLLBACK específico.

Tests: `pg_locks` muestra bloqueo real de B; SQLSTATE de B = 23505; recuento final correcto; no se usó sleep como único indicador de bloqueo.

Demo: log lado a lado sesión A y B con timestamps y estados de lock.

---

**Task 8:** Cambios válidos post-COMMIT y snapshot

Objetivo: aplicar los 3 cambios válidos sobre las tablas normalizadas, confirmar 4 filas en el JOIN y guardar snapshot/hash.

Guía: script `08_valid_changes.sql`. UPDATE + 2 INSERT sobre `responsable_deposito` y `lote_responsable`. Verificar JOIN = 4 filas: `(501,31,801),(502,31,801),(503,31,802),(501,30,803)`. Guardar hash SHA-256 de la reunión actual en `migration_manifest`.

Tests: JOIN = 4 filas exactas; hash guardado; `control_legacy_checkpoint` sigue = 3 filas con hash original; `public.*` inalteradas.

Demo: `SELECT * FROM tpi_migracion.control_legacy` retorna 4 filas; ambos hashes visibles en manifiesto.

---

**Task 9:** Reversión post-COMMIT con conservación de cambios

Objetivo: reconstruir `control_legacy` como tabla desde el JOIN actual (4 filas) bajo bloqueo, retirando solo objetos normalizados nuevos, preservando checkpoint de 3 filas.

Guía: script `09_revert_postcommit.sql`. BEGIN → LOCK SHARE ROW EXCLUSIVE → capturar JOIN en tabla temporal → EXCEPT ALL bilateral contra snapshot fase 8 → crear `control_legacy_new` → DROP VIEW `control_legacy` → renombrar `control_legacy_new` → DROP tablas normalizadas, guardia, funciones, triggers (solo dentro de `tpi_migracion`) → COMMIT. En error: ROLLBACK deja versión normalizada operativa intacta.

Tests: post-COMMIT: `control_legacy` es tabla, 4 filas, hash = snapshot fase 8; `control_legacy_checkpoint` = 3 filas, hash = manifiesto inicial; `responsable_deposito` y `lote_responsable` inexistentes; `public.*` inalteradas.

Demo: desde conexión nueva, `\dt tpi_migracion.*` muestra solo `control_legacy` y `control_legacy_checkpoint`; recuentos correctos.

---

**Task 10:** Validación final e informe de evidencias

Objetivo: ejecutar `10_final_validation.sql` desde conexión nueva, corroborar todos los hashes y recuentos, y producir el informe de evidencias TPI 10/11/2026.

Guía: consultar recuentos, hashes y manifiestos. Verificar huellas `public.*`. Generar tabla resumen: fase / resultado esperado / resultado obtenido / hash / pass. Vincular en informe: objetivo 2 → nueva spec + migración + rollback + down 4 filas; objetivo 1 → FD/FNBC; objetivo 3 → MV historia. No inventar confirmaciones humanas; toda evidencia proviene del runner.

Tests: todos los checks anteriores en verde; huellas `public.*` inalteradas; checkpoint 3 filas intacto; `control_legacy` tabla 4 filas.

Demo: informe TPI10/11/2026 imprimible con tabla de evidencias completa y referencia a fuentes nuevas revisadas con OpenCodePlan.
```
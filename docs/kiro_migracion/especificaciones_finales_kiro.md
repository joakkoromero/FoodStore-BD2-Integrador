### FILE: requirements.md

```markdown
# requirements.md — Complemento FNBC Food Store
**Fecha:** 10/11/2026 | Nueva especificación previa a implementación

## Contexto
Complemento nuevo del TPI Food Store. La migración U4 histórica (20/10/2026) no conservó specs Kiro ni prueba de reversión post-COMMIT de FNBC. Estas tres specs son originales del 10/11/2026 y se archivan antes de generar o ejecutar código nuevo.

## Entorno
- PostgreSQL 17.x (compatible 16+), PL/pgSQL.
- Base de trabajo exclusiva: `foodstore_tpi_migracion_nov10`.
- Esquema nuevo: `tpi_migracion` (inexistente antes de la preparación).
- `public.*` y la fuente oficial: solo lectura. Sin modificar roles, permisos ni entregables anteriores.

## Modelo relacional
Tabla fuente: `public.control_lote_almacen_original` — columnas `(L, D, R)`.
Datos fuente: 3 filas `(501,30,801),(502,30,801),(503,31,802)`.
Claves candidatas: **LD** y **LR**.
FD: `LD→R` y `R→D`. Violación FNBC: `R→D`, R no es superclave.
Descomposición sin pérdida: **RD** (PK R) y **LR** (PK LR).
`LD→R` no es preservable por PK/FK locales; requiere guardia compartida + validación del JOIN.

## Requisitos funcionales — EARS

**RF-01** WHEN `current_database()` o el esquema destino no coincidan con los previstos, THEN abortar antes de escribir nada.

**RF-02** WHEN la tabla operativa contiene filas que violan `R→D` antes de migrar (mismo R, distintos D), THEN rechazar la migración con SQLSTATE 23514, sin instalación parcial ni selección arbitraria de depósito.

**RF-03** WHEN la migración se revierte antes de COMMIT, THEN el esquema `tpi_migracion` permanece en estado preparado: `control_legacy` tabla operativa con 3 filas y `control_legacy_checkpoint` inmutable con 3 filas; ningún objeto normalizado persiste.

**RF-04** WHEN la migración se confirma con COMMIT, THEN la reunión `responsable_deposito ⋈ lote_responsable` es equivalente a `control_legacy_checkpoint` en ambos sentidos (EXCEPT ALL bilateral = 0) y `control_legacy` es la vista operativa.

**RF-05** WHEN dos sesiones intentan confirmar el mismo par `(L,D)` con distinto R, THEN exactamente una confirma y la otra recibe SQLSTATE 23505; `LD→R` no se viola.

**RF-06** WHEN se ejecuta la reversión post-COMMIT tras cambios válidos confirmados, THEN la tabla reconstruida refleja el JOIN actual (4 filas), no el checkpoint de 3 filas; los cambios no se pierden.

**RF-07** WHEN ocurre un error inyectado durante la reversión post-COMMIT, THEN el ROLLBACK preserva la versión normalizada operativa completa con 4 filas; la vista y las tablas normalizadas siguen operativas.

**RF-08** WHEN concluye cualquier ensayo, THEN las tablas de `public.*` conservan sus 5 huellas y recuentos originales, sin excepción.

## Requisitos no funcionales

**RNF-01** Mismo cuerpo SQL de migración para ensayo ROLLBACK y ejecución COMMIT; hash del bloque verificado igual en ambas ejecuciones.

**RNF-02** Respaldo custom con manifiesto y hash verificado en carpeta privada antes de cada fase destructiva; sin credenciales ni datos personales en artefactos.

**RNF-03** BIGINT sin secuencias en `tpi_migracion`.

**RNF-04** Funciones con `search_path = tpi_migracion, pg_catalog` y referencias totalmente cal### FILE: requirements.md

```markdown
# requirements.md — Complemento FNBC Food Store
**Fecha:** 10/11/2026 | Nueva especificación previa a implementación

## Contexto
Complemento nuevo del TPI Food Store. La migración U4 histórica (20/10/2026) no conservó specs Kiro ni prueba de reversión post-COMMIT de FNBC. Estas tres specs son originales del 10/11/2026 y se archivan antes de generar o ejecutar código nuevo.

## Entorno
- PostgreSQL 17.x (compatible 16+), PL/pgSQL.
- Base de trabajo exclusiva: `foodstore_tpi_migracion_nov10`.
- Esquema nuevo: `tpi_migracion` (inexistente antes de la preparación).
- `public.*` y la fuente oficial: solo lectura. Sin modificar roles, permisos ni entregables anteriores.

## Modelo relacional
Tabla fuente: `public.control_lote_almacen_original` — columnas `(L, D, R)`.
Datos fuente: 3 filas `(501,30,801),(502,30,801),(503,31,802)`.
Claves candidatas: **LD** y **LR**. FD: `LD→R` y `R→D`.
Violación FNBC: `R→D`, R no es superclave.
Descomposición sin pérdida: **RD** (PK R) y **LR** (PK LR).
`LD→R` requiere guardia compartida + validación del JOIN; no preservable por PK/FK locales.

## Requisitos funcionales — EARS

**RF-01** WHEN `current_database()` o el esquema destino no coincidan con los previstos, THEN abortar antes de escribir nada.

**RF-02** WHEN la tabla operativa contiene filas que violan `R→D` antes de migrar (mismo R, distintos D), THEN rechazar con SQLSTATE 23514, sin instalación parcial ni selección arbitraria de depósito.

**RF-03** WHEN la migración se revierte antes de COMMIT, THEN `tpi_migracion` permanece en estado preparado: `control_legacy` tabla operativa con 3 filas y `control_legacy_checkpoint` inmutable con 3 filas; ningún objeto normalizado persiste.

**RF-04** WHEN la migración se confirma con COMMIT, THEN la reunión `responsable_deposito ⋈ lote_responsable` es equivalente a `control_legacy_checkpoint` en ambos sentidos (EXCEPT ALL bilateral = 0) y `control_legacy` es la vista operativa.

**RF-05** WHEN dos sesiones intentan confirmar el mismo par `(L,D)` con distinto R, THEN exactamente una confirma y la otra recibe SQLSTATE 23505; `LD→R` no se viola.

**RF-06** WHEN se ejecuta la reversión post-COMMIT tras cambios válidos confirmados, THEN la tabla reconstruida refleja el JOIN actual (4 filas), no el checkpoint de 3 filas; los cambios confirmados no se pierden.

**RF-07** WHEN ocurre un error inyectado durante la reversión post-COMMIT, THEN el ROLLBACK preserva la versión normalizada operativa completa con 4 filas; vista y tablas normalizadas siguen operativas.

**RF-08** WHEN concluye cualquier ensayo, THEN las 5 huellas de `public.*` y la fuente oficial conservan sus valores originales, sin excepción.

## Requisitos no funcionales

**RNF-01** Mismo cuerpo SQL de migración para ensayo ROLLBACK y ejecución COMMIT; hash del bloque verificado idéntico en ambas ejecuciones.

**RNF-02** Respaldo custom con manifiesto y hash verificado en carpeta privada antes de cada fase destructiva; sin credenciales ni datos personales en artefactos.

**RNF-03** BIGINT sin secuencias en `tpi_migracion`.

**RNF-04** Funciones con `search_path = tpi_migracion, pg_catalog` y referencias totalmente calificadas.

**RNF-05** Reversión sin CASCADE; sin DROP fuera de `tpi_migracion`. Tablas normalizadas y guardia se conservan como archivo del ensayo, fuera de la interfaz operativa.

**RNF-06** Toda fuente nueva revisada con OpenCodePlan antes de ejecutarse.

**RNF-07** Pruebas negativas con SAVEPOINT específico por caso; sin captura genérica que oculte fallos.

**RNF-08** Prueba de concurrencia con dos backends independientes gestionados por el runner; verificación por `pg_blocking_pids` / `pg_stat_activity.wait_event_type = 'Lock'`, no por sleep fijo.
```

---

### FILE: design.md

```markdown
# design.md — Diseño técnico FNBC Food Store
**Fecha:** 10/11/2026

## Objetos en tpi_migracion

| Objeto | Tipo | Rol |
|---|---|---|
| `control_legacy` | tabla → vista → tabla | interfaz operativa (evoluciona por fase) |
| `control_legacy_checkpoint` | tabla inmutable | archivo histórico 3 filas, nunca se modifica |
| `responsable_deposito` | tabla | RD normalizada, PK R |
| `lote_responsable` | tabla | LR normalizada, PK (L,R) |
| `_migration_guard` | tabla | fila única de guardia transaccional |
| `control_legacy_fnbc_archivada` | vista (renombrada en down) | archivo de la vista operativa normalizada |
| `fn_check_fd_rd()` | función VOLATILE | valida R→D antes de migrar; 23514 si viola |
| `fn_validate_fd_ld_r()` | función VOLATILE | valida LD→R vía JOIN; 23505 si viola |
| `trg_before_*` | trigger BEFORE STATEMENT | actualiza `turno = NOT turno` en `_migration_guard`; garantiza conflicto en snapshots altos |
| `trg_after_*` | trigger AFTER STATEMENT | llama `fn_validate_fd_ld_r()`; revalida JOIN |
| `migration_manifest` | tabla | hashes, recuentos y fases del ensayo |

## Secuencia de fases

**Fase 1 — Preparación**
Validar identidad de base y ausencia previa de `tpi_migracion`. Verificar 3 filas fuente y 5 huellas de `public.*`. Crear esquema. Crear `control_legacy` (tabla operativa, PK(L,D), FKs) y `control_legacy_checkpoint` (tabla inmutable, mismas restricciones). Copiar 3 filas en ambas. Registrar hashes y manifiesto. Estado resultante: esquema preparado, dos tablas con 3 filas cada una.

**Fase 2 — Precondición negativa**
Insertar `(501,31,801)` en `control_legacy` (tabla operativa, nunca en checkpoint). Invocar `fn_check_fd_rd()`. Capturar SQLSTATE 23514. ROLLBACK. Verificar recuento = 3 en `control_legacy`; checkpoint intacto.

**Fase 3 — Ensayo ROLLBACK**
Mismo cuerpo de migración envuelto en BEGIN/ROLLBACK. Dentro: validar FD sobre `control_legacy`, crear `responsable_deposito`, `lote_responsable`, `_migration_guard`, funciones, triggers, migrar proyecciones, crear vista `control_legacy` (reemplaza la tabla operativa dentro de la transacción), verificar conteos y EXCEPT ALL bilateral = 0. ROLLBACK. Post-rollback: `control_legacy` es de nuevo la tabla con 3 filas; `control_legacy_checkpoint` = 3 filas con hash original; ninguna tabla normalizada existe. Hash del cuerpo SQL = hash registrado en Fase 4.

**Fase 4 — Migración confirmada**
Exactamente el mismo cuerpo SQL de Fase 3. COMMIT solo tras todas las verificaciones. `control_legacy` pasa a ser vista operativa. `control_legacy_checkpoint` permanece tabla inmutable con 3 filas.

**Fase 5 — Restricciones**
Un SAVEPOINT por caso:
- Insertar mismo R con otro D en `responsable_deposito` → 23505 (PK R).
- UPDATE válido de depósito para R801 (no genera colisión LD) → debe confirmar sin error.
- Duplicado `(L,R)` en `lote_responsable` → 23505.
- FK inexistente (lote o responsable fuera de maestros) → 23503.
- Dos R del mismo D asignados al mismo L: vía INSERT en `lote_responsable` → 23505 por `fn_validate_fd_ld_r()`; vía UPDATE maestro en `responsable_deposito` que genera colisión → 23505.
Verificar SQLSTATE exacto; ROLLBACK TO SAVEPOINT tras cada caso.

**Fase 6 — Concurrencia**
Runner lanza dos backends independientes (conexiones TCP separadas, no `\connect`).
Sesión A: BEGIN, INSERT en `lote_responsable` para par `(L,R1)` — trigger BEFORE actualiza `turno` en `_migration_guard`, bloqueando a B.
Sesión B: BEGIN, INSERT mismo `(L,R2)` — queda en espera observable por `pg_blocking_pids` y `wait_event_type = 'Lock'`.
A confirma. `fn_validate_fd_ld_r()` de B detecta violación → 23505. B recibe error.
Cleanup: las filas auxiliares confirmadas por A se eliminan en transacción explícita separada (SAVEPOINT no revierte un COMMIT anterior).
El trigger BEFORE con UPDATE de `turno` también garantiza conflicto serialization (40001) en niveles REPEATABLE READ/SERIALIZABLE, lo cual exigiría reintento completo; este comportamiento se documenta pero no se declara como prueba ejecutada.

**Fase 7 — Cambios válidos post-COMMIT**
Sobre tablas normalizadas en `tpi_migracion`: UPDATE depósito de R801 de 30 a 31; INSERT R803→D30; INSERT L501→R803. JOIN resultante = 4 filas: `(501,31,801),(502,31,801),(503,31,802),(501,30,803)`. Guardar hash SHA-256 de la reunión en `migration_manifest`.

**Fase 8 — Reversión post-COMMIT**
BEGIN. LOCK `responsable_deposito` y `lote_responsable` en SHARE ROW EXCLUSIVE. Capturar JOIN actual en tabla temporal. Validar FD/PK/FK sobre la captura. EXCEPT ALL bilateral contra snapshot de Fase 7 → debe ser 0. Crear `control_legacy_new` con las 4 filas. DROP VIEW `control_legacy`; renombrar vista normalizada como `control_legacy_fnbc_archivada` (archivo, no DROP). Renombrar `control_legacy_new` → `control_legacy` (tabla operativa). `responsable_deposito`, `lote_responsable` y `_migration_guard` quedan como archivo del ensayo, fuera de la interfaz operativa. `control_legacy_checkpoint` intacto con 3 filas. COMMIT solo si todo coincide. En error: ROLLBACK deja la versión normalizada con 4 filas operativa y completa.

**Fase 9 — Validación final**
Desde conexión nueva: `control_legacy` es tabla con 4 filas, hash = snapshot Fase 7. `control_legacy_checkpoint` = 3 filas, hash = manifiesto Fase 1. Tablas normalizadas y guardia existen como archivo. 5 huellas de `public.*` inalteradas.

## Guardia transaccional — detalle

`_migration_guard(id BIGINT PK, turno BOOLEAN, locked_by TEXT, ts TIMESTAMPTZ)` — una sola fila.
Trigger BEFORE STATEMENT en ambas tablas normalizadas ejecuta `UPDATE _migration_guard SET turno = NOT turno` sobre esa fila. Esto produce un bloqueo de escritura que serializa concurrentes en READ COMMITTED y genera conflicto de snapshot (40001) en niveles superiores.
Trigger AFTER STATEMENT invoca `fn_validate_fd_ld_r()` (VOLATILE, referencias calificadas, `search_path = tpi_migracion, pg_catalog`); revalida el JOIN completo post-escritura.
```

---

### FILE: tasks.md

```markdown
# tasks.md — Plan de tareas FNBC Food Store
**Fecha:** 10/11/2026
Revisión OpenCodePlan requerida sobre cada fuente nueva antes de ejecutar.
Secuencia de estados: preparado(3) → rollback(3) → commit(3) → cambios(4) → down(4)/checkpoint(3).

---

**Task 1:** Preparación del entorno y checkpoint inicial

Objetivo: crear `foodstore_tpi_migracion_nov10`, esquema `tpi_migracion`, tabla operativa `control_legacy` y tabla inmutable `control_legacy_checkpoint`, ambas con 3 filas; registrar 5 huellas de `public.*` y manifiesto/hash inicial.

Guía: script `01_prepare.sql`. Guard de identidad de base al inicio. Crear ambas tablas con PK(L,D) BIGINT sin secuencias y FKs a maestros de `public`. Copiar 3 filas en cada una desde la fuente. Crear tabla `migration_manifest`. Calcular y almacenar hash SHA-256 del contenido de ambas tablas y de las 5 huellas de `public.*`.

Tests: recuento de `control_legacy` = 3; recuento de `control_legacy_checkpoint` = 3; hashes almacenados ≠ NULL; `current_database()` = previsto; huellas `public.*` registradas.

Demo: ambas tablas visibles con 3 filas; manifiesto con hashes consultable.

---

**Task 2:** Validación de precondición negativa (FD inválida)

Objetivo: demostrar que intentar migrar con una violación `R→D` en `control_legacy` produce SQLSTATE 23514 sin instalación parcial, y que `control_legacy_checkpoint` nunca se toca.

Guía: script `02_negative_precheck.sql`. BEGIN: insertar `(501,31,801)` en `control_legacy` (tabla operativa). Invocar `fn_check_fd_rd()`. Capturar y registrar SQLSTATE. ROLLBACK explícito.

Tests: SQLSTATE recibido = 23514; recuento post-ROLLBACK de `control_legacy` = 3; `control_legacy_checkpoint` = 3 con hash original; ninguna tabla normalizada existe en `tpi_migracion`.

Demo: runner imprime "SQLSTATE 23514 capturado"; recuentos correctos en ambas tablas.

---

**Task 3:** Ensayo de migración con ROLLBACK

Objetivo: ejecutar el cuerpo de migración completo dentro de BEGIN/ROLLBACK; verificar desde segunda conexión que el estado preparado se restaura íntegro.

Guía: script `03_migration_rollback.sql` con el mismo cuerpo SQL que Task 4. Dentro de la transacción: validar FD, crear `responsable_deposito`, `lote_responsable`, `_migration_guard`, funciones, triggers, migrar proyecciones, sustituir `control_legacy` tabla por vista, verificar EXCEPT ALL bilateral = 0 y conteos. ROLLBACK. Script secundario `03b_verify.sql` desde segunda conexión.

Tests: post-ROLLBACK: `control_legacy` tabla con 3 filas, hash = manifiesto Fase 1; `control_legacy_checkpoint` = 3 filas, hash original; ninguna tabla normalizada ni vista en `tpi_migracion`. Hash del cuerpo SQL = hash del cuerpo SQL de Task 4 (verificado por runner antes de ejecutar).

Demo: runner muestra dos sesiones; sesión B confirma estado preparado intacto post-ROLLBACK.

---

**Task 4:** Migración confirmada (COMMIT)

Objetivo: ejecutar exactamente el mismo cuerpo SQL de Task 3 y confirmar; `control_legacy` pasa a ser vista operativa; checkpoint permanece inmutable.

Guía: script `04_migration_commit.sql`. Mismo wrapper, mismo cuerpo. COMMIT solo tras verificación completa de conteos, PK/FK y EXCEPT ALL bilateral = 0.

Tests: `control_legacy` es vista, retorna 3 filas; EXCEPT ALL bilateral = 0; PK/FK de `responsable_deposito` y `lote_responsable` verificadas; `control_legacy_checkpoint` = 3 filas con hash original; 5 huellas `public.*` inalteradas.

Demo: `control_legacy` consultable como vista con 3 filas; tablas normalizadas consultables.

---

**Task 5:** Pruebas de restricciones de integridad

Objetivo: verificar que cada violación produce el SQLSTATE exacto esperado y no deja efectos secundarios.

Guía: script `05_constraints.sql`. Un SAVEPOINT nombrado por caso:
- Mismo R con otro D en `responsable_deposito` → esperado 23505.
- UPDATE válido de depósito para R801 sin colisión LD → debe confirmar sin error.
- Duplicado `(L,R)` en `lote_responsable` → esperado 23505.
- FK inexistente (lote o responsable fuera de maestros) → esperado 23503.
- INSERT `(L,R2)` donde R2 comparte D con R1 ya asignado a L → esperado 23505 vía `fn_validate_fd_ld_r()`.
- UPDATE maestro en `responsable_deposito` que genera colisión LD → esperado 23505.
ROLLBACK TO SAVEPOINT tras cada caso negativo.

Tests: runner imprime tabla caso/SQLSTATE esperado/SQLSTATE recibido/pass; recuentos de tablas normalizadas inalterados al final; UPDATE válido de R801 confirmado.

Demo: tabla de resultados en log del runner; todos los casos en verde.

---

**Task 6:** Prueba de concurrencia real

Objetivo: demostrar con dos backends independientes que el mecanismo de guardia impide que dos sesiones confirmen el mismo par `(L,D)` con distinto R.

Guía: script `06_concurrency.sql` gestionado por el runner. Runner abre dos conexiones TCP independientes. Sesión A: BEGIN, INSERT en `lote_responsable` para `(L,R1)` — trigger BEFORE actualiza `turno` en `_migration_guard`. Sesión B: BEGIN, INSERT mismo `(L,R2)` — queda bloqueada. Runner consulta `pg_blocking_pids` y `pg_stat_activity.wait_event_type = 'Lock'` para confirmar bloqueo real. A hace COMMIT. B recibe SQLSTATE 23505. Cleanup: eliminar filas auxiliares confirmadas por A en transacción explícita separada.

Tests: `pg_blocking_pids` de B referencia PID de A antes del COMMIT de A; SQLSTATE de B = 23505; recuento de `lote_responsable` correcto tras cleanup; no se usó sleep como único indicador de bloqueo.

Demo: log lado a lado con PIDs, timestamps, estados de lock y SQS

---

**Task 7:** Cambios válidos post-COMMIT y snapshot

Objetivo: aplicar los 3 cambios válidos sobre las tablas normalizadas, confirmar JOIN = 4 filas y guardar snapshot/hash.

Guía: script `07_valid_changes.sql`. UPDATE depósito de R801 (30→31); INSERT R803→D30; INSERT L501→R803. Verificar JOIN vía `control_legacy` = 4 filas exactas. Calcular y almacenar hash SHA-256 de la reunión actual en `migration_manifest`.

Tests: `control_legacy` retorna exactamente `(501,31,801),(502,31,801),(503,31,802),(501,30,803)`; hash guardado ≠ NULL; `control_legacy_checkpoint` = 3 filas con hash original inalterado; 5 huellas `public.*` inalteradas.

Demo: `SELECT * FROM tpi_migracion.control_legacy` retorna 4 filas; ambos hashes visibles en manifiesto.

---

**Task 8:** Reversión post-COMMIT con conservación de cambios

Objetivo: reconstruir `control_legacy` como tabla desde el JOIN actual (4 filas) bajo bloqueo, archivar la vista normalizada, conservar tablas normalizadas como archivo y preservar checkpoint de 3 filas.

Guía: script `08_revert_postcommit.sql`. BEGIN. LOCK ambas tablas normalizadas en SHARE ROW EXCLUSIVE. Capturar JOIN actual en tabla temporal. Validar FD/PK/FK sobre la captura. EXCEPT ALL bilateral contra snapshot de Task 7 → debe ser 0. Crear `control_legacy_new` con 4 filas. DROP VIEW `control_legacy`. Renombrar la vista normalizada como `control_legacy_fnbc_archivada`. Renombrar `control_legacy_new` → `control_legacy` (tabla). `responsable_deposito`, `lote_responsable` y `_migration_guard` permanecen como archivo, fuera de la interfaz operativa. COMMIT solo si todo coincide. En error: ROLLBACK deja versión normalizada con 4 filas intacta.

Tests: post-COMMIT: `control_legacy` es tabla con 4 filas, hash = snapshot Task 7; `control_legacy_checkpoint` = 3 filas, hash = manifiesto Task 1; `control_legacy_fnbc_archivada` existe como vista archivada; tablas normalizadas existen como archivo; 5 huellas `public.*` inalteradas. Prueba de error inyectado: ROLLBACK deja versión normalizada operativa con 4 filas completa.

Demo: desde conexión nueva, `control_legacy` es tabla con 4 filas; `\dt tpi_migracion.*` muestra checkpoint, legacy, archivada y tablas normalizadas como archivo.

---

**Task 9:** Validación final e informe de evidencias

Objetivo: verificar desde conexión nueva todos los hashes, recuentos y huellas; producir informe TPI 10/11/2026 con tabla de evidencias completa.

Guía: script `09_final_validation.sql` desde conexión independiente. Consultar recuentos, hashes y manifiesto. Verificar 5 huellas de `public.*`. Generar tabla resumen: fase / resultado esperado / resultado obtenido / hash / pass. Vincular en informe: objetivo 2 → nueva spec + migración + rollback + down 4 filas; objetivo 1 → FD/FNBC; objetivo 3 → MV historia. Toda evidencia proviene del runner; no se inventan confirmaciones humanas ni firmas.

Tests: todos los checks anteriores en verde; `control_legacy` tabla 4 filas; `control_legacy_checkpoint` tabla 3 filas; tablas normalizadas y `control_legacy_fnbc_archivada` presentes como archivo; 5 huellas `public.*` = valores registrados en Task 1.

Demo: informe TPI 10/11/2026 con tabla de evidencias completa; referencia a fuentes nuevas pendientes de revisión con OpenCodePlan antes de ejecutar.
```
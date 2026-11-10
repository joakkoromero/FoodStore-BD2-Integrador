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

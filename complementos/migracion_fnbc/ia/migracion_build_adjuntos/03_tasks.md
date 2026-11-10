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

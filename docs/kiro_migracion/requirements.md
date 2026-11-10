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

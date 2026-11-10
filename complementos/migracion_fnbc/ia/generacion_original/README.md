# Complemento FNBC Food Store

Fuentes nuevas para revision automatizada OpenCodePlan y lectura tecnica antes
de cualquier ejecucion. Este documento no acredita ejecucion, aprobacion humana
ni resultados observados.

## Alcance

- Python 3.12+, biblioteca estandar y PostgreSQL 16+.
- Unica base de escritura: `foodstore_tpi_migracion_nov10`.
- Unico esquema persistente de escritura: `tpi_migracion`.
- La copia nueva debe existir y contener los maestros necesarios.
- El esquema destino debe estar ausente.
- `public` y la base fuente se consultan exclusivamente en lectura.
- No se crean bases, roles, usuarios, permisos, maestros ni secuencias.
- No hay eliminacion explicita de objetos ni limpieza automatica de esquemas.
- El cliente existente `unidad5/tools/libpq_client.py` se importa sin modificar.
- Importar `reproducir.py` no abre conexiones.

Los archivos SQL son cuerpos transaccionales sin control transaccional externo.
El runner decide la confirmacion o reversion de cada cuerpo.

## Archivos

| Archivo | Responsabilidad |
|---|---|
| `preparar.sql` | Identidad, esquema nuevo, legacy, checkpoint protegido, hashes y precondicion |
| `migrar.sql` | Descomposicion RD/LR, guardia, validacion y vista |
| `revertir.sql` | Reconstruccion actual, archivo normalizado y lifecycle inactivo |
| `reproducir.py` | Preflight, pruebas, concurrencia, verificaciones y evidencia |
| `README.md` | Contrato operativo y limites |

## Datos

La fuente completa debe contener exactamente:

| lote_id | deposito_id | responsable_control_id |
|---:|---:|---:|
| 501 | 30 | 801 |
| 502 | 30 | 801 |
| 503 | 31 | 802 |

Se conservan:

- `control_legacy_checkpoint`: tres filas independientes, protegido.
- `control_legacy_pre_migracion`: tabla operativa inicial renombrada.
- `responsable_deposito`: RD, clave R.
- `lote_responsable`: LR, clave LR.
- `_migration_guard`: guardia compartida y estado del ciclo.
- `migration_manifest`: hashes y fases.
- `down_snapshot`: captura persistente del JOIN actual durante down.
- `control_legacy_fnbc_archivada`: vista normalizada renombrada durante down.
- `control_legacy`: tabla reconstruida final de cuatro filas.

La captura de down se conserva dentro de `tpi_migracion`, en lugar de crear
objetos temporales fuera del esquema exclusivo. Se revierte tambien ante el
error inyectado.

## Preparacion Externa

El operador debe entregar la copia nueva, credenciales privadas y un respaldo
custom anterior al comienzo del ensayo.

El runner no genera respaldos ni restaura bases. Antes de cada fase que escribe
revalida el mismo respaldo privado inicial: contenido, formato custom, bytes,
SHA256, manifiesto y tiempos. Esto no equivale a generar un respaldo actualizado
de cada estado intermedio.

El secreto y el manifiesto deben estar fuera del repositorio. El archivo dump
debe estar junto al manifiesto.

Formato obligatorio del manifiesto privado:

```json
{
  "status": "SUCCESS",
  "database": "foodstore",
  "file": "respaldo_unico.dump",
  "size": 123456,
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  "startUtc": "2026-11-10T10:00:00Z",
  "endUtc": "2026-11-10T10:01:00Z",
  "baseline": {
    "counts": {
      "public.lote": 3
    },
    "fingerprints": {
      "public.lote": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    }
  }
}
```

Los valores son ilustrativos del formato, no evidencia de un respaldo existente.
Todos deben reemplazarse por datos reales del respaldo privado.

`file` debe ser un basename seguro. Se rechazan rutas y escapes mediante enlaces
que resuelvan fuera de la carpeta del manifiesto. Los tiempos deben tener zona;
el final debe preceder al comienzo del ensayo.

Las huellas del manifiesto solo se validan estructuralmente. No se comparan con
las nuevas huellas asumiendo una receta de agregacion desconocida.

La evidencia no incluye contenido del secreto, rutas privadas, nombre del dump,
filas personales ni diagnosticos brutos del servidor.

## Puerta De Revision

El runner exige `--provenance` como entrada adicional para no inventar
proveniencia o declarar una revision que no existe.

Es un indice JSON que enlaza artefactos reales previamente conservados. No lo
genera este complemento. Los archivos referenciados deben estar dentro del
repositorio; los paths son relativos a su raiz.

Estructura del indice:

```text
code_commit_before_execution: commit completo que debe ser HEAD
kiro_spec_commit: commit completo anterior, ancestro de HEAD
kiro_specs: lista de exactamente tres registros path/sha256
codex_prebuild_notes: lista de exactamente dos registros path/sha256
build:
  prompt: registro path/sha256
  answer: registro path/sha256
  metadata: registro path/sha256
plan:
  prompt: registro path/sha256
  answer: registro path/sha256
  metadata: registro path/sha256
```

Cada registro tiene exactamente las claves `path` y `sha256`.

Las specs originales y las dos notas deben coincidir byte a byte con sus
versiones en `kiro_spec_commit`. Los cinco archivos del complemento y los
artefactos Build/Plan deben coincidir con `HEAD`.

El cliente libpq debe coincidir con su version en ambos commits. Los cambios
ajenos a estos archivos no se revierten ni limpian.

Los metadatos JSON conservados de Build y Plan deben contener:

| Campo | Valor requerido |
|---|---|
| `mode` | `pure` |
| `permission` | `deny` |
| `tool_events` | lista vacia |
| `review_automated_not_human` | `true` |
| `kiro_specs_sha256` | mapa path relativo a SHA256 de las tres specs |
| `codex_prebuild_notes_sha256` | mapa path relativo a SHA256 de las dos notas |
| `prompt_sha256` | SHA256 del prompt original enlazado |
| `answer_sha256` | SHA256 de la respuesta original enlazada |

Los metadatos Plan tambien deben contener:

- `reviewed_sources_sha256`: mapa path relativo a SHA256 de los cinco archivos.
- `decision`: `allow_execution`.

Si el wrapper real produce otro formato, se requiere revisar explicitamente
esta puerta y conservar los originales antes de ejecutar. No se deben editar
metadatos originales para simular conformidad. Un indice o hash no demuestra
por si solo la autenticidad del proveedor: el operador debe verificar la
procedencia real de los artefactos.

La revision Plan debe cubrir los bytes finales. Un cambio posterior exige
nueva revision y nuevos hashes. El commit final incorpora fuentes y evidencia
de revision; no se requiere que los metadatos incluyan su propio commit.

## Invocacion

Desde la raiz del repositorio:

```console
python complementos/migracion_fnbc/reproducir.py --secret-file C:\privado\fnbc.secret --backup-manifest C:\privado\backup_manifest.json --provenance complementos/migracion_fnbc/ia/provenance.json
```

Valores predeterminados:

| Opcion | Valor |
|---|---|
| `--host` | `127.0.0.1` |
| `--port` | `55605` |
| `--user` | `u5_bootstrap` |
| `--source-database` | `foodstore` |
| `--evidence` | `docs/evidencias_tpi/migracion_fnbc.json` |

No hay opcion para cambiar la base de escritura.

La evidencia debe ser un JSON nuevo dentro del repositorio. El runner rechaza
sobrescribir evidencia existente. Para conservar un intento anterior, elegir
otro archivo con `--evidence`.

La autenticacion depende del formato soportado por el cliente libpq existente.
El runner no interpreta ni imprime el secreto.

## Secuencia

1. Verificar respaldo, hashes, commits y revision automatizada.
2. Observar huellas de la copia y de la fuente.
3. Preparar dentro de una transaccion; verificar antes de confirmar.
4. Insertar el dato que viola R a D; observar 23514 y revertir.
5. Ejecutar `migrar.sql`, verificar y revertir.
6. Verificar desde conexion nueva catalogo, filas y hashes preparados.
7. Ejecutar exactamente el mismo `migrar.sql`, verificar y confirmar.
8. Probar PK, FK y LD a traves del JOIN con savepoints especificos.
9. Aceptar un UPDATE maestro valido y revertirlo expresamente.
10. Probar dos escritores independientes con monitor independiente.
11. Confirmar limpieza auxiliar en una transaccion posterior.
12. Confirmar los cambios validos que producen cuatro filas.
13. Ejecutar down con error P7501 despues de reconstruir, renombrar y desactivar.
14. Revertir y verificar desde conexion nueva DDL, lifecycle y cuatro filas.
15. Ejecutar down nuevamente y confirmar.
16. Probar rechazos 25006 sobre archivos y checkpoint.
17. Verificar huellas, hashes y ausencia de secuencias; emitir SUCCESS.

Las cinco huellas se verifican al finalizar cada fase completada. Ante fallo se
intenta una observacion adicional independiente y se conserva estado FAILED.

## Guardia Y Concurrencia

Ambas tablas normalizadas tienen un trigger BEFORE STATEMENT que actualiza
`turno = NOT turno` en la misma fila de `_migration_guard`. Los triggers AFTER
STATEMENT validan LD a R sobre el JOIN completo.

La prueba usa READ COMMITTED:

- A inserta L503/R801.
- B intenta insertar L503/R803, con R803 previamente asociado a D30.
- El monitor observa `wait_event_type = 'Lock'` y A dentro de
  `pg_blocking_pids(B)`.
- Solo entonces se autoriza el COMMIT de A.
- B debe observar exactamente 23505.
- Una transaccion posterior elimina la asignacion auxiliar de A y R803.

Cada hilo crea y cierra su propia conexion. Los PIDs de A, B y monitor deben
ser diferentes. Los timeouts limitan conexion, sentencias, locks y coordinacion.

El intervalo corto entre consultas solo regula el polling; nunca constituye
prueba de bloqueo.

REPEATABLE READ y SERIALIZABLE pueden producir 40001 por la actualizacion de
la guardia. Se requiere reintento completo en esos niveles. Este laboratorio
no los declara probados.

## Huellas

Se producen exactamente cinco entradas:

1. `public.lote`.
2. `public.deposito`.
3. `public.usuario`.
4. `public.control_lote_almacen_original`.
5. `public.remaining_tables_and_catalog`.

La quinta agrega todas las demas tablas ordinarias, particionadas y vistas
materializadas de public, junto al inventario de esas relaciones y sus columnas.
No se inventa el nombre de una quinta tabla no especificada.

Cada tabla se resume dentro de PostgreSQL con cantidad y SHA256 del multiconjunto
ordenado de hashes SHA256 de sus filas JSONB. Las filas de usuario nunca salen
del servidor. La quinta entrada se resume desde esos agregados y metadatos.

Las huellas se comparan con su propio before, por base. No se exige igualdad
entre fuente y copia ni entre recetas historicas diferentes.

Para las relaciones L/D/R del complemento se usa SHA256 de:

```text
L,D,R;L,D,R
```

Las filas se ordenan numericamente por L, D y R. No hay salto final. Esta receta
coincide entre SQL y Python y conserva multiplicidad.

## Reversion

Down bloquea RD/LR antes de capturar el JOIN actual. Compara cantidad, hash y
EXCEPT ALL bilateral con el snapshot confirmado de cuatro filas.

La tabla reconstruida tiene PK y las tres FKs a maestros existentes. La vista
normalizada se renombra, no se elimina. El checkpoint inicial no se utiliza
como fuente de reconstruccion.

El error P7501 ocurre despues de reconstruir, renombrar, desactivar el lifecycle
y registrar la fase. Su reversion debe restaurar el estado normalizado completo.

Despues de down, los triggers rechazan INSERT, UPDATE, DELETE y TRUNCATE en
RD/LR con 25006. Se prueba TRUNCATE de ambas tablas juntas porque truncar solo
RD puede ser rechazado antes por su FK entrante. Tambien se prueba LR sola.

El checkpoint rechaza las cuatro operaciones desde su preparacion.

Estas protecciones son de aplicacion. No protegen frente a un propietario o
administrador que altere triggers, funciones, guardia o DDL.

## Fallos Y Limites

- Solo se marca SUCCESS despues de todos los controles.
- No se utilizan comprobaciones `assert` eliminables con `python -O`.
- Los casos negativos comparan `DatabaseError.sqlstate`.
- Las capturas generales solo marcan fallo, nunca exito de una prueba negativa.
- No se imprimen respuestas brutas ni mensajes del servidor.
- Un fallo posterior a un COMMIT no revierte ese COMMIT historico.
- No hay reejecucion destructiva, reutilizacion de esquema ni recuperacion
  automatica de un laboratorio incompleto.
- Un ensayo fallido puede conservar auxiliares confirmados antes del fallo;
  la evidencia FAILED no afirma limpieza global ni exito.
- El operador debe impedir escritores externos durante el ensayo.
- Las huellas detectan diferencias entre observaciones; no son auditoria de
  modificaciones transitorias posteriormente deshechas por terceros.
- Los agregados ordenados se calculan en memoria del servidor; revisar recursos
  para bases grandes.
- No se valida una restauracion real del dump: se validan su manifiesto,
  integridad y firma de formato custom.
- El runner no cambia permisos del sistema operativo; la privacidad efectiva
  de los archivos externos corresponde al operador.
- La persistencia del JSON final tambien puede fallar por permisos o disco lleno;
  nunca debe interpretarse ausencia de evidencia como exito.

## Decisiones Para Revision

- Se conserva `down_snapshot` dentro del esquema exclusivo como evidencia.
- La quinta huella cubre tablas restantes e inventario, sin suponer otro maestro.
- `--provenance` es obligatorio para bloquear ejecucion sin revision verificable.
- Se revalida el respaldo inicial antes de cada fase; no se generan respaldos.
- Estas fuentes no han sido ejecutadas ni se presentan como aprobadas por humanos.

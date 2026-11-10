# Requisitos U8 – Food Store SQLite (Arancibia / Romero)

## Alcance

Tablet SQLite 3.37+ que opera sin conexión a PostgreSQL, usando una copia nueva
`foodstore_u8_arancibia_romero`. La fuente oficial `foodstore` nunca se modifica.
Ningún SIMULADO_APROBADO equivale a una venta real.

---

## REQ-01 — Integridad y atomicidad offline

WHEN la tablet funciona sin conexión o el operador registra un borrador,
THE SYSTEM SHALL consultar el catálogo local y persistir borrador, ítems y
solicitud de forma atómica en las cuatro tablas STRICT, con PRAGMA foreign_keys=ON
activado y verificado en cada conexión, centavos INTEGER no negativo, forma de
pago CHECK IN ('EFECTIVO','TARJETA','TRANSFERENCIA'), cantidades positivas y
solicitud_uuid TEXT PRIMARY KEY; y si cualquier sentencia dentro de la transacción
falla, ejecutar ROLLBACK completo sin dejar filas parciales en ninguna tabla.

Casos de prueba

C1-COMMIT: Insertar borrador con dos ítems válidos y solicitud PENDIENTE dentro
de BEGIN/COMMIT. Resultado: filas presentes; PRAGMA integrity_check = ok.

C1-ROLLBACK: Mismo flujo con ROLLBACK explícito. Resultado: ninguna fila nueva
persiste en ninguna tabla.

C7-cantidad: Transacción que inserta header de borrador válido y luego intenta
insertar ítem con cantidad=0 (viola CHECK). Resultado: ROLLBACK completo; header
tampoco persiste; SELECT devuelve cero filas nuevas.

C7-fk: Transacción que inserta header válido y luego ítem con producto_id
inexistente (viola FK). Resultado: ROLLBACK completo; header tampoco persiste.

---

## REQ-02 — Semáforo con prioridad rojo > amarillo

WHEN se ejecuta la simulación de una solicitud con estado PENDIENTE contra una
instantánea nueva en snapshot_servidor,
THE SYSTEM SHALL evaluar cada ítem del borrador mediante LEFT JOIN a
snapshot_servidor (no a producto_cache), marcar RECHAZADO si el borrador no
contiene ítems, si algún producto_id no aparece en snapshot_servidor, si está
eliminado, si stock=0 o si cantidad pedida supera el stock disponible en
snapshot_servidor; marcar CONFLICTO únicamente si no hay rojo y algún precio
difiere del registrado en item_borrador; marcar SIMULADO_APROBADO solo si no hay
rojo ni amarillo; actualizar estado y motivo en cola_sync solo cuando estado=PENDIENTE;
y, ante un ítem que simultáneamente genera rojo y precio distinto, registrar
siempre RECHAZADO.
Cuando el operador acepta un precio tras CONFLICTO, THE SYSTEM SHALL actualizar
precio_centavos_visto en item_borrador, crear nueva fila en cola_sync con
solicitud_uuid nuevo, conservar la fila anterior con su resultado CONFLICTO.

Casos de prueba

C2: Snapshot con precio modificado; re-simular. Estado = CONFLICTO; motivo
incluye producto_id y ambos precios; fila anterior intacta.

C2-aceptar: Operador acepta precio; re-simular con UUID nuevo. Estado =
SIMULADO_APROBADO; fila C2 permanece CONFLICTO; precio actualizado en
item_borrador.

C3: Snapshot con stock insuficiente (stock < cantidad). Estado = RECHAZADO;
motivo indica stock insuficiente con valores concretos.

C5: Snapshot sin cambios. Estado = SIMULADO_APROBADO.

Mixto: Borrador con un producto sin stock y otro con precio distinto. Estado =
RECHAZADO; motivo menciona el producto sin stock (rojo tiene prioridad).

Borrador vacío: Borrador sin ítems. Estado = RECHAZADO; motivo indica borrador
vacío.

---

## REQ-03 — Idempotencia UUID y una sola solicitud PENDIENTE

WHEN se reenvía o duplica una solicitud ya evaluada,
THE SYSTEM SHALL rechazar INSERT de solicitud_uuid repetido via PRIMARY KEY de
cola_sync, conservar estado y motivo originales sin reevaluar, y garantizar como
máximo una solicitud PENDIENTE simultánea por borrador mediante índice UNIQUE
parcial ON cola_sync(id_local) WHERE estado='PENDIENTE', sin imponer UNIQUE global
sobre id_local.

Casos de prueba

C6-PK: Re-insertar el mismo solicitud_uuid de C2. Resultado: error UNIQUE
constraint; fila original inalterada.

C6-semáforo: Ejecutar el semáforo nuevamente sobre el UUID ya evaluado de C2
(estado distinto de PENDIENTE). Resultado: estado y motivo sin cambios; el
semáforo no actualiza filas que no estén PENDIENTE.

C6-PENDIENTE: Intentar insertar segunda solicitud PENDIENTE para el mismo
id_local. Resultado: error de índice parcial; primera PENDIENTE inalterada.

C6-histórico: Insertar segunda fila con estado CONFLICTO para el mismo id_local
que ya tiene un CONFLICTO previo. Resultado: inserción exitosa; id_local aparece
dos veces en cola_sync.

---

## REQ-04 — Snapshot con lápidas y autoridad exclusiva de PostgreSQL

WHEN se descarga o recarga el catálogo desde PostgreSQL,
THE SYSTEM SHALL importar la instantánea desde CSV producido por psql \copy sobre
v_snapshot_movil de la copia autorizada, cargar filas en snapshot_servidor,
actualizar e insertar en producto_cache mediante UPSERT ON CONFLICT DO UPDATE sin
eliminar filas referenciadas, conservar productos dados de baja como lápidas
(eliminado=1) ocultos en v_catalogo_disponible pero presentes en producto_cache,
tomar capturado_en del servidor PostgreSQL, y no emitir ninguna escritura sobre
tablas de PostgreSQL durante la simulación; al finalizar, comparar conteo de
pedidos y stock fixture en la copia antes y después, y verificar que las huellas
de al menos cinco tablas de foodstore permanecen idénticas.

Casos de prueba

C4-importar: CSV con un producto nuevo y uno con eliminado=t. Resultado:
producto_cache contiene ambos; v_catalogo_disponible oculta el eliminado.

C4-baja: Simular borrador que incluye el producto con eliminado=1 en
snapshot_servidor. Estado = RECHAZADO; motivo indica baja.

C4-lápida: Consultar producto_cache directamente. Fila con eliminado=1 presente;
v_catalogo_disponible no la muestra.

Conservación: Conteo de pedidos y stock fixture en la copia = idénticos antes y
después de todas las pruebas.

Huella foodstore: Hashes de al menos cinco tablas de foodstore = idénticos;
verificación real de filas y bytes, sin sustitución por comandos shell como
evidencia única.

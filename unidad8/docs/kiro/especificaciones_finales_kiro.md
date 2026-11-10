### FILE: requirements.md

```
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
```

---

### FILE: design.md

```
# Diseño U8 – Food Store SQLite (Arancibia / Romero)

## 1. Copia PostgreSQL

Base nueva foodstore_u8_arancibia_romero creada desde template foodstore.
Respaldo previo guardado de forma privada y verificado por conteo y hash antes
de cualquier modificación. La base original no recibe DROP ni alteración.

Esquema real relevante: la PK de producto es producto.id; la PK de categoria es
categoria.id; la relación es producto.categoria_id = categoria.id. La vista de
exportación móvil expone producto_id = p.id como alias de salida. disponible se
deriva de (p.stock > 0). La baja se calcula como (p.eliminado OR c.eliminado).
precio_centavos = (p.precio * 100) convertido a BIGINT para manejar importes
mayores al límite de INTEGER 32-bit. capturado_en proviene de now() del servidor.

Fixture: productos "U8-FERIA-*" en categoría propia, identificables como datos
de prueba; sin exportar usuarios, contraseñas, mails ni datos de pago.

Preparación administrativa explícita solo en la copia: C2 requiere modificar el
precio de un producto fixture antes de exportar el CSV; C4 requiere marcar
eliminado=true en un producto fixture. Ninguna de estas modificaciones es efecto
del semáforo.

Exportación: psql \copy sobre v_snapshot_movil produce snapshot.csv con cabecera,
booleanos t/f, fecha del servidor.

Verificación de conservación: hashes de al menos cinco tablas de foodstore
calculados antes y después de todas las pruebas; comparación real de filas y
bytes, no solo comandos shell.

## 2. Esquema SQLite

Cinco tablas: producto_cache, pedido_borrador, item_borrador, cola_sync y
snapshot_servidor. Las primeras cuatro son STRICT. snapshot_servidor es la tabla
de importación auxiliar (recibe CSV crudo; no STRICT para tolerar tipos de texto).

PRAGMA foreign_keys=ON se ejecuta y verifica en cada conexión.

producto_cache: producto_id PK, nombre, precio_centavos INTEGER>=0,
stock_visto INTEGER>=0, disponible_visto 0/1, eliminado 0/1, capturado_en TEXT.

pedido_borrador: id_local TEXT PK (UUID válido), usuario_id_servidor INTEGER de
prueba, forma_pago con CHECK, creado_en TEXT ISO 8601. Sin nombre, contacto ni
credenciales.

item_borrador: PK compuesta (id_local, producto_id); ambas columnas FK;
cantidad INTEGER CHECK >0; precio_centavos_visto INTEGER CHECK >=0.

cola_sync: solicitud_uuid TEXT PK, id_local FK, estado CHECK IN
('PENDIENTE','CONFLICTO','RECHAZADO','SIMULADO_APROBADO'), motivo TEXT,
evaluado_en TEXT. Índice UNIQUE parcial ON cola_sync(id_local) WHERE
estado='PENDIENTE'. Sin UNIQUE global sobre id_local.

snapshot_servidor: refleja la captura actual completa exportada por CSV;
columnas disponible y eliminado como TEXT (t/f); se usa exclusivamente como
fuente de la evaluación del semáforo y de la recarga de producto_cache.

## 3. Recarga de catálogo (UPSERT)

Importar snapshot.csv a snapshot_servidor. Convertir t/f a 1/0 con control de
formato al leer. Propagar a producto_cache mediante INSERT ... ON CONFLICT
(producto_id) DO UPDATE SET nombre=..., precio_centavos=..., stock_visto=...,
disponible_visto=..., eliminado=..., capturado_en=...; esta forma preserva la fila
existente, sus FK y lápidas, sin eliminarla. No usar REPLACE (eliminaría la fila
previa y podría romper referencias o activar cascadas no deseadas).

## 4. Lógica del semáforo

Transacción SQLite local; sin conexión ni escritura a PostgreSQL.

Pasos: (a) verificar que el borrador tenga ítems; si no, RECHAZADO "borrador
vacío". (b) LEFT JOIN item_borrador a snapshot_servidor por producto_id; evaluar
rojo si producto_id IS NULL en snapshot, eliminado=1, stock=0 o cantidad >
stock. (c) si hay rojo: estado=RECHAZADO, registrar motivo con producto_ids y
causas. (d) si no hay rojo y algún precio difiere: estado=CONFLICTO. (e) si no
hay rojo ni amarillo: estado=SIMULADO_APROBADO. (f) UPDATE cola_sync SET
estado=..., motivo=..., evaluado_en=... WHERE solicitud_uuid=... AND
estado='PENDIENTE'; la condición AND estado='PENDIENTE' garantiza que solicitudes
ya evaluadas no se sobreescriban.

Aceptación de precio (C2-aceptar): actualizar precio_centavos_visto en
item_borrador, insertar nueva fila en cola_sync con solicitud_uuid nuevo y
estado PENDIENTE, re-ejecutar semáforo con el UUID nuevo.

## 5. Plan de continuidad U6 (extensión)

Contemplar: invalidar tablets con snapshot anterior a un umbral de tiempo tras
restaurar un respaldo de PostgreSQL; resincronizar colas UUID antes de reenviar
solicitudes pendientes; reconciliar conflictos generados durante el período de
indisponibilidad sin fingir ventas; revisar periódicamente solicitudes PENDIENTE
huérfanas.
```

---

### FILE: tasks.md

```
# Tareas U8 – Food Store SQLite (Arancibia / Romero)

Task 1: Congelar especificaciones

Guardar requirements.md, design.md y tasks.md en docs/kiro/. Registrar sha256 y
fecha de cada archivo. Anotar en bitácora que estos archivos son autoría de
Codex/Kiro y aún no constituyen evidencia de ejecución de código.
Demo: tres archivos en docs/kiro/, hashes verificables, bitácora con entrada
inicial.

Task 2: Preparar copia PostgreSQL y fixture

Respaldar foodstore privadamente y verificar por conteo y hash. Crear
foodstore_u8_arancibia_romero desde template sin DROP ni reemplazar la fuente.
Verificar que foodstore sigue intacto (hash pre/post de al menos cinco tablas).
Insertar productos "U8-FERIA-*". Crear vista v_snapshot_movil con el mapeo
correcto (producto_id=p.id, precio*100 BIGINT, disponible derivado, baja por
producto.eliminado OR categoria.eliminado). Exportar snapshot_inicial.csv.
Demo: conteo de fixture, CSV con cabecera correcta, hashes de foodstore sin
cambios.

Task 3: Generar esquema SQLite con OpenCode Build

OpenCode Build genera movil/schema_sqlite.sql a partir de design.md. Leer el
script antes de ejecutarlo. Crear SQLite desde cero; verificar PRAGMA
integrity_check=ok, PRAGMA foreign_keys=1, cinco tablas presentes, índice
parcial en cola_sync.
Demo: salida de verificaciones sin errores; base vacía lista para datos.

Task 4: Generar e integrar importación de snapshot

OpenCode Build genera el script de importación. Leer antes de ejecutar.
Importar snapshot_inicial.csv a snapshot_servidor; convertir t/f con control
de formato; propagar a producto_cache con UPSERT ON CONFLICT DO UPDATE.
Verificar v_catalogo_disponible oculta eliminados.
Demo: SELECT COUNT(*) en producto_cache; fila eliminada visible en cache y
ausente de la vista.

Task 5: Pruebas de atomicidad C1 y C7

OpenCode Build genera movil/pruebas_sqlite.sql. Leer antes de ejecutar.
C1-COMMIT: borrador + ítems + PENDIENTE; verificar filas. C1-ROLLBACK: mismo
flujo con ROLLBACK; verificar cero filas. C7-cantidad: header válido + ítem
cantidad=0; verificar ROLLBACK completo (header tampoco persiste). C7-fk: header
válido + producto_id inexistente; verificar ROLLBACK completo. UUIDs con formato
válido; sin datos personales.
Demo: salidas SELECT antes/después de cada transacción documentadas.

Task 6: Semáforo — preparación administrativa y casos C2 a C6

Preparación en la copia: modificar precio de un producto fixture (C2), marcar
eliminado en otro (C4). Estos cambios los ejecuta el operador explícitamente, no
el semáforo. OpenCode Build genera movil/semaforo.sql. Revisar con OpenCode Plan
antes de ejecutar. Ejecutar en orden: C3, C4, C5, C2, C2-aceptar, mixto
rojo/amarillo, borrador vacío. Ejecutar C6: C6-PK (UUID duplicado), C6-semáforo
(re-evaluar UUID ya evaluado, verificar igualdad estado/motivo), C6-PENDIENTE
(segunda PENDIENTE misma id_local), C6-histórico (segunda entrada CONFLICTO).
Demo: tabla cola_sync con todas las filas; estados y motivos correctos; ninguna
escritura en PostgreSQL.

Task 7: Verificar conservación de PostgreSQL

Comparar conteo de pedidos y stock fixture en la copia antes y después de las
pruebas. Calcular hashes de al menos cinco tablas de foodstore antes y después.
Verificar que snapshot_servidor es de solo lectura en el flujo de semáforo.
Documentar explícitamente: SIMULADO_APROBADO ≠ venta; ninguna transacción de
venta fue creada en PostgreSQL.
Demo: tabla comparativa de conteos y hashes; afirmación de no-escritura
fundamentada en ausencia de logs de modificación.

Task 8: Review OpenCode Plan, correcciones y segunda ejecución

Congelar trabajo en rama review-final. OpenCode Plan revisa TODOS los scripts
disponibles de la cursada por unidades; si un adjunto se trunca, dividir y
continuar. El informe desarrolla como mínimo tres hallazgos de al menos dos
unidades; al menos uno descartado con fundamentación y prueba. Cada hallazgo
registra decisión: aceptado, corregido o descartado. Corregir en commits
separados. Reproducir desde SQLite vacío y comparar evidencia de primera y
segunda ejecución.
Demo: rama review-final, log de commits, dos salidas comparadas, registro de
hallazgos con decisiones reales.

Task 9: Artefactos finales

Mapa PostgreSQL/MongoDB/SQLite. Extensión del plan U6 según design.md sección 5.
Bitácora de IA con al menos tres entradas reales (fecha, herramienta, resultado).
DUIA de la cátedra. README con estructura del proyecto. Informe máximo seis
páginas. ZIP food-store/ con base SQLite y archivos requeridos; verificación
real de entradas y bytes; scan sin secretos ni datos personales (verificación
de contenido, no solo comando shell). Guion de defensa de diez minutos; el
ensayo real lo realiza el equipo en clase y no se simula aquí.
Demo: ZIP verificado por contenido; hashes documentados; bitácora con al menos
tres entradas reales.
```
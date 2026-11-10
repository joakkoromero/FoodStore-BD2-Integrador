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

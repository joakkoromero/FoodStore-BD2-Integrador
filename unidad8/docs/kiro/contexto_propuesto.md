# Propuesta de especificación U8 para trabajar en Kiro

Autoría de esta propuesta: Codex. Estado: borrador previo a Kiro; no es evidencia de una ejecución de Kiro. Todavía no se generaron los scripts U8.

## Contexto que debe conservar Kiro

Equipo: Exequiel Arancibia / Joaquin Romero. Food Store de PostgreSQL 17.11 acumulado desde los TP anteriores y las unidades 4 a 6; pedidos y detalles documentales consultados en MongoDB en U7. La fuente oficial es `foodstore`, que no se modifica. El cliente se llama `usuario`; `detalle_pedido` tiene clave `(pedido_id, producto_id)` y subtotal generado. El servidor oficial decide precios, stock y ventas.

El laboratorio usará una copia nueva `foodstore_u8_arancibia_romero`, creada desde `foodstore` y sin reemplazar ninguna base existente. Antes de cambios se verificará la copia y se conservará un respaldo. Se agregarán productos de feria inventados, identificables como fixture de U8. No se exportarán usuarios, contraseñas, mails, teléfonos ni datos de pagos. El identificador numérico de usuario de los borradores será un valor de prueba, sin datos personales asociados en SQLite.

Adaptación necesaria al modelo real: `producto` no posee un flag `disponible`. La vista lo obtiene como `(p.stock > 0) AS disponible`. La baja se calcula con `(p.eliminado OR c.eliminado) AS eliminado`, incluyendo la categoría. Los centavos se convierten con `(p.precio * 100)::BIGINT`, porque el `NUMERIC(12,2)` real admite importes mayores al máximo de INTEGER de 32 bits. SQLite almacena enteros de 64 bits. La tablet recibe sólo el catálogo ficticio de la feria, no los 50.000 productos de todo el proyecto.

## requirements.md propuesto: exactamente cuatro requisitos EARS

**REQ-01.** WHEN la tablet funciona sin conexión o registra un borrador THE SYSTEM SHALL consultar el catálogo local y guardar borrador, ítems y solicitud de forma atómica, con cuatro tablas STRICT, claves foráneas activas, centavos enteros no negativos, formas de pago válidas, cantidades positivas e identificadores UUID. Si una operación falla o se cancela, no deberá dejar filas nuevas. **Pruebas:** C1, C7, COMMIT y ROLLBACK.

**REQ-02.** WHEN se simula una solicitud PENDIENTE contra una instantánea nueva THE SYSTEM SHALL guardar RECHAZADO si falta un producto, está dado de baja, no está disponible o falta stock; en ausencia de rojo, CONFLICTO si cambió un precio; y en otro caso SIMULADO_APROBADO. El rojo deberá tener prioridad sobre el cambio de precio. La aceptación explícita del precio actualizará el borrador y creará una solicitud con UUID nuevo, conservando el resultado anterior. **Pruebas:** C2, C3, C4, C5 y caso mixto rojo/amarillo.

**REQ-03.** WHEN se reenvía una solicitud ya evaluada THE SYSTEM SHALL conservar el estado y el motivo previos sin reevaluar, y rechazar un UUID de solicitud duplicado mediante la clave primaria. Un borrador podrá tener varios intentos históricos, pero sólo una solicitud PENDIENTE simultánea. **Pruebas:** C6 y segundo envío tras C2.

**REQ-04.** WHEN se descarga o recarga el catálogo THE SYSTEM SHALL importar una instantánea fechada de PostgreSQL, conservar las bajas como lápidas y ocultarlas del catálogo disponible, sin cambiar stock, pedidos o ventas del servidor durante la simulación. SIMULADO_APROBADO se deberá identificar siempre como simulación y nunca como venta. **Pruebas:** C4, C5, C6, comparación de pedidos y stock antes/después y huellas de conservación de `foodstore`.

## design.md propuesto

- PostgreSQL de pruebas: copia nueva con fixture explícito. Vista `v_snapshot_movil` con producto_id, nombre, precio_centavos, stock, disponible, eliminado y capturado_en. Exportación CSV real con `psql \copy`, booleanos `t`/`f`. La fecha proviene del servidor.
- SQLite 3.37+: `producto_cache`, `pedido_borrador`, `item_borrador` y `cola_sync`, todas STRICT, más tabla de importación `snapshot_servidor`. El esquema empieza con `PRAGMA foreign_keys = ON;`; cada conexión vuelve a activarlo y lo verifica.
- `producto_cache`: producto_id conservado, nombre, precio_centavos INTEGER no negativo, stock_visto no negativo, disponible_visto y eliminado en 0/1, capturado_en. La recarga actualiza e inserta sin borrar productos referenciados por borradores. Una baja lógica permanece como fila y desaparece de `v_catalogo_disponible`.
- `pedido_borrador`: UUID local TEXT PRIMARY KEY, usuario_id_servidor numérico de prueba, forma_pago con CHECK EFECTIVO/TARJETA/TRANSFERENCIA y creado_en ISO 8601. No contiene nombre, contacto, credenciales ni detalles de tarjeta.
- `item_borrador`: PK compuesta id_local/producto_id, ambas FK, cantidad positiva, precio_centavos_visto no negativo.
- `cola_sync`: solicitud_uuid TEXT PRIMARY KEY, FK id_local, estado PENDIENTE/CONFLICTO/RECHAZADO/SIMULADO_APROBADO, motivo y fecha. Índice único parcial por id_local únicamente WHERE estado='PENDIENTE'; no UNIQUE global sobre id_local.
- Semáforo SQL: agrupar por cada solicitud pendiente, LEFT JOIN a la instantánea, detectar inexistentes y reglas rojas antes de precios, registrar motivo comprensible. Proteger adicionalmente contra aprobar un borrador vacío. Se ejecuta dentro de una transacción local y no contiene una conexión ni una escritura a PostgreSQL.
- Las modificaciones preparatorias de C2 (precio) y C4 (baja) las realiza explícitamente el operador en la copia. C3 pide más stock del existente sin descontarlo. Se comparan cantidad de pedidos y stock después de preparar el fixture y al final, y huellas de la fuente oficial antes/después.
- C6 demuestra dos controles diferentes: la PK rechaza un INSERT duplicado y el filtro PENDIENTE impide reevaluar. En producción, la protección definitiva iría en PostgreSQL: UUID único y creación de venta en la misma transacción; no se implementa esa venta en este TP.
- Herramientas reproducibles: SQL y Python estándar (`sqlite3`, `subprocess`, `csv`, `json`, `hashlib`); PostgreSQL por CLI y credenciales externas. Ningún secreto se incluye en el ZIP ni en los prompts de IA.

## tasks.md propuesto

1. Conservar estas tres especificaciones de Kiro antes de generar código y registrar hashes/fechas y el origen de cada intervención de IA.
2. Usar OpenCode Build para generar `movil/schema_sqlite.sql`, `movil/pruebas_sqlite.sql`, `movil/semaforo.sql`, los scripts PostgreSQL de fixture/vista/verificación y un ejecutor reproducible, a partir de estos requisitos y tareas. Leer el código antes de ejecutarlo.
3. Respaldar y crear la copia nueva de PostgreSQL sin sustituir `foodstore`; verificar versión, esquema real y conservación. Preparar fixture inventado y exportar CSV inicial.
4. Crear SQLite desde cero. Verificar STRICT, foreign_keys=1, tablas, índices y FK. Importar CSV, normalizar t/f a 1/0 y conservar fecha del servidor.
5. Ejecutar transacción COMMIT, ROLLBACK, catálogo sin servidor C1 y rechazos C7; guardar resultados reales.
6. Ejecutar C2 con precio cambiado y aceptación; C3 sin stock suficiente; C4 con baja y lápida; C5 sin cambios; C6 UUID repetido y segunda simulación sin cambios. Agregar precedencia rojo/amarillo y borrador vacío como controles de borde.
7. Capturar comandos y salidas legibles, estados/motivos, fecha y CSV de cada instantánea. Probar que el semáforo no cambió pedidos/stock ni la fuente `foodstore`.
8. Congelar el trabajo en una rama `review-final`. Solicitar review OpenCode Plan de los scripts de todas las unidades por partes, usando una copia saneada de fuentes sin datos personales ni secretos. Registrar cada hallazgo y decidir aceptado/corregido/descartado, con al menos tres desarrollados de dos unidades y uno descartado con prueba.
9. Corregir en commits separados y reproducir desde una base SQLite vacía. Comparar la evidencia de esta segunda ejecución.
10. Armar el mapa PostgreSQL/MongoDB/SQLite, extensión del plan U6 (backups/restauración, resincronización tras rollback del servidor, revisión periódica de conflictos), bitácora de IA con al menos tres entradas, DUIA de la cátedra y README ordenado.
11. Generar informe de máximo seis páginas y ZIP con estructura `food-store/`, base SQLite y archivos requeridos. Renderizar y revisar cada página, verificar ZIP y ausencia de datos personales/secretos. Preparar un guion de defensa de diez minutos, dejando claro que el ensayo en clase debe realizarlo el equipo y no se simula su realización.

## Evidencia y límites que no deben inventarse

- Registrar las herramientas Kiro/OpenCode que efectivamente se usaron y las fechas reales; esta propuesta sola no prueba su uso.
- Las pruebas sólo cuentan si se ejecutan en los motores y sus salidas se conservan.
- No atribuir a revisión humana del equipo las verificaciones hechas por Codex; pedir validación sobre un resultado concreto cuando corresponda.
- No afirmar que el ensayo en clase ocurrió ni que una venta se confirmó.

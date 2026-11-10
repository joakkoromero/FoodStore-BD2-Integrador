# Consulta de IA y contraste - Unidad 7

Herramienta: Codex, subagente `comparacion_ia`. Consulta realizada el 10/11/2026.
La respuesta siguiente se conserva fielmente. Es asistencia de IA y fue contrastada
con el laboratorio ejecutado y las fuentes oficiales citadas en el informe.
No se enviaron filas, datos personales, contraseñas ni archivos privados.

## Prompt exacto

Food Store está implementado en PostgreSQL: pedido(id,usuario_id,fecha timestamptz,estado,total numeric), detalle_pedido(pedido_id,producto_id,cantidad,precio_unitario numeric,subtotal generado), usuario y producto. Las claves foráneas, restricciones y triggers mantienen cantidades, precios históricos y total coherentes. Se accede frecuentemente a un pedido completo con sus líneas y datos esenciales del cliente. Compará mantener PostgreSQL frente a representar pedidos como documentos MongoDB con líneas embebidas: almacenamiento, consultas por estado y producto, y conservación de coherencia. Formulá dos afirmaciones concretas comprobables y una recomendación acotada; evitá suponer benchmarks o que MongoDB carece de transacciones.

## Respuesta exacta

1. **Un pedido con sus líneas embebidas puede recuperarse de MongoDB como un solo documento, sin unir colecciones.** El documento puede conservar `_id` igual al identificador original, fecha, estado, cliente y un arreglo de líneas con producto, cantidad y precio histórico. Las búsquedas por estado y por `lineas.producto_id` se expresan como filtros; pueden apoyarse en un índice de estado y otro multikey sobre el arreglo. PostgreSQL obtiene información equivalente mediante consultas entre `pedido`, `detalle_pedido` y las tablas relacionadas. Esto describe una diferencia de estructura y acceso; no demuestra que un motor sea más rápido.

2. **MongoDB ofrece atomicidad al modificar un documento, pero embeber líneas no garantiza por sí mismo la coherencia matemática del pedido.** Una actualización puede cambiar conjuntamente líneas y total, aunque deben implementarse validaciones o lógica que aseguren cantidades válidas, precios históricos y total correcto. MongoDB también admite transacciones entre documentos. En PostgreSQL, las claves foráneas, restricciones, subtotal generado y triggers existentes ya protegen estas reglas. Para la migración deben conservarse identificadores y fechas, y utilizar tipos decimales para importes, evitando conversiones a punto flotante. Los datos del cliente embebidos constituyen una copia: debe definirse si representan el momento de la migración o si requieren sincronización posterior.

**Recomendación.** Mantener PostgreSQL como fuente principal de Food Store, porque las reglas de integridad ya están implementadas y los pedidos se relacionan con clientes y productos. MongoDB puede evaluarse como proyección de lectura para pedidos completos si existe una necesidad concreta y se define cómo sincronizar cambios. La equivalencia de resultados en una muestra valida la migración y las consultas, pero no alcanza para justificar una mejora de rendimiento ni una sustitución del sistema actual.

## Contraste y decisiones

- Afirmación 1 aceptada con alcance estructural: la consulta a devuelve los cinco
  documentos completos de una colección. MongoDB documenta el acceso conjunto
  mediante embebidos. No se hizo un benchmark ni se atribuye una ventaja temporal.
- Afirmación 2 aceptada: la documentación distingue atomicidad de una escritura
  documental y transacciones multidocumento. El laboratorio agregó validadores
  explícitos y rechazó total incoherente y cantidad cero (código 121). La atomicidad
  por sí sola no expresa estas reglas de negocio.
- La descripción de cliente se aplica como copia al momento de exportación;
  sólo se conserva usuario_id y un alias nuevo de presentación. No se sincroniza
  automáticamente ni se modifica PostgreSQL.

Fuentes oficiales:
- https://www.mongodb.com/docs/manual/data-modeling/embedding/
- https://www.mongodb.com/docs/manual/core/write-operations-atomicity/
- https://www.mongodb.com/docs/manual/core/schema-validation/
- https://www.mongodb.com/docs/manual/core/indexes/index-types/index-multikey/
- https://www.postgresql.org/docs/17/ddl-constraints.html

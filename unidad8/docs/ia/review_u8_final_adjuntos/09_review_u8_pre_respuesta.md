**Cobertura**
Revisión estática de las **seis fuentes completas**, usando exclusivamente el contenido adjunto, sin herramientas, comandos, modificaciones ni ejecución.

| Fuente | Alcance revisado |
|---|---|
| `schema_sqlite.sql` | Líneas 1–87: cuatro tablas `STRICT`, auxiliar `snapshot_servidor`, restricciones, claves foráneas, índice parcial y vista local. |
| `pruebas_sqlite.sql` | Líneas 1–128: consulta local, persistencia con `COMMIT`, reversión explícita y errores esperados CHECK/FK. |
| `semaforo.sql` | Líneas 1–86: evaluación local, agregación por borrador, prioridad de estados y actualización exclusiva de pendientes. |
| `10_fixture_y_snapshot.sql` | Líneas 1–99: guardas, cuatro productos ficticios, vista de exportación y verificaciones transaccionales. |
| `20_validar_no_ventas.sql` | Líneas 1–106: transacción de lectura, conteos, vectores y huellas. |
| `tools/reproducir.py` | **Líneas originales 1–1039**, integrando ambas partes como un único programa: parte 1, líneas 1–520; parte 2, líneas 521–1039. Revisados preparación, subprocessos, respaldo, importación, casos, verificaciones y manejo de fallos. |

No identifico adjuntos faltantes ni truncamiento en el contenido presentado. Las referencias al runner que siguen corresponden a sus **líneas originales**, no a las líneas de los Markdown contenedores. El SHA256 declarado no fue recalculado.

**Observaciones**
No encuentro un bug funcional demostrado en la lógica SQL del semáforo bajo las condiciones del laboratorio. Sí hay un riesgo de privacidad en un entorno admitido y dos oportunidades concretas para mejorar la fidelidad de las evidencias. Las observaciones sobre ACL e historial sintético contrastan notas previas de Codex; no son descubrimientos independientes.

| ID | Severidad / Tipo | Archivo y Líneas Originales | Evidencia Concreta | Condición | Propuesta Comprobable |
|---|---|---|---|---|---|
| **U8-01** | **Alta si queda accesible a terceros. Riesgo condicional de privacidad.** | `tools/reproducir.py:306–307, 368, 403–408, 595–609` | Se admite Python 3.12+, se crea el directorio con `mkdir(mode=0o700)` y luego se guardan diagnósticos y un dump completo de la copia anterior al fixture. En Windows con Python 3.12, ese modo no establece por sí solo una ACL privada. Estar fuera del proyecto tampoco garantiza confidencialidad. | Ejecución en Windows con una combinación de versión y ACL heredada que permita acceso a otros usuarios. No demuestra una exposición ya ocurrida. Tampoco corresponde generalizarlo a todas las versiones: Python 3.13 añadió tratamiento de `0o700` en Windows. | Proteger o verificar la ACL **inmediatamente después de crear el directorio y antes del primer diagnóstico o dump**; abortar si no se puede garantizar la restricción requerida. Probar posteriormente con Python 3.12 en Windows y un directorio padre con permisos heredables amplios, verificando que otro usuario no pueda leer los archivos generados. |
| **U8-02** | **Media. Mejora de exactitud de las evidencias, no escritura de ventas detectada.** | `20_validar_no_ventas.sql:63`; `tools/reproducir.py:971–977, 997–1002` | La comprobación de `pedido` en la copia compara solamente `count(*)`, pero el resultado declara `pedidos_copia_identicos=True`. Igual cardinalidad no prueba identidad de las filas ni conservación de `detalle_pedido`. Por inspección, el código entregado no escribe en esas tablas, pero la comprobación dinámica es más acotada que su etiqueta. | Importa si se presenta esa salida como demostración de identidad completa, o si una modificación posterior o una escritura externa altera filas sin cambiar el conteo. | Para el alcance mínimo, renombrar la evidencia a `conteo_pedidos_copia_identico`. Si se quiere conservar la afirmación de identidad, comparar huellas antes/después de `pedido` y `detalle_pedido` en la copia, reutilizando el patrón existente. Probar con una modificación controlada que conserve el número de filas: la evidencia no debe afirmar identidad sin detectarla. |
| **U8-03** | **Baja. Mejora de representatividad.** | `tools/reproducir.py:790–803, 834–850` | C2 ya conserva dos solicitudes con UUID distintos y verifica que el conflicto anterior permanezca intacto. Después, C6 inserta directamente otro estado `CONFLICTO`, sin evaluación del semáforo, para demostrar que el índice no impone unicidad global por borrador. Está explícitamente rotulado como sintético, por lo que no hay engaño ni fallo funcional. | Sólo afecta la claridad del historial final entregado como evidencia; el caso sintético es legal según el esquema. | Omitir esa inserción del historial final y conservar C2 como demostración de solicitudes históricas múltiples. Si se desea probar específicamente dos filas `CONFLICTO`, hacerlo en una copia efímera. Verificar luego que C2 conserve ambos UUID y que el segundo pendiente simultáneo siga fallando por el índice parcial. |

**Contraste De `createdb`**
La llamada está en `tools/reproducir.py:588–592` y utiliza `--maintenance-db foodstore --template foodstore`.

- **No la clasifico como bug actual demostrado.** La conexión del propio backend que ejecuta `CREATE DATABASE` no equivale, por sí sola, a otra sesión bloqueante sobre el template.
- Sí existe el requisito operativo habitual de que no haya **otras conexiones** al origen durante la copia. El runner aborta si `createdb` falla; no elimina ni reemplaza una base existente.
- Usar `postgres` como base de mantenimiento es una simplificación razonable para evitar esa conexión propia al origen, siempre que esté disponible y autorizada. **No elimina** los bloqueos provocados por otras sesiones conectadas a `foodstore`.
- La prueba posterior adecuada es contrastar ambos destinos de mantenimiento con el origen sin otras sesiones y, separadamente, con otra sesión abierta. No corresponde anticipar resultados de esa ejecución.

**Controles A Conservar**
- **Separación del origen:** las operaciones dirigidas a `foodstore` son lecturas, cálculo de huellas y uso como template. Fixture y cambios administrativos apuntan a la copia exacta autorizada, con guardas SQL adicionales.
- **Preparación transaccional:** fixture y vista se crean dentro de una transacción. Los nombres preexistentes y una vista existente provocan aborto, sin reemplazo deliberado.
- **Modelo real del producto:** `disponible` se deriva de `stock > 0`; no se presupone una columna homónima en `producto`. La baja exportada combina `p.eliminado OR c.eliminado`.
- **Dinero:** la conversión PostgreSQL usa `NUMERIC` y `bigint`, sin paso por `float`; el importador valida el rango INTEGER64.
- **C7 y atomicidad:** el ejecutor procesa sentencias individualmente en la misma conexión, comprueba los códigos extendidos CHECK/FK y exige una transacción abierta tras el error. El `ROLLBACK` posterior revierte también el encabezado insertado previamente. Las consultas comprueban ausencia de residuos.
- **CSV y fecha:** se validan cabecera, columnas, números, duplicados, los cuatro nombres, booleanos `t/f` y fecha con zona. Se conserva `capturado_en` del servidor; la hora local sólo registra diagnóstico.
- **Importación atómica:** reemplazo del snapshot auxiliar y UPSERT de caché comparten transacción. No se borran filas de caché referenciadas. En este fixture completo, la baja queda como lápida y desaparece del catálogo visible.
- **Semáforo local:** usa `LEFT JOIN` al snapshot; rechaza ausentes, bajas, stock insuficiente, indisponibles y borradores vacíos. Rojo prevalece sobre precio, tanto dentro de un ítem como entre ítems del mismo borrador.
- **Reintentos e idempotencia:** la PK protege el UUID textual; el índice parcial limita solamente los pendientes por borrador. Tras conflicto se permite otro UUID. El semáforo sólo actualiza `PENDIENTE` y la prueba compara estados, motivos y timestamps históricos.
- **C1–C7 y bordes:** están contemplados consulta local, commit/rollback, precio, cantidad superior al stock, baja, aprobación simulada, UUID duplicado, restricciones e índices; también vacío, mezcla rojo/amarillo, ausente, indisponible y stock cero.
- **Sin venta ni descuento:** ni el semáforo ni el runner contienen escrituras de venta o descuentos de stock. Las únicas actualizaciones administrativas PostgreSQL previstas son precio C2 y baja C4. `SIMULADO_APROBADO` se identifica expresamente como simulación.
- **Respaldo y reproducción:** el dump precede al fixture; se rechazan destinos y salidas preexistentes, se registran versiones y hashes, y los fallos conservan salidas parciales sin borrar bases.

**Límites**
Esta revisión establece lo que permite concluir el texto, **no resultados de ejecución**. Quedan pendientes la compatibilidad con el esquema PostgreSQL efectivo, permisos, ACL, disponibilidad del origen para copiarlo, autenticación, ejecución de C1–C7 y comprobación de los artefactos resultantes.

Las huellas del origen comparan estados antes/después de cinco tablas; no constituyen una auditoría de todo el clúster ni excluyen cambios transitorios o concurrencia externa. El respaldo se comprueba por existencia, tamaño y hash, pero **no se ensaya su restauración**.

No se verificaron las versiones instaladas ni el hash declarado del runner. No se emite aprobación en nombre del equipo humano.

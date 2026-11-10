Voy a revisar los siete archivos del adjunto sin ejecutar herramientas ni SQL, separando los defectos deducibles del código de las hipótesis que necesitan pruebas en una copia aislada.


## Resultado
Se revisaron estáticamente los **siete archivos** del adjunto. Se identifican **dos defectos de integridad demostrables por lectura** y **dos riesgos que requieren comprobación o definición funcional**. No ejecuté herramientas, SQL ni pruebas, y no modifiqué archivos.

El alcance es exclusivamente el **TP5 histórico**. No hay fuentes suficientes para atribuir estos hallazgos al acumulado U4–U7. Los placeholders no se consideran errores.

**Referencias:** las líneas aproximadas se reconstruyeron para cada archivo, descontando los dos comentarios agregados por el saneamiento. No son las líneas globales del bundle. Todos los archivos pertenecen a `work\antecedentes\TP5\Arancibia_Romero_TP5\`.

## Defectos Demostrables

### H1. Un pedido confirmado o entregado puede quedar sin detalles
**Severidad:** alta, por integridad.  
**Archivo:** `schema.sql`, líneas 75–116, especialmente 105–116.  
**Certeza estática:** alta.  
**Alcance:** histórico; acumulado no determinable.

Fragmentos relevantes:

```sql
AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido
...
BEFORE INSERT OR UPDATE OF estado ON pedido
```

`validar_confirmacion_pedido()` comprueba la existencia de detalles al insertar el pedido o actualizar explícitamente `estado`. No controla la eliminación o el traslado de sus líneas.

**Escenario:** el pedido 5 del seed tiene una sola línea y queda `CONFIRMADO`. Si se elimina esa línea, `recalcular_total_pedido()` actualiza únicamente `total`, por lo que no dispara el trigger definido como `UPDATE OF estado`. El resultado es un pedido confirmado, vacío y con total cero. También puede ocurrir al cambiar el `pedido_id` de la última línea.

Esto contradice incluso la regla más acotada implementada por el código: los pedidos confirmados o entregados deben tener detalle. No depende de interpretar si un pedido cancelado puede estar vacío.

**Prueba mínima propuesta:** en una transacción de una copia aislada con el seed, eliminar el detalle del pedido 5 y consultar su estado, total y cantidad de líneas. Se espera que el código permita `CONFIRMADO / 0 / 0`. Finalizar con `ROLLBACK`.

### H2. El total almacenado puede modificarse sin modificar sus líneas
**Severidad:** media; depende de quién tenga autorización para escribir pedidos.  
**Archivo:** `schema.sql`, líneas 48–59 y 75–99.  
**Certeza estática:** alta respecto de la ausencia de protección.  
**Alcance:** histórico; acumulado no determinable.

Fragmentos:

```sql
total NUMERIC(14,2) NOT NULL DEFAULT 0
...
CONSTRAINT ck_pedido_total CHECK (total >= 0)
```

La función que mantiene el total se ejecuta por cambios en `detalle_pedido`, pero no existe una validación equivalente para una escritura directa de `pedido.total`.

**Escenario:** un actor con permiso efectivo para actualizar esa columna puede asignar un importe no negativo distinto de la suma de los subtotales. También puede insertar un pedido pendiente vacío con total positivo. La restricción `CHECK` acepta ambas inconsistencias.

No hace falta desactivar triggers ni tener privilegios de superusuario. **Sí hace falta autorización de escritura**; el bundle no contiene roles, `GRANT` ni código de aplicación que permitan afirmar que un usuario final pueda hacerlo. Es una brecha de integridad del esquema, no evidencia de explotación externa.

La actualización manual de totales en `carga_masiva.sql` es deliberada y coherente con su procedimiento de carga; no constituye por sí misma el defecto.

**Prueba mínima propuesta:** dentro de una transacción aislada, actualizar el total de un pedido existente a un importe positivo diferente de su suma de detalles. Comparar ambos valores y revertir. Con el esquema mostrado, la escritura no tiene una validación que la rechace.

## Hipótesis Para Comprobar

### H3. Escrituras concurrentes pueden dejar un total calculado con una suma incompleta
**Severidad:** alta si se confirma.  
**Archivo:** `schema.sql`, líneas 80–91.  
**Certeza estática:** media sobre la anomalía concreta; alta sobre la ausencia de serialización previa explícita.  
**Alcance:** histórico; acumulado no determinable.

Fragmento:

```sql
UPDATE pedido
SET total = COALESCE((
    SELECT SUM(subtotal)
    FROM detalle_pedido
    WHERE pedido_id = v_pedido
), 0)
WHERE id = v_pedido;
```

**Mecanismo esperado:** en `READ COMMITTED`, dos transacciones pueden agregar productos distintos al mismo pedido. Cada una ve sus cambios, pero no los cambios todavía no confirmados de la otra.

El bloqueo de la fila de `pedido` serializa las escrituras del total, pero no demuestra que la suma utilizada por la segunda escritura se recalcule con una instantánea posterior a la espera. Una suma calculada antes de esa espera puede terminar sobrescribiendo el total con un valor incompleto.

La confirmación debe verificar el comportamiento efectivo de PostgreSQL 17; no presento este escenario como una reproducción realizada.

**Prueba mínima propuesta:**
1. Preparar un pedido pendiente y dos productos que todavía no figuren en sus detalles.
2. En sesión A, iniciar una transacción, insertar una línea y mantenerla abierta.
3. En sesión B, iniciar otra transacción e insertar otra línea del mismo pedido; verificar que espera al actualizar el padre.
4. Confirmar A y luego B.
5. Desde una nueva consulta, comparar `pedido.total` con `SUM(detalle_pedido.subtotal)`.

Conviene usar importes distintos para identificar qué contribución falta. Si el total queda correcto, registrar el intercalado y refutar ese escenario concreto antes de generalizar.

### H4. La facturación mensual depende de la zona horaria de creación o refresh
**Severidad:** media si el reporte debe representar meses del negocio.  
**Archivo:** `views.sql`, líneas 48–60, especialmente 51 y 60.  
**Certeza estática:** alta sobre la dependencia de `TimeZone`; media sobre su impacto funcional.  
**Alcance:** histórico; acumulado no determinable.

Fragmento:

```sql
date_trunc('month', p.fecha) AS mes
```

`p.fecha` es `TIMESTAMPTZ`. Esta forma de `date_trunc` utiliza la zona horaria de la sesión. Por tanto, crear o refrescar la materializada desde sesiones con distintas zonas puede producir claves temporales diferentes y cambiar la asignación mensual de pedidos próximos al límite de mes.

Q1 usa explícitamente `America/Argentina/Buenos_Aires`, lo que aporta contexto, pero **no prueba por sí solo** que la materializada deba usar esa misma definición de mes.

**Escenario:** un pedido fechado el 1 de marzo a las 01:00 UTC corresponde todavía a febrero en Buenos Aires. Puede contribuir a meses diferentes según la sesión que ejecute el refresh.

**Prueba mínima propuesta:** en una copia aislada, asignar esa fecha a un pedido existente incluido en el reporte. Refrescar y registrar resultados con `TimeZone` de sesión en UTC; repetir con Buenos Aires. Comparar las claves normalizadas a una misma zona y los importes por mes. No es necesario modificar configuración global.

## Rendimiento Y Mejoras Opcionales

- **Cobertura de índices:** `indices.sql`, líneas 8–11 y 22–24, frente a `queries.sql`, líneas 5–11 y 20–23. Q1 proyecta `fecha`, pero su índice incluye la expresión local, `id`, `usuario_id` y `total`, no la columna `fecha`. Q3 proyecta `subtotal`, ausente del índice complementario. Por tanto, no corresponde describirlos como plenamente cubrientes para esas consultas ni dar por asegurado un `Index Only Scan`. No afecta la correctitud y no justifica ampliar índices sin medir tamaño, lecturas y costo de escritura.
- **Semántica de facturación:** `views.sql`, línea 59, incluye pedidos pendientes mediante `estado <> 'CANCELADO'`. Puede ser una decisión válida. Antes de tratarlo como defecto, debe definirse si “facturación” representa pedidos no cancelados, confirmados o entregados.
- **Detención ante errores:** `schema.sql` y `data.sql` no incluyen `\set ON_ERROR_STOP on`, a diferencia de los otros scripts operativos. Sus transacciones evitan persistencia parcial ante errores SQL ordinarios, pero un invocador de `psql` sin esa opción puede continuar y no comunicar el fallo como espera la automatización. Es una mejora de reproducción condicionada al comando de ejecución, no un fallo probado del proceso completo.

## Observaciones De Alcance

- El `ROLLBACK` de `benchmark_escrituras.sql` es deliberado. En el camino exitoso revierte tanto las inserciones como la desactivación transaccional de triggers. No se identifica allí una pérdida persistente de integridad.
- Ese benchmark aísla expresamente escritura e índices **sin triggers de negocio**. Sus resultados no representarían el costo completo de una operación ordinaria con esos triggers activos. Tampoco `LIMIT 3000` garantiza 3000 inserciones si faltan candidatos.
- La carga presupone un esquema recién reconstruido y el seed indicado. Bajo esa condición, sus cantidades son coherentes: 199.995 pedidos nuevos y 399.990 detalles nuevos, más los siete originales.
- El seed pasa directamente de pendiente a entregado. El esquema histórico no implementa una máquina de transiciones que lo prohíba; no corresponde importar esa prohibición desde otra entrega.
- `v_pedidos_usuario` omite la contraseña, pero expone contacto de los usuarios incluidos. Sin permisos, roles ni política de acceso no puede afirmarse una exposición no autorizada ni aislamiento por usuario.
- No se observa un impedimento estructural para el índice único de la materializada requerido por futuros `REFRESH ... CONCURRENTLY`. Su existencia no implica que los refresh actuales sean concurrentes.

## Cobertura

| Archivo | Revisado | Resultado |
|---|---|---|
| `benchmark_escrituras.sql` | Sí | Sin defecto concreto detectado; límites de interpretación de la medición señalados. |
| `carga_masiva.sql` | Sí | Sin defecto concreto bajo el supuesto declarado de reconstrucción y seed inicial. |
| `data.sql` | Sí | Sin defecto concreto detectado; observación sobre control de errores del invocador. |
| `indices.sql` | Sí | Cobertura incompleta de algunas proyecciones; mejora opcional sujeta a medición. |
| `queries.sql` | Sí | Sin error concreto detectado; revisada su correspondencia con los índices. |
| `schema.sql` | Sí | H1 y H2 demostrables; H3 requiere prueba concurrente. |
| `views.sql` | Sí | H4 requiere validar contrato temporal; semántica de facturación y permisos no especificados. |

## Pruebas Prioritarias U8

1. **H1:** eliminar o trasladar la última línea de un pedido confirmado y comprobar si queda vacío conservando el estado.
2. **H3:** ejecutar el intercalado de dos sesiones sobre líneas distintas del mismo pedido y contrastar total contra suma.
3. **H2:** comprobar la escritura directa de un total inconsistente con el rol real de la aplicación, además del propietario del laboratorio.
4. **H4:** comparar refresh en UTC y Buenos Aires con un pedido próximo al cambio de mes.
5. **Reproducción y rendimiento:** reconstruir únicamente la copia aislada con los originales locales, verificar cantidades y totales, y luego registrar planes de Q1–Q3 antes y después de los índices y el número real de filas del benchmark. No dar por anticipados tiempos, planes ni mejoras.

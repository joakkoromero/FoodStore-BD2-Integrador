Revisaré los dos archivos del adjunto sin usar herramientas ni ejecutar SQL. Separaré los defectos verificables por lectura de los riesgos que necesitan pruebas, con referencias a las líneas reconstruidas de cada archivo.


## Alcance y Referencias
Revisión estática de **los dos archivos completos**, únicamente sobre el adjunto aprobado. No ejecuté herramientas, SQL ni pruebas, ni modifiqué archivos.

Las referencias siguientes reconstruyen las **líneas originales del SQL**, excluyendo los encabezados del bundle y los dos comentarios añadidos por la sanitización. Por ejemplo, `BEGIN;` corresponde a `data.sql:2` y `schema.sql:3`. Son referencias aproximadas, no verificadas contra los originales.

Se identifican **dos defectos demostrables por lectura** y **un riesgo de concurrencia que requiere confirmación experimental**. Todos corresponden al **TP1 histórico**; no hay fuentes suficientes para atribuirlos a la versión acumulada U4–U7.

## Defectos Demostrables

### H1. Un Pedido Confirmado o Entregado Puede Quedar Sin Detalles
**Severidad:** alta.  
**Ubicación:** `work\antecedentes\TP1\schema.sql:100–115`; relacionado con `:75–98`.  
**Certeza estática:** alta.  
**Afectación:** histórico TP1; acumulado indeterminado.

Fragmentos relevantes:

```sql
IF NEW.estado IN ('CONFIRMADO', 'ENTREGADO')
   AND NOT EXISTS (...)
```

```sql
BEFORE INSERT OR UPDATE OF estado ON pedido
```

**Mecanismo y escenario:** la comprobación de existencia de detalles solo se ejecuta al insertar un pedido o actualizar su estado. Después de confirmarlo, se puede borrar su último detalle. El trigger de `detalle_pedido` recalcula `total` a cero, pero no vuelve a comprobar la regla de confirmación. También se puede trasladar el último detalle a otro pedido mediante `UPDATE pedido_id`.

Esto contradice, como mínimo, la regla implementada para `CONFIRMADO` y `ENTREGADO`: ambos estados pueden terminar sin líneas.

El comentario “Un pedido puede estar vacío solo mientras permanece PENDIENTE” es además más estricto que el código respecto de `CANCELADO`. No considero esa diferencia otro defecto: falta una definición funcional que aclare si un cancelado debe conservar detalles.

**Prueba mínima propuesta:** en una copia aislada, crear un pedido con una sola línea, confirmarlo y borrar esa línea. Consultar estado, total y cantidad de detalles. El fallo queda confirmado si el pedido conserva `CONFIRMADO`, tiene total cero y ninguna línea. Revertir la prueba.

### H2. El Total Puede Escribirse Sin Coincidir Con Los Detalles
**Severidad:** media.  
**Ubicación:** `work\antecedentes\TP1\schema.sql:54–57, 74–98`.  
**Certeza estática:** alta respecto del esquema; accesibilidad desde la aplicación desconocida.  
**Afectación:** histórico TP1; acumulado indeterminado.

Fragmentos relevantes:

```sql
total NUMERIC(14,2) NOT NULL DEFAULT 0
```

```sql
CONSTRAINT ck_pedido_total CHECK (total >= 0)
```

**Mecanismo y escenario:** el total almacenado solo se recalcula cuando cambia `detalle_pedido`. Una escritura directa sobre `pedido.total` puede dejar un importe positivo que no coincida con la suma de sus líneas; también puede insertarse un pedido pendiente vacío con un total positivo. Ninguna restricción incluida lo impide.

Por ejemplo, modificar únicamente `total` no dispara el trigger de validación de estado ni el de recálculo de detalles. La discrepancia persiste hasta una modificación posterior de las líneas, si ocurre.

**Condiciones de permisos:** requiere un rol con permiso de insertar ese campo o actualizar `pedido.total`, o ejecutar como propietario. El bundle no contiene roles ni concesiones. Por tanto, esto demuestra una **brecha de integridad del esquema**, no una explotación remota ni una vulnerabilidad comprobada de la aplicación.

**Prueba mínima propuesta:** con el rol previsto para operar la aplicación en el laboratorio, intentar cambiar el total de un pedido con detalles a un valor positivo diferente de su suma. Comprobar permisos y comparar ambos importes. Si el rol no puede escribir ese campo, queda mitigada esa vía para ese rol, aunque la restricción no está expresada en el esquema.

## Hipótesis Que Requiere Ejecución

### H3. Dos Cambios Concurrentes Pueden Dejar Un Total Desactualizado
**Severidad:** alta si se confirma en las condiciones de operación.  
**Ubicación:** `work\antecedentes\TP1\schema.sql:75–98`, especialmente `:80–84`.  
**Certeza estática:** media para el resultado concurrente; alta respecto de la ausencia de sincronización explícita previa a la suma.  
**Afectación:** histórico TP1; acumulado indeterminado.

Fragmento relevante:

```sql
UPDATE pedido
   SET total = COALESCE((SELECT SUM(subtotal)
                          FROM detalle_pedido
                         WHERE pedido_id = v_pedido), 0)
 WHERE id = v_pedido;
```

**Mecanismo y escenario:** el trigger vuelve a calcular la suma consultando las líneas visibles para su sentencia. No bloquea previamente el pedido antes de obtener esa suma.

En el aislamiento habitual `READ COMMITTED`, dos sesiones pueden modificar **líneas diferentes del mismo pedido**. La segunda puede calcular la suma sin ver el cambio aún no confirmado de la primera y luego esperar por la fila de `pedido`. El bloqueo de esa fila serializa las escrituras, pero no debe suponerse que por sí solo garantiza una suma actualizada tras la espera.

El riesgo es que ambas modificaciones de detalles queden confirmadas, mientras `pedido.total` refleje solo una de ellas. Debe verificarse en PostgreSQL 17, observando la evaluación de la subconsulta y el comportamiento tras el bloqueo; no afirmo haber reproducido ese intercalado.

**Prueba mínima propuesta:**

1. Preparar un pedido con dos productos distintos y total consistente.
2. En sesión A, abrir una transacción y aumentar la cantidad de la primera línea, sin confirmar.
3. En sesión B, bajo `READ COMMITTED`, aumentar la segunda línea. Observar si queda esperando al actualizar el padre.
4. Confirmar A; dejar terminar B y confirmar B.
5. Comparar `pedido.total` con `SUM(detalle_pedido.subtotal)` desde una nueva sentencia.

Una diferencia confirma el fallo para ese intercalado. La igualdad en una sola corrida no descarta todos los intercalados; conviene repetir con coordinación de sesiones y registrar el aislamiento efectivo.

## Mejoras Opcionales y Límites

- **Índice para la referencia a producto:** la PK de `detalle_pedido` es `(pedido_id, producto_id)` (`schema.sql:69`). No ofrece necesariamente una búsqueda eficiente por `producto_id` solo. Un índice por esa columna podría ayudar a consultas por producto y a las comprobaciones de borrado o actualización de productos referenciados. Es una oportunidad de medición, no un problema de rendimiento demostrado: faltan volumen, consultas y planes.
- **Precondición de la carga:** `data.sql:7–25` usa identificadores explícitos como referencias, pero deja que las identidades generen los identificadores de las entidades. Es coherente con ejecutar primero este `schema.sql`, que recrea las tablas. No es una carga genérica ni idempotente para una base preexistente; eso no constituye por sí solo un defecto del ejercicio.
- **Reconstrucción destructiva:** `schema.sql:5–6` incluye `DROP ... CASCADE`. Es una decisión explícita de reconstrucción, no un hallazgo independiente. Solo corresponde ensayarla en una copia desechable, nunca en la base principal.
- **Contraseñas y permisos:** los placeholders impiden determinar si las contraseñas originales eran hashes o texto claro. Tampoco se incluyen roles, permisos ni código consumidor. No hay evidencia para afirmar almacenamiento inseguro, inyección SQL o explotación mediante privilegios.
- **Reglas no documentadas:** no atribuyo errores por ausencia de descuento de stock, restricciones sobre registros con `eliminado = TRUE` o transiciones adicionales de estado. El bundle no establece esas obligaciones.

## Cobertura

| Archivo | Estado | Resultado |
|---|---|---|
| `work\antecedentes\TP1\data.sql` | Revisado completo | Sin defecto concreto detectado bajo la precondición de esquema recién reconstruido. Los totales esperados, 2800, 1500, 3150, 6200 y 1050, coinciden aritméticamente con las líneas. No se ejecutó la carga. |
| `work\antecedentes\TP1\schema.sql` | Revisado completo | H1 y H2 demostrables por lectura; H3 pendiente de prueba concurrente. Revisados tablas, identidades, FK, restricciones, subtotal generado, funciones, triggers, índices y transacción de reconstrucción. |

## Pruebas Priorizadas Para U8
Todas sobre **originales locales en una copia aislada**, no sobre los adjuntos saneados.

1. **H1:** borrar o trasladar el último detalle de un pedido confirmado y comprobar si conserva un estado que exige líneas.
2. **H3:** coordinar dos sesiones que modifiquen líneas distintas del mismo pedido y comparar el total almacenado con la suma tras ambos commits.
3. **H2:** comprobar con el rol real de aplicación si es posible insertar o actualizar un total inconsistente; registrar los permisos efectivos sin alterarlos globalmente.
4. **Reproducción base:** reconstruir y cargar TP1 en una base desechable; verificar los cinco totales esperados, restricciones y comportamiento de identidades.
5. **Rendimiento condicionado:** con volumen representativo, medir búsquedas y comprobaciones referenciales por `producto_id` antes de decidir si hace falta un índice adicional.

**Conclusión:** TP1 presenta dos brechas de integridad verificables en el código y un riesgo concurrente material pendiente de reproducción. Nada del adjunto permite concluir que esos problemas persistan en el Food Store acumulado.

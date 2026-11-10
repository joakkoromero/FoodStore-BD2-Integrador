Revisaré los 12 archivos únicamente a partir del adjunto, sin herramientas ni ejecución. Separaré los defectos verificables por lectura de las hipótesis de concurrencia y marcaré las dependencias del orden de instalación.


## Hallazgos Confirmables

**H1. La instalación de `restricciones.sql` elimina la validación de pedidos insertados directamente en un estado final**
- **Severidad:** alta, por integridad.
- **Archivo y líneas:** `restricciones.sql`, aproximadamente 29–33; contraste con `schema.sql`, 113–115.
- **Fragmento:** `DROP TRIGGER IF EXISTS trg_validar_confirmacion ...` seguido de `BEFORE UPDATE OF estado ON pedido`.
- **Mecanismo:** el esquema original valida la existencia de detalles tanto en `INSERT` como en cambios de estado. El reemplazo elimina ese trigger y crea uno que solamente atiende `UPDATE`. Por tanto, después de instalar las restricciones, un `INSERT` puede crear un pedido `CONFIRMADO` o `ENTREGADO` sin detalles. El enum admite esos valores y no existe otra comprobación que lo impida. También permite insertar directamente un estado que nunca recorrió las transiciones definidas.
- **Alcance:** defecto del histórico TP2 al aplicar `restricciones.sql` sobre el esquema adjunto. No se puede determinar si persiste en el acumulado U4–U7.
- **Certeza estática:** alta. La aceptación requiere un usuario con permiso de inserción en `pedido` y un `usuario_id` existente; no supone acceso de un usuario externo.
- **Prueba mínima propuesta:** en una copia con esquema, datos y restricciones instalados, abrir una transacción e insertar un pedido con usuario válido, forma de pago válida y `estado='CONFIRMADO'`, sin detalles. Consultar el pedido y sus detalles; repetir con `ENTREGADO` y finalizar con `ROLLBACK`. Comparar, en una reconstrucción separada, con el comportamiento anterior a instalar `restricciones.sql`.

**H2. El total derivado del pedido puede modificarse sin modificar sus detalles**
- **Severidad:** media, por integridad.
- **Archivo y líneas:** `schema.sql`, aproximadamente 54–57 y 74–98; `restricciones.sql` no añade protección sobre `total`.
- **Fragmentos:** `total NUMERIC(14,2) NOT NULL DEFAULT 0` y `AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido`.
- **Mecanismo:** el trigger recalcula el total cuando cambian los detalles, pero no protege una escritura directa en `pedido.total`. Por ejemplo, un pedido cuyos detalles suman 2800 puede quedar con `total=1`: cumple `CHECK (total >= 0)` y no dispara el recálculo. También se admite insertar un pedido pendiente vacío con total positivo. Esto contradice la invariante declarada en el comentario: mantener el total igual a la suma de las líneas.
- **Alcance:** histórico, tanto con el esquema solo como después de instalar las restricciones. Persistencia en el acumulado no determinable.
- **Certeza estática:** alta respecto de la ausencia de protección en estas fuentes. El impacto operativo depende de quién tenga permiso de escritura sobre esa columna y de las rutas de escritura de la aplicación, no incluidas.
- **Prueba mínima propuesta:** dentro de una transacción de la copia, elegir un pedido con detalles, registrar `total` y `SUM(subtotal)`, actualizar solamente `total` a otro valor no negativo y volver a comparar. Finalizar con `ROLLBACK`. Para evaluar exposición, repetir usando el rol real de la aplicación, sin cambiar permisos.

Estos son defectos de integridad verificables por lectura; **no se ejecutaron pruebas**.

## Hipótesis Para Laboratorio

**H3. Posible total incorrecto por recálculos concurrentes con `schema.sql` sin las restricciones adicionales**
- **Severidad:** media, condicionada a esa configuración.
- **Archivo y líneas:** `schema.sql`, aproximadamente 75–98, especialmente 80–84.
- **Fragmento:** `UPDATE pedido SET total = COALESCE((SELECT SUM(subtotal) ...), 0)`.
- **Mecanismo propuesto:** en `READ COMMITTED`, dos sesiones pueden insertar detalles distintos del mismo pedido. Cada recálculo es un `UPDATE` con una subconsulta agregada. Si una sesión calcula usando una instantánea que no incluye el detalle aún no confirmado de la otra y luego espera por la fila del pedido, no debe suponerse que esa espera refresque la instantánea del agregado. El último total escrito podría omitir una línea.
- **Distinción importante:** `restricciones.sql`, aproximadamente 39–69, toma `FOR UPDATE` sobre el pedido **antes** de modificar sus detalles. Esa serialización cambia el escenario y no permite trasladar automáticamente esta hipótesis al TP2 completo. No identifico aquí una carrera equivalente demostrada con esas restricciones activas.
- **Alcance:** configuración histórica con `schema.sql` solamente; relevancia para la instalación efectiva de TP2 y para el acumulado no determinada.
- **Certeza estática:** media; requiere comprobar el intercalado y el resultado en PostgreSQL 17.
- **Prueba mínima propuesta:** en una copia con esquema y datos, sin `restricciones.sql`, usar un pedido pendiente y dos productos distintos aún no asociados a él. A inserta una línea y deja abierta la transacción; B intenta insertar la otra y se observa dónde espera; A confirma y luego B confirma. Desde una tercera sesión comparar `pedido.total` con `SUM(subtotal)`. Repetir en otra reconstrucción con las restricciones instaladas. Limpiar únicamente los registros de prueba identificados.

## Reproducción Y Límites

**Orden de instalación.** Hay una dependencia concreta que conviene documentar, pero no alcanza para afirmar un defecto del procedimiento sin sus instrucciones:

- `data.sql`, aproximadamente 27–28, lleva cuatro pedidos directamente de `PENDIENTE` a `ENTREGADO`.
- `restricciones.sql`, aproximadamente 11–17, rechaza esa transición directa.
- Por tanto, `schema → data → restricciones` es compatible con esa carga; `schema → restricciones → data` la rechazaría. El bundle no incluye un procedimiento que indique que deba usarse el segundo orden. No lo clasifico como error confirmado de entrega.

**Configuración base frente a TP2 completo.** El esquema solo tampoco impide borrar o modificar detalles de un pedido ya confirmado. `restricciones.sql` sí agrega esa protección. Es una diferencia entre etapas explícitas del material, no evidencia de que el TP2 completo carezca de ella.

**Pruebas existentes.** `pruebas_restricciones.sql` comprueba correctamente el rechazo de confirmar sin detalles, el retroceso de estado y la modificación de un detalle confirmado; también recorre transiciones válidas. Los bloques capturan `23514`, mientras que el `RAISE EXCEPTION` de fallo usa por defecto otro código, por lo que no veo una falsa aprobación causada por capturar su propia aserción. El `ROLLBACK` final es deliberado. Faltan casos que detectarían H1 y H2, pero eso no invalida los casos existentes.

**Ejercicios de concurrencia.** No detecto un defecto concreto en los ocho scripts ilustrativos:

- Las lecturas no repetibles y los fantasmas son resultados intencionales de `READ COMMITTED`; su ausencia en `REPEATABLE READ` es coherente con PostgreSQL.
- Los comentarios de B contemplan restablecer el precio y limpiar el producto insertado entre pruebas. Los valores esperados requieren cumplir esos pasos y partir de la carga indicada.
- El bloqueo necesita que A conserve la transacción abierta cuando B solicite la misma fila. `pg_sleep(5)` no reemplaza la coordinación entre sesiones.
- El deadlock requiere intercalar las primeras y segundas adquisiciones de ambos scripts. Ejecutarlos completos de forma secuencial no demostraría el ciclo; eso no convierte el ejemplo en incorrecto.
- Los identificadores fijos dependen de una reconstrucción y carga compatibles. Son una precondición del ejercicio, no prueba de un fallo en la base principal.

**Seguridad y rendimiento.** No hay evidencia suficiente para afirmar exposición de contraseñas: los literales fueron saneados y el almacenamiento efectivo no se puede reconstruir a partir de placeholders. Tampoco hay roles, permisos o código de aplicación para afirmar explotación externa de H1/H2. Los `DROP ... CASCADE` pertenecen a una reconstrucción explícita; no son por sí mismos un hallazgo de seguridad.

No atribuyo tiempos ni mejoras de planes sin medición. El bloqueo pesimista de los detalles puede generar contención, pero también cumple una función de integridad; no es por sí solo un defecto de rendimiento.

## Cobertura

Las líneas anteriores son **aproximadas del archivo original**, reconstruidas excluyendo los encabezados del bundle y las dos líneas añadidas de advertencia de saneamiento. Todos los archivos comparten el prefijo `work\antecedentes\TP2\Arancibia_Romero_TP2\`.

| Archivo | Estado | Resultado |
|---|---|---|
| `concurrencia\01_no_repetible_A.sql` | Revisado | Sin problema concreto detectado; depende del intercalado y del restablecimiento indicado. |
| `concurrencia\01_no_repetible_B.sql` | Revisado | Sin problema concreto detectado; incluye indicación de restablecimiento. |
| `concurrencia\02_fantasma_A.sql` | Revisado | Sin problema concreto detectado; conteos sujetos a carga y limpieza. |
| `concurrencia\02_fantasma_B.sql` | Revisado | Sin problema concreto detectado; inserción y limpieza ilustrativas. |
| `concurrencia\03_bloqueo_A.sql` | Revisado | Sin problema concreto detectado; requiere coordinación manual. |
| `concurrencia\03_bloqueo_B.sql` | Revisado | Sin problema concreto detectado; modificación revertida deliberadamente. |
| `concurrencia\04_deadlock_A.sql` | Revisado | Sin problema concreto detectado; ciclo intencional. |
| `concurrencia\04_deadlock_B.sql` | Revisado | Sin problema concreto detectado; ciclo intencional. |
| `data.sql` | Revisado | Totales esperados coherentes con los detalles; dependencia del orden de instalación. |
| `pruebas_restricciones.sql` | Revisado | Sin fallo concreto en los casos incluidos; no cubre H1/H2. |
| `restricciones.sql` | Revisado | H1; no cierra H2; serialización relevante para contrastar H3. |
| `schema.sql` | Revisado | H2; H3 condicionada; trigger original de inserción relevante para H1. |

## Prioridad U8

1. **Confirmar H1:** comparar inserciones de pedidos confirmados/entregados vacíos antes y después de instalar las restricciones.
2. **Confirmar H2 y su exposición:** intentar desalinear total y detalles, primero con el rol de laboratorio y luego con el rol efectivo de aplicación, sin modificar permisos.
3. **Resolver H3:** comparar el mismo intercalado de inserciones concurrentes con esquema solo y con restricciones activas.
4. **Verificar la carrera confirmación–detalle:** enfrentar una confirmación con inserción, modificación y eliminación concurrentes de detalles. Comprobar espera, estado final y coherencia del total en ambas órdenes de adquisición.
5. **Validar reproducción desde cero:** ejecutar, exclusivamente con los originales locales autorizados y en una copia descartable, el orden documentado de instalación y las pruebas existentes; registrar errores y SQLSTATE. Si no existe orden documentado, contrastar los dos órdenes señalados.

La revisión queda limitada al adjunto: no implica aprobación humana de la entrega ni permite concluir que los problemas históricos persistan en la versión acumulada.

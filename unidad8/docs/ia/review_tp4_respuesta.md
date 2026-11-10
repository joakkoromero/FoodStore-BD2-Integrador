Voy a revisar los diez archivos del adjunto sin usar herramientas ni ejecutar código. Separaré los defectos deducibles por lectura de las hipótesis que necesitan pruebas, con referencias a las líneas internas de cada archivo.


## Hallazgos Confirmables

La revisión cubre los diez archivos, exclusivamente por lectura del adjunto. No ejecuté herramientas ni SQL, ni modifiqué archivos. Las líneas indicadas son **internas de cada archivo**, contando los dos comentarios iniciales de la copia saneada y excluyendo encabezados y cercos Markdown del bundle.

Los hallazgos corresponden al TP4 histórico. **No puede determinarse su persistencia en el acumulado U4–U7** con estas fuentes. Los placeholders no se consideran errores.

### H1. La instalación de las restricciones elimina la validación de estado al insertar pedidos
**Severidad:** alta para integridad.  
**Referencia:** `restricciones.sql:31–35`; `schema.sql:116–118`.  
**Fragmento:** `DROP TRIGGER ... trg_validar_confirmacion` seguido de `BEFORE UPDATE OF estado ON pedido`.

**Mecanismo y escenario:** el esquema original valida en `INSERT` y en cambios de estado que un pedido confirmado o entregado tenga detalles. `restricciones.sql` elimina ese trigger y lo reemplaza por otro que solamente interviene en actualizaciones. Después de instalar ambos archivos se puede insertar directamente un pedido `CONFIRMADO` o `ENTREGADO`, sin detalles, porque `estado` admite explícitamente esos valores.

Además, `validar_detalle_pendiente()` impide agregar detalles a ese pedido porque ya no está pendiente. Un pedido insertado como entregado tampoco puede volver a pendiente mediante las transiciones permitidas.

**Alcance:** histórico con `schema.sql` y `restricciones.sql` instalados. Requiere permiso de inserción en `pedido`, no privilegios administrativos. No demuestra una vulnerabilidad de acceso externo.

**Certeza estática:** alta.

**Prueba mínima propuesta:** en una copia con ambos scripts instalados y un usuario existente, abrir una transacción e insertar un pedido indicando `estado='ENTREGADO'`, una forma de pago válida y omitiendo `total`. Verificar que queda sin detalles; intentar agregarle uno y comprobar el rechazo. Finalizar con `ROLLBACK`.

### H2. El total del pedido puede modificarse sin mantener la igualdad con sus detalles
**Severidad:** media.  
**Referencia:** `schema.sql:57–60,77–101`.  
**Fragmentos:** `CHECK (total >= 0)` y trigger `AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido`.

**Mecanismo y escenario:** el comentario del esquema establece que `pedido.total` debe ser la suma de sus líneas. El trigger mantiene esa igualdad cuando cambian los detalles, pero nada comprueba las escrituras directas sobre `pedido.total`. Una actualización con cualquier importe no negativo puede dejar un total falso, incluso en un pedido entregado. El trigger de estados no interviene si solamente cambia `total`.

Esto afecta a `consultas_parte3.sql`, cuya parte 3B suma `p.total`; las consultas que agregan `d.subtotal` pueden entonces producir cifras incompatibles.

**Alcance:** histórico. Requiere permiso efectivo para escribir `total`. Si un rol de aplicación tiene ese permiso restringido por columna o únicamente opera mediante una interfaz controlada, la exposición disminuye; esos permisos no están incluidos.

**Certeza estática:** alta respecto de la falta de protección en las fuentes; exposición operativa no determinada.

**Prueba mínima propuesta:** sobre un pedido con detalles, dentro de una transacción, modificar su total a un importe positivo distinto de la suma. Consultar ambos valores y comprobar que la modificación no se rechaza. Usar `ROLLBACK`. Para evaluar seguridad operativa, repetir con el rol real del laboratorio, no solamente con el propietario.

### H3. El seed es incompatible con las restricciones si estas se instalan antes
**Severidad:** media, condicionada al orden de reconstrucción.  
**Referencia:** `data.sql:29–31`; `restricciones.sql:13–19`.  
**Fragmento:** `UPDATE pedido SET estado='ENTREGADO' WHERE id IN (1,2,3,4)`.

**Mecanismo y escenario:** el seed crea esos pedidos como pendientes y después los pasa directamente a entregados. Con `restricciones.sql` instalado, solamente se permite `PENDIENTE → CONFIRMADO → ENTREGADO`; la actualización falla y deja abortada la transacción del seed.

**No es un fallo incondicional de la entrega:** ejecutar primero `schema.sql`, luego `data.sql` y después `restricciones.sql` permite cargar esos estados con el validador original. El bundle no incluye un orquestador o instrucciones que permitan confirmar cuál era el orden previsto.

**Alcance:** reconstrucción del histórico; no demuestra que la carga histórica efectivamente haya fallado.

**Certeza estática:** alta sobre la incompatibilidad; indeterminada sobre el orden utilizado.

**Prueba mínima propuesta:** comparar en dos copias vacías las secuencias `schema → restricciones → data` y `schema → data → restricciones`, usando los originales locales y detención ante errores. La primera debe rechazar la transición; verificar el resultado y los conteos de la segunda.

## Hipótesis Que Requieren Ejecución

### H4. Posible pérdida de actualización del total con escrituras concurrentes usando solamente el esquema base
**Severidad:** media, bajo esa configuración.  
**Referencia:** `schema.sql:78–101`; contraste con `restricciones.sql:41–61`.  
**Fragmento:** `SET total = COALESCE((SELECT SUM(subtotal) ...), 0)`.

**Mecanismo y escenario:** el esquema base no bloquea previamente el pedido antes de modificar sus detalles. Dos transacciones pueden insertar productos distintos en el mismo pedido pendiente y llegar simultáneamente al recálculo. La suma de una sesión puede evaluarse con una instantánea que no incluya la inserción todavía no confirmada de la otra; esperar después por la fila del pedido no garantiza por sí solo que aquella suma se vuelva a calcular.

**Condición importante:** con `restricciones.sql`, el trigger `BEFORE` toma `FOR UPDATE` sobre el pedido antes de modificar el detalle. Eso serializa el acceso al mismo padre y cambia sustancialmente el escenario. No hay evidencia suficiente para atribuir esta anomalía a la instalación completa bajo `READ COMMITTED`.

**Alcance:** hipótesis del histórico si se utiliza `schema.sql` sin las restricciones adicionales. No se extrapola a otros niveles de aislamiento ni al acumulado.

**Certeza estática:** media.

**Prueba mínima propuesta:** en dos sesiones `READ COMMITTED`, insertar detalles de productos diferentes en el mismo pedido pendiente, coordinando la superposición de los recálculos mediante instrumentación exclusiva del laboratorio. Tras confirmar ambas transacciones, comparar `pedido.total` con `SUM(subtotal)`. Repetir con `restricciones.sql` instalado. Una prueba secuencial no evalúa esta hipótesis.

## Mejoras Opcionales Y Límites

- **Instalación con detención y atomicidad.** `restricciones.sql` no está envuelto en una transacción y elimina triggers antes de recrearlos. Una interrupción o fallo entre esas instrucciones puede dejar una instalación parcial. `schema.sql` y `data.sql` sí usan transacciones, pero no declaran `ON_ERROR_STOP`; este puede establecerlo un invocador externo no incluido. Es una mejora de reproducción, no evidencia de que haya ocurrido un fallo.
- **Aislamiento del laboratorio.** La guarda de nombre de base está en `carga_masiva_tp3.sql:8–13`, no en los demás scripts. `schema.sql:8–9` contiene borrados destructivos y `preparar_linea_base.sql:4–7` elimina índices. Son operaciones coherentes con una reconstrucción aislada; no constituyen por sí solas un defecto. El nombre de base tampoco es una frontera de seguridad.
- **Mediciones insuficientes para concluir rendimiento.** `medir_antes.sql` y `medir_despues.sql` ejecutan las mismas consultas, lo cual permite comparar, pero no controlan por sí solos calentamiento de caché, repeticiones ni carga concurrente. El bundle no contiene sus salidas. No es posible afirmar mejoras, regresiones ni tiempos.
- **Índice de cobertura.** `indices_optimizacion.sql:5–7` ofrece un acceso por producto con las columnas analíticas necesarias. Eso no garantiza un `Index Only Scan` ni ausencia de accesos al heap: dependen también del plan y de la visibilidad de las páginas. `ANALYZE` no sustituye esa verificación.
- **Semántica de facturación.** Las consultas analíticas incluyen pendientes al usar `estado <> 'CANCELADO'` y seleccionan la franja por el precio **actual** del producto, aunque suman subtotales históricos. Eso coincide con sus predicados y no contradice una especificación explícita del bundle. Conviene aclararlo si se interpretan como ventas realizadas o franja de precio histórico, pero no lo califico como bug.
- **Seguridad.** No aparecen funciones `SECURITY DEFINER` ni SQL dinámico que justifiquen afirmar escalamiento de privilegios o inyección. Los permisos y la autenticación no están disponibles. Los literales saneados de `contrasena` tampoco permiten determinar el tratamiento real de credenciales.

En las consultas de la parte 3 no detecté un error concreto de equivalencia: el ranking agrega los mismos detalles entregados en ambas versiones y `DENSE_RANK` permite más de diez productos cuando hay empates, conforme a la especificación. La variante correlacionada y la agrupada aplican los mismos filtros; las comprobaciones bidireccionales con `EXCEPT` son pertinentes para estas salidas, únicas por producto o usuario.

## Cobertura

Todos los archivos están bajo `work\antecedentes\TP4\Arancibia_Romero_TP4\`.

| Archivo | Estado | Resultado |
|---|---|---|
| `carga_masiva_tp3.sql` | Revisado | Sin problema concreto detectado. Deshabilita triggers de usuario dentro de una transacción, recompone totales y los rehabilita antes del commit. Las comprobaciones finales informan, pero no abortan automáticamente ante discrepancias. |
| `consultas_analiticas.sql` | Revisado | Sin defecto concreto; aclaraciones opcionales sobre estados y precio actual. |
| `consultas_parte3.sql` | Revisado | Sin error concreto de equivalencia; H2 puede contaminar los resultados basados en `p.total`. Rendimiento sin verificar. |
| `data.sql` | Revisado | H3: dependencia del orden de instalación. |
| `indices_optimizacion.sql` | Revisado | Sin defecto concreto; beneficio y accesos al heap pendientes de medición. |
| `medir_antes.sql` | Revisado | Sin error concreto en las consultas; limitaciones del protocolo de medición. |
| `medir_despues.sql` | Revisado | Mismos predicados que antes; no acredita una mejora sin resultados. |
| `preparar_linea_base.sql` | Revisado | Sin defecto concreto. Retira los candidatos TP4 nombrados; la procedencia completa de los índices TP3 no puede verificarse. |
| `restricciones.sql` | Revisado | H1; interacción H3. Bloqueo del padre relevante para H4; instalación no atómica como mejora opcional. |
| `schema.sql` | Revisado | H2; H4 condicionado al uso sin restricciones. Validador de inserción eliminado por H1. |

## Pruebas Priorizadas Para U8

1. **H1:** insertar directamente un pedido entregado sin detalles tras instalar las restricciones y comprobar también el rechazo posterior de detalles.
2. **H3:** contrastar los dos órdenes de reconstrucción, registrando el primer error y los conteos finales.
3. **H2:** intentar alterar directamente el total con el propietario y con el rol operativo; comparar con la suma de detalles.
4. **H4:** reproducir escrituras concurrentes sobre un mismo pedido, primero con el esquema base y después con las restricciones.
5. **Validación y rendimiento:** sobre una copia reconstruida desde originales, comprobar conteos y totales, ejecutar las diferencias bidireccionales de la parte 3 y comparar planes antes/después con repeticiones y condiciones registradas.

Hay defectos confirmables por lectura en la protección de inserciones y del total; la incompatibilidad del seed depende del orden. La concurrencia y el rendimiento requieren las pruebas señaladas antes de emitir conclusiones operativas.

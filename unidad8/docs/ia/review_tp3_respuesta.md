Revisaré los diez archivos del adjunto sin usar herramientas ni ejecutar código. Separaré los defectos demostrables por lectura de las hipótesis y mejoras, y reconstruiré las líneas de cada archivo excluyendo los encabezados del bundle.


**Resultado**
La lectura del bundle identifica **tres defectos confirmables**, uno de ellos condicionado al orden de instalación, y **una hipótesis de concurrencia** que requiere prueba. No ejecuté herramientas, SQL ni pruebas, ni modifiqué archivos.

Las referencias siguientes son **líneas aproximadas de los archivos originales**, reconstruidas excluyendo los encabezados del bundle y las dos líneas agregadas de advertencia de saneamiento. Todos los archivos pertenecen a `work\antecedentes\TP3\Arancibia_Romero_TP3\`.

Los hallazgos corresponden al **histórico TP3**. No permiten afirmar que existan en la versión acumulada U4–U7, cuyas fuentes no están incluidas. Los placeholders no se consideran errores.

**Defectos Confirmables**

### H1. El reemplazo del trigger permite insertar pedidos confirmados o entregados sin detalle
- **Severidad:** alta, por pérdida de una regla explícita de integridad.
- **Archivos y líneas:** `restricciones.sql`, aproximadamente 29–33; contraste con `schema.sql`, 101–116.
- **Fragmento:** `DROP TRIGGER ... trg_validar_confirmacion` seguido de `BEFORE UPDATE OF estado ON pedido`.
- **Mecanismo:** el trigger original controla `INSERT` y actualizaciones de estado. Su reemplazo controla únicamente actualizaciones. Después de instalar `restricciones.sql`, un `INSERT` con `estado='CONFIRMADO'` o `'ENTREGADO'` no verifica la existencia de detalles ni atraviesa las transiciones previstas. También puede insertarse directamente un pedido cancelado vacío, aunque el comentario del esquema indica que solo un pendiente puede estar vacío.
- **Escenario:** un rol con permiso de inserción sobre `pedido`, usuario válido y forma de pago válida inserta un pedido entregado sin detalles. No necesita deshabilitar triggers ni privilegios de administración.
- **Alcance:** histórico TP3 con `restricciones.sql` instalado. Acumulado: no determinable.
- **Certeza estática:** alta.
- **Prueba mínima propuesta:** en una copia, instalar esquema y restricciones, crear las dependencias mínimas e intentar insertar un pedido confirmado sin detalles dentro de una transacción que termine en `ROLLBACK`. Comparar con el esquema sin el reemplazo: el trigger original debería rechazarlo.

### H2. El seed es incompatible con las transiciones estrictas si las restricciones ya están instaladas
- **Severidad:** media, por impedir una reconstrucción según el orden elegido.
- **Archivos y líneas:** `data.sql`, aproximadamente 27–29; `restricciones.sql`, 11–16.
- **Fragmentos:** `UPDATE pedido SET estado='ENTREGADO' WHERE id IN (1,2,3,4)` y la transición permitida `PENDIENTE → CONFIRMADO`.
- **Mecanismo:** el seed inserta pedidos sin especificar estado, por lo que nacen pendientes. Luego intenta llevar cuatro directamente a entregados. El esquema inicial permite esa operación si tienen detalle; `validar_estado_pedido()` la rechaza.
- **Escenario:** ejecutar `schema.sql → restricciones.sql → data.sql` provoca una excepción y aborta la transacción del seed. En cambio, `schema.sql → data.sql → restricciones.sql` evita esta incompatibilidad.
- **Alcance:** histórico TP3. **No se adjunta un procedimiento de instalación que determine cuál era el orden previsto**, por lo que no afirmo que la reconstrucción utilizada efectivamente haya fallado.
- **Certeza estática:** alta para la incompatibilidad; indeterminada para su ocurrencia real.
- **Prueba mínima propuesta:** probar ambos órdenes en copias separadas. Registrar el primer error y verificar si quedaron cargadas las filas del seed.

### H3. `pedido.total` puede modificarse sin concordancia con sus detalles
- **Severidad:** media, por permitir inconsistencias en importes.
- **Archivos y líneas:** `schema.sql`, aproximadamente 48–59 y 75–99; `carga_masiva.sql`, 63–71, muestra además una escritura directa legítima del total.
- **Fragmentos:** `total NUMERIC(14,2) ... CHECK (total >= 0)` y trigger `AFTER INSERT OR UPDATE OR DELETE ON detalle_pedido`.
- **Mecanismo:** los cambios en detalles recalculan el total, pero ninguna regla adjunta valida una modificación directa de `pedido.total`. El `CHECK` solo exige que no sea negativo. Por ejemplo, asignar un total positivo arbitrario a un pedido con detalles deja una discrepancia persistente hasta un posterior recálculo.
- **Escenario y permisos:** requiere un rol con permiso para actualizar esa columna, como el propietario usado en el laboratorio. No demuestra una vulnerabilidad explotable desde la aplicación: no se adjuntan roles, privilegios ni código de acceso.
- **Alcance:** histórico TP3, tanto con el esquema inicial como con las restricciones adicionales. La condición de igualdad está expresada en el comentario del trigger y comprobada al final de la carga masiva.
- **Certeza estática:** alta respecto de la posibilidad de inconsistencia. Su exposición a usuarios de aplicación no puede determinarse.
- **Prueba mínima propuesta:** tomar un pedido con detalles, modificar únicamente su total dentro de `BEGIN … ROLLBACK` y comparar con `SUM(subtotal)`. Repetir usando el rol real del laboratorio para establecer si sus permisos lo permiten.

**Hipótesis A Verificar**

### H4. Posible total perdido ante modificaciones concurrentes usando solo el esquema base
- **Severidad potencial:** alta si deja un total incorrecto.
- **Archivos y líneas:** `schema.sql`, aproximadamente 80–85 y 97–99; mitigación relevante en `restricciones.sql`, 39–59.
- **Fragmento:** `UPDATE pedido SET total = (SELECT SUM(subtotal) ... )`.
- **Mecanismo sospechado:** con el esquema base, dos sesiones pueden insertar detalles distintos del mismo pedido. El recálculo combina una lectura agregada y una actualización del padre; bloquear la fila del pedido durante esa actualización no garantiza por sí solo que el agregado se haya calculado con visibilidad del detalle concurrente. Es necesario verificar el comportamiento de snapshots, espera y reevaluación en PostgreSQL 17.
- **Distinción importante:** `validar_detalle_pendiente()` adquiere un `FOR UPDATE` sobre el pedido **antes de modificar el detalle**. Esto introduce una serialización que cambia sustancialmente el escenario. No traslado automáticamente la hipótesis al conjunto final con restricciones instaladas.
- **Alcance:** candidato para la variante histórica con `schema.sql` solamente. Afectación del conjunto completo y del acumulado: no demostrada.
- **Certeza estática:** media; no presento la anomalía como reproducida.
- **Prueba mínima propuesta:** dos sesiones en `READ COMMITTED`, mismo pedido pendiente y productos distintos. La primera inserta y mantiene abierta su transacción; la segunda intenta insertar; luego se confirma la primera y finalmente la segunda. Comparar total almacenado y suma de detalles. Repetir con `restricciones.sql` instalado y registrar dónde espera cada sesión.

**Mejoras Opcionales**
No tienen la misma prioridad ni certeza que los defectos anteriores.

- **M1. Índice de Q3 no completamente cubriente.** `indices_optimizacion.sql`, aproximadamente 12–16, incluye `usuario_id` y `total`, pero Q3 también selecciona `id`, ausente del índice. El índice sigue siendo útil para filtro y orden; no es incorrecto. Si se pretendía una consulta cubierta, faltaría esa columna. Un eventual `Index Only Scan` también depende del mapa de visibilidad: agregarla no garantiza por sí solo una mejora.
- **M2. Medición insuficiente para conclusiones generales.** `medir_antes.sql` y `medir_despues.sql` contienen una ejecución por consulta, sin controlar repeticiones ni calentamiento de caché. Son capturas válidas, pero aisladas no separan bien el efecto del índice de otras variaciones. No hay planes ni tiempos adjuntos que permitan cuantificar beneficios.
- **M3. Comentario impreciso en la equivalencia.** `consultas_parte4.sql`, aproximadamente 27–41, dice que la prueba “debe devolver cero filas”, pero devuelve dos filas con contadores. El criterio correcto es **cero diferencias en ambos contadores**. No altera la equivalencia de las consultas mostradas.

**Observaciones De Alcance**
- La desactivación de triggers de usuario en `carga_masiva.sql` está dentro de una transacción, restaura los triggers y recompone los totales antes del `COMMIT`. Con estas fuentes no demuestra una inconsistencia por sí misma.
- Esa carga presupone una copia con el seed esperado, sin actividad concurrente que altere identidades o filas. No es una carga genérica ni idempotente; no la considero defectuosa por no serlo.
- `schema.sql` reconstruye destructivamente y `preparar_linea_base.sql` elimina índices deliberadamente. Bajo el aislamiento exigido para este laboratorio, esas operaciones no son hallazgos de seguridad.
- No infiero contraseñas en claro, credenciales expuestas ni formatos inválidos a partir de literales saneados. Tampoco se dispone de privilegios o configuración de conexión para evaluar exposición real.

**Cobertura**
| Archivo | Revisión y resultado |
|---|---|
| `carga_masiva.sql` | Revisado. Relacionado con H3; sin otro defecto concreto en la carga bajo sus precondiciones. Los recuentos esperados son coherentes con el seed. |
| `consultas_lentas.sql` | Revisado. Sin problema concreto de correctitud detectado. El rendimiento requiere planes y medición. |
| `consultas_parte4.sql` | Revisado. Las variantes mostradas son coherentes entre sí; M3 afecta el comentario de verificación. No se adjunta una consigna externa para resolver otras interpretaciones del promedio. |
| `data.sql` | Revisado. H2: incompatibilidad condicionada al orden de instalación. |
| `indices_optimizacion.sql` | Revisado. Índices coherentes con filtros y órdenes; M1 sobre cobertura incompleta de Q3. |
| `medir_antes.sql` | Revisado. Consultas coincidentes con las declaradas; M2 sobre alcance de la evidencia. |
| `medir_despues.sql` | Revisado. Mismas consultas que antes; M2. |
| `preparar_linea_base.sql` | Revisado. Sin problema concreto detectado bajo uso aislado; preserva las restricciones declaradas y elimina índices de acceso deliberadamente. |
| `restricciones.sql` | Revisado. H1, H2 y serialización relevante para H4. |
| `schema.sql` | Revisado. H3 y variante base de H4; trigger original relevante para H1/H2. |

**Pruebas Priorizadas Para U8**
1. **Verificar inserciones con estados finales (H1):** contrastar esquema base y esquema con restricciones; comprobar que ningún pedido confirmado o entregado pueda quedar vacío.
2. **Validar la reconstrucción histórica (H2):** ensayar ambos órdenes de seed/restricciones en copias y documentar el orden reproducible, sin modificar retrospectivamente las fuentes.
3. **Comprobar integridad del total y permisos (H3):** intentar la escritura directa con el rol de laboratorio y ejecutar el control de suma; distinguir posibilidad estructural de exposición efectiva.
4. **Ensayar concurrencia en dos sesiones (H4):** comparar las variantes con y sin bloqueo previo del pedido, verificando los totales tras ambos commits.
5. **Reproducir la optimización:** con datos originales locales, comparar resultados, planes y buffers de Q1–Q3 mediante varias ejecuciones equivalentes; registrar índices presentes y condiciones de caché. Ejecutar también los contadores de equivalencia de Parte 4.

Estas pruebas se proponen exclusivamente para copias aisladas; ninguna fue ejecutada durante esta revisión.

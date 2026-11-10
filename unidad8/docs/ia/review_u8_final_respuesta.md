**Resultado**
No identifico hallazgos nuevos que constituyan un fallo actual demostrado en las siete fuentes entregadas, dentro del alcance del laboratorio U8. No corresponde generar una tabla de IDs `U8-F01`, etc., sin hallazgos que registrar.

Esta conclusión es de **revisión estática**. No utilicé herramientas, ejecuté comandos ni modifiqué archivos. Los resultados de ejecución informados por Codex se consideran contexto aportado, no pruebas realizadas por mí ni aprobación humana.

**Cobertura 7/7**
| Fuente | Cobertura Completa |
|---|---|
| `movil/schema_sqlite.sql` | Líneas 1–87. |
| `movil/pruebas_sqlite.sql` | Líneas 1–128. |
| `movil/semaforo.sql` | Líneas 1–86. |
| `postgresql/10_fixture_y_snapshot.sql` | Líneas 1–99. |
| `postgresql/20_validar_no_ventas.sql` | Líneas 1–119. |
| `postgresql/30_corregir_estado_inicial.sql` | Líneas 1–31. |
| `tools/reproducir.py` | Líneas originales 1–1054, integrando ambos adjuntos contiguos. |

El runner está completo: la primera parte contiene las líneas originales **1–540** y la segunda **541–1054**. La continuidad del bloque SQL de `administrative_change()` entre ambas partes es coherente. No observo truncamiento ni un segmento faltante en el contenido presentado. El SHA256 declarado no fue recalculado.

La respuesta Plan previa se utilizó como contexto, no como una octava fuente. Sus rangos antiguos no describen las versiones actuales del validador y del runner.

**Coherencia Final**
- **Integridad local:** las cuatro tablas principales son `STRICT`; hay restricciones de cantidades, importes, booleanos e identificadores, claves foráneas y una PK compuesta para los ítems. La auxiliar no `STRICT` restringe explícitamente los tipos de sus valores numéricos relevantes. El runner activa y comprueba `foreign_keys` por conexión y verifica integridad y referencias al finalizar.
- **C7 y transacciones:** `pruebas_sqlite.sql:78–128` provoca errores CHECK y FK reales. El ejecutor procesa sentencias individualmente, comprueba el código extendido esperado y exige que la transacción siga abierta. El `ROLLBACK` posterior revierte también el encabezado previo; las consultas verifican ausencia de residuos. No se confunde el aborto de una sentencia con la reversión de toda la transacción.
- **UUID e índice parcial:** el esquema valida la representación hexadecimal con guiones y protege el UUID textual mediante PK. El índice de `schema_sqlite.sql:59–61` permite históricos múltiples, pero una sola solicitud `PENDIENTE` por borrador. El runner genera UUID con `uuid4()` y prueba por separado duplicación de PK y unicidad parcial. No hace falta atribuir al CHECK una validación de versión UUID que no implementa.
- **Importación y lápidas:** se validan estructura CSV, rangos, booleanos, duplicados, nombres del fixture y fecha con zona. El reemplazo del snapshot y el UPSERT de caché son atómicos. No se eliminan filas de caché referenciadas; la baja explícita permanece como lápida y queda oculta en el catálogo. La exigencia de exactamente cuatro productos es coherente con este fixture cerrado.
- **Semáforo por lote:** cada ejecución evalúa el lote, no únicamente el UUID que luego inspecciona `simulate()`. Esto es coherente con `semaforo.sql:74–84`: **sólo persiste cambios sobre solicitudes `PENDIENTE`**. Las llamadas posteriores pueden comprobar resultados ya obtenidos por la primera ejecución. Los históricos no se reevalúan ni cambian sus timestamps.
- **Prioridades:** ausencia, baja, falta o insuficiencia de stock e indisponibilidad producen rechazo; rojo prevalece sobre diferencias de precio. Los borradores vacíos también se rechazan. La aprobación se identifica como simulación y no genera ventas ni descuentos.
- **Respaldo y privacidad:** la protección explícita del directorio privado precede a diagnósticos y dump. Los archivos completos quedan fuera del proyecto; la evidencia pública conserva metadatos y huellas. El respaldo precede al fixture. Las guardas evitan reemplazar deliberadamente bases o salidas preexistentes.
- **Evidencia de conservación:** el validador actual incorpora huellas de `pedido` y `detalle_pedido`, además de suma y huella de stock de todo el catálogo. El runner compara esas propiedades antes/después y verifica separadamente los cambios administrativos C2/C4 permitidos.
- **Guarda PostgreSQL:** `30_corregir_estado_inicial.sql:13–30` instala un trigger `BEFORE INSERT` que exige `PENDIENTE`, con error `23514` para cualquier otro estado, incluido un nulo explícito. No modifica los triggers de actualización ni redefine las transiciones anteriores. Corrige el estado de nacimiento; no pretende prohibir todo pedido vacío ni sustituir las ACL existentes.

Las pruebas auxiliares en copias efímeras están claramente diferenciadas de los snapshots exportados y de la base final. No constituyen por sí mismas un defecto ni una falsificación de evidencia.

**Hallazgos Previos**
| ID Previo | Estado | Fundamento |
|---|---|---|
| `U8-01` | Atendido; premisa histórica corregida | El runner aplica ACL explícita mediante `icacls` antes de escribir información privada. Además, la documentación de Python 3.12 sitúa el soporte Windows de `mode=0o700` desde **3.12.4**, por backport. La referencia previa exclusivamente a 3.13 era incompleta y no demuestra defecto ni exposición en Python 3.12.14. |
| `U8-02` | Resuelto en las fuentes actuales | Las comparaciones incorporan huellas de pedidos y detalles, y controles globales de stock, sustentando las declaraciones de conservación más allá de la igualdad de conteos. |
| `U8-03` | Resuelto en las fuentes actuales | Se eliminó el `CONFLICTO` artificial del historial final. C2 conserva dos solicitudes reales de la simulación, y sigue existiendo la prueba independiente del segundo pendiente simultáneo. |

El cambio a `--maintenance-db postgres` mejora la claridad operativa. No convierte retrospectivamente la variante anterior en un bug demostrado ni elimina el requisito de disponibilidad del template frente a otras conexiones.

**Límites**
- Codex informa dos ejecuciones completas con iguales resultados semánticos, siete casos C1–C7 y siete bordes satisfactorios, y cinco huellas agregadas del origen idénticas. No inspeccioné los artefactos ni reproduje esas ejecuciones.
- La conservación de la primera copia renombrada, el estado de la segunda copia canónica y la aplicación de la guarda en ambas son hechos aportados, no comprobaciones independientes de esta revisión.
- Las pruebas informadas con propietario y `app_web` respaldan la guarda en el entorno real. Las ACL U5 y las funciones de transición anteriores no están entre estas siete fuentes, por lo que su implementación no puede revisarse aquí.
- El script `30_corregir_estado_inicial.sql` no está integrado en el runner mostrado. Su aplicación y prueba separadas están declaradas explícitamente; no atribuyo al runner esa cobertura.
- Un `INSERT` con identidad automática puede avanzar una secuencia de la copia aunque termine en `ROLLBACK`. Las cinco huellas de tablas no prueban conservación de secuencias, ni se exige aquí esa conservación.
- Las huellas comparan estados observados, no una auditoría de cambios transitorios o de todo el clúster. El dump se verifica por existencia, tamaño y hash; estas fuentes no incluyen un ensayo de restauración.

No se emite aprobación en nombre del equipo humano.

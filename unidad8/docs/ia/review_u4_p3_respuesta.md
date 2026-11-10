**Resultado**
Revisé estáticamente los dos archivos completos de esta parte, exclusivamente a partir del adjunto. No ejecuté SQL, herramientas ni comandos; tampoco modifiqué archivos.

**No identifiqué un defecto material incondicional demostrable con estas fuentes.** Hay tres puntos condicionados por dependencias o por el entorno operativo que conviene verificar antes de dar por validada la solución. No los presento como fallos confirmados.

Las líneas indicadas abajo corresponden a los **archivos SQL saneados**, contando la primera línea dentro de cada bloque como línea 1, sin encabezados ni cercos Markdown. La numeración original podría diferir por los comentarios de saneamiento.

**Hipótesis Por Verificar**

### H1. La excepción por profundidad de trigger no identifica el origen de la actualización
- **Severidad:** media, condicionada a que exista otro camino de actualización.
- **Archivo:** `outputs\Arancibia_Romero_U4\tp_desnormalizacion_top_categorias.sql`, líneas aproximadas **109–119**.
- **Fragmento:**
  ```sql
  IF TG_TABLE_SCHEMA='public' AND TG_TABLE_NAME='pedido'
     AND pg_trigger_depth()>1 THEN
      RETURN NULL;
  END IF;
  ```
- **Mecanismo:** el comentario limita conceptualmente la excepción al camino heredado `detalle_pedido -> pedido`, pero la condición implementada reconoce cualquier ejecución anidada sobre `pedido`. `pg_trigger_depth()` indica profundidad, no qué tabla o función originó la actualización.
- **Escenario de fallo:** un trigger de una tabla ajena a las cuatro fuentes actualiza `pedido.fecha` o `pedido.eliminado`. El refresco de `pedido` se omite por profundidad y esa tabla externa no tiene el refresco final que sí tiene `detalle_pedido`. La MV podría quedar desactualizada.
- **Límite de la evidencia:** el adjunto no muestra ese camino externo. Si todas las actualizaciones anidadas relevantes provienen de las cuatro fuentes instrumentadas y culminan en su refresco externo, este escenario no demuestra un fallo actual.
- **Afectación:** potencialmente al acumulado; no puede determinarse con esta parte. No demuestra un defecto del histórico.
- **Certeza estática:** **alta** sobre la amplitud de la condición; **baja** sobre la existencia de un camino problemático en la entrega.
- **Prueba mínima propuesta:** primero revisar los triggers heredados que pueden escribir `pedido`. Si existe un origen externo a las cuatro fuentes, usar ese camino en una copia aislada para modificar una fecha o una baja lógica de un pedido con detalle. Comparar fuente y MV mediante la auditoría bilateral incluida. Una prueba con un trigger auxiliar únicamente demostraría la limitación del diseño, no que el proyecto actual la ejerza.

### H2. Las escrituras requieren permisos adicionales para ejecutar el refresco
- **Severidad:** media si la aplicación utiliza un rol de escritura restringido.
- **Archivo:** `outputs\Arancibia_Romero_U4\tp_desnormalizacion_top_categorias.sql`, líneas aproximadas **105–122**, con instalación de triggers en **124–150**.
- **Fragmento:**
  ```sql
  CREATE FUNCTION public.u4_refrescar_ventas()
  RETURNS trigger LANGUAGE plpgsql VOLATILE
  SET search_path=pg_catalog AS $$
  ...
  REFRESH MATERIALIZED VIEW public.mv_u4_ventas_categoria_dia;
  ```
- **Mecanismo:** la función no declara `SECURITY DEFINER`, por lo que se ejecuta con los privilegios efectivos del invocador. En PostgreSQL 17, el refresco exige privilegio `MAINTAIN` sobre la MV. Tener autorización para modificar una tabla fuente no implica disponer de ese privilegio.
- **Escenario de fallo:** el propietario instala correctamente el script, pero el rol de la aplicación solo dispone de DML sobre las tablas. Una escritura alcanza el trigger, falla el refresco por permisos y se revierte la sentencia.
- **Límite de la evidencia:** no se incluyen roles ni concesiones. Si la aplicación usa el propietario o un rol suficientemente autorizado, no se produce este fallo. No es evidencia de escalada de privilegios ni justifica introducir funciones privilegiadas automáticamente.
- **Afectación:** potencialmente al acumulado tras instalar los triggers; no al histórico por sí solo.
- **Certeza estática:** **alta** sobre el requisito de permisos; **media** sobre su relevancia operativa, porque falta la configuración del rol.
- **Prueba mínima propuesta:** en una copia aislada, conectar con el rol real previsto para la aplicación y efectuar una escritura válida sobre una fuente, dentro de una transacción que se revierta. Verificar si completa el refresco o falla por autorización. No hace falta alterar permisos globales.

### H3. La equivalencia del reporte depende de conservar la zona horaria de sesión
- **Severidad:** baja; condicionada a reutilizar las consultas en otras sesiones.
- **Archivo:** `outputs\Arancibia_Romero_U4\tp_desnormalizacion_top_categorias.sql`, líneas aproximadas **9**, **55–56**, **67–75** y **154–166**.
- **Fragmentos:**
  ```sql
  SET timezone = 'America/Argentina/Buenos_Aires';
  ```
  ```sql
  (ped.fecha AT TIME ZONE 'America/Argentina/Buenos_Aires')::date
  ```
  ```sql
  WHERE fecha=CURRENT_DATE
  ```
- **Mecanismo:** la MV clasifica siempre por día de Buenos Aires. `CURRENT_DATE` y los límites de la consulta fuente dependen de la zona de la sesión.
- **Escenario de fallo:** si las consultas se reutilizan en una conexión configurada con otra zona, el día seleccionado y los límites temporales pueden dejar de representar el mismo conjunto. Cerca del cambio de día también puede seleccionarse una fecha distinta de la fecha actual de Buenos Aires.
- **Límite de la evidencia:** **el script completo sí configura la zona adecuada**. No hay un error demostrado al ejecutarlo tal como está. El riesgo pertenece al consumo posterior del reporte.
- **Afectación:** potencialmente al uso del acumulado desde otras conexiones.
- **Certeza estática:** **alta** sobre la dependencia de sesión; **baja** sobre que exista una conexión mal configurada.
- **Prueba mínima propuesta:** comparar fuente y resumen en sesiones de laboratorio con Buenos Aires y UTC, usando pedidos cercanos a medianoche argentina. Comprobar tanto las fechas elegidas como las sumas, sin depender del instante real de ejecución.

**Comprobaciones Favorables**
En `tp_desnormalizacion_top_categorias.sql`:

- La instalación de la MV y los triggers es transaccional. El bloqueo de las cuatro fuentes impide escrituras concurrentes durante esa instalación.
- El resumen conserva todas las fechas y reproduce la agrupación por nombre de categoría. No introduce un filtro por estado que no estuviera en la consulta fuente.
- El protocolo combina un bloqueo asesor transaccional con rechazo explícito de aislamientos distintos de `READ COMMITTED`. Las funciones son `VOLATILE`, coherentemente con la necesidad de obtener visibilidad posterior a la espera. No identifico una carrera demostrable entre escritores ordinarios que respeten estos triggers.
- `TRUNCATE` se rechaza deliberadamente. No corresponde tratar ese rechazo como un defecto.
- La auditoría usa diferencias en ambos sentidos con `EXCEPT ALL` y toma el mismo bloqueo asesor. Además, verifica por separado la invariante de `pedido.total`.

En `tp_fnbc_control_lote.sql`:

- Las claves candidatas y la descomposición descritas son consistentes con `LD -> R` y `R -> D`.
- El archivo reconoce correctamente que las PK/FK de las tablas descompuestas no preservan por sí solas `LD -> R`, y agrega una comprobación sobre el JOIN.
- Tanto las escrituras en `lote_responsable` como en `responsable_deposito` actualizan la misma guardia antes de comprobar la regla. No identifiqué una carrera demostrable que permita confirmar dos responsables para un mismo lote y depósito mediante DML ordinario.
- El `UPDATE` real sobre la guardia, a diferencia de un mero bloqueo asesor, también permite que un conflicto con snapshots antiguos produzca un error de serialización en los aislamientos superiores.
- Las pruebas negativas capturan `unique_violation` y abortan si la operación inválida fue aceptada. La comparación bilateral de la migración se ejecuta antes del `COMMIT`.

Estas conclusiones no validan los cuerpos de los triggers históricos, que no aparecen en esta parte.

**Costos Y Mejoras Opcionales**
No los considero defectos materiales sin requisitos adicionales:

- **Refresco completo y serialización:** en el primer archivo, líneas **100** y **119**, cada sentencia instrumentada puede reconstruir toda la MV, y el bloqueo asesor se conserva hasta terminar la transacción. Incluso una sentencia sin cambios relevantes puede llegar al refresco. Es un costo estructural verificable por lectura, pero no demuestra tiempos inaceptables ni que una alternativa vaya a mejorar el rendimiento. Conviene medir por separado consultas del panel y escrituras.
- **Guardia y validación global:** en el segundo archivo, líneas **170–203**, todas las escrituras de ambas relaciones compiten por una fila y disparan una validación global. Es una limitación de concurrencia reconocida expresamente por el script, no una anomalía oculta.
- **Evidencia original con FK activas:** `control_lote_almacen_original` se conserva como evidencia, pero sus FK siguen restringiendo eliminaciones de maestros aunque posteriormente se retiren las relaciones operativas. No lo clasifico como bug: conservar esa evidencia puede ser deliberado. Si U8 incluye pruebas de eliminación física, debe contemplar esta restricción.
- **Reproducción:** el segundo archivo pide ejecutarse con `ON_ERROR_STOP=1`, pero no lo establece internamente. Es una precondición documentada del lanzador. No constituye por sí sola un error de la migración.

**Cobertura**
| Archivo | Estado | Resultado |
|---|---|---|
| `outputs\Arancibia_Romero_U4\tp_desnormalizacion_top_categorias.sql` | Revisado completo | Sin defecto material incondicional demostrado. H1: origen de actualizaciones anidadas; H2: permisos del invocador; H3: zona de sesiones consumidoras. Costos de refresco completo pendientes de medición. |
| `outputs\Arancibia_Romero_U4\tp_fnbc_control_lote.sql` | Revisado completo | Sin problema concreto de integridad demostrado. Revisados descomposición, migración, guardia concurrente, validación de ambas relaciones y pruebas negativas. Costos de serialización y conservación de evidencia explícitos. |

**Pruebas Priorizadas Para U8**
1. **Concurrencia FNBC:** en dos sesiones, intentar asignar distintos responsables del mismo depósito al mismo lote; repetir enfrentando una asignación con un cambio de depósito del responsable. Verificar espera y rechazo, o error de serialización según aislamiento, sin duplicados confirmados.
2. **Concurrencia del resumen:** intercalar escrituras relevantes sobre las fuentes en dos sesiones `READ COMMITTED`, manteniendo abierta la primera transacción. Tras ambas confirmaciones, ejecutar la auditoría bilateral y comprobar `pedido.total`.
3. **Rol real de aplicación:** probar una escritura válida con sus privilegios efectivos para confirmar o descartar H2.
4. **Caminos heredados y fechas:** revisar los orígenes de escrituras anidadas sobre `pedido` y probar los existentes; contrastar además el reporte con distintas zonas de sesión para delimitar H1 y H3.
5. **Costo operativo representativo:** medir refrescos por sentencia, espera de bloqueos y comportamiento de escrituras de varias filas, además del `EXPLAIN (ANALYZE, BUFFERS)` del panel. No deducir la conveniencia global de la desnormalización únicamente de la mejora de lectura.

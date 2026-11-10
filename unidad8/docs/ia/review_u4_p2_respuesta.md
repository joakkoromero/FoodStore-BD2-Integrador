Voy a revisar ambos archivos únicamente a partir del adjunto, sin herramientas ni ejecución. Separaré los defectos verificables por lectura de las hipótesis que dependan del esquema, los triggers o el entorno no incluidos en esta parte.


## Resultado

Se revisaron íntegramente los **dos archivos de esta parte**, exclusivamente a partir del adjunto. **No ejecuté herramientas, SQL ni pruebas, y no modifiqué archivos.**

Se identificaron **dos problemas del verificador**: sus validaciones desaparecen al ejecutar Python con optimización y la coordinación temporal de la prueba concurrente puede producir falsos negativos. No se demuestra aquí un defecto de integridad de la solución SQL acumulada ni un problema material en el script de reversión.

Las líneas indicadas corresponden a los **archivos saneados**, incluyendo sus dos comentarios iniciales, pero excluyendo encabezados y delimitadores Markdown del bundle. Para reconstruirlas se restaron 13 líneas en Python y 571 en SQL.

## Defectos Verificables

### H1. Las comprobaciones desaparecen con Python optimizado

**Severidad:** media.  
**Archivo:** `outputs\Arancibia_Romero_U4\reproduccion\verify_foodstore.py`  
**Líneas:** 202–206, 239–240, 410–425 y 503–531, entre otras.  
**Certeza estática:** alta.

**Fragmentos:**
```python
def assert_clean(result: dict, label: str) -> None:
    assert result["difference_count"] == 0, (label, result)
```

```python
assert metrics["top5_original"] == metrics["top5_materialized"], "Top 5 mismatch"
...
metrics["status"] = "passed"
```

**Mecanismo y escenario:** las validaciones funcionales, de integridad y de concurrencia se implementan mediante `assert`. Python elimina esas instrucciones con `-O`, `-OO` o una configuración equivalente de `PYTHONOPTIMIZE`.

En ese modo, una auditoría que devuelva diferencias puede continuar sin provocar un error; también desaparecen las comprobaciones de rechazo esperado, preservación histórica y resultados concurrentes. Si las demás operaciones terminan normalmente, el programa puede escribir `"status": "passed"` aun con resultados inconsistentes registrados en las métricas.

No significa que cualquier error SQL quede oculto: `run_raw()` sigue comprobando el código de salida y algunas operaciones todavía podrían fallar por otras causas. El defecto concreto es que **el estado de aprobación deja de garantizar las condiciones que el verificador pretende comprobar**.

**Alcance:** afecta a la confiabilidad de la evidencia del acumulado U4 y de su preservación histórica. No demuestra que los datos históricos estén dañados. El adjunto no informa si el procedimiento externo prohíbe o detecta Python optimizado.

**Prueba mínima propuesta:** en una copia aislada del verificador original, suministrar a `assert_clean()` un resultado con `difference_count=1` y las restantes claves válidas. Comparar ejecución normal y optimizada. La primera debe rechazarlo; la segunda permitirá continuar. Para verificar el impacto integral, usar luego una inconsistencia controlada de la vista materializada en el laboratorio, sin modificar la base principal.

### H2. La prueba concurrente depende de observar una pausa de solo dos segundos

**Severidad:** baja, por riesgo de falso negativo de reproducción.  
**Archivo:** `outputs\Arancibia_Romero_U4\reproduccion\verify_foodstore.py`  
**Líneas:** 349–354 y 386–410.  
**Certeza estática:** alta sobre la dependencia temporal; su incidencia real requiere ejecución.

**Fragmentos:**
```python
sql += ("SELECT pg_sleep(2); " if pause else "")+"COMMIT;"
```

```python
if any(r.get("wait_event") == "PgSleep" for r in observed_a):
    break
```

```python
assert any(
    r.get("wait_event_type") == "Lock"
    and r.get("wait_event") == "advisory"
    for r in observed_b
), observed_b
```

**Mecanismo y escenario:** A conserva su transacción abierta durante una pausa fija de dos segundos. El controlador debe observar esa pausa mediante una nueva invocación de `psql`, iniciar B y observar su espera antes de que A confirme.

El límite de 25 segundos para observar A no extiende su pausa. Una demora del controlador, del inicio de procesos o de las consultas de actividad puede hacer que A termine antes de ser observado. También puede ocurrir que se observe A cerca del final de la pausa y B ya no llegue a bloquearse.

En esos casos la prueba falla aunque la serialización de la base sea correcta. El intervalo de sondeo de 30 ms tampoco garantiza esa frecuencia efectiva, porque cada consulta incluye el tiempo de arranque y conexión de otro proceso.

**Alcance:** afecta a la reproducción de la prueba concurrente del acumulado, no demuestra una anomalía en sus triggers ni corrupción histórica.

**Prueba mínima propuesta:** ejecutar el verificador original en laboratorio e introducir, mediante un arnés externo, una demora controlada superior a dos segundos antes del primer sondeo de A o entre la observación de A y el lanzamiento de B. Comprobar si la prueba falla por falta de observación mientras una auditoría independiente permanece limpia.

## Hipótesis Pendientes

### H3. La limpieza de procesos no garantiza por sí sola la finalización de los backends

**Severidad potencial:** baja, limitada al laboratorio.  
**Archivo:** `outputs\Arancibia_Romero_U4\reproduccion\verify_foodstore.py`  
**Líneas:** 436–451; relacionado con 119–123.  
**Certeza estática:** media. El efecto depende de cómo y cuándo PostgreSQL detecte la desconexión.

**Fragmento:**
```python
if process is not None and process.poll() is None:
    process.kill()
    process.communicate(timeout=10)
...
restoration_audit = sql_json(
    "BEGIN ISOLATION LEVEL READ COMMITTED; "
    + LOCK_SQL + " " + restore + " " + AUDIT_CTE + "; COMMIT;"
)
```

**Mecanismo posible:** `process.kill()` termina el cliente `psql`, no constituye una confirmación explícita de que su backend PostgreSQL ya terminó o revirtió la transacción. Si el servidor sigue procesando o esperando antes de detectar la desconexión, la restauración puede quedar esperando el bloqueo asesor. Su límite de tiempo del lado cliente puede entonces agotarse y dejar la restauración sin confirmar.

El código sí intenta restaurar en `finally` y toma el bloqueo de serialización: son medidas relevantes. **No hay evidencia suficiente para afirmar que los precios queden alterados en una ejecución normal**, ni que exista una carrera de restauración demostrada.

**Alcance:** recuperación ante fallos del verificador sobre la copia acumulada de laboratorio; no puede extrapolarse al histórico de producción.

**Prueba mínima propuesta:** provocar un timeout o una interrupción cuando un escritor esté activo, observar sus sesiones desde una conexión independiente y comprobar cuándo desaparecen, qué bloqueos conservan y si la restauración termina. Registrar precios y auditoría final incluso cuando el verificador haya fallado.

## Revisión Del Resto

### `verify_foodstore.py`

No se detectó otro defecto material confirmable por lectura. Se revisaron consultas, auditorías, hashes, mediciones, mutaciones, recursión, concurrencia, metadatos y persistencia de métricas.

Aspectos relevantes y límites:

- La auditoría utiliza `EXCEPT ALL` en ambos sentidos, compara también el resultado diario y verifica totales de pedidos. No se limita a comparar el top cinco.
- Las pruebas negativas comprueban el SQLSTATE esperado; una excepción diferente se propaga. Con Python normal, también comprueban la presencia del aviso esperado.
- La concurrencia audita los cambios **antes** de restaurarlos y comprueba los incrementos de precios y subtotales. Esto evita que la restauración oculte por sí sola una inconsistencia previa.
- Las consultas diarias y la agrupación por fecha local son coherentes con la zona horaria fijada. El cambio de día durante la ejecución sigue siendo una condición de borde a controlar en el laboratorio.
- Las llamadas de `subprocess` emplean argumentos separados y no activan un shell. Los identificadores usados en las mutaciones se convierten a enteros y `activity()` restringe los nombres de aplicación. No se observa una vía concreta de inyección desde entrada externa en este archivo.
- Los permisos necesarios para inspeccionar actividad y modificar los objetos dependen de la configuración real de `tp_admin`, no incluida aquí. No puede afirmarse una vulnerabilidad por su nombre ni recomendar cambios globales de permisos.
- La existencia y el comportamiento de los triggers heredados, las restricciones y el SQL de instalación no pueden validarse con esta parte. Sus dependencias no se consideran ausentes.

**Mejoras opcionales, no defectos adicionales:**

- `node_summary()`, líneas 141–160, resta costos de hijos sin ponderar sus ejecuciones y mezcla esa aproximación con tiempos ajustados por `Actual Loops`. El propio resultado advierte que son valores aproximados. Conviene no usar el “nodo dominante” como atribución exacta, especialmente ante ciclos anidados o subplanes.
- Las comparaciones del top cinco no tienen desempate. Un empate puede producir listas distintas válidas; la auditoría completa de grupos proporciona una comprobación más sólida. No se demuestra que el conjunto de datos tenga ese empate.
- Los `INSERT` revertidos pueden consumir valores de secuencias en PostgreSQL. Esto no contradice la restauración declarada de precios ni prueba alteración de filas históricas, pero una repetición no necesariamente conserva el estado de las secuencias.

### `reversion_desnormalizacion.sql`

**Sin problema material concreto detectado.**

El script se declara explícitamente opcional y de reversión. No corresponde considerar un fallo que retire la vista materializada y sus triggers.

Se verificó por lectura que:

- Activa `ON_ERROR_STOP` y comprueba la base de destino antes de iniciar la reversión.
- Encierra bloqueos y eliminaciones de objetos en una transacción.
- Usa nombres calificados con `public`.
- No incluye `CASCADE` en los `DROP`, ni borra las tablas fuente o sus filas.
- Retira los objetos U4 enumerados y conserva las fuentes e índices heredados en lo visible.

La integridad de la lista de objetos U4 depende del instalador, que no aparece en esta parte. Los bloqueos pueden esperar o participar en interbloqueos si se revierte con escritores activos; eso no demuestra corrupción y se evita operativamente ejecutando esta reversión deliberada en un laboratorio sin carga concurrente.

## Cobertura

| Archivo | Estado | Hallazgos o conclusión |
|---|---|---|
| `outputs\Arancibia_Romero_U4\reproduccion\verify_foodstore.py` | Revisado completo | H1: validaciones eliminables; H2: sincronización temporal frágil; H3: hipótesis de recuperación ante interrupciones. |
| `outputs\Arancibia_Romero_U4\reversion_desnormalizacion.sql` | Revisado completo | Sin problema material concreto detectado; correspondencia con el instalador pendiente de otras partes. |

## Pruebas Prioritarias U8

1. **Validaciones activas:** confirmar el comportamiento normal frente a `-O`/`PYTHONOPTIMIZE` y comprobar que ninguna aprobación se acepte con validaciones deshabilitadas.
2. **Concurrencia con demoras:** repetir la prueba incorporando retrasos controlados del controlador para distinguir fallos de observación de verdaderas anomalías de serialización.
3. **Recuperación ante interrupciones:** provocar timeout con escritores activos y verificar sesiones, bloqueos, precios restaurados y auditoría final desde una conexión independiente.
4. **Mutaciones e integridad real:** ejecutar las pruebas originales contra el esquema acumulado completo y comprobar resultados y efectos de las mutaciones, no únicamente la ausencia de diferencias posteriores.
5. **Reversión aislada:** instalar U4 y revertirlo sin escritores; comparar filas históricas, restricciones, índices y objetos restantes con el estado previo a la instalación.

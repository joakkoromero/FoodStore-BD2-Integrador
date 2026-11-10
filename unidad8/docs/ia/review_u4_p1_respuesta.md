Revisaré los seis archivos del adjunto sin usar herramientas ni ejecutar código. Separaré los defectos visibles de las hipótesis que dependan del respaldo, del esquema heredado o de pruebas en una copia aislada.


## Resultado

Revisados los **seis archivos completos de esta parte**, exclusivamente a partir del adjunto. No ejecuté código, SQL, herramientas ni consultas externas, y no modifiqué archivos.

Identifiqué **dos defectos confirmables por lectura**, relativos a la recuperación de la carga y a la fiabilidad del verificador bajo optimización de Python. Además, hay **dos hipótesis relevantes** que requieren comprobar el estado de las secuencias y el tipo de `pedido.fecha`. No encontré una vulnerabilidad de seguridad demostrable con las fuentes disponibles.

Las líneas indicadas corresponden a **cada archivo saneado**, reconstruidas contando desde el primer comentario dentro de su bloque, sin encabezados ni delimitadores Markdown. Se conservan los dos comentarios iniciales de saneamiento.

## Defectos Confirmables

### H1. La carga queda confirmada antes de un refresco necesario, sin recuperación mediante reejecución

- **Severidad:** media.
- **Archivo:** `01_actividad_del_dia.sql`, líneas 13–22 y 74–78.
- **Certeza estática:** alta.
- **Alcance:** preparación acumulada U4; no demuestra corrupción del histórico.

**Fragmento:**
```sql
COMMIT;

-- Este refresco explicito incorpora la nueva carga inicial de laboratorio.
REFRESH MATERIALIZED VIEW public.mv_facturacion_categoria_mes;
```

**Mecanismo y escenario:** los pedidos, detalles y totales quedan confirmados antes del refresco. Si este falla, por ejemplo por cancelación, falta de espacio o permisos, `ON_ERROR_STOP` interrumpe el archivo, pero no revierte la actividad ya confirmada. La materializada conserva su instantánea anterior.

La reejecución completa no permite completar la preparación: el control inicial exige exactamente 200000 pedidos y 399997 detalles, condiciones que ya dejaron de cumplirse. Por tanto, el procedimiento puede terminar con carga persistida, materializada desactualizada y resultado global de error.

La política de instantánea del TP5 es deliberada y **no constituye el defecto**. El problema es la frontera de confirmación y la falta de una ruta explícita de recuperación para el refresco que este mismo archivo declara necesario. Una recuperación manual sigue siendo posible; no es pérdida irreversible.

**Prueba mínima propuesta:** en una copia aislada, conservar una sesión con un bloqueo incompatible sobre la materializada y ejecutar el original con un `lock_timeout` breve establecido externamente para esa sesión. Tras el fallo del refresco, verificar que permanecen los 225000 pedidos, que la instantánea anterior no cambió y que la reejecución completa se rechaza por los controles iniciales.

### H2. Python optimizado puede declarar éxito aunque existan pruebas fallidas

- **Severidad:** media.
- **Archivo:** `reproduccion/verify_fnbc.py`, líneas 132–141, 399–400 y 485–487.
- **Certeza estática:** alta, condicionada a ejecutar con `-O` o `PYTHONOPTIMIZE`.
- **Alcance:** verificación y evidencias U4, no integridad de las tablas históricas.

**Fragmento:**
```python
assert process_a.returncode == 0, (out_a, err_a)
assert expected_rejection, (out_b, err_b)
```

Y al cerrar:
```python
assert all(test["ok"] for test in REPORT["tests"])
REPORT["success"] = True
```

**Mecanismo y escenario:** Python elimina los `assert` al activar optimización. Las comprobaciones matemáticas también desaparecen, aunque después se registra `"ok": True`.

Además, la prueba concurrente puede agregar un resultado con `"ok": False` sin que ese valor cause una excepción: sus validaciones posteriores dependen de `assert`. Si las demás comprobaciones SQL pasan, la validación global también desaparece y se emiten `"success": True`, mensaje satisfactorio y código de salida cero pese al resultado fallido registrado.

`require_success()` y las excepciones explícitas SQL siguen funcionando: el problema no invalida todas las comprobaciones ni implica que una ejecución normal ya haya dado un falso positivo.

**Prueba mínima propuesta:** sobre una copia desechable del verificador, usar un arnés que haga retornar las fases SQL satisfactoriamente pero agregue una entrada con `"ok": False`. Comparar ejecución normal y optimizada: la segunda puede alcanzar el éxito global. Otra comprobación independiente es introducir una expectativa matemática incorrecta en esa copia y observar que `-O` elimina su validación. No requiere tocar la entrega ni la base principal.

## Hipótesis Pendientes

### H3. La carga presupone que los identificadores nuevos comienzan exactamente en 200001

- **Severidad potencial:** media.
- **Archivo:** `01_actividad_del_dia.sql`, líneas 16–20, 30–35, 47 y 63–71.
- **Certeza estática:** alta sobre el supuesto; media sobre su materialización.
- **Alcance:** carga acumulada U4; depende del respaldo y de operaciones previas.

**Fragmento:**
```sql
INSERT INTO public.pedido (usuario_id, fecha, forma_pago)
...
WHERE p.id BETWEEN 200001 AND 225000;
```

**Mecanismo y escenario:** el control inicial valida cantidad y máximo de `pedido`, pero no el siguiente valor del generador de identificadores. Los detalles y el recálculo posterior usan un rango fijo.

Si la secuencia está adelantada, por ejemplo por una carga anterior abortada, los pedidos nuevos no coincidirán con ese rango. Los controles finales normalmente detectarán el desajuste y revertirán las filas, pero los valores consumidos de una secuencia PostgreSQL **no se recuperan con `ROLLBACK`**. Reintentar puede seguir fallando.

Esto no demuestra que el respaldo adjunto tenga una secuencia incorrecta: su contenido y el DDL del identificador no están incluidos aquí. El hash del respaldo verifica identidad del archivo, no permite deducir su estado interno.

**Prueba mínima propuesta:** restaurar el respaldo original en una copia aislada, inspeccionar el valor predeterminado o identidad de `pedido.id` y su secuencia. Comprobar primero el caso limpio. Después, en otra copia, consumir un identificador dentro de una transacción revertida y repetir la carga. Verificar si el control inicial pasa y el final rechaza la operación.

### H4. Los meses de facturación podrían depender de la zona horaria de cada refresco

- **Severidad potencial:** media.
- **Archivos:** `antecedentes/views_tp5.sql`, líneas 53 y 62; `01_actividad_del_dia.sql`, líneas 9 y 78.
- **Certeza estática:** media; falta confirmar el tipo de `pedido.fecha`.
- **Alcance:** objeto heredado TP5 utilizado por el acumulado U4.

**Fragmento:**
```sql
date_trunc('month', p.fecha) AS mes
```

Frente a:
```sql
SET TIME ZONE 'America/Argentina/Buenos_Aires';
```

**Mecanismo y escenario:** si `p.fecha` es `timestamptz`, la variante utilizada de `date_trunc` interpreta el mes según `TimeZone` de la sesión. El script de vistas no fija esa zona; la carga U4 sí la fija antes del refresco.

En ese caso, crear o refrescar la misma materializada desde sesiones con zonas distintas puede producir límites de mes distintos y reclasificar pedidos cercanos al cambio de mes. Si `fecha` es `timestamp without time zone`, este mecanismo específico no aplica.

No puede afirmarse que ya existan diferencias: faltan el tipo efectivo, la configuración del entorno y las fechas originales.

**Prueba mínima propuesta:** confirmar el tipo de `fecha`. Si es `timestamptz`, comparar la consulta agregada en UTC y Buenos Aires con un pedido de prueba cercano a medianoche del primer día del mes, dentro de una copia aislada. Comparar claves `mes`, pertenencia de pedidos e importes, sin modificar la definición entregada.

## Mejoras Opcionales Y Límites

**Índices parcialmente solapados.** `antecedentes/indices_tp4.sql`, líneas 5–7, y `antecedentes/indices_tp5.sql`, líneas 24–26, crean índices con las mismas claves `(producto_id, pedido_id)`, pero diferentes columnas incluidas:

```sql
INCLUDE (cantidad, subtotal)
INCLUDE (cantidad, precio_unitario)
```

El reconstruidor instala ambos. Esto implica mantener dos estructuras similares durante la carga, pero **no demuestra que alguno sea innecesario**: cada cobertura puede servir a consultas distintas. Antes de considerar su consolidación en una variante experimental, medir tamaño, uso y planes con las consultas originales. No atribuyo tiempos ni mejoras sin medición.

**Concurrencia del verificador.** La coordinación mantiene A abierta hasta observar B esperando un bloqueo; no depende únicamente de una pausa temporal. Comprueba el resultado de A, el rechazo de B y el estado final, y dispone de limpieza en `finally`. No considero esas modificaciones auxiliares ni las anomalías con `ROLLBACK` errores funcionales. La implementación de las restricciones o disparadores pertenece a otras fuentes: este archivo, por sí solo, no permite aprobar su corrección general.

**Seguridad y reproducción.** No aparecen credenciales literales ni SQL dinámico alimentado por entradas externas no confiables. Los nombres interpolados por el verificador proceden de constantes internas. El endpoint fijo del verificador difiere de los valores predeterminados del reconstruidor, pero este acepta parámetros y el verificador documenta su endpoint: no es una incompatibilidad demostrada.

Los antecedentes usan nombres SQL sin calificar. Su resolución depende del entorno y los permisos sobre los esquemas; sin evidencia de esquemas escribibles por usuarios no confiables, no corresponde afirmar una explotación. Asimismo, que el reconstruidor deje una base parcialmente preparada tras un fallo no implica que haya borrado o modificado la principal.

## Cobertura

Todos los archivos se encuentran bajo `outputs\Arancibia_Romero_U4\`.

| Archivo | Estado | Hallazgos o conclusión |
|---|---|---|
| `00_reconstruir_base.ps1` | Revisado completo | Sin defecto material propio demostrado. Comprueba hash y códigos de salida; crea una base nueva y no borra otras. |
| `01_actividad_del_dia.sql` | Revisado completo | H1; hipótesis H3 y participación en H4. La pausa del disparador de recálculo es deliberada, transaccional y acompañada de recálculo y controles. |
| `antecedentes\indices_tp4.sql` | Revisado completo | Sin problema concreto de correctitud. Solapamiento opcional a medir. |
| `antecedentes\indices_tp5.sql` | Revisado completo | Sin problema concreto de correctitud. Solapamiento opcional a medir. |
| `antecedentes\views_tp5.sql` | Revisado completo | Hipótesis H4. Sin otro defecto material demostrado; no se trata la recreación deliberada de la materializada como un bug. |
| `reproduccion\verify_fnbc.py` | Revisado completo | H2. Anomalías intencionales y limpieza distinguidas de errores funcionales. |

## Pruebas Priorizadas U8

Todas se proponen sobre originales locales y **copias aisladas**, nunca sobre las copias saneadas ni sobre la base principal.

1. **Reconstrucción limpia y secuencias:** confirmar el generador de `pedido.id`, los identificadores realmente asignados, los cuatro detalles por pedido nuevo y los totales. Después probar el reintento tras un consumo de secuencia revertido.
2. **Fallo del refresco posterior al `COMMIT`:** comprobar persistencia de la carga, antigüedad de la materializada y procedimiento necesario para completar la preparación.
3. **Fiabilidad del verificador:** comparar modo normal y optimizado con un fallo controlado en una copia desechable; exigir coherencia entre resultados individuales, éxito global y código de salida.
4. **Meses y zona horaria:** verificar el tipo de `fecha` y comparar agrupaciones UTC/Buenos Aires en límites de mes.
5. **Concurrencia real:** ejecutar el verificador original en el entorno documentado y comprobar que el `23505` corresponde a la restricción esperada, que B está bloqueada por A y que la limpieza restituye el estado inicial.

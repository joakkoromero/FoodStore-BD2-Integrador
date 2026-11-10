# Revisión de antecedentes TP1–TP5 y Unidad4

**Estado completa: 51/51 fuentes revisadas completas.** Cobertura completa de las fuentes asignadas a esta matriz. Ninguna decisión de esta matriz está aplicada ni validada como resultado de motor.

Las respuestas originales, prompts, metadatos y snapshots saneados se conservan fielmente en `docs/ia`. Sus SHA256 se verificaron. OpenCode 1.18.23, modelo solicitado `openai/gpt-6.1-sol`, agente Plan puro y permisos deny: cero eventos de herramientas en las consultas completas.

| Consulta | Archivos completos | Estado |
|---|---:|---|
| review_tp1 | 2 | Completa, hashes verificados |
| review_tp2 | 12 | Completa, hashes verificados |
| review_tp3 | 10 | Completa, hashes verificados |
| review_tp4 | 10 | Completa, hashes verificados |
| review_tp5 | 7 | Completa, hashes verificados |
| review_u4_p1 | 6 | Completa, hashes verificados |
| review_u4_p2 | 2 | Completa, hashes verificados |
| review_u4_p3 | 2 | Completa, hashes verificados |

Los IDs se forman como `queryprefix:ID_original`. Los duplicados se consolidan sin eliminar referencias. Los IDs OBS se asignan aquí a observaciones sin ID propio y se distinguen de los H/M emitidos por IA.

## Matriz de decisiones propuestas

### RH01. Borrado del último detalle de un pedido cerrado en esquemas históricos

**Decisión propuesta: corregido.** Alcance: historico_TP1_y_TP5_esquemas_base, acumulado_por_confirmar.

- `review_tp1:H1` — `work/antecedentes/TP1/schema.sql`, líneas aproximadas 100-115; relacionado con 75-98. IA: «Después de confirmarlo, se puede borrar su último detalle.»
- `review_tp5:H1` — `work/antecedentes/TP5/Arancibia_Romero_TP5/schema.sql`, líneas aproximadas 75-116; especialmente105-116. IA: «No controla la eliminación o el traslado de sus líneas.»

**Fundamento.** Propuesta descriptiva: el código de restricciones TP2 añade validar_detalle_pendiente y exige PENDIENTE antes de modificar/borrar. Eso corrige por lectura la configuración histórica base; no se afirma aún el resultado de una prueba del acumulado.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En copia U8, crear/usar un pedido confirmado con líneas e intentar borrar o trasladar su último detalle. Registrar rol, SQLSTATE, estado y recuento final; no probar en la principal.

### RH02. Total almacenado escribible directamente

**Decisión propuesta: aceptado.** Alcance: historico_TP1_TP2_TP3_TP4_TP5, actual_condicionado_por_rol_y_columnas.

- `review_tp1:H2` — `work/antecedentes/TP1/schema.sql`, líneas aproximadas 54-57; 74-98. IA: «Una escritura directa sobre pedido.total puede dejar un importe positivo que no coincida con la suma de sus líneas.»
- `review_tp2:H2` — `work/antecedentes/TP2/Arancibia_Romero_TP2/schema.sql`, líneas aproximadas 54-57; 74-98. IA: «El trigger recalcula el total cuando cambian los detalles, pero no protege una escritura directa en pedido.total.»
- `review_tp3:H3` — `work/antecedentes/TP3/Arancibia_Romero_TP3/schema.sql`, líneas aproximadas 48-59; 75-99. IA: «Ninguna regla adjunta valida una modificación directa de pedido.total.»
- `review_tp4:H2` — `work/antecedentes/TP4/Arancibia_Romero_TP4/schema.sql`, líneas aproximadas 57-60;77-101 (copia saneada; restar2 para original). IA: «Nada comprueba las escrituras directas sobre pedido.total.»
- `review_tp5:H2` — `work/antecedentes/TP5/Arancibia_Romero_TP5/schema.sql`, líneas aproximadas 48-59;75-99. IA: «Es una brecha de integridad del esquema, no evidencia de explotación externa.»

**Fundamento.** Aceptar la observación estructural histórica, no una explotación de la aplicación. Requiere INSERT/UPDATE sobre total. El equipo U8 informó metadatos de UPDATE total=false para app_web; hasta enlazar la evidencia y probar la operación no se considera decisión final sobre exposición actual.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En una copia y dentro de transacciones revertidas, contrastar escritura arbitraria de total como propietario y SET LOCAL ROLE app_web; comparar total/suma y SQLSTATE, sin conceder permisos nuevos.

### RH03. Hipótesis de total perdido por concurrencia en esquema base

**Decisión propuesta: aceptado.** Alcance: hipotesis_historica_esquema_base, acumulado_no_demostrado.

- `review_tp1:H3` — `work/antecedentes/TP1/schema.sql`, líneas aproximadas 75-98; especialmente 80-84. IA: «No debe suponerse que por sí solo garantiza una suma actualizada tras la espera.»
- `review_tp2:H3` — `work/antecedentes/TP2/Arancibia_Romero_TP2/schema.sql`, líneas aproximadas 75-98; especialmente 80-84. IA: «No identifico aquí una carrera equivalente demostrada con esas restricciones activas.»
- `review_tp3:H4` — `work/antecedentes/TP3/Arancibia_Romero_TP3/schema.sql`, líneas aproximadas 80-85; 97-99. IA: «No traslado automáticamente la hipótesis al conjunto final con restricciones instaladas.»
- `review_tp4:H4` — `work/antecedentes/TP4/Arancibia_Romero_TP4/schema.sql`, líneas aproximadas 78-101 (copia saneada; original aprox.76-99). IA: «No hay evidencia suficiente para atribuir esta anomalía a la instalación completa bajo READ COMMITTED.»
- `review_tp5:H3` — `work/antecedentes/TP5/Arancibia_Romero_TP5/schema.sql`, líneas aproximadas 80-91. IA: «No presento este escenario como una reproducción realizada.»

**Fundamento.** Aceptar únicamente como hipótesis que merece contraste, no como fallo reproducido. El BEFORE FOR UPDATE de TP2 serializa por pedido antes de cambiar detalles y modifica el escenario del AFTER aislado; una evaluación que lo ignore produciría una extrapolación injustificada.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** Dos sesiones coordinadas READ COMMITTED modifican líneas distintas del mismo pedido PENDIENTE. Esperar/confirmar en orden controlado y comparar total/suma desde otra sentencia. Contrastar esquema solo y conjunto con BEFORE si se pretende una afirmación histórica.

### RH04. Inserción directa de CONFIRMADO/ENTREGADO sin líneas

**Decisión propuesta: aceptado.** Alcance: historico_con_restricciones, actual_condicionado_a_INSERT_estado.

- `review_tp2:H1` — `work/antecedentes/TP2/Arancibia_Romero_TP2/restricciones.sql`, líneas aproximadas 29-33; contraste schema.sql:113-115. IA: «El reemplazo elimina ese trigger y crea uno que solamente atiende UPDATE.»
- `review_tp3:H1` — `work/antecedentes/TP3/Arancibia_Romero_TP3/restricciones.sql`, líneas aproximadas 29-33; contraste schema.sql:101-116. IA: «Su reemplazo controla únicamente actualizaciones.»
- `review_tp4:H1` — `work/antecedentes/TP4/Arancibia_Romero_TP4/restricciones.sql`, líneas aproximadas 31-35 (copia saneada; original aprox.29-33). IA: «solamente interviene en actualizaciones»

**Fundamento.** Aceptar la brecha de cobertura INSERT/UPDATE que se ve en el código histórico. No convertirla en vulnerabilidad actual sin comprobar los privilegios por columna del rol efectivo: un rol que no puede insertar estado queda limitado al valor PENDIENTE por defecto.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En copia U8 intentar INSERT de pedido CONFIRMADO y ENTREGADO sin líneas primero con propietario y luego con app_web; comprobar INSERT privilege sobre estado y SQLSTATE. Registrar también el control PENDIENTE permitido.

### RH05. Orden de seed y restricciones estrictas

**Decisión propuesta: descartado.** Alcance: condicional_historico, no_defecto_de_entrega_demostrado.

- `review_tp3:H2` — `work/antecedentes/TP3/Arancibia_Romero_TP3/data.sql`, líneas aproximadas 27-29; restricciones.sql:11-16. IA: «No afirmo que la reconstrucción utilizada efectivamente haya fallado.»
- `review_tp4:H3` — `work/antecedentes/TP4/Arancibia_Romero_TP4/data.sql`, líneas aproximadas 29-31 (copia saneada; original aprox.27-29). IA: «No es un fallo incondicional de la entrega.»

**Fundamento.** Proponer descartar la afirmación de que la entrega histórica estaba rota: falta su procedimiento de instalación. Mantener la observación como precondición real: schema→restricciones→data rechaza el salto PENDIENTE→ENTREGADO, mientras schema→data→restricciones es compatible. TP2 ya lo presenta como dependencia, no defecto confirmado.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** Si se necesita certificar reconstrucción histórica, ejecutar ambos órdenes sólo en copias desechables y registrar primer SQLSTATE. Si no se realiza, dejar explícita la precondición sin inventar resultado.

### RH06. Cobertura de índice Q3 incompleta para id

**Decisión propuesta: aceptado.** Alcance: mejora_opcional_historica, rendimiento_actual_no_medido.

- `review_tp3:M1` — `work/antecedentes/TP3/Arancibia_Romero_TP3/indices_optimizacion.sql`, líneas aproximadas 12-16. IA: «El índice sigue siendo útil para filtro y orden; no es incorrecto.»

**Fundamento.** Aceptar como candidato de medición, no defecto lógico ni promesa de mayor velocidad. El índice incluye usuario_id/total pero Q3 también devuelve id; un Index Only Scan depende además del mapa de visibilidad.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En copia y con carga equivalente, registrar EXPLAIN ANALYZE BUFFERS de Q3 y los índices presentes. Sólo si la medición justifica un INCLUDE adicional proponer el cambio; no tocar índices de la principal.

### RH07. Alcance de mediciones antes/después de una corrida

**Decisión propuesta: aceptado.** Alcance: limitacion_de_evidencia_historica, no_resultado_funcional_incorrecto.

- `review_tp3:M2` — `work/antecedentes/TP3/Arancibia_Romero_TP3/medir_antes.sql y medir_despues.sql`, líneas aproximadas archivo completo; sin rango más preciso en la respuesta. IA: «Son capturas válidas, pero aisladas no separan bien el efecto del índice de otras variaciones.»
- `review_tp4:OBS02` — `work/antecedentes/TP4/Arancibia_Romero_TP4/medir_antes.sql y medir_despues.sql`, líneas aproximadas archivos completos; sin rango preciso en la respuesta. IA: «No es posible afirmar mejoras, regresiones ni tiempos.»
- `review_tp5:OBS03` — `work/antecedentes/TP5/Arancibia_Romero_TP5/benchmark_escrituras.sql`, líneas aproximadas archivo completo; sin rango preciso en la observación. IA: «Sus resultados no representarían el costo completo de una operación ordinaria con esos triggers activos.»

**Fundamento.** Aceptar la limitación de generalización: una captura antes/después es evidencia del ensayo, pero no establece por sí sola causalidad universal ni rendimientos futuros. La revisión no contiene planes o tiempos adicionales que puedan inventarse.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** Para una afirmación de rendimiento, repetir consultas equivalentes con condiciones documentadas de caché/carga y comparar mediana/variación, planes y buffers; conservar las capturas históricas sin reescribir sus resultados.

### RH08. Comentario de equivalencia: contadores cero, no cero filas

**Decisión propuesta: corregido.** Alcance: aclaracion_documental_historica, sin_diferencia_logica_observada.

- `review_tp3:M3` — `work/antecedentes/TP3/Arancibia_Romero_TP3/consultas_parte4.sql`, líneas aproximadas 27-41. IA: «El criterio correcto es cero diferencias en ambos contadores.»

**Fundamento.** Propuesta de corrección documental en U8: interpretar las dos filas como contadores y exigir valor cero en ambos. No modificar retrospectivamente la entrega TP3 ni afirmar que las consultas eran diferentes por un comentario impreciso.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En la documentación U8 aclarar el criterio; si se reproduce, adjuntar los dos contadores reales. Mientras no haya ejecución enlazada, la aclaración es estática y propuesta.

### RH09. Índice adicional por producto_id como oportunidad de medición

**Decisión propuesta: aceptado.** Alcance: observacion_opcional_sin_ID_en_respuesta, historico_TP1.

- `review_tp1:OBS01` — `work/antecedentes/TP1/schema.sql`, líneas aproximadas 69 y sección de índices; referencia aproximada de IA. IA: «Es una oportunidad de medición, no un problema de rendimiento demostrado.»

**Fundamento.** OBS01 es un identificador asignado por esta matriz a una observación sin H/M propio. La PK comienza por pedido_id; consultas sólo por producto_id podrían beneficiarse de otro índice. No se conoce un plan lento ni la necesidad actual; versiones posteriores ya agregan índices.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** Revisar índices presentes en copia y medir una consulta por producto_id antes de proponer cambios. No duplicar un índice existente ni presentar la oportunidad como regresión confirmada.

### RH10. Instalación de restricciones no atómica ante interrupción

**Decisión propuesta: aceptado.** Alcance: mejora_opcional_historica, fallo_de_instalacion_no_reproducido.

- `review_tp4:OBS01` — `work/antecedentes/TP4/Arancibia_Romero_TP4/restricciones.sql`, líneas aproximadas archivo completo; sin rango más preciso en la respuesta. IA: «Una interrupción o fallo entre esas instrucciones puede dejar una instalación parcial.»

**Fundamento.** Aceptar como mejora de reproducción: el archivo elimina y vuelve a crear triggers sin una transacción envolvente propia. No se afirma que haya ocurrido una interrupción. El invocador puede aportar ON_ERROR_STOP o una transacción, y no se adjunta aquí dicho procedimiento. OBS01 se asigna por la matriz a la observación sin ID propio.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En la documentación U8 proponer aplicación atómica y detención ante error en copia; una prueba de fallo, si se realiza, debe inyectarse sólo en un script de prueba y una copia, nunca en las fuentes históricas ni la principal.

### RH11. Agrupación mensual TIMESTAMPTZ dependiente de TimeZone

**Decisión propuesta: aceptado.** Alcance: riesgo_temporal_historico, actual_condicionado_al_contrato_y_definicion_de_vista.

- `review_tp5:H4` — `work/antecedentes/TP5/Arancibia_Romero_TP5/views.sql`, líneas aproximadas 48-60; especialmente51y60. IA: «Esta forma de date_trunc utiliza la zona horaria de la sesión.»
- `review_u4_p1:H4` — `outputs/Arancibia_Romero_U4/antecedentes/views_tp5.sql`, líneas aproximadas 53y62; actividad_del_dia9y78 (copia saneada). IA: «El script de vistas no fija esa zona; la carga U4 sí la fija antes del refresco.»

**Fundamento.** Aceptar el riesgo de reproducción temporal y pedir contrato explícito. date_trunc('month', TIMESTAMPTZ) sin zona fija depende de la sesión del refresh. No se afirma que un reporte concreto haya estado errado ni que deba usarse Buenos Aires sin definir mes de negocio. U4 añade una caché diaria distinta: no asumir que eso cambia automáticamente la materializada mensual heredada.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En copia, inspeccionar pg_get_viewdef y comparar agrupaciones explícitas UTC y America/Argentina/Buenos_Aires con pedidos próximos al borde de mes. Si se prueba refresh, hacerlo sólo en copia con transacción revertida y registrar TimeZone. En las fuentes nuevas U8, fijar la zona elegida y no reescribir las entregas históricas.

### RH12. Proyecciones históricas no plenamente cubiertas por índices

**Decisión propuesta: aceptado.** Alcance: mejora_opcional_TP5, sin_regresion_demostrada.

- `review_tp5:OBS01` — `work/antecedentes/TP5/Arancibia_Romero_TP5/indices.sql`, líneas aproximadas 8-11;22-24; contraste queries.sql5-11;20-23. IA: «No afecta la correctitud y no justifica ampliar índices sin medir tamaño, lecturas y costo de escritura.»

**Fundamento.** Aceptar como oportunidad de medición, no como índice incorrecto. Q1 devuelve fecha original, ausente de su índice de expresión local; Q3 devuelve subtotal, ausente de su índice complementario. La visibilidad y el plan también intervienen: un INCLUDE adicional no garantiza Index Only Scan ni una mejora neta.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** Registrar planes, buffers, heap fetches, tamaño y costo de escritura en copia antes de decidir ampliar un índice. No duplicar índices ya presentes en el acumulado ni cambiar la principal.

### RH13. Detención del invocador psql ante errores de reconstrucción

**Decisión propuesta: aceptado.** Alcance: mejora_opcional_historica, dependencia_del_invocador.

- `review_tp5:OBS02` — `work/antecedentes/TP5/Arancibia_Romero_TP5/schema.sql y data.sql`, líneas aproximadas archivos completos; sin rango preciso en la observación. IA: «Es una mejora de reproducción condicionada al comando de ejecución, no un fallo probado del proceso completo.»

**Fundamento.** Proponer ON_ERROR_STOP en el invocador/documentación reproducible. Las transacciones de los scripts protegen persistencia parcial por errores SQL ordinarios, pero el código de salida esperado depende también del comando psql. El wrapper U4 puede ya aportar esa opción: no afirmar fallo sin leerlo.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En una copia de prueba y un script sintético de fallo, registrar código de salida con el invocador documentado; inspeccionar el wrapper U4 antes de clasificar la mejora como pendiente del acumulado. No modificar fuentes históricas.

### RH14. Aserciones de verificadores eliminables con Python optimizado

**Decisión propuesta: aceptado.** Alcance: fiabilidad_de_verificacion, condicional_a_O_OO_o_PYTHONOPTIMIZE, no_invalida_ejecucion_normal.

- `review_u4_p1:H2` — `outputs/Arancibia_Romero_U4/reproduccion/verify_fnbc.py`, líneas aproximadas 132-141;399-400;485-487 (copia saneada). IA: «Python elimina los assert al activar optimización.»
- `review_u4_p2:H1` — `outputs/Arancibia_Romero_U4/reproduccion/verify_foodstore.py`, líneas aproximadas 202-206;239-240;410-425;503-531 (copia saneada). IA: «El estado de aprobación deja de garantizar las condiciones que el verificador pretende comprobar.»

**Fundamento.** Aceptar el riesgo condicionado de ejecutar estos verificadores con optimización, no afirmar que las evidencias históricas ya sean falsas. Se hizo comprobación offline real: compilar sin importar/ejecutar fuentes produce13y30 LOAD_ASSERTION_ERROR con optimize0 y0conoptimize1/2. El falso aprobado integral sugerido por IA no fue reproducido por esta prueba estática.

**Prueba: compilacion_offline_confirmada; falso_aprobado_integral_no_ejecutado.** En nuevas herramientas U8 usar comprobaciones explícitas o rechazar sys.flags.optimize. La compilación estática está enlazada; si se ensaya el fallo integral, hacerlo en copia de verificador y base, sin alterar fuentes entregadas.

- Evidencia sin motor: [docs/evidencias/review_historicos_asserts_offline.json](docs/evidencias/review_historicos_asserts_offline.json). Compilación sin importar/ejecutar verificadores:13/30instruccionesassert normales,0conoptimize1/2. No es prueba SQL ni falso aprobado integral.

### RH15. Carga inicial confirmada antes de refresco que puede fallar

**Decisión propuesta: aceptado.** Alcance: recuperacion_de_laboratorio_U4, condicional_a_fallo_posterior_al_COMMIT.

- `review_u4_p1:H1` — `outputs/Arancibia_Romero_U4/01_actividad_del_dia.sql`, líneas aproximadas 13-22;74-78 (copia saneada). IA: «Una recuperación manual sigue siendo posible; no es pérdida irreversible.»

**Fundamento.** Aceptar una mejora de recuperación: el REFRESH explícito posterior al COMMIT no revierte carga si falla, y la guarda inicial impide repetir el archivo completo. No llamar incorrecta a la política deliberada de instantánea TP5 ni afirmar que el fallo ocurrió. La ejecución limpia documentada puede ser totalmente correcta.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** Documentar completar sólo el REFRESH cuando la carga se confirmó y falla ese paso. Para demostrar el escenario, usar lock_timeout y bloqueo únicamente en copia; registrar que filas persisten e instantánea conserva antigüedad, nunca hacerlo en principal.

### RH16. Carga por rango fijo depende del siguiente valor de identidad

**Decisión propuesta: aceptado.** Alcance: precondicion_de_carga_U4, condicional_a_consumo_previo_de_secuencia.

- `review_u4_p1:H3` — `outputs/Arancibia_Romero_U4/01_actividad_del_dia.sql`, líneas aproximadas 16-20;30-35;47;63-71 (copia saneada). IA: «Esto no demuestra que el respaldo adjunto tenga una secuencia incorrecta.»

**Fundamento.** Aceptar como precondición y riesgo de reintento tras fallo: cantidad/máximo no prueban el siguiente valor de identidad y rollback no recupera secuencias. No afirmar que el respaldo original estuviera mal ni que las filas históricas cambien; los controles finales normalmente rechazan la carga incoherente.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En copia restaurada, observar secuencia/identidad y el caso limpio; en otra copia consumir un ID y revertir antes de repetir. Proponer recuperar desde copia limpia o usar IDs realmente devueltos en una versión futura, sin corregir secuencias de la principal.

### RH17. Observación concurrente dependiente de pausa fija de dos segundos

**Decisión propuesta: aceptado.** Alcance: fiabilidad_de_prueba, falso_negativo_condicional_a_demora_del_controlador.

- `review_u4_p2:H2` — `outputs/Arancibia_Romero_U4/reproduccion/verify_foodstore.py`, líneas aproximadas 349-354;386-410 (copia saneada). IA: «La prueba falla aunque la serialización de la base sea correcta.»

**Fundamento.** Aceptar como oportunidad de coordinación determinista: un controlador lento puede no observar A en pg_sleep2 o iniciar B tarde. No demuestra una carrera de la MV ni invalida una corrida histórica que sí observó bloqueos y verificó datos. El verificador FNBC usa una coordinación distinta y no debe confundirse.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En arnés externo/copia introducir demora>2s antes del sondeo o entre observarA e iniciarB, y contrastar fallo de observación con auditoría independiente limpia. Proponer barrera explícita para herramientas nuevas, sin reescribir evidencia anterior.

### RH18. Matar cliente no confirma que su backend haya terminado

**Decisión propuesta: aceptado.** Alcance: hipotesis_de_recuperacion_ante_interrupcion, laboratorio_no_principal.

- `review_u4_p2:H3` — `outputs/Arancibia_Romero_U4/reproduccion/verify_foodstore.py`, líneas aproximadas 436-451; relacionado119-123 (copia saneada). IA: «No hay evidencia suficiente para afirmar que los precios queden alterados en una ejecución normal.»

**Fundamento.** Aceptar sólo como hipótesis de recuperación: process.kill finaliza psql y no confirma directamente el rollback/cierre del backend. El finally y la adquisición del bloqueo asesor son mitigaciones reales. No afirmar pérdida de restauración ni cambios persistentes sin ejecutar el escenario de fallo.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** Si se prueba, forzar timeout sólo en copia y observar desde otra conexión backend, bloqueos y auditoría final. Confirmar terminación de sesiones propias antes de declarar recuperación; no conceder permisos ni terminar sesiones ajenas.

### RH19. Índices parcialmente solapados con distintos INCLUDE

**Decisión propuesta: aceptado.** Alcance: mejora_opcional, costo_de_mantenimiento_sin_regresion_medida.

- `review_u4_p1:OBS01` — `outputs/Arancibia_Romero_U4/antecedentes/indices_tp4.sql y antecedentes/indices_tp5.sql`, líneas aproximadas 5-7y24-26 (copia saneada). IA: «No demuestra que alguno sea innecesario.»

**Fundamento.** Aceptar como medición opcional, no como duplicación semántica completa: comparten(producto_id,pedido_id) pero INCLUDE difiere(cantidad/subtotal frente a cantidad/precio_unitario). Cada cobertura puede servir consultas distintas y fusionarlas tiene costos propios.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En copia comparar tamaño, planes, uso y costo de escritura con las consultas originales antes de proponer consolidación. No eliminar índices de la principal ni prometer mejoras sin medición.

### RH20. Excepción por profundidad de trigger admite otros orígenes anidados

**Decisión propuesta: descartado.** Alcance: sin_camino_problematico_demostrado_en_proyecto, limite_condicional_a_extensiones.

- `review_u4_p3:H1` — `outputs/Arancibia_Romero_U4/tp_desnormalizacion_top_categorias.sql`, líneas aproximadas 109-119 (copia saneada). IA: «Una prueba con un trigger auxiliar únicamente demostraría la limitación del diseño, no que el proyecto actual la ejerza.»

**Fundamento.** Proponer descartar la etiqueta de defecto actual por falta de un origen externo que lo ejerza; conservar la limitación: pg_trigger_depth>1 no identifica detalle_pedido como origen. Antes de decisión final, inventariar triggers heredados que escriben pedido. Un trigger auxiliar nuevo no prueba que la entrega actual ya falle.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** Inspeccionar definiciones e inventario reales en copia. Si existe un camino externo a las cuatro fuentes instrumentadas que actualice fecha/eliminado, probar ese camino y auditar bilateralmente; no inventar una extensión y atribuir su fallo al proyecto original.

### RH21. Permisos del invocador para refrescar materializada desde un trigger

**Decisión propuesta: corregido.** Alcance: condicion_de_U4_aislada, mitigacion_estatica_explicita_en_U5, operacion_actual_por_confirmar.

- `review_u4_p3:H2` — `outputs/Arancibia_Romero_U4/tp_desnormalizacion_top_categorias.sql`, líneas aproximadas 105-122;124-150 (copia saneada). IA: «Tener autorización para modificar una tabla fuente no implica disponer de ese privilegio.»

**Fundamento.** Propuesta de corrección ya incorporada en la etapa U5: sql/roles.sql285-310 redefine u4_refrescar_ventas como SECURITY DEFINER, dueño rol_funciones, search_path fijo y GRANT MAINTAIN sólo sobre la MV diaria a ese rol. Esto se verificó por lectura local; no aconseja ampliar privilegios globales ni implica ejecutar nuevo cambio. Confirmar que la copia efectiva conserve esa política.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En copia inspeccionar SECURITY DEFINER/owner/search_path/MAINTAIN y realizar DML válido como rol real de aplicación, dentro de rollback. Enlazar evidencia U8 o U5 pertinente antes de decisión final sobre comportamiento efectivo.

### RH22. Consumo del reporte diario requiere conservar la zona de negocio

**Decisión propuesta: descartado.** Alcance: sin_error_demostrado_al_ejecutar_script_completo, precondicion_para_consumidores_externos.

- `review_u4_p3:H3` — `outputs/Arancibia_Romero_U4/tp_desnormalizacion_top_categorias.sql`, líneas aproximadas 9;55-56;67-75;154-166 (copia saneada). IA: «El script completo sí configura la zona adecuada.»

**Fundamento.** Proponer descartar como bug del script tal como está: configura Buenos Aires y la MV agrupa en esa zona. Mantener explícita la precondición cuando se copian consultas que usan CURRENT_DATE a otras conexiones. No confundir este consumo diario con el riesgo de la materializada mensual heredada RH11.

**Prueba: pendiente_de_ejecucion_o_enlace_por_equipo_u8.** En herramientas nuevas fijar fecha/zona de negocio. Si se comparan consumidores externos, usar parámetros de fecha y pedidos borde en copia; no depender del reloj real ni modificar configuraciones globales.

## Límites y operación

- No se afirman fallos de la aplicación sin contrastar el rol y los privilegios por columna.
- El primer TP2 falló al arrancar por SQLite `database is locked`, sin respuesta; su retry exitoso conserva metadatos de la tentativa.
- Los intentos previos de cola TP4/TP5 y la consulta monolítica U4 se difirieron en preflight: aquellos intentos no cuentan como revisiones. Las consultas reales posteriores se identifican en la tabla de cobertura. Unidad4 se dividió por archivos completos para mantener cada adjunto por debajo de40KB y evitar truncamiento.
- No se reescribieron los trabajos anteriores ni se ejecutaron scripts durante estas consultas. Las pruebas y decisiones finales se fusionan por el equipo Unidad8.

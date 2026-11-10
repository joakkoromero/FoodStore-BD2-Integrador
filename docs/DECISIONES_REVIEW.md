# Decisiones del integrador y ratificación humana

**Estado: ratificado por respuesta explícita del usuario.** Constancia y alcance en `REVISION_HUMANA.json`. No se firma por los integrantes ni se acredita una lectura que no hayan declarado.

## A. Review acumulado de todos los scripts

Se conservan los 43 grupos y las 64 referencias de la matriz tecnica de U8. Los fundamentos siguientes son decisiones técnicas verificadas; el usuario ratificó expresamente cada una y sus fundamentos presentados.

### RH01. Borrado del último detalle de un pedido cerrado en esquemas históricos

Referencias: review_tp1:H1, review_tp5:H1.

Decision tecnica: **descartado**. Descartado como defecto del acumulado actual: app_web intentó borrar el único detalle de un pedido final y recibió SQLSTATE23514. La guarda heredada TP2 ya impide ese cambio; no se modifica retrospectivamente TP1/TP5. Cada transacción terminó en ROLLBACK y cinco huellas de tablas iguales.

Evidencia: `unidad8/docs/evidencias/review_bd_antes_correccion.json`; `unidad8/docs/ia/review_tp1_respuesta.md`; `unidad8/docs/ia/review_tp5_respuesta.md`.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH02. Total almacenado escribible directamente

Referencias: review_tp1:H2, review_tp2:H2, review_tp3:H3, review_tp4:H2, review_tp5:H2.

Decision tecnica: **aceptado**. Se acepta la observación estructural para un escritor privilegiado del total, sin atribuirla a la app actual. La mitigación U5 se conserva: app_web UPDATE pedido.total fue rechazado42501 y la tabla quedó intacta. No se amplían permisos ni se afirma haber probado una explotación con propietario.

Evidencia: `unidad8/docs/evidencias/review_agregados_y_catalogo.json`; `unidad8/docs/evidencias/review_bd_antes_correccion.json`; `unidad8/docs/ia/review_tp1_respuesta.md`; `unidad8/docs/ia/review_tp2_respuesta.md`; `unidad8/docs/ia/review_tp3_respuesta.md`; `unidad8/docs/ia/review_tp4_respuesta.md`; `unidad8/docs/ia/review_tp5_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH03. Hipótesis de total perdido por concurrencia en esquema base

Referencias: review_tp1:H3, review_tp2:H3, review_tp3:H4, review_tp4:H4, review_tp5:H3.

Decision tecnica: **aceptado**. Se acepta sólo la hipótesis del AFTER aislado como límite de análisis, no una carrera demostrada del acumulado. El BEFORE heredado contiene FOR UPDATE; no se ejecutó una nueva prueba de dos sesiones en U8 ni se atribuyen resultados inexistentes. Se conserva ese bloqueo; no hay cambio de código basado únicamente en la hipótesis.

Evidencia: `unidad8/docs/evidencias/review_agregados_y_catalogo.json`; `unidad8/docs/ia/review_tp1_respuesta.md`; `unidad8/docs/ia/review_tp2_respuesta.md`; `unidad8/docs/ia/review_tp3_respuesta.md`; `unidad8/docs/ia/review_tp4_respuesta.md`; `unidad8/docs/ia/review_tp5_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH04. Inserción directa de CONFIRMADO/ENTREGADO sin líneas

Referencias: review_tp2:H1, review_tp3:H1, review_tp4:H1.

Decision tecnica: **corregido**. Confirmado en copia: el administrador pudo insertar CONFIRMADO sin líneas y se revirtió. app_web carece INSERT sobre estado; no se lo presenta como explotación de la app. La nueva guarda BEFORE INSERT exige PENDIENTE sólo en las copias U8. Después rechaza23514 y permite PENDIENTE con administrador bootstrap y app, con ROLLBACK y cinco huellas iguales. La segunda copia canónica también está corregida.

Evidencia: `unidad8/docs/evidencias/correccion_tp2_primera_ejecucion.json`; `unidad8/docs/evidencias/correccion_tp2_segunda_ejecucion.json`; `unidad8/docs/evidencias/review_bd_antes_correccion.json`; `unidad8/docs/evidencias/review_bd_despues_correccion_segunda.json`; `unidad8/docs/ia/review_tp2_respuesta.md`; `unidad8/docs/ia/review_tp3_respuesta.md`; `unidad8/docs/ia/review_tp4_respuesta.md`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH05. Orden de seed y restricciones estrictas

Referencias: review_tp3:H2, review_tp4:H3.

Decision tecnica: **descartado**. Se descarta como afirmación de entrega histórica fallida: la condición depende del orden de carga, que no se reprodujo en U8. Se conserva como precondición de reconstrucción; U8 parte explícitamente de la base acumulada y no ejecuta semillas antiguas sobre ella.

Evidencia: `unidad8/docs/ia/review_tp3_respuesta.md`; `unidad8/docs/ia/review_tp4_respuesta.md`.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH06. Cobertura de índice Q3 incompleta para id

Referencias: review_tp3:M1.

Decision tecnica: **aceptado**. Aceptar como candidato de medición, no defecto lógico ni promesa de mayor velocidad. El índice incluye usuario_id/total pero Q3 también devuelve id; un Index Only Scan depende además del mapa de visibilidad.

Evidencia: `unidad8/docs/ia/review_tp3_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH07. Alcance de mediciones antes/después de una corrida

Referencias: review_tp3:M2, review_tp4:OBS02, review_tp5:OBS03.

Decision tecnica: **aceptado**. Aceptar la limitación de generalización: una captura antes/después es evidencia del ensayo, pero no establece por sí sola causalidad universal ni rendimientos futuros. La revisión no contiene planes o tiempos adicionales que puedan inventarse.

Evidencia: `unidad8/docs/ia/review_tp3_respuesta.md`; `unidad8/docs/ia/review_tp4_respuesta.md`; `unidad8/docs/ia/review_tp5_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH08. Comentario de equivalencia: contadores cero, no cero filas

Referencias: review_tp3:M3.

Decision tecnica: **aceptado**. Se acepta y aclara la imprecisión documental: la consulta devuelve dos contadores y ambos deben valer cero, no cero filas. No se editó el script histórico ni se etiqueta su fuente como corregida; la aclaración queda en esta matriz.

Evidencia: `unidad8/docs/ia/review_tp3_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH09. Índice adicional por producto_id como oportunidad de medición

Referencias: review_tp1:OBS01.

Decision tecnica: **aceptado**. OBS01 es un identificador asignado por esta matriz a una observación sin H/M propio. La PK comienza por pedido_id; consultas sólo por producto_id podrían beneficiarse de otro índice. No se conoce un plan lento ni la necesidad actual; versiones posteriores ya agregan índices.

Evidencia: `unidad8/docs/ia/review_tp1_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH10. Instalación de restricciones no atómica ante interrupción

Referencias: review_tp4:OBS01.

Decision tecnica: **aceptado**. Aceptar como mejora de reproducción: el archivo elimina y vuelve a crear triggers sin una transacción envolvente propia. No se afirma que haya ocurrido una interrupción. El invocador puede aportar ON_ERROR_STOP o una transacción, y no se adjunta aquí dicho procedimiento. OBS01 se asigna por la matriz a la observación sin ID propio.

Evidencia: `unidad8/docs/ia/review_tp4_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH11. Agrupación mensual TIMESTAMPTZ dependiente de TimeZone

Referencias: review_tp5:H4, review_u4_p1:H4.

Decision tecnica: **aceptado**. Aceptar el riesgo de reproducción temporal y pedir contrato explícito. date_trunc('month', TIMESTAMPTZ) sin zona fija depende de la sesión del refresh. No se afirma que un reporte concreto haya estado errado ni que deba usarse Buenos Aires sin definir mes de negocio. U4 añade una caché diaria distinta: no asumir que eso cambia automáticamente la materializada mensual heredada.

Evidencia: `unidad8/docs/ia/review_tp5_respuesta.md`; `unidad8/docs/ia/review_u4_p1_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH12. Proyecciones históricas no plenamente cubiertas por índices

Referencias: review_tp5:OBS01.

Decision tecnica: **aceptado**. Aceptar como oportunidad de medición, no como índice incorrecto. Q1 devuelve fecha original, ausente de su índice de expresión local; Q3 devuelve subtotal, ausente de su índice complementario. La visibilidad y el plan también intervienen: un INCLUDE adicional no garantiza Index Only Scan ni una mejora neta.

Evidencia: `unidad8/docs/ia/review_tp5_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH13. Detención del invocador psql ante errores de reconstrucción

Referencias: review_tp5:OBS02.

Decision tecnica: **aceptado**. Se decide ON_ERROR_STOP en el invocador/documentación reproducible. Las transacciones de los scripts protegen persistencia parcial por errores SQL ordinarios, pero el código de salida esperado depende también del comando psql. El wrapper U4 puede ya aportar esa opción: no afirmar fallo sin leerlo.

Evidencia: `unidad8/docs/ia/review_tp5_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH14. Aserciones de verificadores eliminables con Python optimizado

Referencias: review_u4_p1:H2, review_u4_p2:H1.

Decision tecnica: **aceptado**. Aceptar el riesgo condicionado de ejecutar estos verificadores con optimización, no afirmar que las evidencias históricas ya sean falsas. Se hizo comprobación offline real: compilar sin importar/ejecutar fuentes produce13y30 LOAD_ASSERTION_ERROR con optimize0 y0conoptimize1/2. El falso aprobado integral sugerido por IA no fue reproducido por esta prueba estática.

Evidencia: `unidad8/docs/ia/review_u4_p1_respuesta.md`; `unidad8/docs/ia/review_u4_p2_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH15. Carga inicial confirmada antes de refresco que puede fallar

Referencias: review_u4_p1:H1.

Decision tecnica: **aceptado**. Aceptar una mejora de recuperación: el REFRESH explícito posterior al COMMIT no revierte carga si falla, y la guarda inicial impide repetir el archivo completo. No llamar incorrecta a la política deliberada de instantánea TP5 ni afirmar que el fallo ocurrió. La ejecución limpia documentada puede ser totalmente correcta.

Evidencia: `unidad8/docs/ia/review_u4_p1_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH16. Carga por rango fijo depende del siguiente valor de identidad

Referencias: review_u4_p1:H3.

Decision tecnica: **aceptado**. Aceptar como precondición y riesgo de reintento tras fallo: cantidad/máximo no prueban el siguiente valor de identidad y rollback no recupera secuencias. No afirmar que el respaldo original estuviera mal ni que las filas históricas cambien; los controles finales normalmente rechazan la carga incoherente.

Evidencia: `unidad8/docs/ia/review_u4_p1_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH17. Observación concurrente dependiente de pausa fija de dos segundos

Referencias: review_u4_p2:H2.

Decision tecnica: **aceptado**. Aceptar como oportunidad de coordinación determinista: un controlador lento puede no observar A en pg_sleep2 o iniciar B tarde. No demuestra una carrera de la MV ni invalida una corrida histórica que sí observó bloqueos y verificó datos. El verificador FNBC usa una coordinación distinta y no debe confundirse.

Evidencia: `unidad8/docs/ia/review_u4_p2_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH18. Matar cliente no confirma que su backend haya terminado

Referencias: review_u4_p2:H3.

Decision tecnica: **aceptado**. Aceptar sólo como hipótesis de recuperación: process.kill finaliza psql y no confirma directamente el rollback/cierre del backend. El finally y la adquisición del bloqueo asesor son mitigaciones reales. No afirmar pérdida de restauración ni cambios persistentes sin ejecutar el escenario de fallo.

Evidencia: `unidad8/docs/ia/review_u4_p2_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH19. Índices parcialmente solapados con distintos INCLUDE

Referencias: review_u4_p1:OBS01.

Decision tecnica: **aceptado**. Aceptar como medición opcional, no como duplicación semántica completa: comparten(producto_id,pedido_id) pero INCLUDE difiere(cantidad/subtotal frente a cantidad/precio_unitario). Cada cobertura puede servir consultas distintas y fusionarlas tiene costos propios.

Evidencia: `unidad8/docs/ia/review_u4_p1_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH20. Excepción por profundidad de trigger admite otros orígenes anidados

Referencias: review_u4_p3:H1.

Decision tecnica: **descartado**. Se descarta como defecto actual demostrado: la respuesta no identifica un recorrido externo existente que aproveche la profundidad del trigger. Se conserva la limitación de que pg_trigger_depth no identifica por sí solo el origen. app_web no puede crear objetos en public; no se añadió un trigger artificial para fabricar un fallo ni se afirma una prueba dinámica de esa hipótesis.

Evidencia: `unidad8/docs/evidencias/review_agregados_y_catalogo.json`; `unidad8/docs/ia/review_u4_p3_respuesta.md`.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH21. Permisos del invocador para refrescar materializada desde un trigger

Referencias: review_u4_p3:H2.

Decision tecnica: **descartado**. Descartado como fallo del estado actual porque U5 ya instaló SECURITY DEFINER, owner rol_funciones y MAINTAIN acotado a la materializada diaria. Se verificó el catálogo efectivo y un INSERT PENDIENTE como app completó sus triggers y se revirtió. No se modifica U5 ni se atribuye esta mitigación anterior a un cambio nuevo U8.

Evidencia: `unidad8/docs/evidencias/review_agregados_y_catalogo.json`; `unidad8/docs/evidencias/review_bd_despues_correccion_segunda.json`; `unidad8/docs/ia/review_u4_p3_respuesta.md`.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### RH22. Consumo del reporte diario requiere conservar la zona de negocio

Referencias: review_u4_p3:H3.

Decision tecnica: **descartado**. Se descarta como defecto del script diario completo: configura explícitamente la zona de Buenos Aires. Se conserva la precondición para consumidores externos que copien consultas con CURRENT_DATE; no se confunde con la materializada mensual heredada RH11, cuyo riesgo se acepta.

Evidencia: `unidad8/docs/ia/review_u4_p3_respuesta.md`.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA01. Una cadena sensible escapada podría sobrevivir en un valor JSON aunque no exista como subcadena literal del texto serializado.

Referencias: review_u5/H-01.

Decision tecnica: **aceptado**. Regresión local confirmada con una cadena exclusivamente sintética: después de sanear texto JSON, el valor decodificado conservaba la cadena escapada. No se cambió el original U5 y NO se lo marca como corregido; no se afirma filtración histórica. U8 conserva diagnósticos en privado y no envía logs con datos reales.

Evidencia: `unidad8/docs/evidencias/review_u5_json_escapado.json`; `unidad8/docs/ia/review_u5_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA02. La publicación de dos archivos no es atómica; puede quedar un dump huérfano. El selector no lo considera exitoso.

Referencias: review_u6/U6-01.

Decision tecnica: **aceptado**. Se acepta la publicación no atómica de dump/manifiesto como límite operativo. La prueba local real del selector rechazó un .dump ficticio huérfano con «No hay manifiesto exitoso», sin llamar clientes PG. No se transforma esa salvaguarda en negación del posible residuo ni en un falso éxito.

Evidencia: `unidad8/docs/evidencias/review_u6_selector_huerfano.json`; `unidad8/docs/ia/review_u6_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA03. Dos capas del mismo problema diagnóstico: excepciones locales sin causa detallada y stderr nativo descartado. Los fallos sí producen salida no cero.

Referencias: review_u6/U6-02, review_u6_c01/U6-C01-02.

Decision tecnica: **aceptado**. Los códigos de salida se comprueban, se lanza excepción y los llamadores terminan en 1. Capturar la causa permitiría distinguir errores, pero su almacenamiento debe ser privado y no debe publicar credenciales o valores de filas. Se agrupan las observaciones conservando ambos IDs originales. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u6_c01_respuesta.md`; `unidad8/docs/ia/review_u6_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA04. La validación del generador no cubre uniformemente prosa y adjuntos; un literal accidental en un informe podría publicarse.

Referencias: review_u6/U6-03.

Decision tecnica: **aceptado**. La observación distingue correctamente cobertura automática y contenido efectivo. Los controles finales de U6 incluyeron inspección y escaneo de valores privados conocidos sin coincidencias; esta revisión nueva no los reejecutó ni atribuye una exposición actual. Se propone comprobar la mejora con un marcador sintético, preservando el original. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u6_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA05. El reintento con igual prefijo sólo funciona si el fallo anterior no dejó respuesta parcial.

Referencias: review_u6_c01/U6-C01-01, review_u5_c04/U5-C04-01.

Decision tecnica: **aceptado**. El bloqueo protege evidencia existente frente a sobreescritura, pero la opción de reintento no abarca todos los fallos. Para U8 puede mantenerse la regla explícita de usar un prefijo nuevo cuando hay respuesta parcial o implementarse archivado íntegro antes del reintento. No se afirma una corrección que todavía no se hizo. Se conserva la referencia independiente que revisó el wrapper U5 y se agrupa con el mismo defecto revisado en U6. Una solución futura debe preservar respuesta parcial y metadatos antes de autorizar el reintento. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c04_respuesta.md`; `unidad8/docs/ia/review_u6_c01_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA06. El contador de líneas no interpretadas se conserva, pero no condiciona el estado completed.

Referencias: review_u6_c01/U6-C01-03.

Decision tecnica: **aceptado**. No toda línea no JSON demuestra pérdida de una respuesta. Conviene distinguir completed limpio y completed que requiere revisión, sin inventar fallos de las consultas actuales. Los metadatos de las cuatro consultas aquí consolidadas indican unparsed_line_count=0. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u6_c01_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA07. Un fallo del validador detiene la prueba y conserva el documento inesperado como residuo del laboratorio.

Referencias: review_u7/U7-01.

Decision tecnica: **aceptado**. Las salidas originales y el cierre prueban cinco documentos y cero inválidos persistidos en esta ejecución. La observación no exige borrar automáticamente la evidencia de una regresión ni cambiar fuentes congeladas. Para futuras pruebas que debiliten el validador debe usarse una colección o copia separada. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u7_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA08. El generador no fuerza la limpieza de Git; los controles independientes sí acreditan la correspondencia de esta entrega congelada.

Referencias: review_u7/U7-02.

Decision tecnica: **descartado**. La condición de cambios sin confirmar no ocurre: working tree limpio y git diff contra 8178b01 sin diferencias. JS/SQL coinciden byte a byte con el commit; EJSON conserva el mismo contenido con CRLF en el archivo ejecutado y LF normalizado en Git. Los tres hashes de los bytes ejecutados sí coinciden exactamente con validacion.json y los adjuntos. HEAD posterior incorpora cierre documental. La prueba es local y no se presenta como una prueba de motor.

Evidencia: `unidad8/docs/evidencias/qa_u7_congelamiento.json`; `unidad8/docs/ia/review_u7_respuesta.md`.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA09. El umbral fija una población concreta y podría divergir si se reutiliza el helper con otro conjunto de IDs.

Referencias: review_u5_c01/U5-C01-01.

Decision tecnica: **descartado**. Descartado como defecto de la población actual, manteniendo el límite de reutilización: PostgreSQL confirmó 20.000 IDs heredados1..20000 y sólo una cuenta posterior20001. La huella agregada heredada coincide con U5. No se exportaron filas, contactos ni verificadores de contraseñas.

Evidencia: `unidad8/docs/evidencias/review_agregados_y_catalogo.json`; `unidad8/docs/ia/review_u5_c01_respuesta.md`.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA10. Tres capas de precondiciones de logging parciales: ajuste de error, configuración por sesión y registro por duración.

Referencias: review_u5_c01/U5-C01-02, review_u5_c02/U5-C02-01, review_u5_c03/U5-C03-01.

Decision tecnica: **aceptado**. Se conservan los tres IDs y sus condiciones distintas. La parametrización impide interpolación SQL, pero no garantiza por sí sola que el servidor nunca registre valores. Las comprobaciones deberían incluir las vías y sesiones efectivamente usadas. Una prueba futura debe emplear exclusivamente centinelas sintéticos y guardar el diagnóstico privado. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c01_respuesta.md`; `unidad8/docs/ia/review_u5_c02_respuesta.md`; `unidad8/docs/ia/review_u5_c03_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA11. Una carpeta puede contener artefactos de una corrida fallida junto a un JSON anterior satisfactorio.

Referencias: review_u5_c01/U5-C01-03, review_u5_c05/U5-C05-01.

Decision tecnica: **aceptado**. El fallo del proceso sí se comunica. El riesgo reside en consumir archivos aislados sin correlacionar la ejecución. Para procedimientos nuevos se propone una carpeta por corrida y un manifiesto final; no se altera ni se regenera retrospectivamente la evidencia U5. Se agrupa con U5-C01-03 por la vigencia de artefactos. El proceso sí rechaza coincidencias o errores, pero un consumidor no debe interpretar el JSON viejo como estado del intento nuevo. La mejora usa resultados por corrida y marcador final explícito. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c01_respuesta.md`; `unidad8/docs/ia/review_u5_c05_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA12. Una regresión de privilegios podría persistir la membresía justo cuando la prueba detecta el éxito indebido.

Referencias: review_u5_c02/U5-C02-02.

Decision tecnica: **aceptado**. Se debe distinguir el comportamiento correcto probado del catálogo actual de la contención ante una regresión. La comprobación detecta la anomalía, pero debería ensayarse con roles descartables y rollback para no dejar una concesión inesperada. No se propone conceder roles reales de negocio para probarlo. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c02_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA13. Un helper de reset sin efecto podría superar esas aserciones positivas aunque conserve validaciones de entrada.

Referencias: review_u5_c02/U5-C02-03.

Decision tecnica: **aceptado**. La función y los permisos originales tienen otras verificaciones, pero esas llamadas concretas no prueban el efecto de reset. La mejora propuesta es autenticar con el valor temporal dentro de la misma transacción y revertir todo, conservando únicamente el ID booleano de resultado. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c02_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA14. Un NOTICE con contenido sensible podría salir por una vía distinta del saneamiento de DatabaseError.

Referencias: review_u5_c03/U5-C03-02.

Decision tecnica: **aceptado**. El saneamiento de errores es un control presente y diferente. En helpers nuevos debe definirse una política explícita de avisos o capturarse su salida sólo en almacenamiento privado. No se atribuye una filtración real a partir de la mera ausencia del callback. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c03_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA15. Determinadas entradas Markdown pueden perder asteriscos o sintaxis de enlaces en el PDF.

Referencias: review_u5_c03/U5-C03-03.

Decision tecnica: **aceptado**. La mejora debe proteger primero los fragmentos de código y procesar el resto del marcado después. El informe histórico se conserva; no se necesita regenerarlo para aceptar una mejora del renderizador de uso futuro. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c03_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA16. Un repositorio grande con muchos objetos pequeños puede superar un presupuesto razonable de memoria.

Referencias: review_u5_c03/U5-C03-04.

Decision tecnica: **aceptado**. El empaquetador ya inspecciona objetos, credenciales, CRC, manifiesto y restauración Git. Esta observación propone un límite acumulado o procesamiento incremental, no niega esas garantías ni exige construir grandes archivos para validar un laboratorio pequeño. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c03_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA17. Puede notificarse un fallo aunque la solicitud de rotación haya sido procesada, porque el nombre tiene resolución de segundos.

Referencias: review_u5_c04/U5-C04-02.

Decision tecnica: **aceptado**. El control de cambio de ruta es correcto para exigir una fuente cerrada. La mejora sería solicitar otra rotación al cruzar el segundo, dentro de un plazo acotado, no tomar pg_rotate_logfile()=true como prueba de cierre. Las evidencias originales se conservan. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c04_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### QA18. La verificación se interrumpe ante ese estado del árbol de trabajo y no genera evidencia nueva.

Referencias: review_u5_c05/U5-C05-02.

Decision tecnica: **aceptado**. El proceso no produce un falso éxito. Puede rechazarse explícitamente ese estado con un diagnóstico claro, manteniendo el análisis del contenido todavía conservado en Git. No se interpreta como archivo perdido ni como defecto de la entrega U5 limpia. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

Evidencia: `unidad8/docs/ia/review_u5_c05_respuesta.md`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### U801. Protección privada del respaldo y diagnóstico

Referencias: review_u8_pre/U8-01.

Decision tecnica: **corregido**. Mejora de robustez aplicada antes de datos: ACL explícita en Windows. Se corrigió también la premisa del review: Windows0700 tiene backport en Python3.12.4; no se afirma defecto ni exposición en el runtime3.12.14. ACL efectiva y propietarios permitidos se inspeccionaron en124elementos; OWNER RIGHTS representa al propietario ya verificado, no a una cuenta ajena.

Evidencia: `unidad8/docs/ia/review_u8_pre_respuesta.md`; `unidad8/docs/ia/review_u8_final_respuesta.md`; `unidad8/docs/evidencias/verificacion_acl_privada.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### U802. Alcance real de la evidencia de conservación

Referencias: review_u8_pre/U8-02.

Decision tecnica: **corregido**. Corregido: además del conteo, se comparan huellas completas de pedido y detalle y suma/huella del stock de todo el catálogo. Ambas ejecuciones pasaron. Se mantienen los límites: no prueba secuencias ni cambios transitorios de todo el clúster.

Evidencia: `unidad8/docs/ia/review_u8_pre_respuesta.md`; `unidad8/docs/ia/review_u8_final_respuesta.md`; `unidad8/docs/evidencias/reproduccion_u8.json`; `unidad8/docs/evidencias/segunda_ejecucion_comparacion.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### U803. Representatividad del historial C6

Referencias: review_u8_pre/U8-03.

Decision tecnica: **corregido**. Corregido: se omitió la inserción directa de un CONFLICTO artificial. C2 conserva dos UUID producidos por la simulación, suficientes para demostrar historia múltiple; el segundo pendiente simultáneo se rechaza por índice parcial. Nueve filas finales coinciden exactamente con la evidencia.

Evidencia: `unidad8/docs/ia/review_u8_pre_respuesta.md`; `unidad8/docs/ia/review_u8_final_respuesta.md`; `unidad8/docs/evidencias/reproduccion_u8.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

## B. Auditoria de seguridad U5

### SEG01. Confidencialidad del log y parametrizacion

Decision tecnica: **aceptado**. El registro nativo oculta parametros con los limites configurados, pero no garantiza ocultar secretos escritos como literales SQL. Se conserva el riesgo residual y se exige no introducir credenciales en sentencias registradas; la copia que se comparte se sanea. No se afirma una redaccion universal.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SEG02. Permisos ajenos preexistentes

Decision tecnica: **aceptado**. La matriz del laboratorio coincide exactamente con 44 ACL y tres membresias previstas. roles.sql no constituye un saneamiento universal de permisos arbitrarios de cualquier instalacion previa. Se conserva ese alcance y se exige revisar el inventario antes de aplicar en otro entorno.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SEG03. Canales temporales y limitacion de intentos

Decision tecnica: **aceptado**. La revision de seguridad identifico limites que el script de roles no resuelve por si solo, incluidos el canal temporal y la ausencia de limitacion de intentos. Se aceptan como riesgos residuales documentados; no se atribuye una mitigacion no implementada.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SEG04. Dar lectura general al rol de soporte

Decision tecnica: **descartado**. La alternativa solicitada para contrastar el diseno ampliaria datos accesibles sin ser necesaria para soporte. Se mantienen las seis columnas de contacto y UPDATE telefono, sin lectura de catalogo, pedidos ni created_at; el reset conserva su puente puntual. Se respeta el minimo privilegio.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SEG05. SELECT general de public para reportes

Decision tecnica: **descartado**. La alternativa solicitada concederia acceso general donde bastan las proyecciones autorizadas. Se conservan vistas y permisos puntuales; no se amplian privilegios por comodidad.

Decision humana: **descartado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

## C. Complementos nuevos del TPI

### SCH-01. El primer SPEC no enumeraba el contrato interno del manifiesto; Build adoptó explícitamente un esquema supuesto, incompatible con los campos U6 reales.

Origen: Codex line-by-line integration review. Componente: mantenimiento_programado.

Decision tecnica: **corregido**. El consumidor nuevo ahora usa database/file/size/sha256/startUtc/endUtc, subdirectorio backups y baseline de cinco MD5 de32 caracteres. No se modificó U6 ni se fabricaron manifiestos.

Evidencia: `complementos/mantenimiento_programado/SPEC_SCHEDULER.md`; `complementos/mantenimiento_programado/run_backup_job.ps1`; `complementos/mantenimiento_programado/ia/generacion_original/run_backup_job.ps1`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SCH-02. La propuesta requería DACL protegida incluso cuando la herencia sólo concedía los tres SID autorizados. El PGPASSFILE anterior tiene herencia y tres entradas privadas.

Origen: Codex local compatibility/privacy review. Componente: mantenimiento_programado.

Decision tecnica: **corregido**. Se validan todas las concesiones efectivas, permitiendo herencia de esos mismos SID; no se cambian permisos ni contenidos del PGPASSFILE.

Evidencia: `complementos/mantenimiento_programado/run_backup_job.ps1`; `complementos/mantenimiento_programado/README.md`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SCH-03. El consumidor no comprobaba previamente backups/logs existentes antes de delegar escrituras al backend opaco.

Origen: OpenCode scheduler_plan finding1. Componente: mantenimiento_programado.

Decision tecnica: **corregido**. Se requieren y verifican ambos directorios privados y sus cadenas antes de ejecutar U6 y justo antes de delegar. No se reparan ACL ajenas. No se observó una exposición real.

Evidencia: `complementos/mantenimiento_programado/run_backup_job.ps1`; `complementos/mantenimiento_programado/ia/scheduler_plan_respuesta.md`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SCH-04. Inventarios recursivos de JSON fuera del directorio contractual de manifiestos.

Origen: OpenCode scheduler_plan finding2. Componente: mantenimiento_programado.

Decision tecnica: **corregido**. Ambos inventarios se limitan a logs/*.manifest.json, sin recursión ni JSON de terceros.

Evidencia: `complementos/mantenimiento_programado/run_backup_job.ps1`; `complementos/mantenimiento_programado/ia/scheduler_plan_respuesta.md`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SCH-05. El patrón estricto de basename no estaba declarado en el primer contrato adjunto.

Origen: OpenCode scheduler_plan finding3. Componente: mantenimiento_programado.

Decision tecnica: **corregido**. Se confirmó localmente el patrón real New-RunToken de U6 y se agregó explícitamente a SPEC; se conserva la validación acotada. La corrección es del contrato/documentación, no de un nombre U6 defectuoso.

Evidencia: `complementos/mantenimiento_programado/SPEC_SCHEDULER.md`; `complementos/mantenimiento_programado/ia/scheduler_plan_respuesta.md`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SCH-06. Comprobación de reparse points/Git en ancestros sin verificar ACL capaces de sustituir objetos protegidos.

Origen: OpenCode scheduler_plan_final finding1. Componente: mantenimiento_programado.

Decision tecnica: **corregido**. Validación de propietarios y derechos efectivos peligrosos de ancestros, distinguiendo lectura/tránsito y ACE InheritOnly. Excepción TrustedInstaller sólo para ancestros del sistema; destinos privados mantienen lista restringida. El entorno observado no mostró derechos de sustitución a terceros.

Evidencia: `complementos/mantenimiento_programado/run_backup_job.ps1`; `complementos/mantenimiento_programado/SPEC_SCHEDULER.md`; `complementos/mantenimiento_programado/ia/scheduler_plan_final_respuesta.md`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### SCH-07. RegisterTask received a BSTR whose XML declaration said UTF-8, producing an encoding error before registration.

Origen: Real Windows COM registration failure0x8004131A, then OpenCode microPlan. Componente: mantenimiento_programado.

Decision tecnica: **corregido**. Deep clone DOM and remove only XmlDeclaration for the COM BSTR; preserve private UTF-8 file. MicroPlan complete336lines, then real daily task registration+automatic backup succeeded.

Evidencia: `complementos/mantenimiento_programado/crear_tarea_diaria.ps1`; `complementos/mantenimiento_programado/ia/scheduler_micro_codificacion_respuesta.md`; `complementos/mantenimiento_programado/evidencias/intento_registro_fallido/fallo_registro.json`; `complementos/mantenimiento_programado/evidencias/scheduler_ejecucion.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### FD01. El runner suponia dump junto al manifiesto; U6 real usa logs/ y backups/ hermanos.

Origen: Codex y QA independiente sobre Build. Componente: migracion_fnbc.

Decision tecnica: **corregido**. Resolver exclusivamente basename seguro en ubicaciones conocidas, exigir candidato unico y comprobar formato, bytes y SHA256; no modificar manifiesto real.

Evidencia: `complementos/migracion_fnbc/reproducir.py`; `complementos/migracion_fnbc/README.md`; `complementos/migracion_fnbc/ia/generacion_original/reproducir.py`; `complementos/migracion_fnbc/../../docs/evidencias_tpi/migracion_fnbc.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### FD02. El runner exigia64hex a baseline.fingerprints; la receta real U6 es MD5 de32, distinta del SHA256 del dump.

Origen: Codex y QA independiente sobre Build. Componente: migracion_fnbc.

Decision tecnica: **corregido**. Validar MD5 de32 en baseline y mantener SHA256 de64 para el dump. No comparar recetas diferentes ni falsificar hashes.

Evidencia: `complementos/migracion_fnbc/reproducir.py`; `complementos/migracion_fnbc/README.md`; `complementos/migracion_fnbc/ia/generacion_original/reproducir.py`; `complementos/migracion_fnbc/../../docs/evidencias_tpi/migracion_fnbc.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### FD03. La puerta de provenance exigia campos que el wrapper real no genera, como mode,tool_events y decision de Plan.

Origen: Codex y QA independiente sobre Build. Componente: migracion_fnbc.

Decision tecnica: **corregido**. Leer pure,permission_config,tool_event_count,kiro_specs_frozen_before_call y demas campos reales; mantener originales y separar cobertura/decision automatizada Codex de los metadatos del proveedor.

Evidencia: `complementos/migracion_fnbc/reproducir.py`; `complementos/migracion_fnbc/README.md`; `complementos/migracion_fnbc/ia/migracion_build_metadatos.json`; `complementos/migracion_fnbc/../../docs/evidencias_tpi/migracion_fnbc.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### FD04. La negativa FD invocaba solo fn_check_fd_rd, sin intentar el cuerpo real de migracion.

Origen: QA independiente sobre runner Build. Componente: migracion_fnbc.

Decision tecnica: **corregido**. Ejecutar el MISMO migrar.sql dentro del caso negativo; capturar23514 y verificar rollback/catalogo/objetos intactos.

Evidencia: `complementos/migracion_fnbc/reproducir.py`; `complementos/migracion_fnbc/migrar.sql`; `complementos/migracion_fnbc/ia/generacion_original/reproducir.py`; `complementos/migracion_fnbc/../../docs/evidencias_tpi/migracion_fnbc.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### FD05. Construir manualmente el indice de revision real agregaba riesgo operativo de campos inventados o fuentes no coincidentes.

Origen: Codex, reproducibilidad complementaria. Componente: migracion_fnbc.

Decision tecnica: **aceptado**. Agregar preparar_proveniencia.py, helper Codex sin conexiones, incluido entre las seis fuentes y en Plan. Exige flag tecnico explicito; no afirma revision humana.

Evidencia: `complementos/migracion_fnbc/preparar_proveniencia.py`; `complementos/migracion_fnbc/reproducir.py`; `complementos/migracion_fnbc/README.md`; `complementos/migracion_fnbc/../../docs/evidencias_tpi/migracion_fnbc.json`.

Decision humana: **aceptado**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### FD06. El Build agrupaba las cinco huellas como cuatro tablas de control y una agregacion del resto, lo que dificultaba verificar las cinco tablas centrales de Food Store por separado.

Origen: Codex, precision de evidencia RF08. Componente: migracion_fnbc.

Decision tecnica: **corregido**. Informar categoria/producto/usuario/pedido/detalle_pedido individualmente y una sexta huella de extensiones/catalogo; conservar la proteccion mas amplia.

Evidencia: `complementos/migracion_fnbc/reproducir.py`; `complementos/migracion_fnbc/README.md`; `complementos/migracion_fnbc/../../docs/evidencias_tpi/migracion_fnbc.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

### FD07. La validacion de SAVEPOINT [a-z_]+ rechazaba los digitos presentes en nombres internos que incluyen SQLSTATE23505/25006, abortando las pruebas antes del SQL.

Origen: OpenCode Plan pre, hallazgo1; cobertura completa de seis fuentes. Componente: migracion_fnbc.

Decision tecnica: **corregido**. Permitir [a-z_][a-z0-9_]* para identificadores internos, manteniendo exclusion de espacios/separadores y primer digito; renovar hashes y review FULL final antes de ejecutar.

Evidencia: `complementos/migracion_fnbc/reproducir.py`; `complementos/migracion_fnbc/ia/migracion_plan_pre_respuesta.md`; `complementos/migracion_fnbc/ia/migracion_plan_pre_metadatos.json`; `complementos/migracion_fnbc/../../docs/evidencias_tpi/migracion_fnbc.json`.

Decision humana: **corregido**. Ratificada expresamente por el usuario junto con el fundamento presentado; constancia en `REVISION_HUMANA.json`.

## Alcance de la ratificacion

Ante un incidente real confirmado: preservar evidencia y evaluar restringir app_web con intervencion responsable. No ejecutar contencion automaticamente.

Se requiere que el equipo lea y comprenda los scripts y las evidencias, confirme o cambie las decisiones y pueda explicarlas en la defensa. No se acredita automaticamente esa lectura por generar este documento.

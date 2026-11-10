# Revisión final de la cursada: decisiones técnicas

Registro final de Codex. No representa una firma humana del equipo. Revisión estática completa: **83 fuentes anteriores y 7 fuentes U8**. **43 grupos, 64 referencias originales, todas con decisión**. Los registros de propuestas se preservan como trazabilidad y son reemplazados por esta disposición final.

Los tres contrastes desarrollados en PostgreSQL son: último detalle final rechazado23514; UPDATE total bajo app rechazado42501; INSERT final vacío del administrador aceptado antes y rechazado23514 después de la guarda. Todos con rollback y huellas de cinco tablas iguales. Las recomendaciones estáticas restantes tienen ese alcance explícito; no se inventa la ejecución de sus escenarios condicionales.

| Grupo | Referencias originales | Hallazgo / observación | Decisión final | Comprobación y alcance |
|---|---|---|---|---|
| RH01 | review_tp1:H1, review_tp5:H1 | Borrado del último detalle de un pedido cerrado en esquemas históricos | descartado | Descartado como defecto del acumulado actual: app_web intentó borrar el único detalle de un pedido final y recibió SQLSTATE23514. La guarda heredada TP2 ya impide ese cambio; no se modifica retrospectivamente TP1/TP5. Cada transacción terminó en ROLLBACK y cinco huellas de tablas iguales. |
| RH02 | review_tp1:H2, review_tp2:H2, review_tp3:H3, review_tp4:H2, review_tp5:H2 | Total almacenado escribible directamente | aceptado | Se acepta la observación estructural para un escritor privilegiado del total, sin atribuirla a la app actual. La mitigación U5 se conserva: app_web UPDATE pedido.total fue rechazado42501 y la tabla quedó intacta. No se amplían permisos ni se afirma haber probado una explotación con propietario. |
| RH03 | review_tp1:H3, review_tp2:H3, review_tp3:H4, review_tp4:H4, review_tp5:H3 | Hipótesis de total perdido por concurrencia en esquema base | aceptado | Se acepta sólo la hipótesis del AFTER aislado como límite de análisis, no una carrera demostrada del acumulado. El BEFORE heredado contiene FOR UPDATE; no se ejecutó una nueva prueba de dos sesiones en U8 ni se atribuyen resultados inexistentes. Se conserva ese bloqueo; no hay cambio de código basado únicamente en la hipótesis. |
| RH04 | review_tp2:H1, review_tp3:H1, review_tp4:H1 | Inserción directa de CONFIRMADO/ENTREGADO sin líneas | corregido | Confirmado en copia: el administrador pudo insertar CONFIRMADO sin líneas y se revirtió. app_web carece INSERT sobre estado; no se lo presenta como explotación de la app. La nueva guarda BEFORE INSERT exige PENDIENTE sólo en las copias U8. Después rechaza23514 y permite PENDIENTE con administrador bootstrap y app, con ROLLBACK y cinco huellas iguales. La segunda copia canónica también está corregida. |
| RH05 | review_tp3:H2, review_tp4:H3 | Orden de seed y restricciones estrictas | descartado | Se descarta como afirmación de entrega histórica fallida: la condición depende del orden de carga, que no se reprodujo en U8. Se conserva como precondición de reconstrucción; U8 parte explícitamente de la base acumulada y no ejecuta semillas antiguas sobre ella. |
| RH06 | review_tp3:M1 | Cobertura de índice Q3 incompleta para id | aceptado | Aceptar como candidato de medición, no defecto lógico ni promesa de mayor velocidad. El índice incluye usuario_id/total pero Q3 también devuelve id; un Index Only Scan depende además del mapa de visibilidad. |
| RH07 | review_tp3:M2, review_tp4:OBS02, review_tp5:OBS03 | Alcance de mediciones antes/después de una corrida | aceptado | Aceptar la limitación de generalización: una captura antes/después es evidencia del ensayo, pero no establece por sí sola causalidad universal ni rendimientos futuros. La revisión no contiene planes o tiempos adicionales que puedan inventarse. |
| RH08 | review_tp3:M3 | Comentario de equivalencia: contadores cero, no cero filas | aceptado | Se acepta y aclara la imprecisión documental: la consulta devuelve dos contadores y ambos deben valer cero, no cero filas. No se editó el script histórico ni se etiqueta su fuente como corregida; la aclaración queda en esta matriz. |
| RH09 | review_tp1:OBS01 | Índice adicional por producto_id como oportunidad de medición | aceptado | OBS01 es un identificador asignado por esta matriz a una observación sin H/M propio. La PK comienza por pedido_id; consultas sólo por producto_id podrían beneficiarse de otro índice. No se conoce un plan lento ni la necesidad actual; versiones posteriores ya agregan índices. |
| RH10 | review_tp4:OBS01 | Instalación de restricciones no atómica ante interrupción | aceptado | Aceptar como mejora de reproducción: el archivo elimina y vuelve a crear triggers sin una transacción envolvente propia. No se afirma que haya ocurrido una interrupción. El invocador puede aportar ON_ERROR_STOP o una transacción, y no se adjunta aquí dicho procedimiento. OBS01 se asigna por la matriz a la observación sin ID propio. |
| RH11 | review_tp5:H4, review_u4_p1:H4 | Agrupación mensual TIMESTAMPTZ dependiente de TimeZone | aceptado | Aceptar el riesgo de reproducción temporal y pedir contrato explícito. date_trunc('month', TIMESTAMPTZ) sin zona fija depende de la sesión del refresh. No se afirma que un reporte concreto haya estado errado ni que deba usarse Buenos Aires sin definir mes de negocio. U4 añade una caché diaria distinta: no asumir que eso cambia automáticamente la materializada mensual heredada. |
| RH12 | review_tp5:OBS01 | Proyecciones históricas no plenamente cubiertas por índices | aceptado | Aceptar como oportunidad de medición, no como índice incorrecto. Q1 devuelve fecha original, ausente de su índice de expresión local; Q3 devuelve subtotal, ausente de su índice complementario. La visibilidad y el plan también intervienen: un INCLUDE adicional no garantiza Index Only Scan ni una mejora neta. |
| RH13 | review_tp5:OBS02 | Detención del invocador psql ante errores de reconstrucción | aceptado | Se decide ON_ERROR_STOP en el invocador/documentación reproducible. Las transacciones de los scripts protegen persistencia parcial por errores SQL ordinarios, pero el código de salida esperado depende también del comando psql. El wrapper U4 puede ya aportar esa opción: no afirmar fallo sin leerlo. |
| RH14 | review_u4_p1:H2, review_u4_p2:H1 | Aserciones de verificadores eliminables con Python optimizado | aceptado | Aceptar el riesgo condicionado de ejecutar estos verificadores con optimización, no afirmar que las evidencias históricas ya sean falsas. Se hizo comprobación offline real: compilar sin importar/ejecutar fuentes produce13y30 LOAD_ASSERTION_ERROR con optimize0 y0conoptimize1/2. El falso aprobado integral sugerido por IA no fue reproducido por esta prueba estática. |
| RH15 | review_u4_p1:H1 | Carga inicial confirmada antes de refresco que puede fallar | aceptado | Aceptar una mejora de recuperación: el REFRESH explícito posterior al COMMIT no revierte carga si falla, y la guarda inicial impide repetir el archivo completo. No llamar incorrecta a la política deliberada de instantánea TP5 ni afirmar que el fallo ocurrió. La ejecución limpia documentada puede ser totalmente correcta. |
| RH16 | review_u4_p1:H3 | Carga por rango fijo depende del siguiente valor de identidad | aceptado | Aceptar como precondición y riesgo de reintento tras fallo: cantidad/máximo no prueban el siguiente valor de identidad y rollback no recupera secuencias. No afirmar que el respaldo original estuviera mal ni que las filas históricas cambien; los controles finales normalmente rechazan la carga incoherente. |
| RH17 | review_u4_p2:H2 | Observación concurrente dependiente de pausa fija de dos segundos | aceptado | Aceptar como oportunidad de coordinación determinista: un controlador lento puede no observar A en pg_sleep2 o iniciar B tarde. No demuestra una carrera de la MV ni invalida una corrida histórica que sí observó bloqueos y verificó datos. El verificador FNBC usa una coordinación distinta y no debe confundirse. |
| RH18 | review_u4_p2:H3 | Matar cliente no confirma que su backend haya terminado | aceptado | Aceptar sólo como hipótesis de recuperación: process.kill finaliza psql y no confirma directamente el rollback/cierre del backend. El finally y la adquisición del bloqueo asesor son mitigaciones reales. No afirmar pérdida de restauración ni cambios persistentes sin ejecutar el escenario de fallo. |
| RH19 | review_u4_p1:OBS01 | Índices parcialmente solapados con distintos INCLUDE | aceptado | Aceptar como medición opcional, no como duplicación semántica completa: comparten(producto_id,pedido_id) pero INCLUDE difiere(cantidad/subtotal frente a cantidad/precio_unitario). Cada cobertura puede servir consultas distintas y fusionarlas tiene costos propios. |
| RH20 | review_u4_p3:H1 | Excepción por profundidad de trigger admite otros orígenes anidados | descartado | Se descarta como defecto actual demostrado: la respuesta no identifica un recorrido externo existente que aproveche la profundidad del trigger. Se conserva la limitación de que pg_trigger_depth no identifica por sí solo el origen. app_web no puede crear objetos en public; no se añadió un trigger artificial para fabricar un fallo ni se afirma una prueba dinámica de esa hipótesis. |
| RH21 | review_u4_p3:H2 | Permisos del invocador para refrescar materializada desde un trigger | descartado | Descartado como fallo del estado actual porque U5 ya instaló SECURITY DEFINER, owner rol_funciones y MAINTAIN acotado a la materializada diaria. Se verificó el catálogo efectivo y un INSERT PENDIENTE como app completó sus triggers y se revirtió. No se modifica U5 ni se atribuye esta mitigación anterior a un cambio nuevo U8. |
| RH22 | review_u4_p3:H3 | Consumo del reporte diario requiere conservar la zona de negocio | descartado | Se descarta como defecto del script diario completo: configura explícitamente la zona de Buenos Aires. Se conserva la precondición para consumidores externos que copien consultas con CURRENT_DATE; no se confunde con la materializada mensual heredada RH11, cuyo riesgo se acepta. |
| QA01 | review_u5/H-01 | Una cadena sensible escapada podría sobrevivir en un valor JSON aunque no exista como subcadena literal del texto serializado. | aceptado | Regresión local confirmada con una cadena exclusivamente sintética: después de sanear texto JSON, el valor decodificado conservaba la cadena escapada. No se cambió el original U5 y NO se lo marca como corregido; no se afirma filtración histórica. U8 conserva diagnósticos en privado y no envía logs con datos reales. |
| QA02 | review_u6/U6-01 | La publicación de dos archivos no es atómica; puede quedar un dump huérfano. El selector no lo considera exitoso. | aceptado | Se acepta la publicación no atómica de dump/manifiesto como límite operativo. La prueba local real del selector rechazó un .dump ficticio huérfano con «No hay manifiesto exitoso», sin llamar clientes PG. No se transforma esa salvaguarda en negación del posible residuo ni en un falso éxito. |
| QA03 | review_u6/U6-02, review_u6_c01/U6-C01-02 | Dos capas del mismo problema diagnóstico: excepciones locales sin causa detallada y stderr nativo descartado. Los fallos sí producen salida no cero. | aceptado | Los códigos de salida se comprueban, se lanza excepción y los llamadores terminan en 1. Capturar la causa permitiría distinguir errores, pero su almacenamiento debe ser privado y no debe publicar credenciales o valores de filas. Se agrupan las observaciones conservando ambos IDs originales. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA04 | review_u6/U6-03 | La validación del generador no cubre uniformemente prosa y adjuntos; un literal accidental en un informe podría publicarse. | aceptado | La observación distingue correctamente cobertura automática y contenido efectivo. Los controles finales de U6 incluyeron inspección y escaneo de valores privados conocidos sin coincidencias; esta revisión nueva no los reejecutó ni atribuye una exposición actual. Se propone comprobar la mejora con un marcador sintético, preservando el original. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA05 | review_u6_c01/U6-C01-01, review_u5_c04/U5-C04-01 | El reintento con igual prefijo sólo funciona si el fallo anterior no dejó respuesta parcial. | aceptado | El bloqueo protege evidencia existente frente a sobreescritura, pero la opción de reintento no abarca todos los fallos. Para U8 puede mantenerse la regla explícita de usar un prefijo nuevo cuando hay respuesta parcial o implementarse archivado íntegro antes del reintento. No se afirma una corrección que todavía no se hizo. Se conserva la referencia independiente que revisó el wrapper U5 y se agrupa con el mismo defecto revisado en U6. Una solución futura debe preservar respuesta parcial y metadatos antes de autorizar el reintento. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA06 | review_u6_c01/U6-C01-03 | El contador de líneas no interpretadas se conserva, pero no condiciona el estado completed. | aceptado | No toda línea no JSON demuestra pérdida de una respuesta. Conviene distinguir completed limpio y completed que requiere revisión, sin inventar fallos de las consultas actuales. Los metadatos de las cuatro consultas aquí consolidadas indican unparsed_line_count=0. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA07 | review_u7/U7-01 | Un fallo del validador detiene la prueba y conserva el documento inesperado como residuo del laboratorio. | aceptado | Las salidas originales y el cierre prueban cinco documentos y cero inválidos persistidos en esta ejecución. La observación no exige borrar automáticamente la evidencia de una regresión ni cambiar fuentes congeladas. Para futuras pruebas que debiliten el validador debe usarse una colección o copia separada. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA08 | review_u7/U7-02 | El generador no fuerza la limpieza de Git; los controles independientes sí acreditan la correspondencia de esta entrega congelada. | descartado | La condición de cambios sin confirmar no ocurre: working tree limpio y git diff contra 8178b01 sin diferencias. JS/SQL coinciden byte a byte con el commit; EJSON conserva el mismo contenido con CRLF en el archivo ejecutado y LF normalizado en Git. Los tres hashes de los bytes ejecutados sí coinciden exactamente con validacion.json y los adjuntos. HEAD posterior incorpora cierre documental. La prueba es local y no se presenta como una prueba de motor. |
| QA09 | review_u5_c01/U5-C01-01 | El umbral fija una población concreta y podría divergir si se reutiliza el helper con otro conjunto de IDs. | descartado | Descartado como defecto de la población actual, manteniendo el límite de reutilización: PostgreSQL confirmó 20.000 IDs heredados1..20000 y sólo una cuenta posterior20001. La huella agregada heredada coincide con U5. No se exportaron filas, contactos ni verificadores de contraseñas. |
| QA10 | review_u5_c01/U5-C01-02, review_u5_c02/U5-C02-01, review_u5_c03/U5-C03-01 | Tres capas de precondiciones de logging parciales: ajuste de error, configuración por sesión y registro por duración. | aceptado | Se conservan los tres IDs y sus condiciones distintas. La parametrización impide interpolación SQL, pero no garantiza por sí sola que el servidor nunca registre valores. Las comprobaciones deberían incluir las vías y sesiones efectivamente usadas. Una prueba futura debe emplear exclusivamente centinelas sintéticos y guardar el diagnóstico privado. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA11 | review_u5_c01/U5-C01-03, review_u5_c05/U5-C05-01 | Una carpeta puede contener artefactos de una corrida fallida junto a un JSON anterior satisfactorio. | aceptado | El fallo del proceso sí se comunica. El riesgo reside en consumir archivos aislados sin correlacionar la ejecución. Para procedimientos nuevos se propone una carpeta por corrida y un manifiesto final; no se altera ni se regenera retrospectivamente la evidencia U5. Se agrupa con U5-C01-03 por la vigencia de artefactos. El proceso sí rechaza coincidencias o errores, pero un consumidor no debe interpretar el JSON viejo como estado del intento nuevo. La mejora usa resultados por corrida y marcador final explícito. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA12 | review_u5_c02/U5-C02-02 | Una regresión de privilegios podría persistir la membresía justo cuando la prueba detecta el éxito indebido. | aceptado | Se debe distinguir el comportamiento correcto probado del catálogo actual de la contención ante una regresión. La comprobación detecta la anomalía, pero debería ensayarse con roles descartables y rollback para no dejar una concesión inesperada. No se propone conceder roles reales de negocio para probarlo. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA13 | review_u5_c02/U5-C02-03 | Un helper de reset sin efecto podría superar esas aserciones positivas aunque conserve validaciones de entrada. | aceptado | La función y los permisos originales tienen otras verificaciones, pero esas llamadas concretas no prueban el efecto de reset. La mejora propuesta es autenticar con el valor temporal dentro de la misma transacción y revertir todo, conservando únicamente el ID booleano de resultado. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA14 | review_u5_c03/U5-C03-02 | Un NOTICE con contenido sensible podría salir por una vía distinta del saneamiento de DatabaseError. | aceptado | El saneamiento de errores es un control presente y diferente. En helpers nuevos debe definirse una política explícita de avisos o capturarse su salida sólo en almacenamiento privado. No se atribuye una filtración real a partir de la mera ausencia del callback. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA15 | review_u5_c03/U5-C03-03 | Determinadas entradas Markdown pueden perder asteriscos o sintaxis de enlaces en el PDF. | aceptado | La mejora debe proteger primero los fragmentos de código y procesar el resto del marcado después. El informe histórico se conserva; no se necesita regenerarlo para aceptar una mejora del renderizador de uso futuro. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA16 | review_u5_c03/U5-C03-04 | Un repositorio grande con muchos objetos pequeños puede superar un presupuesto razonable de memoria. | aceptado | El empaquetador ya inspecciona objetos, credenciales, CRC, manifiesto y restauración Git. Esta observación propone un límite acumulado o procesamiento incremental, no niega esas garantías ni exige construir grandes archivos para validar un laboratorio pequeño. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA17 | review_u5_c04/U5-C04-02 | Puede notificarse un fallo aunque la solicitud de rotación haya sido procesada, porque el nombre tiene resolución de segundos. | aceptado | El control de cambio de ruta es correcto para exigir una fuente cerrada. La mejora sería solicitar otra rotación al cruzar el segundo, dentro de un plazo acotado, no tomar pg_rotate_logfile()=true como prueba de cierre. Las evidencias originales se conservan. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| QA18 | review_u5_c05/U5-C05-02 | La verificación se interrumpe ante ese estado del árbol de trabajo y no genera evidencia nueva. | aceptado | El proceso no produce un falso éxito. Puede rechazarse explícitamente ese estado con un diagnóstico claro, manteniendo el análisis del contenido todavía conservado en Git. No se interpreta como archivo perdido ni como defecto de la entrega U5 limpia. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados. |
| U801 | review_u8_pre/U8-01 | Protección privada del respaldo y diagnóstico | corregido | Mejora de robustez aplicada antes de datos: ACL explícita en Windows. Se corrigió también la premisa del review: Windows0700 tiene backport en Python3.12.4; no se afirma defecto ni exposición en el runtime3.12.14. ACL efectiva y propietarios permitidos se inspeccionaron en124elementos; OWNER RIGHTS representa al propietario ya verificado, no a una cuenta ajena. |
| U802 | review_u8_pre/U8-02 | Alcance real de la evidencia de conservación | corregido | Corregido: además del conteo, se comparan huellas completas de pedido y detalle y suma/huella del stock de todo el catálogo. Ambas ejecuciones pasaron. Se mantienen los límites: no prueba secuencias ni cambios transitorios de todo el clúster. |
| U803 | review_u8_pre/U8-03 | Representatividad del historial C6 | corregido | Corregido: se omitió la inserción directa de un CONFLICTO artificial. C2 conserva dos UUID producidos por la simulación, suficientes para demostrar historia múltiple; el segundo pendiente simultáneo se rechaza por índice parcial. Nueve filas finales coinciden exactamente con la evidencia. |

## Correspondencia por referencia original

| ID original | Grupo | Decisión final | Respuesta fiel |
|---|---|---|---|
| review_tp1:H1 | RH01 | descartado | docs/ia/review_tp1_respuesta.md |
| review_tp5:H1 | RH01 | descartado | docs/ia/review_tp5_respuesta.md |
| review_tp1:H2 | RH02 | aceptado | docs/ia/review_tp1_respuesta.md |
| review_tp2:H2 | RH02 | aceptado | docs/ia/review_tp2_respuesta.md |
| review_tp3:H3 | RH02 | aceptado | docs/ia/review_tp3_respuesta.md |
| review_tp4:H2 | RH02 | aceptado | docs/ia/review_tp4_respuesta.md |
| review_tp5:H2 | RH02 | aceptado | docs/ia/review_tp5_respuesta.md |
| review_tp1:H3 | RH03 | aceptado | docs/ia/review_tp1_respuesta.md |
| review_tp2:H3 | RH03 | aceptado | docs/ia/review_tp2_respuesta.md |
| review_tp3:H4 | RH03 | aceptado | docs/ia/review_tp3_respuesta.md |
| review_tp4:H4 | RH03 | aceptado | docs/ia/review_tp4_respuesta.md |
| review_tp5:H3 | RH03 | aceptado | docs/ia/review_tp5_respuesta.md |
| review_tp2:H1 | RH04 | corregido | docs/ia/review_tp2_respuesta.md |
| review_tp3:H1 | RH04 | corregido | docs/ia/review_tp3_respuesta.md |
| review_tp4:H1 | RH04 | corregido | docs/ia/review_tp4_respuesta.md |
| review_tp3:H2 | RH05 | descartado | docs/ia/review_tp3_respuesta.md |
| review_tp4:H3 | RH05 | descartado | docs/ia/review_tp4_respuesta.md |
| review_tp3:M1 | RH06 | aceptado | docs/ia/review_tp3_respuesta.md |
| review_tp3:M2 | RH07 | aceptado | docs/ia/review_tp3_respuesta.md |
| review_tp4:OBS02 | RH07 | aceptado | docs/ia/review_tp4_respuesta.md |
| review_tp5:OBS03 | RH07 | aceptado | docs/ia/review_tp5_respuesta.md |
| review_tp3:M3 | RH08 | aceptado | docs/ia/review_tp3_respuesta.md |
| review_tp1:OBS01 | RH09 | aceptado | docs/ia/review_tp1_respuesta.md |
| review_tp4:OBS01 | RH10 | aceptado | docs/ia/review_tp4_respuesta.md |
| review_tp5:H4 | RH11 | aceptado | docs/ia/review_tp5_respuesta.md |
| review_u4_p1:H4 | RH11 | aceptado | docs/ia/review_u4_p1_respuesta.md |
| review_tp5:OBS01 | RH12 | aceptado | docs/ia/review_tp5_respuesta.md |
| review_tp5:OBS02 | RH13 | aceptado | docs/ia/review_tp5_respuesta.md |
| review_u4_p1:H2 | RH14 | aceptado | docs/ia/review_u4_p1_respuesta.md |
| review_u4_p2:H1 | RH14 | aceptado | docs/ia/review_u4_p2_respuesta.md |
| review_u4_p1:H1 | RH15 | aceptado | docs/ia/review_u4_p1_respuesta.md |
| review_u4_p1:H3 | RH16 | aceptado | docs/ia/review_u4_p1_respuesta.md |
| review_u4_p2:H2 | RH17 | aceptado | docs/ia/review_u4_p2_respuesta.md |
| review_u4_p2:H3 | RH18 | aceptado | docs/ia/review_u4_p2_respuesta.md |
| review_u4_p1:OBS01 | RH19 | aceptado | docs/ia/review_u4_p1_respuesta.md |
| review_u4_p3:H1 | RH20 | descartado | docs/ia/review_u4_p3_respuesta.md |
| review_u4_p3:H2 | RH21 | descartado | docs/ia/review_u4_p3_respuesta.md |
| review_u4_p3:H3 | RH22 | descartado | docs/ia/review_u4_p3_respuesta.md |
| review_u5/H-01 | QA01 | aceptado | docs/ia/review_u5_respuesta.md |
| review_u6/U6-01 | QA02 | aceptado | docs/ia/review_u6_respuesta.md |
| review_u6/U6-02 | QA03 | aceptado | docs/ia/review_u6_respuesta.md |
| review_u6_c01/U6-C01-02 | QA03 | aceptado | docs/ia/review_u6_c01_respuesta.md |
| review_u6/U6-03 | QA04 | aceptado | docs/ia/review_u6_respuesta.md |
| review_u6_c01/U6-C01-01 | QA05 | aceptado | docs/ia/review_u6_c01_respuesta.md |
| review_u5_c04/U5-C04-01 | QA05 | aceptado | docs/ia/review_u5_c04_respuesta.md |
| review_u6_c01/U6-C01-03 | QA06 | aceptado | docs/ia/review_u6_c01_respuesta.md |
| review_u7/U7-01 | QA07 | aceptado | docs/ia/review_u7_respuesta.md |
| review_u7/U7-02 | QA08 | descartado | docs/ia/review_u7_respuesta.md |
| review_u5_c01/U5-C01-01 | QA09 | descartado | docs/ia/review_u5_c01_respuesta.md |
| review_u5_c01/U5-C01-02 | QA10 | aceptado | docs/ia/review_u5_c01_respuesta.md |
| review_u5_c02/U5-C02-01 | QA10 | aceptado | docs/ia/review_u5_c02_respuesta.md |
| review_u5_c03/U5-C03-01 | QA10 | aceptado | docs/ia/review_u5_c03_respuesta.md |
| review_u5_c01/U5-C01-03 | QA11 | aceptado | docs/ia/review_u5_c01_respuesta.md |
| review_u5_c05/U5-C05-01 | QA11 | aceptado | docs/ia/review_u5_c05_respuesta.md |
| review_u5_c02/U5-C02-02 | QA12 | aceptado | docs/ia/review_u5_c02_respuesta.md |
| review_u5_c02/U5-C02-03 | QA13 | aceptado | docs/ia/review_u5_c02_respuesta.md |
| review_u5_c03/U5-C03-02 | QA14 | aceptado | docs/ia/review_u5_c03_respuesta.md |
| review_u5_c03/U5-C03-03 | QA15 | aceptado | docs/ia/review_u5_c03_respuesta.md |
| review_u5_c03/U5-C03-04 | QA16 | aceptado | docs/ia/review_u5_c03_respuesta.md |
| review_u5_c04/U5-C04-02 | QA17 | aceptado | docs/ia/review_u5_c04_respuesta.md |
| review_u5_c05/U5-C05-02 | QA18 | aceptado | docs/ia/review_u5_c05_respuesta.md |
| review_u8_pre/U8-01 | U801 | corregido | docs/ia/review_u8_pre_respuesta.md |
| review_u8_pre/U8-02 | U802 | corregido | docs/ia/review_u8_pre_respuesta.md |
| review_u8_pre/U8-03 | U803 | corregido | docs/ia/review_u8_pre_respuesta.md |

## RH01 - Borrado del último detalle de un pedido cerrado en esquemas históricos

**Decisión:** descartado. Descartado como defecto del acumulado actual: app_web intentó borrar el único detalle de un pedido final y recibió SQLSTATE23514. La guarda heredada TP2 ya impide ese cambio; no se modifica retrospectivamente TP1/TP5. Cada transacción terminó en ROLLBACK y cinco huellas de tablas iguales.

**Comprobación:** motor PostgreSQL real, copia U8: rechazo23514 y conservación.

**Evidencia:** `docs/evidencias/review_bd_antes_correccion.json`, `docs/ia/review_tp1_respuesta.md`, `docs/ia/review_tp5_respuesta.md`.

## RH02 - Total almacenado escribible directamente

**Decisión:** aceptado. Se acepta la observación estructural para un escritor privilegiado del total, sin atribuirla a la app actual. La mitigación U5 se conserva: app_web UPDATE pedido.total fue rechazado42501 y la tabla quedó intacta. No se amplían permisos ni se afirma haber probado una explotación con propietario.

**Comprobación:** motor PostgreSQL real: app42501; alcance de propietario delimitado por lectura.

**Evidencia:** `docs/evidencias/review_agregados_y_catalogo.json`, `docs/evidencias/review_bd_antes_correccion.json`, `docs/ia/review_tp1_respuesta.md`, `docs/ia/review_tp2_respuesta.md`, `docs/ia/review_tp3_respuesta.md`, `docs/ia/review_tp4_respuesta.md`, `docs/ia/review_tp5_respuesta.md`.

## RH03 - Hipótesis de total perdido por concurrencia en esquema base

**Decisión:** aceptado. Se acepta sólo la hipótesis del AFTER aislado como límite de análisis, no una carrera demostrada del acumulado. El BEFORE heredado contiene FOR UPDATE; no se ejecutó una nueva prueba de dos sesiones en U8 ni se atribuyen resultados inexistentes. Se conserva ese bloqueo; no hay cambio de código basado únicamente en la hipótesis.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/evidencias/review_agregados_y_catalogo.json`, `docs/ia/review_tp1_respuesta.md`, `docs/ia/review_tp2_respuesta.md`, `docs/ia/review_tp3_respuesta.md`, `docs/ia/review_tp4_respuesta.md`, `docs/ia/review_tp5_respuesta.md`.

## RH04 - Inserción directa de CONFIRMADO/ENTREGADO sin líneas

**Decisión:** corregido. Confirmado en copia: el administrador pudo insertar CONFIRMADO sin líneas y se revirtió. app_web carece INSERT sobre estado; no se lo presenta como explotación de la app. La nueva guarda BEFORE INSERT exige PENDIENTE sólo en las copias U8. Después rechaza23514 y permite PENDIENTE con administrador bootstrap y app, con ROLLBACK y cinco huellas iguales. La segunda copia canónica también está corregida.

**Comprobación:** motor PostgreSQL real antes/después, con roles diferenciados.

**Evidencia:** `docs/evidencias/correccion_tp2_primera_ejecucion.json`, `docs/evidencias/correccion_tp2_segunda_ejecucion.json`, `docs/evidencias/review_bd_antes_correccion.json`, `docs/evidencias/review_bd_despues_correccion_segunda.json`, `docs/ia/review_tp2_respuesta.md`, `docs/ia/review_tp3_respuesta.md`, `docs/ia/review_tp4_respuesta.md`.

**Cambio aplicado:** `postgresql/30_corregir_estado_inicial.sql`.

## RH05 - Orden de seed y restricciones estrictas

**Decisión:** descartado. Se descarta como afirmación de entrega histórica fallida: la condición depende del orden de carga, que no se reprodujo en U8. Se conserva como precondición de reconstrucción; U8 parte explícitamente de la base acumulada y no ejecuta semillas antiguas sobre ella.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp3_respuesta.md`, `docs/ia/review_tp4_respuesta.md`.

## RH06 - Cobertura de índice Q3 incompleta para id

**Decisión:** aceptado. Aceptar como candidato de medición, no defecto lógico ni promesa de mayor velocidad. El índice incluye usuario_id/total pero Q3 también devuelve id; un Index Only Scan depende además del mapa de visibilidad.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp3_respuesta.md`.

## RH07 - Alcance de mediciones antes/después de una corrida

**Decisión:** aceptado. Aceptar la limitación de generalización: una captura antes/después es evidencia del ensayo, pero no establece por sí sola causalidad universal ni rendimientos futuros. La revisión no contiene planes o tiempos adicionales que puedan inventarse.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp3_respuesta.md`, `docs/ia/review_tp4_respuesta.md`, `docs/ia/review_tp5_respuesta.md`.

## RH08 - Comentario de equivalencia: contadores cero, no cero filas

**Decisión:** aceptado. Se acepta y aclara la imprecisión documental: la consulta devuelve dos contadores y ambos deben valer cero, no cero filas. No se editó el script histórico ni se etiqueta su fuente como corregida; la aclaración queda en esta matriz.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp3_respuesta.md`.

## RH09 - Índice adicional por producto_id como oportunidad de medición

**Decisión:** aceptado. OBS01 es un identificador asignado por esta matriz a una observación sin H/M propio. La PK comienza por pedido_id; consultas sólo por producto_id podrían beneficiarse de otro índice. No se conoce un plan lento ni la necesidad actual; versiones posteriores ya agregan índices.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp1_respuesta.md`.

## RH10 - Instalación de restricciones no atómica ante interrupción

**Decisión:** aceptado. Aceptar como mejora de reproducción: el archivo elimina y vuelve a crear triggers sin una transacción envolvente propia. No se afirma que haya ocurrido una interrupción. El invocador puede aportar ON_ERROR_STOP o una transacción, y no se adjunta aquí dicho procedimiento. OBS01 se asigna por la matriz a la observación sin ID propio.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp4_respuesta.md`.

## RH11 - Agrupación mensual TIMESTAMPTZ dependiente de TimeZone

**Decisión:** aceptado. Aceptar el riesgo de reproducción temporal y pedir contrato explícito. date_trunc('month', TIMESTAMPTZ) sin zona fija depende de la sesión del refresh. No se afirma que un reporte concreto haya estado errado ni que deba usarse Buenos Aires sin definir mes de negocio. U4 añade una caché diaria distinta: no asumir que eso cambia automáticamente la materializada mensual heredada.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp5_respuesta.md`, `docs/ia/review_u4_p1_respuesta.md`.

## RH12 - Proyecciones históricas no plenamente cubiertas por índices

**Decisión:** aceptado. Aceptar como oportunidad de medición, no como índice incorrecto. Q1 devuelve fecha original, ausente de su índice de expresión local; Q3 devuelve subtotal, ausente de su índice complementario. La visibilidad y el plan también intervienen: un INCLUDE adicional no garantiza Index Only Scan ni una mejora neta.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp5_respuesta.md`.

## RH13 - Detención del invocador psql ante errores de reconstrucción

**Decisión:** aceptado. Se decide ON_ERROR_STOP en el invocador/documentación reproducible. Las transacciones de los scripts protegen persistencia parcial por errores SQL ordinarios, pero el código de salida esperado depende también del comando psql. El wrapper U4 puede ya aportar esa opción: no afirmar fallo sin leerlo.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_tp5_respuesta.md`.

## RH14 - Aserciones de verificadores eliminables con Python optimizado

**Decisión:** aceptado. Aceptar el riesgo condicionado de ejecutar estos verificadores con optimización, no afirmar que las evidencias históricas ya sean falsas. Se hizo comprobación offline real: compilar sin importar/ejecutar fuentes produce13y30 LOAD_ASSERTION_ERROR con optimize0 y0conoptimize1/2. El falso aprobado integral sugerido por IA no fue reproducido por esta prueba estática.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_u4_p1_respuesta.md`, `docs/ia/review_u4_p2_respuesta.md`.

## RH15 - Carga inicial confirmada antes de refresco que puede fallar

**Decisión:** aceptado. Aceptar una mejora de recuperación: el REFRESH explícito posterior al COMMIT no revierte carga si falla, y la guarda inicial impide repetir el archivo completo. No llamar incorrecta a la política deliberada de instantánea TP5 ni afirmar que el fallo ocurrió. La ejecución limpia documentada puede ser totalmente correcta.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_u4_p1_respuesta.md`.

## RH16 - Carga por rango fijo depende del siguiente valor de identidad

**Decisión:** aceptado. Aceptar como precondición y riesgo de reintento tras fallo: cantidad/máximo no prueban el siguiente valor de identidad y rollback no recupera secuencias. No afirmar que el respaldo original estuviera mal ni que las filas históricas cambien; los controles finales normalmente rechazan la carga incoherente.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_u4_p1_respuesta.md`.

## RH17 - Observación concurrente dependiente de pausa fija de dos segundos

**Decisión:** aceptado. Aceptar como oportunidad de coordinación determinista: un controlador lento puede no observar A en pg_sleep2 o iniciar B tarde. No demuestra una carrera de la MV ni invalida una corrida histórica que sí observó bloqueos y verificó datos. El verificador FNBC usa una coordinación distinta y no debe confundirse.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_u4_p2_respuesta.md`.

## RH18 - Matar cliente no confirma que su backend haya terminado

**Decisión:** aceptado. Aceptar sólo como hipótesis de recuperación: process.kill finaliza psql y no confirma directamente el rollback/cierre del backend. El finally y la adquisición del bloqueo asesor son mitigaciones reales. No afirmar pérdida de restauración ni cambios persistentes sin ejecutar el escenario de fallo.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_u4_p2_respuesta.md`.

## RH19 - Índices parcialmente solapados con distintos INCLUDE

**Decisión:** aceptado. Aceptar como medición opcional, no como duplicación semántica completa: comparten(producto_id,pedido_id) pero INCLUDE difiere(cantidad/subtotal frente a cantidad/precio_unitario). Cada cobertura puede servir consultas distintas y fusionarlas tiene costos propios.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_u4_p1_respuesta.md`.

## RH20 - Excepción por profundidad de trigger admite otros orígenes anidados

**Decisión:** descartado. Se descarta como defecto actual demostrado: la respuesta no identifica un recorrido externo existente que aproveche la profundidad del trigger. Se conserva la limitación de que pg_trigger_depth no identifica por sí solo el origen. app_web no puede crear objetos en public; no se añadió un trigger artificial para fabricar un fallo ni se afirma una prueba dinámica de esa hipótesis.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/evidencias/review_agregados_y_catalogo.json`, `docs/ia/review_u4_p3_respuesta.md`.

## RH21 - Permisos del invocador para refrescar materializada desde un trigger

**Decisión:** descartado. Descartado como fallo del estado actual porque U5 ya instaló SECURITY DEFINER, owner rol_funciones y MAINTAIN acotado a la materializada diaria. Se verificó el catálogo efectivo y un INSERT PENDIENTE como app completó sus triggers y se revirtió. No se modifica U5 ni se atribuye esta mitigación anterior a un cambio nuevo U8.

**Comprobación:** catálogo PostgreSQL y INSERT real bajo app en copia, ROLLBACK.

**Evidencia:** `docs/evidencias/review_agregados_y_catalogo.json`, `docs/evidencias/review_bd_despues_correccion_segunda.json`, `docs/ia/review_u4_p3_respuesta.md`.

## RH22 - Consumo del reporte diario requiere conservar la zona de negocio

**Decisión:** descartado. Se descarta como defecto del script diario completo: configura explícitamente la zona de Buenos Aires. Se conserva la precondición para consumidores externos que copien consultas con CURRENT_DATE; no se confunde con la materializada mensual heredada RH11, cuyo riesgo se acepta.

**Comprobación:** lectura_estatica; escenario de fallo no ejecutado ni presentado como ocurrido.

**Evidencia:** `docs/ia/review_u4_p3_respuesta.md`.

## QA01 - Una cadena sensible escapada podría sobrevivir en un valor JSON aunque no exista como subcadena literal del texto serializado.

**Decisión:** aceptado. Regresión local confirmada con una cadena exclusivamente sintética: después de sanear texto JSON, el valor decodificado conservaba la cadena escapada. No se cambió el original U5 y NO se lo marca como corregido; no se afirma filtración histórica. U8 conserva diagnósticos en privado y no envía logs con datos reales.

**Comprobación:** prueba local real en memoria con datos sintéticos, no prueba de motor.

**Evidencia:** `docs/evidencias/review_u5_json_escapado.json`, `docs/ia/review_u5_respuesta.md`.

## QA02 - La publicación de dos archivos no es atómica; puede quedar un dump huérfano. El selector no lo considera exitoso.

**Decisión:** aceptado. Se acepta la publicación no atómica de dump/manifiesto como límite operativo. La prueba local real del selector rechazó un .dump ficticio huérfano con «No hay manifiesto exitoso», sin llamar clientes PG. No se transforma esa salvaguarda en negación del posible residuo ni en un falso éxito.

**Comprobación:** selector U6 ejecutado localmente con archivo ficticio aislado.

**Evidencia:** `docs/evidencias/review_u6_selector_huerfano.json`, `docs/ia/review_u6_respuesta.md`.

## QA03 - Dos capas del mismo problema diagnóstico: excepciones locales sin causa detallada y stderr nativo descartado. Los fallos sí producen salida no cero.

**Decisión:** aceptado. Los códigos de salida se comprueban, se lanza excepción y los llamadores terminan en 1. Capturar la causa permitiría distinguir errores, pero su almacenamiento debe ser privado y no debe publicar credenciales o valores de filas. Se agrupan las observaciones conservando ambos IDs originales. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u6_c01_respuesta.md`, `docs/ia/review_u6_respuesta.md`.

## QA04 - La validación del generador no cubre uniformemente prosa y adjuntos; un literal accidental en un informe podría publicarse.

**Decisión:** aceptado. La observación distingue correctamente cobertura automática y contenido efectivo. Los controles finales de U6 incluyeron inspección y escaneo de valores privados conocidos sin coincidencias; esta revisión nueva no los reejecutó ni atribuye una exposición actual. Se propone comprobar la mejora con un marcador sintético, preservando el original. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u6_respuesta.md`.

## QA05 - El reintento con igual prefijo sólo funciona si el fallo anterior no dejó respuesta parcial.

**Decisión:** aceptado. El bloqueo protege evidencia existente frente a sobreescritura, pero la opción de reintento no abarca todos los fallos. Para U8 puede mantenerse la regla explícita de usar un prefijo nuevo cuando hay respuesta parcial o implementarse archivado íntegro antes del reintento. No se afirma una corrección que todavía no se hizo. Se conserva la referencia independiente que revisó el wrapper U5 y se agrupa con el mismo defecto revisado en U6. Una solución futura debe preservar respuesta parcial y metadatos antes de autorizar el reintento. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c04_respuesta.md`, `docs/ia/review_u6_c01_respuesta.md`.

## QA06 - El contador de líneas no interpretadas se conserva, pero no condiciona el estado completed.

**Decisión:** aceptado. No toda línea no JSON demuestra pérdida de una respuesta. Conviene distinguir completed limpio y completed que requiere revisión, sin inventar fallos de las consultas actuales. Los metadatos de las cuatro consultas aquí consolidadas indican unparsed_line_count=0. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u6_c01_respuesta.md`.

## QA07 - Un fallo del validador detiene la prueba y conserva el documento inesperado como residuo del laboratorio.

**Decisión:** aceptado. Las salidas originales y el cierre prueban cinco documentos y cero inválidos persistidos en esta ejecución. La observación no exige borrar automáticamente la evidencia de una regresión ni cambiar fuentes congeladas. Para futuras pruebas que debiliten el validador debe usarse una colección o copia separada. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u7_respuesta.md`.

## QA08 - El generador no fuerza la limpieza de Git; los controles independientes sí acreditan la correspondencia de esta entrega congelada.

**Decisión:** descartado. La condición de cambios sin confirmar no ocurre: working tree limpio y git diff contra 8178b01 sin diferencias. JS/SQL coinciden byte a byte con el commit; EJSON conserva el mismo contenido con CRLF en el archivo ejecutado y LF normalizado en Git. Los tres hashes de los bytes ejecutados sí coinciden exactamente con validacion.json y los adjuntos. HEAD posterior incorpora cierre documental. La prueba es local y no se presenta como una prueba de motor.

**Comprobación:** Git/SHA256 real de sólo lectura; no es prueba de motor.

**Evidencia:** `docs/evidencias/qa_u7_congelamiento.json`, `docs/ia/review_u7_respuesta.md`.

## QA09 - El umbral fija una población concreta y podría divergir si se reutiliza el helper con otro conjunto de IDs.

**Decisión:** descartado. Descartado como defecto de la población actual, manteniendo el límite de reutilización: PostgreSQL confirmó 20.000 IDs heredados1..20000 y sólo una cuenta posterior20001. La huella agregada heredada coincide con U5. No se exportaron filas, contactos ni verificadores de contraseñas.

**Comprobación:** motor PostgreSQL real, agregados y huella heredada.

**Evidencia:** `docs/evidencias/review_agregados_y_catalogo.json`, `docs/ia/review_u5_c01_respuesta.md`.

## QA10 - Tres capas de precondiciones de logging parciales: ajuste de error, configuración por sesión y registro por duración.

**Decisión:** aceptado. Se conservan los tres IDs y sus condiciones distintas. La parametrización impide interpolación SQL, pero no garantiza por sí sola que el servidor nunca registre valores. Las comprobaciones deberían incluir las vías y sesiones efectivamente usadas. Una prueba futura debe emplear exclusivamente centinelas sintéticos y guardar el diagnóstico privado. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c01_respuesta.md`, `docs/ia/review_u5_c02_respuesta.md`, `docs/ia/review_u5_c03_respuesta.md`.

## QA11 - Una carpeta puede contener artefactos de una corrida fallida junto a un JSON anterior satisfactorio.

**Decisión:** aceptado. El fallo del proceso sí se comunica. El riesgo reside en consumir archivos aislados sin correlacionar la ejecución. Para procedimientos nuevos se propone una carpeta por corrida y un manifiesto final; no se altera ni se regenera retrospectivamente la evidencia U5. Se agrupa con U5-C01-03 por la vigencia de artefactos. El proceso sí rechaza coincidencias o errores, pero un consumidor no debe interpretar el JSON viejo como estado del intento nuevo. La mejora usa resultados por corrida y marcador final explícito. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c01_respuesta.md`, `docs/ia/review_u5_c05_respuesta.md`.

## QA12 - Una regresión de privilegios podría persistir la membresía justo cuando la prueba detecta el éxito indebido.

**Decisión:** aceptado. Se debe distinguir el comportamiento correcto probado del catálogo actual de la contención ante una regresión. La comprobación detecta la anomalía, pero debería ensayarse con roles descartables y rollback para no dejar una concesión inesperada. No se propone conceder roles reales de negocio para probarlo. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c02_respuesta.md`.

## QA13 - Un helper de reset sin efecto podría superar esas aserciones positivas aunque conserve validaciones de entrada.

**Decisión:** aceptado. La función y los permisos originales tienen otras verificaciones, pero esas llamadas concretas no prueban el efecto de reset. La mejora propuesta es autenticar con el valor temporal dentro de la misma transacción y revertir todo, conservando únicamente el ID booleano de resultado. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c02_respuesta.md`.

## QA14 - Un NOTICE con contenido sensible podría salir por una vía distinta del saneamiento de DatabaseError.

**Decisión:** aceptado. El saneamiento de errores es un control presente y diferente. En helpers nuevos debe definirse una política explícita de avisos o capturarse su salida sólo en almacenamiento privado. No se atribuye una filtración real a partir de la mera ausencia del callback. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c03_respuesta.md`.

## QA15 - Determinadas entradas Markdown pueden perder asteriscos o sintaxis de enlaces en el PDF.

**Decisión:** aceptado. La mejora debe proteger primero los fragmentos de código y procesar el resto del marcado después. El informe histórico se conserva; no se necesita regenerarlo para aceptar una mejora del renderizador de uso futuro. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c03_respuesta.md`.

## QA16 - Un repositorio grande con muchos objetos pequeños puede superar un presupuesto razonable de memoria.

**Decisión:** aceptado. El empaquetador ya inspecciona objetos, credenciales, CRC, manifiesto y restauración Git. Esta observación propone un límite acumulado o procesamiento incremental, no niega esas garantías ni exige construir grandes archivos para validar un laboratorio pequeño. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c03_respuesta.md`.

## QA17 - Puede notificarse un fallo aunque la solicitud de rotación haya sido procesada, porque el nombre tiene resolución de segundos.

**Decisión:** aceptado. El control de cambio de ruta es correcto para exigir una fuente cerrada. La mejora sería solicitar otra rotación al cruzar el segundo, dentro de un plazo acotado, no tomar pg_rotate_logfile()=true como prueba de cierre. Las evidencias originales se conservan. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c04_respuesta.md`.

## QA18 - La verificación se interrumpe ante ese estado del árbol de trabajo y no genera evidencia nueva.

**Decisión:** aceptado. El proceso no produce un falso éxito. Puede rechazarse explícitamente ese estado con un diagnóstico claro, manteniendo el análisis del contenido todavía conservado en Git. No se interpreta como archivo perdido ni como defecto de la entrega U5 limpia. Decisión técnica final: se acepta como recomendación o límite condicionado, se conservan las fuentes históricas y no se afirma una corrección ni una exposición que no se ejecutó. La prueba propuesta del registro preliminar es una recomendación de extensión, no una prueba realizada ni un requisito de los tres casos desarrollados.

**Comprobación:** lectura_estatica; no se ejecutó el escenario condicional ni se atribuye un incidente histórico.

**Evidencia:** `docs/ia/review_u5_c05_respuesta.md`.

## U801 - Protección privada del respaldo y diagnóstico

**Decisión:** corregido. Mejora de robustez aplicada antes de datos: ACL explícita en Windows. Se corrigió también la premisa del review: Windows0700 tiene backport en Python3.12.4; no se afirma defecto ni exposición en el runtime3.12.14. ACL efectiva y propietarios permitidos se inspeccionaron en124elementos; OWNER RIGHTS representa al propietario ya verificado, no a una cuenta ajena.

**Comprobación:** código corregido, dos ejecuciones reales y review Plan final7/7.

**Evidencia:** `docs/ia/review_u8_pre_respuesta.md`, `docs/ia/review_u8_final_respuesta.md`, `docs/evidencias/verificacion_acl_privada.json`.

**Cambio aplicado:** `tools/reproducir.py`.

## U802 - Alcance real de la evidencia de conservación

**Decisión:** corregido. Corregido: además del conteo, se comparan huellas completas de pedido y detalle y suma/huella del stock de todo el catálogo. Ambas ejecuciones pasaron. Se mantienen los límites: no prueba secuencias ni cambios transitorios de todo el clúster.

**Comprobación:** código corregido, dos ejecuciones reales y review Plan final7/7.

**Evidencia:** `docs/ia/review_u8_pre_respuesta.md`, `docs/ia/review_u8_final_respuesta.md`, `docs/evidencias/reproduccion_u8.json`, `docs/evidencias/segunda_ejecucion_comparacion.json`.

**Cambio aplicado:** `postgresql/20_validar_no_ventas.sql`, `tools/reproducir.py`.

## U803 - Representatividad del historial C6

**Decisión:** corregido. Corregido: se omitió la inserción directa de un CONFLICTO artificial. C2 conserva dos UUID producidos por la simulación, suficientes para demostrar historia múltiple; el segundo pendiente simultáneo se rechaza por índice parcial. Nueve filas finales coinciden exactamente con la evidencia.

**Comprobación:** código corregido, dos ejecuciones reales y review Plan final7/7.

**Evidencia:** `docs/ia/review_u8_pre_respuesta.md`, `docs/ia/review_u8_final_respuesta.md`, `docs/evidencias/reproduccion_u8.json`.

**Cambio aplicado:** `tools/reproducir.py`.

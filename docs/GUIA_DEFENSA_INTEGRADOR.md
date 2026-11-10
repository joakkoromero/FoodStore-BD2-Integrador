# Guia de defensa del TPI - Food Store

Equipo: Exequiel Arancibia / Joaquin Romero. Material de preparacion con
asistencia declarada de IA. Este guion no acredita un ensayo ni una defensa
realizados. Las respuestas deben contrastarse con el codigo y las evidencias.

## Recorrido de diez minutos

| Tiempo | Que explicar | Evidencia que conviene abrir |
|---|---|---|
| 0:00 a 2:00 | Arquitectura y refactorizacion FNBC; por que la reunion es sin perdida y necesita guardia. | Informe pp. 1-2; unidad4/tp_fnbc_control_lote.sql; docs/kiro_migracion/. |
| 2:00 a 4:00 | Minimo privilegio, ACL de tabla/columna, incidente y contencion propuesta. | Informe p. 3; unidad5/sql/roles.sql; log saneado e informe_incidente.md. |
| 4:00 a 6:00 | Respaldo realmente programado, mismo ultimo backup restaurado, RTO y limites. | Informe p. 4; complementos/mantenimiento_programado/evidencias/ y su post-incidente. |
| 6:00 a 8:00 | Pedidos documentales, comparacion SQL/Mongo y un conflicto SQLite resuelto con UUID nuevo. | Informe pp. 5-6; consultas U7; SQLite/evidencias U8. |
| 8:00 a 10:00 | Hallazgos aceptados/corregidos/descartados, procedencia de IA, Git y mantenimiento integrado. | Informe pp. 7-8; DECISIONES_REVIEW; DUIA; bitacora; commits y hashes. |

## Unidad 4: dependencias, redundancia y reversibilidad

**Que significan L, D y R?** Lote, deposito y responsable. Las reglas son
LD->R y R->D. Las clausuras LD+ y LR+ contienen los tres atributos; son claves
candidatas. R+ contiene R y D pero no L: R no es superclave, por eso R->D viola
FNBC aunque todos los atributos de la relacion sean primos.

**Por que RD y LR no pierden datos?** Su interseccion R determina RD. La
reunion reconstruye las tuplas originales; la prueba material compara los
multiconjuntos mediante EXCEPT ALL en ambos sentidos. No basta comparar conteos.

**Por que no alcanzan PK y FK?** Permiten que dos responsables del mismo
deposito queden asignados al mismo lote, violando LD->R. La misma fila tecnica
de guardia serializa escrituras de ambas tablas; el trigger posterior valida
la reunion. Su costo es reducir concurrencia de escritura. La prueba debe
mostrar que B realmente espera a A y recibe el SQLSTATE previsto tras su COMMIT.

**Que cambia entre ROLLBACK y una reversion posterior?** ROLLBACK deshace una
transaccion aun no confirmada. Despues de COMMIT se necesita otra transaccion
de migracion inversa. El complemento del integrador especifica reconstruir
desde el JOIN actual bajo bloqueo, conservando cambios posteriores. Un
checkpoint viejo de tres filas no reemplaza la captura actual de cuatro.
El ensayo nuevo termino SUCCESS: la tabla reconstruida conservo cuatro filas,
el checkpoint mantuvo tres y se comprobaron doce rechazos de escritura 25006.
El registro completo esta en docs/evidencias_tpi/migracion_fnbc.json.

**Por que una materializada?** Acelera una lectura repetida, a costa de
almacenamiento y mantenimiento. U4 midio medianas 173,044 ms y 0,095 ms, pero
el refresh costo 922,234 ms y la escritura observada 930,009 ms. Son cifras
de aquel laboratorio, no una promesa universal. Revisar la instalacion atomica,
el bloqueo asesor, READ COMMITTED y las pruebas de coherencia.

## Unidad 5: permisos y auditoria

**Como se demuestra minimo privilegio?** Hay seis roles NOLOGIN y dos LOGIN,
44 ACL exactas y tres membresias INHERIT=true, SET=false, ADMIN=false. La app
no obtiene escritura libre del total ni hashes o administracion del catalogo.
Soporte conserva sus columnas puntuales; reportes sus objetos autorizados.

**Un REVOKE de columna anula SELECT de tabla?** No. Son capas distintas:
si queda SELECT de tabla, la columna sigue accesible. Por eso se revisan las
ACL de tabla y de columna y se rechazo lectura general de public para reportes.

**Por que SECURITY DEFINER?** Los cuatro puentes necesitan permisos internos
acotados que no se otorgan directamente al login. Tienen propietario limitado,
objetos calificados y path fijo. Un path por si solo no vuelve segura cualquier
funcion; hay que leer su cuerpo y las ACL efectivas. Los propietarios y el
bootstrap conservan facultades que las revocaciones ordinarias no eliminan.

**Que probo el incidente?** Tres autenticaciones negativas, una positiva de
negocio, lectura autorizada e intento GRANT rechazado con 42501; la membresia
administrativa era falsa antes y despues. La lectura autorizada de 20.001
filas no demuestra por si sola exfiltracion ni compromiso real.

**El log prueba COMMIT?** Registra conexiones e intentos de sentencias,
incluidas operaciones revertidas. No es un historial OLD/NEW ni prueba de que
una transaccion se haya confirmado. Los limites de parametros no ocultan
secretos literales dentro del texto SQL. Ante incidente real: preservar
evidencia, reconstruir alcance y evaluar restricciones con responsable.

## Unidad 6 y complemento de mantenimiento

**Que evidencia que el backup fue programado?** La tarea diaria tenia primer
disparo a las 14:37:41 UTC-03 del 10/11/2026, CalendarTrigger con intervalo un
dia, principal Interactive/Limited y resultado cero. No se inicio manualmente.
Su resumen SUCCESS y hash enlazan el backup real. La tarea temporal se retiro;
no se afirma un servicio permanente en produccion.

**Que significa el RTO?** El cronometro monotono abarco creacion de destino,
aislamiento, restore y validaciones. U6 observo 11,350 s el 03/11; el TPI
restauro el mismo ultimo backup programado en 13,430 s el 10/11. Los controles
posteriores fuera del cronometro no deben incorporarse ficticiamente al RTO.

**Que significa la antiguedad de copia?** Usa el inicio de pg_dump como
referencia conservadora: 31,808 s en U6 y 19,074 s en el TPI. No es perdida
real medida ni prueba de PITR. Las ventanas observadas no tenian escritores.

**La copia restaurada esta lista para conectar la app?** No se habilito:
--no-owner y --no-privileges no recuperan la politica de roles/ACL de U5.
La restauracion valida datos y objetos en aislamiento; antes de una
recuperacion productiva habria que revisar identidades y seguridad por separado.

**Que mantenimiento se propone?** Backup diario, salud, estadisticas y
autovacuum, ANALYZE puntual justificado, validaciones y restauraciones aisladas.
No se propone VACUUM FULL periodico indiscriminado. Se conservan responsables,
ventanas, monitoreo y propuesta de una segunda copia cifrada externa.

## Unidades 7 y 8: documental y movil

**Por que embeber lineas?** Permite recuperar el pedido completo desde una
coleccion. Se preservan cinco pedidos existentes y siete lineas, con importes
historicos Decimal128. Los validadores deben controlar suma, cantidad y
producto unico; embeber no garantiza automaticamente esa coherencia.

**Que se comparo realmente?** ENTREGADO devolvio IDs 1,2,3,4 y producto 1
devolvio 1,3,5, iguales en SQL y Mongo. Total >3000 devolvio 3,4 en una consulta
Mongo adicional. No hubo benchmark ni se demostro superioridad de velocidad.
PostgreSQL sigue siendo autoridad transaccional; Mongo es proyeccion experimental.

**Por que centavos INTEGER64 en SQLite?** Evitan flotantes y preservan la
escala monetaria. PostgreSQL usa BIGINT al convertir NUMERIC(12,2) por 100;
INTEGER32 no alcanza todo ese dominio. Cada conexion SQLite activa FK; las
tablas STRICT no sustituyen las reglas CHECK y las restricciones de negocio.

**Como se resuelve un precio cambiado?** El semaforo compara contra la nueva
instantanea del servidor. Muzzarella 9000->9100 genera CONFLICTO. En el
laboratorio se simula aceptar el nuevo precio, actualizar lo visto y crear
otro UUID; el anterior conserva el conflicto. El resultado verde se llama
SIMULADO_APROBADO: no confirma venta ni descuenta o reserva stock.

**Que pasa con una baja o falta de stock?** Tiene prioridad roja sobre un
cambio de precio. Las lapidas se conservan para referencias e historia pero
se ocultan del catalogo. Una fila ausente del snapshot nuevo tambien rechaza,
aunque la cache vieja la conserve.

**Un UUID local garantiza la venta unica remota?** La prueba demuestra PK
local, una sola pendiente por borrador e idempotencia del semaforo. Una venta
remota real requeriria unicidad del UUID y validacion de precio/stock dentro
de la misma transaccion del servidor; esa API productiva no se implementa aqui.

## Review final, IA y conservacion

**Que debe ratificarse?** Todas las decisiones de DECISIONES_REVIEW, sus
fundamentos y evidencias: 43 grupos/64 referencias heredadas, seguridad U5 y
hallazgos nuevos. Aceptar un riesgo condicionado no significa que ocurrio
un incidente ni que se corrigio el original. La constancia humana se registra
solo con una respuesta real, sin firmas simuladas.

**Como se prueba procedencia?** Prompts, respuestas integras, adjuntos exactos,
hashes y metadatos; Kiro antes del codigo nuevo; originales Build separados
de correcciones; Plan completo antes del motor; commits tecnicos identificados
como asistencia de Codex. No se reatribuyen retroactivamente fechas o autores.

**Que sucede tras restaurar un servidor viejo?** Todas las tablets invalidan
catalogos e instantaneas, descargan tambien bajas y reconcilian UUID/resultados
antes de reenviar. Se conservan borradores e historia. El reloj del telefono
no decide autoridad ni habilita reutilizar un verde anterior.

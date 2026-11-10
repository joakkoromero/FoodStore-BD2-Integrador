# Complemento nuevo TPI: contexto para Kiro, migracion FNBC reversible

Fecha:10/11/2026. Es una NUEVA especificacion y una NUEVA prueba del integrador; no se atribuye a Kiro la migracion historica U4 del20/10/2026. Este contexto es propuesta de Codex para que Kiro produzca requirements.md/design.md/tasks.md antes de generar o ejecutar implementacion nueva.

## Modelo verificado de los antecedentes

- PostgreSQL17.11 (compatible16+), PL/pgSQL. Base acumulada Food Store con usuario, producto, categoria, pedido, detalle_pedido y extension mayorista U4.
- public.lote(id), public.deposito(id), public.usuario(id) ya existen; los IDs801/802/803 son referencias numericas de prueba, no se envia nombre/contacto/credencial de usuario.
- public.control_lote_almacen_original tiene3 filas: (501,30,801),(502,30,801),(503,31,802), columnas(lote_id,deposito_id,responsable_control_id). Se clonaran esos datos, no se modificara la fuente.
- Reglas: LD->R y R->D. Claves candidatasLD y LR. R->D viola FNBC porqueR+ = RD. DescomposicionRDcon PK R yLRcon PK LR; reunion sin perdida por interseccion R, clave de RD. LD->R no queda preservada por PK/FK locales; requiere validacion del JOIN con serializacion de escrituras.
- Estado previo U4 comprobado: migracion atomica con original conservado, vista compatible y EXCEPT ALL bilateral0,3 filas. Hay evidencia matematica/anomalias/concurrencia con 23505. NO existe provenance Kiro FNBC original ni reversion postCOMMIT de FNBC (solo una reversion de desnormalizacion/MV). Este complemento subsana esas dos evidencias.

## Alcance y barreras

Base nueva EXCLUSIVA foodstore_tpi_migracion_nov10, creada como copia aislada. Cualquier escritura debe abortar si current_database no coincide. Nuevo esquema tpi_migracion, inexistente antes de preparar. No ejecutar sobre foodstore ni otras copias U4-U8. No modificar public.*, roles, permisos anteriores, archivos ya entregados ni las83 fuentes anteriores/7 fuentes U8 congeladas.

Solo se leen de public la tabla original3 filas y las claves maestras necesarias. Se verifican filas/FKs/FD antes de copiar y se rechaza entrada inesperada. Dentro de tpi_migracion se usan nombres nuevos, PK/FK explicitas y columnasBIGINT sin secuencias; asi no se confunde reversibilidad de tablas con secuencias no transaccionales. Funciones con referencias totalmente calificadas y search_path seguro. Reversion sin CASCADE ni DROPfuera del esquema nuevo. Backups custom en carpeta privada con manifiesto/hash antes de cambios relevantes; no dumps, filas personales ni credenciales en entregables o prompts.

## Secuencia que debe especificarse

1. Preparacion de la copia y respaldo: validar identidad, origen3 filas, claves maestras, FD, huellas de las tablas public antes. Crear tpi_migracion y una tabla heredada control_legacy(lote,deposito,responsable), PK (L,D), FKs a maestros existentes; copiar las3 filas. Conservar checkpoint3 filas y manifiesto inicial. No recrear usuarios.
2. Precondicion negativa: en una transaccion insertar una fila adicional que violaR->D sin violarPK (L,D), por ejemplo(501,31,801). Intentar migrar: debe rechazarse SQLSTATE 23514, sin elegir arbitrariamente un deposito. ROLLBACK explicito; estado inicial intacto y ninguna instalacion parcial.
3. Ensayo de migracion con ROLLBACK: dentro de BEGIN validar FD, preservar tabla heredada renombrada como control_legacy_checkpoint, crear responsable_deposito(R,D), lote_responsable(L,R), guardia tecnica/funciones/triggers y vista control_legacy(L,D,R). Migrar proyecciones. Comprobar conteos, PK/FK, reglas y EXCEPT ALL bilateral del multiconjunto. ROLLBACK. Probar desde otra conexion que sigue la tabla heredada inicial,3 filas, y no quedaron objetos normalizados.
4. Migracion confirmada: repetir la misma migracion y COMMIT solo despues de todas las verificaciones. La tabla previa y su hash permanecen como archivo de la migracion; la vista es la interfaz operativa.
5. Pruebas de restricciones: R->D local porPKR; duplicado(L,R) y FK inexistentes; duplicado(L,D) via dosR del mismoD debe fallar23505. Probar tanto altaLR como cambio maestroRD. Toda prueba negativa con ROLLBACK/SAVEPOINT especifico y sin captura generica que esconda fallas.
6. Concurrencia: ambas tablas normalizadas tienen BEFORE STATEMENT que actualiza la MISMA fila de guardia hasta COMMIT/ROLLBACK y AFTER STATEMENT que valida el JOIN. En READ COMMITTED las consultas VOLATILE posteriores al bloqueo ven el commit anterior; en REPEATABLE READ/SERIALIZABLE una colision puede abortar40001 y exige reintento completo. Probar dos sesiones reales: A y B proponen mismo(L,D) mediante dosR; observarB esperandoLock, confirmar A y rechazar B con SQLSTATE 23505, luego limpiar solo auxiliares. No usar solo un sleep fijo como prueba de que B estaba bloqueada.
7. Cambio valido despues del COMMIT que DEBE sobrevivir la reversion: cambiarR801 de D30 a D31 (afectaL501 y L502), agregar R803->D30 y asignar L501->R803. Resultado actual4 filas: (501,31,801),(502,31,801),(503,31,802),(501,30,803). Confirmar. Estos cambios son ficticios y SOLO en tpi_migracion. Guardar snapshot/hash de la reunion ACTUAL y respaldo/manifest si se requiere antes de retirar objetos.
8. Reversion postCOMMIT: transaccion nueva, bloquear escritores sobre ambas tablas normalizadas antes de capturar su reunion, validar de nuevo FDs/PK/FK, reconstruir una tabla heredada NUEVA con el JOIN ACTUAL (4 filas), no con el checkpoint viejo3 filas. Comprobar EXCEPT ALL bilateral y huella/valor contra la reunion capturada. Sustituir atomicamente la vista por la tabla reconstruida y retirar solo objetos normalizados nuevos que queden fuera de uso; preservar el checkpoint previo 3 filas. COMMIT solo si todo coincide. No tocar fuentes public. En error, ROLLBACK debe dejar la version normalizada operativa intacta.
9. Validacion desde conexion nueva: control_legacy es tabla con4 filas y coincide con el snapshot previo a reversion; checkpoint original sigue3 filas e igual a su hash. Esto demuestra que no se perdieron cambios confirmados posteriores a migrar. Huellas public y de la fuente global siguen iguales. No presentar restaurar un backup viejo como prueba de reconciliacion de esos cambios.

## Evidencia y artefactos previstos (no implementados aun)

- Tres specs reales de Kiro con prompts/respuesta/provenance, previas al codigo.
- Scripts nuevos versionados para preparar, migrar, revertir y verificar, con wrapper que controla transacciones. La misma implementacion de migracion debe usarse para ROLLBACK y COMMIT; no dos variantes divergentes.
- Runner nuevo que captura SQL, SQLSTATE, filas, diferencias bilaterales, huellas/checkpoints, tipo de objeto antes/despues, filas maestros solo IDs, sesiones concurrentes/esperas y tiempos. Comprueba exitcodes y evita assert eliminable con -O.
- Mantener outputs/evidencias historicos sin cambios; nuevas pruebas identificadas TPI10/11/2026. No falsear lectura humana.
- Code review real OpenCodePlan de cada fuente NUEVA luego de generar y antes de ejecutar; los 83 + 7 antecedentes ya revisados no deben modificarse para esta prueba.
- Informe breve vincula objetivo2 a nueva spec/migracion+rollback+down4 filas; objetivo 1 a FD/FNBC yobjetivo 3 a MVhistoria.

## Criterios de aceptacion a expresar EARS

- WHEN la base o el esquema no son los previstos, THEN abortar antes de escribir.
- WHEN la fuente violaR->D, THEN rechazar sin migracion parcial ni arbitrariedad.
- WHEN la migracion se revierte antes deCOMMIT, THEN recupera esquema/datos originales exactos.
- WHEN se confirma la migracion, THEN reunion normalizada equivale en ambos sentidos a la fuente y sus multiplicidades.
- WHEN dos escritores compiten por mismo LD, THEN no pueden confirmar ambos y violar LD->R.
- WHEN la reversion postCOMMIT se ejecuta despues de cambios validos, THEN conserva esos cambios desde el JOIN actual, no desde un checkpoint obsoleto.
- WHEN ocurre error durante la reversion, THEN la transaccion restaura la version operativa normalizada anterior completa.
- WHEN termina el ensayo, THEN public yfuente oficial conservan las huellas y datos anteriores.

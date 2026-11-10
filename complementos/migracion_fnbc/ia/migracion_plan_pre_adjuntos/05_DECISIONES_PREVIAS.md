# Decisiones tecnicas de Codex previas a generar el complemento FNBC

Fecha: 10/11/2026. Son precisiones de implementacion y prueba que complementan la respuesta genuina de Kiro. No se editan las respuestas originales ni se atribuyen estas decisiones a Kiro. No son aprobacion humana del equipo. No contienen implementacion SQL.

## 1. Fixture antes de concurrencia

La prueba de UPDATE maestro valido R801 de D30 a D31, mencionada antes de la concurrencia, debe hacerse dentro de una transaccion y terminar en ROLLBACK. Se comprueba que el cambio valido es aceptado, pero se recuperan exactamente las tres filas originales antes de probar escritores. Los cambios CONFIRMADOS que producen cuatro filas ocurren solamente en la fase posterior a concurrencia: R801 a D31, R803 a D30 y asignacion L501 a R803. No contaminar el estado que usa el caso A/B.

## 2. Checkpoint protegido

La preparacion deja control_legacy como tabla de tres filas y un checkpoint inicial separado de tres filas. Despues de cargar el checkpoint se instala proteccion de escritura que rechaza INSERT/UPDATE/DELETE/TRUNCATE con SQLSTATE 25006. Se registra el hash y se verifica al terminar. Se trata de proteccion de aplicacion dentro del ensayo: un propietario privilegiado siempre puede alterar/deshabilitar mecanismos; no afirmar invulnerabilidad frente al administrador.

## 3. Archivo normalizado tras la reversion

La reversion no usa DROP ni CASCADE. Bloquea las dos tablas normalizadas, toma su JOIN ACTUAL de cuatro filas, reconstruye una tabla heredada nueva, compara multiconjuntos/huellas y renombra la vista vieja a control_legacy_fnbc_archivada. La tabla reconstruida ocupa control_legacy. RD, LR, guardia, funciones y triggers se conservan. Una marca de ciclo activo=false queda confirmada dentro de la misma transaccion; los triggers BEFORE STATEMENT de ambas tablas rechazan cualquier DML posterior con SQLSTATE 25006, incluido TRUNCATE si se expone esa operacion. Esto hace efectiva la politica de no escribir el archivo normalizado y evita describir como inmutable una vista sobre tablas aun modificables por la aplicacion. No se afirma que el propietario no pueda desactivar esa proteccion.

La guardia de concurrencia actualiza turno=NOT turno antes de escribir RD o LR y valida LD->R despues de la sentencia mediante JOIN. El rechazo por ciclo inactivo debe ocurrir antes de modificar tablas archivadas. Durante la reversion la marca se desactiva solamente despues de reconstruir/comprobar datos y antes de COMMIT.

## 4. Errores exactos y reversibilidad

- FD R->D invalida antes de migrar: 23514.
- PK de R duplicado, PK LR duplicada y duplicado LD a traves del JOIN: 23505.
- FK inexistente: 23503.
- Escritura al checkpoint o a RD/LR tras archivar: 25006.
- Error inyectado de la reversion: SQLSTATE dedicado de laboratorio, declarado en el runner; no capturar cualquier excepcion como exito.

Se usa el MISMO cuerpo de migracion para ensayo ROLLBACK y ejecucion COMMIT. El error inyectado durante down debe ocurrir despues de suficientes pasos de reconstruccion/renombrado para demostrar que ROLLBACK recupera los objetos y las cuatro filas normalizadas originales. Desde conexion nueva se verifican nombres, tipos de objeto, estado del ciclo y huellas. Nunca se presenta un ROLLBACK en otra conexion como reversion de un COMMIT anterior.

## 5. Cliente de base de datos y captura segura

Para evitar una dependencia nueva se puede reutilizar SIN CAMBIOS el cliente ya revisado unidad5/tools/libpq_client.py. API relevante: Connection(user,password=None,host=None,port=None,dbname=None,application_name=...,secret_file=...); execute(sql,params=None) devuelve QueryResult(columns,rows,status,sqlstate); las filas son tuplas de texto/None; DatabaseError.sqlstate contiene el estado observado y el error no imprime mensajes brutos. Connection es de un solo propietario: cada escritor concurrente crea y cierra su propia conexion dentro de su hilo. Usar un monitor independiente para observar pg_blocking_pids y wait_event_type=Lock antes de liberar la primera sesion. El runner no debe interpolar credenciales en SQL, imprimir secretos ni exportar filas de usuario. Todas las escrituras apuntan a la copia de nombre exacto.

## 6. Secuencia de autoria y review

Las tres specs finales reales de Kiro deben guardarse y confirmarse en Git antes de llamar OpenCode Build. Esta nota y el contrato se adjuntan como contexto complementario identificado Codex. El wrapper nuevo comprueba los bytes de las tres specs contra el commit anterior y bloquea cualquier consulta si falta esa evidencia. Build y Plan son consultas reales --pure, permission=deny y cero uso de herramientas. Ningun SQL se ejecuta antes de lectura tecnica y Plan; la generacion original, los cambios y sus decisiones permanecen conservados. No se modifica ni reetiqueta historia U4 ni las fuentes previas congeladas.

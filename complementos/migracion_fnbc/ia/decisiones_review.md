# Decisiones tecnicas del complemento FNBC

Codex: revision automatizada, sin firma humana. Originales conservados; no hubo ejecucion de base antes de cerrar el Plan final. Revision humana pendiente.

## FD01 - corregido

Origen: Codex y QA independiente sobre Build.

El runner suponia dump junto al manifiesto; U6 real usa logs/ y backups/ hermanos.

Accion: Resolver exclusivamente basename seguro en ubicaciones conocidas, exigir candidato unico y comprobar formato, bytes y SHA256; no modificar manifiesto real.

Evidencia: `reproducir.py`, `README.md`, `ia/generacion_original/reproducir.py`.

## FD02 - corregido

Origen: Codex y QA independiente sobre Build.

El runner exigia64hex a baseline.fingerprints; la receta real U6 es MD5 de32, distinta del SHA256 del dump.

Accion: Validar MD5 de32 en baseline y mantener SHA256 de64 para el dump. No comparar recetas diferentes ni falsificar hashes.

Evidencia: `reproducir.py`, `README.md`, `ia/generacion_original/reproducir.py`.

## FD03 - corregido

Origen: Codex y QA independiente sobre Build.

La puerta de provenance exigia campos que el wrapper real no genera, como mode,tool_events y decision de Plan.

Accion: Leer pure,permission_config,tool_event_count,kiro_specs_frozen_before_call y demas campos reales; mantener originales y separar cobertura/decision automatizada Codex de los metadatos del proveedor.

Evidencia: `reproducir.py`, `README.md`, `ia/migracion_build_metadatos.json`.

## FD04 - corregido

Origen: QA independiente sobre runner Build.

La negativa FD invocaba solo fn_check_fd_rd, sin intentar el cuerpo real de migracion.

Accion: Ejecutar el MISMO migrar.sql dentro del caso negativo; capturar23514 y verificar rollback/catalogo/objetos intactos.

Evidencia: `reproducir.py`, `migrar.sql`, `ia/generacion_original/reproducir.py`.

## FD05 - aceptado

Origen: Codex, reproducibilidad complementaria.

Construir manualmente el indice de revision real agregaba riesgo operativo de campos inventados o fuentes no coincidentes.

Accion: Agregar preparar_proveniencia.py, helper Codex sin conexiones, incluido entre las seis fuentes y en Plan. Exige flag tecnico explicito; no afirma revision humana.

Evidencia: `preparar_proveniencia.py`, `reproducir.py`, `README.md`.

## FD06 - corregido

Origen: Codex, precision de evidencia RF08.

El Build agrupaba las cinco huellas como cuatro tablas de control y una agregacion del resto, lo que dificultaba verificar las cinco tablas centrales de Food Store por separado.

Accion: Informar categoria/producto/usuario/pedido/detalle_pedido individualmente y una sexta huella de extensiones/catalogo; conservar la proteccion mas amplia.

Evidencia: `reproducir.py`, `README.md`.

## FD07 - corregido

Origen: OpenCode Plan pre, hallazgo1; cobertura completa de seis fuentes.

La validacion de SAVEPOINT [a-z_]+ rechazaba los digitos presentes en nombres internos que incluyen SQLSTATE23505/25006, abortando las pruebas antes del SQL.

Accion: Permitir [a-z_][a-z0-9_]* para identificadores internos, manteniendo exclusion de espacios/separadores y primer digito; renovar hashes y review FULL final antes de ejecutar.

Evidencia: `reproducir.py`, `ia/migracion_plan_pre_respuesta.md`, `ia/migracion_plan_pre_metadatos.json`.


## Cierre Plan final

OpenCode Plan final leyo las seis fuentes completas y los rangos1-740/741-1480 del runner, sin truncado ni hallazgos bloqueantes adicionales. FD07 corregido. Es revision estatica automatizada; aun no acredita ejecucion ni revision humana. Los metadatos/respuesta originales se conservan en migracion_plan_final_*.

# Respaldo programado del integrador

Complemento nuevo del 10/11/2026. La Unidad 6 original propuso frecuencias y ejecutó backup/restore manuales; no instaló tareas. Este complemento aporta una configuración diaria y un ensayo programado temporal, con evidencia separada. Estado actual: generación y revisiones reales de OpenCode cerradas, disparo diario real verificado, respaldo y restauración desde ese mismo último respaldo correctos. La tarea temporal fue retirada; no hay un servicio permanente activo.

## Procedencia

OpenCode 1.18.23, agente Build, recibió sólo SPEC nueva, sin fuentes U6, credenciales, datos ni identidades personales. La respuesta completa y cuatro archivos originales están en `ia/`. Codex leyó todas sus líneas y contrastó localmente la interfaz U6. Se adaptó únicamente el runner nuevo para consumir el manifiesto real y permitir ACL heredadas estrictamente limitadas. La primera propuesta asumía explícitamente otro contrato porque la SPEC no enumeraba los campos; no se presenta como un formato observado ni una ejecución exitosa. La revisión técnica automatizada no constituye revisión o firma humana.

## Archivos y contrato

Mantener juntos `run_backup_job.ps1`, `crear_tarea_diaria.ps1` y `tarea_diaria.template.xml`. El backup original de U6, su `validaciones.sql` y `tools/ps_common.ps1` permanecen intactos y se indican mediante U6Root.

Crear fuera de Git un JSON privado con exactamente U6Root, PgBin, DbUser=u5_bootstrap, HostName=127.0.0.1, Port, PassFile, BackupWorkDir y WindowExpiresUtc. Las rutas son locales absolutas. PassFile contiene sólo una ruta; las contraseñas permanecen en PGPASSFILE externo, nunca en scripts, argv o XML. El resultado y el XML operativo deben escribirse en destinos privados nuevos. No se sobrescriben archivos ni tareas existentes.

La privacidad se verifica por propietario y todas las entradas Allow: usuario actual, SYSTEM y Administradores. OWNER RIGHTS sólo se admite si el propietario es el usuario actual. Se permite herencia de esas mismas identidades; otras entradas o rutas redirigidas/Git causan rechazo. El programa no cambia permisos ajenos.

WindowExpiresUtc es UTC futuro y hasta 60 minutos: lo establece el operador únicamente tras coordinar una ventana sin escritores. El chequeo de otras sesiones cliente es una observación, no un bloqueo de conexiones futuras. La configuración diaria no renueva esa confirmación: si expira, falla segura antes del backup.

El runner invoca U6 en proceso hijo PowerShell7.5+, con `-ConfirmNoWrites` sólo tras los controles. El manifiesto real tiene status/database/file/size/sha256/startUtc/endUtc/baseline; el dump se encuentra en backups y el manifiesto en logs del directorio privado. Cinco conteos y cinco MD5 completos, dos invalidaciones cero; SHA256 verifica el dump. Se exige exactamente un SUCCESS nuevo, archivo/tamaño/hash correctos, código nativo0 y creación exclusiva del resumen. No se hace restore, DROP ni escritura SQL de negocio.

## Configuración diaria y ensayo

La plantilla usa CalendarTrigger diario (DaysInterval=1), InteractiveToken del usuario actual, LeastPrivilege, sin contraseña guardada, sin elevación, sin inicio manual, sin reintentos, IgnoreNew y límite de 10 minutos. Requiere equipo encendido y sesión iniciada. `crear_tarea_diaria.ps1` sin FirstRun propone próximo horario de las 02:00 UTC-03; ExportOnly genera XML privado sin registrar. El XML de plantilla con marcadores sirve para revisar; el creador inserta los valores reales con DOM y TASK_CREATE, sin reemplazar tareas.

Ejemplo genérico, sustituyendo rutas locales privadas:

`pwsh -NoProfile -File .\crear_tarea_diaria.ps1 -ConfigPath 'C:\Privado\config.json' -ResultDirectory 'C:\Privado\resultados' -XmlPath 'C:\Privado\diario.xml' -ExportOnly`

En el ensayo se registra un nombre FoodStore-TPI-Lab-[GUID], trigger DIARIO con primer disparo a 90 s futuro y ventana coordinada. Se espera al Programador; no se usa Start-ScheduledTask para simularlo. Se correlacionan LastRunTime/LastTaskResult con el nuevo resumen SUCCESS y manifiesto. Se exporta XML real y se sanea SID/rutas, conservando calendario/token/runlevel/resultado. Tras finalizar se deshabilita y retira exclusivamente esa tarea temporal. No se borran respaldos ni otras tareas.

Una tarea diaria registrada, ensayada y retirada acredita configuración y ejecución programada de laboratorio; no un servicio permanente activo. Para operación continua el responsable debe gestionar ventanas, disponibilidad, monitoreo, retención y copia cifrada externa. El ensayo histórico U6 conserva RTO de 11,350 s del 03/11. Este complemento realizó además una restauración nueva del 10/11 desde su propio respaldo programado: RTO de 13,430 s y antigüedad19,074 s; ambos registros se mantienen separados.

## Correcciones verificadas tras primer Plan

Se exige preparar `BackupWorkDir/backups` y `BackupWorkDir/logs` antes del registro; el runner valida ambos destinos antes de delegar escrituras. Sólo busca `logs/*.manifest.json`, sin recorrer JSON ajenos. El formato de basename es el New-RunToken real de U6, documentado en SPEC. El ensayo conserva SHA256 del XML operativo original y del XML exportado, guardados privados; entrega una copia saneada y su hash. Los tres hallazgos del primer Plan quedan aceptados y corregidos/aclarados con estos artefactos; no se atribuyen incidentes de exposición observados.

El segundo Plan señaló sustitución desde un ancestro modificable. El runner final comprueba además propietarios y permisos efectivos peligrosos en todos los ancestros, sin rechazar simples derechos de lectura/tránsito. La raíz Windows puede pertenecer a TrustedInstaller, resuelto localmente como excepción sólo para ancestros; no para los archivos privados. Las ACL observadas del laboratorio no mostraron concesiones de sustitución a terceros. No se cambió ninguna ACL anterior ni se afirma exposición real.

## Resultados reales del 10/11/2026

- Registro diario con primer disparo 14:37:41 UTC-03, observado por el Programador. LastTaskResult=0; no se utilizó Start-ScheduledTask. Principal CIM Interactive/Limited, sin contraseña almacenada.
- El XML solicitado tiene LeastPrivilege; Windows omitió ese valor predeterminado al exportar. La evidencia conserva esa omisión y el valor Limited observado por CIM, sin insertar un nodo ficticio en la exportación saneada.
- Respaldo custom de 8.224.005 bytes, SHA256 `8067e36dca81ea6b8c5a870d1bddc2927634a33aad842d22d96bf09c1bd82b19`. Dump/credenciales/XML operativos originales permanecen privados fuera de Git.
- Restauración nueva desde ese mismo último manifiesto SUCCESS: RTO monotónico13,4303715 s; antigüedad desde inicio de pg_dump: 19,0739065 s. Los cinco conteos y huellas coincidieron, invalidaciones 0/0. Ver `evidencias/restauracion_tpi_resultado.json` y `informe_post_incidente_tpi.md`.
- Se conservó la copia anterior mediante RENAME exacto a foodstore_restore_test_u6_conservada_20261110, sin DROP. Se creó otra foodstore_restore_test aislada. La fuente foodstore conserva sus cinco huellas; U6 original conserva sus bytes.
- Se deshabilitó y retiró sólo la tarea temporal creada. PG quedó disponible para el ensayo coordinado siguiente; ese estado es de cierre de esta etapa, no una garantía futura.

Dos fallos previos se conservaron: declaración UTF-8 en BSTR de RegisterTask (corregida sólo en clon del DOM, microrevisión Plan completo de 336 líneas aprobado), y un verificador operativo de Codex que exigía un RunLevel explícito omitido en la exportación de Windows (se corrigió para contrastar CIM). No produjeron respaldos ni alteraron filas; las tareas diagnósticas se retiraron. No se atribuye el segundo fallo a OpenCode.

OpenCode realizó cinco consultas reales: Build, tres Plan completos y un microrevisión Plan del creador corregido, todas sin herramientas. `ia/decisiones_review.*` registra decisiones técnicas y justificaciones. La revisión y las ejecuciones son asistencia de Codex: no firmas ni declaraciones ficticias de lectura humana.

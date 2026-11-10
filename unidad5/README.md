# Food Store — Trabajo práctico Unidad 5

**Integrantes:** Exequiel Arancibia y Joaquin Romero.
**Asignatura:** Base de Datos II — UTN, ciclo 2026.
**Motor verificado:** PostgreSQL 17.11 sobre Windows.

La resolución continúa los TP1 a TP5 y la Unidad 4. El ZIP contiene el repositorio y su carpeta `.git`, con commits progresivos; el PDF reúne las explicaciones paso a paso. Las pruebas técnicas A–D están completas. La persona solicitante dio conformidad al cierre mediante su pedido final de entrega; su respuesta y el alcance de esa conformidad se registran en `docs/validacion_humana.md`.

## Archivos principales

| Parte | Resolución y evidencia |
|---|---|
| A | `sql/roles.sql`; `docs/kiro_roles_spec/requirements.md` y `design.md`; `docs/informe_roles.md`; salidas reales de `\du`, ACL y comparación exacta en `docs/evidencias/a_*`. |
| B | `sql/configurar_auditoria.sql`, `sql/auditoria_test.sql`; `docs/informe_auditoria.md`; `docs/log_auditoria_prueba.txt`. |
| C | `sql/simulacro_incidente.sql`; `docs/log_simulacro_anonimizado.txt`; respuesta completa `docs/ia/c_reconstruccion_respuesta.md`; `docs/informe_incidente.md`. |
| D | `sql/usuario_anon.sql`; consultas real/copia y resultados lado a lado en `docs/verificacion_equivalencia.md`; resultados originales `docs/d_ejecucion_psql.txt` y `d_equivalencia.json`. |
| E | `BITACORA.md`; prompts, respuestas y procedencia en `docs/ia/`; historial Git completo. |

El informe complementario es `docs/TP_U5_FoodStore_Arancibia_Romero.pdf`. Los SQL B/C son catálogos de consultas parametrizadas: se ejecutan mediante el orquestador Python y sus marcadores, no enviando el archivo entero a psql.

## Resultados comprobados

| Comprobación real | Resultado |
|---|---|
| Roles y permisos existentes | Ocho roles; 44 entradas ACL de negocio exactas, sin faltantes ni adicionales; tres membresías INHERIT TRUE, SET FALSE, ADMIN FALSE. |
| Permisos y reset | 52 eventos de verificación aprobados, con conexiones reales app_web/admin_datos y pruebas de grupos claramente identificadas. |
| Objetos futuros | 71 eventos aprobados; public sin acceso automático de negocio; datos_anon con SELECT de reportes; funciones sin EXECUTE público para tres creadores. Probes revertidos. |
| Auditoría | Lectura, inserción, actualización y login PostgreSQL fallido reales; filas de prueba revertidas. |
| Simulacro | Tres fallos comerciales y un éxito; 20.001 filas recibidas y descartadas; escalamiento rechazado con 42501; membresía administrativa false antes y después. |
| Equivalencia | 20.001 filas por copia; dos grupos; diferencias EXCEPT ALL 0/0; propietario rol_propietario y SELECT de reportes verificados. |
| Conservación | Conteos y huellas ordenadas de las cinco tablas de negocio iguales antes/después. |

Los 20.000 usuarios heredados permanecen intactos; una cuenta sintética adicional sirve para autenticación. Se conservan los índices, vistas, reglas TP2, extensión FNBC y materializadas anteriores. La lectura masiva no equivale por sí sola a exfiltración ni identifica a una persona; los permisos por columna no implementan aislamiento por fila.

## Reproducción desde una copia U4

Se requieren Windows, Python y PostgreSQL 17 instalado. La generación del PDF requiere además ReportLab y las fuentes Arial/Consolas de Windows. El operador debe aportar privadamente un respaldo equivalente de su Food Store acumulativo U4: se excluye del ZIP porque contiene datos y credenciales almacenadas. Los hashes del respaldo utilizado y la continuidad están en `docs/continuidad_y_alcance.md`.

Ejecutar desde la raíz del repositorio en PowerShell. Este bloque crea un laboratorio NUEVO; el preparador rechaza un runtime existente y no borra otro servidor.

```powershell
$respaldoU5 = 'C:\ruta-privada\base_u4.dump'
$repoU5 = (Get-Location).Path
$runtimeU5 = Join-Path (Split-Path -Parent $repoU5) 'food-store-tp-u5-runtime'

python .\tools\preparar_laboratorio.py --source-dump $respaldoU5 --runtime $runtimeU5 --port 55605
$env:U5_SECRET_FILE = Join-Path $runtimeU5 'secrets.json'

python .\tools\crear_cuenta_prueba.py
python .\tools\ejecutar_anonimizacion.py --bootstrap
python .\tools\verificar_conservacion.py --phase before --evidence-dir (Join-Path $runtimeU5 'evidencias')
python .\tools\instalar_seguridad.py
python .\tools\ejecutar_pruebas.py --phase permissions
python .\tools\ejecutar_pruebas.py --phase defaults
python .\tools\ejecutar_anonimizacion.py
python .\tools\verificar_matriz.py
python .\tools\capturar_permisos.py

python .\tools\activar_auditoria.py
python .\tools\ejecutar_pruebas.py --phase audit
python .\tools\ejecutar_pruebas.py --phase incident
python .\tools\verificar_conservacion.py --phase after --evidence-dir (Join-Path $runtimeU5 'evidencias')
python .\tools\rotar_log.py
```

Primero D con `--bootstrap` crea la copia previa exigida por la migración A; después D sin esa opción la reconstruye realmente bajo `rol_propietario` y comprueba sus permisos. La adaptación de bootstrap sustituye únicamente la línea SET LOCAL ROLE por CREATE SCHEMA IF NOT EXISTS y registra el SHA-256 del SQL efectivo. La cuenta y los roles se instalan antes de habilitar sentencias en el log; las contraseñas viajan como parámetros y no aparecen en los archivos entregados.

Las especificaciones Kiro conservadas se generaron realmente antes de roles.sql. No hace falta regenerarlas para reproducir el SQL. Si se cambia la política, primero se revisan las matrices y luego el SQL: no se amplían permisos sólo para hacer pasar una prueba.

## Captura y revisión de logs

El JSON nativo permanece en el runtime privado. Después de rotar, se seleccionan las sesiones completas de las ventanas UTC de `audit_resultados.json` e `incident_resultados.json`, correlacionando la zona efectiva de `configuracion_auditoria.json`; el FATAL 28P01 del login fallido se identifica además por rol, instante y session_id.

`tools/anonimizar_log.py` recibe el fragmento privado seleccionado y escribe la copia pública; admite `--application` y `--session`. El procedimiento y las sesiones reales de esta ejecución se registran en `docs/evidencias/logs_procedencia.json`. Se revisa la anonimización antes de consultar a una IA. OpenCode recibió sólo el log C anonimizado y el prompt neutral conservado; no recibió la secuencia del cliente ni los conteos verificados por separado.

Los logs registran sentencias e intentos, incluidos cambios revertidos. No muestran valores OLD/NEW de cada fila ni prueban por sí solos cuántas filas recibió el cliente. La decisión de contención descrita es humana e hipotética; no se ejecutó automáticamente ninguna medida sobre cuentas, red o roles.

## Seguridad del paquete y herramientas de IA

El repositorio excluye respaldos, runtime, claves, hashes de contraseñas y logs originales. Los secretos aleatorios se guardan fuera de Git con ACL Windows restringida al usuario actual, SYSTEM y Administradores. El servidor de pruebas escucha sólo en loopback y usa SCRAM. No se publican filas de usuario ni parámetros de autenticación.

Se usaron Kiro real y OpenCode 1.18.23 con el modelo `openai/gpt-6.1-sol`; las respuestas completas se conservan sin alterar sus bytes. Codex implementó herramientas, integró propuestas y ejecutó verificaciones: esa asistencia automática se distingue de la revisión humana. Los commits usan la identidad técnica Codex y no suplantan a los integrantes.

Para generar el PDF y verificar el paquete, tras guardar y comprometer los informes finales:

```powershell
python .\tools\generar_informe_pdf.py
git add docs/TP_U5_FoodStore_Arancibia_Romero.pdf
git commit -m 'docs: actualizar informe PDF'
python .\tools\empaquetar_entrega.py --dry-run
python .\tools\empaquetar_entrega.py
git log --oneline --reverse
```

El empaquetador exige árbol Git limpio, verifica hashes del manifiesto y comprueba el repositorio restaurado. La entrega prevista por esta guía es el ZIP con Git o un enlace al repositorio; el PDF acompaña esa entrega. El trabajo se deja preparado para que los integrantes lo presenten por el canal del aula virtual.

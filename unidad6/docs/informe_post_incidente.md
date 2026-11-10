# Informe post-incidente - Simulacro U6

Exequiel Arancibia y Joaquin Romero | Base de Datos II | 03/11/2026

## Respaldo utilizado

Base principal `foodstore`, continuadora de U1-U5; PostgreSQL 17.11 y
PowerShell 7.6.5. Se utilizó el último manifiesto SUCCESS, cuyo respaldo
custom comenzó el **03/11/2026 a las 18:56:43,475 UTC-03**
(21:56:43,475 UTC) y se completó a las 18:56:47,637 UTC-03.
El archivo fechado ocupa **8.224.005 bytes**; se verificaron TOC y SHA-256.
La evidencia incluye nombre completo, log y manifiesto sin credenciales.

## Recuperación y objetivos

El ensayo comenzó a las **18:57:15,284 UTC-03**. El cronómetro monotónico
abarcó creación de `foodstore_restore_test`, aislamiento, restauración,
validación y comparación; no se eliminó ni reemplazó `foodstore`.

| Indicador | Previsto para el laboratorio | Observado |
|---|---|---|
| RTO: tiempo de recuperación | <=120 s | **11,350 s**, objetivo cumplido. |
| RPO: antigüedad de la copia de referencia | <=24 h, con respaldo diario exitoso | **31,808 s** al iniciar el ensayo. |

El RPO observado usa el inicio de pg_dump como referencia conservadora del
corte, no la hora final del archivo. No se midió pérdida real ni se probó
PITR; las lecturas previas/posteriores coincidieron en una ventana sin escrituras.

## Validaciones y conservación

Coincidieron categorías **2**, usuarios **20.001**, productos **50.000**,
pedidos **225.000** y detalles **499.997**; productos y detalles inválidos: **0/0**.
Las cinco huellas completas coincidieron. El control complementario posterior
confirmó las 12 tablas base, definiciones heredadas y ambas materializadas;
la principal y el origen U5 permanecieron intactos. El destino queda aislado:
`--no-owner --no-privileges` no recupera la política de roles/ACL de U5.

## Problema, mejora y asistencia

Se detectó que la limpieza del entorno dejaba variables libpq vacías y
provocaba un fallo de conexión; se corrigió con eliminación efectiva de las
variables y se repitieron las pruebas. El fallo real controlado de pg_dump
devolvió error sin publicar copia válida; repetir restauración también abortó.
Mejora propuesta: mantener otra copia cifrada fuera del equipo y verificarla
periódicamente en un servidor independiente.

OpenCode generó la propuesta a partir de SPEC/AGENTS autorizados. La revisión
técnica de Codex corrigió, entre otros puntos, una opción inexistente de
createdb; luego se ejecutaron y verificaron los scripts. La persona solicitante
revisó las conclusiones y confirmó la entrega el 03/11/2026. Esa conformidad
se distingue de las pruebas automáticas y no implica lectura exhaustiva del código.

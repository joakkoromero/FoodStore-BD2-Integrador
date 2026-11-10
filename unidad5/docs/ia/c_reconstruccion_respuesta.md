## Hechos Observados

El registro contiene **una sesión de PostgreSQL** en la base `foodstore_lab`, identificada como `6ada67f0.ee4`, con PID `3812`. El actor identificado por la base es el rol **`app_web`**; el log no identifica a la persona o proceso que lo utilizó.

Todas las horas corresponden al **22/10/2026, zona horaria −03**.

| Hora | Líneas | Actor y operación | Resultado observado y origen |
|---|---|---|---|
| 16:45:52.418 | 1 | Se recibe una conexión. | Origen registrado: `127.0.0.1`, puerto `60572`. |
| 16:45:52.427 | 2–3 | `app_web` se autentica ante PostgreSQL mediante `scram-sha-256`. | Autenticación y autorización de conexión registradas para `foodstore_lab`. Se declara `application_name=u5_incident`. |
| 16:45:52.429 | 4 | Ejecuta `SELECT session_user,current_user;`. | Se registra la consulta, pero no sus valores de respuesta. |
| 16:45:52.430–16:45:52.638 | 5–10 | Realiza tres llamadas parametrizadas a `public.fn_autenticar($1::text,$2::text)`. | Cada llamada genera un mensaje `U5_AUTH success=f`. No se muestran los parámetros. |
| 16:45:52.639–16:45:52.707 | 11–12 | Realiza una cuarta llamada a la misma función. | La función registra `U5_AUTH success=t`. No se identifica qué cuenta o valores se evaluaron. |
| 16:45:52.707 | 13 | Vuelve a ejecutar `SELECT session_user,current_user;`. | No se muestran los resultados; no puede establecerse un cambio de identidad efectiva. |
| 16:45:52.707 | 14 | Solicita `id`, `nombre`, `apellido`, `eliminado` y `created_at` de `public.usuario`, ordenados por `id`, sin filtro `WHERE`. | Se registra la sentencia, pero no filas devueltas, cantidad de registros ni confirmación explícita de finalización. |
| 16:45:52.923 | 15–16 | Intenta `GRANT admin_datos TO app_web;`. | **Rechazado**, con código `42501`: permiso denegado. El detalle indica que se requiere la opción `ADMIN` sobre `admin_datos` para otorgar ese rol. |
| 16:45:52.923 | 17 | Finaliza la conexión. | Desconexión registrada para `app_web`, desde el mismo origen. Duración informada: `0,511` segundos. |

La autenticación inicial ante PostgreSQL y los resultados de `fn_autenticar` son **eventos distintos**: la conexión ya estaba autorizada cuando comenzaron las cuatro llamadas a la función.

## Hipótesis

- La secuencia de tres resultados `success=f` y uno `success=t` es compatible con intentos sucesivos de autenticación mediante la función. **No demuestra fuerza bruta**, ni que se haya usado la misma cuenta o variado la contraseña.
- La consulta de usuarios seguida del `GRANT` es compatible con una exploración de datos y un intento de obtener la pertenencia a `admin_datos`. También podría corresponder a una prueba controlada; el nombre `u5_incident` no acredita por sí solo esa finalidad.
- `127.0.0.1` identifica el extremo de conexión que PostgreSQL observa como local. No permite atribuir el origen a una persona ni descartar intermediarios.

## Límites Del Registro

- Solo hay 17 entradas de una sesión, en un intervalo de aproximadamente medio segundo. No permiten reconstruir actividad anterior, posterior o de otras conexiones.
- No se incluyen credenciales, parámetros de la función, su implementación ni resultados de las consultas. `success=t` acredita el mensaje emitido por la función, no una elevación de privilegios en PostgreSQL.
- No puede confirmarse que se hayan leído o extraído datos de `public.usuario`. La ausencia de un error en este fragmento no sustituye una confirmación de resultado.
- El `GRANT` mostrado fue rechazado. Esto no permite determinar qué otros privilegios o membresías tenía `app_web`, ni si ya pertenecía a `admin_datos`.
- No se observan modificaciones de datos. Tampoco hay información suficiente para afirmar compromiso, intención maliciosa o alcance de un posible incidente.

## Hipótesis De Contención

**Si una persona responsable confirma que esta actividad no estaba autorizada**, podría evaluar restringir temporalmente nuevas conexiones de `app_web` mientras se revisan sus permisos y el componente que usa esas credenciales.

Antes de actuar, debería verificar si se trataba de una prueba autorizada, qué servicios dependen del rol y qué impacto tendría la restricción. La sesión mostrada ya terminó; terminarla no sería una medida aplicable a esa conexión.

Esta es una propuesta condicional, no una conclusión de compromiso ni una instrucción de ejecución. No se ejecutaron herramientas ni acciones.

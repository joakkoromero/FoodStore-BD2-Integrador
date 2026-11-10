## 1. Inventario Exhaustivo

| Archivo recibido | Alcance revisado | Estado |
|---|---|---|
| `tools/ejecutar_pruebas.py` | Archivo completo: importaciones, utilidades, carga del catálogo SQL, conexiones, credenciales, evidencias, comprobación de logging, rechazo de operaciones, fases `audit`, `incident`, `permissions` y `defaults`, pruebas de privilegios futuros y CLI. Incluye todos los auxiliares definidos en el propio archivo. | Revisión estática completa. Se identifican mejoras de robustez y cobertura; no se demuestra una vulnerabilidad efectiva de las ACL desplegadas. |

El adjunto contiene **un único archivo fuente**, completo hasta `if __name__ == "__main__": raise SystemExit(main())`. No se aprecia truncamiento. El último archivo completamente visible es `tools/ejecutar_pruebas.py`.

Las referencias siguientes son **relativas al archivo Python**, contando como línea 1 el comentario `# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.`; equivalen a restar 10 a la numeración del documento adjunto.

## 2. Hallazgos

No identifico un defecto incondicional que demuestre, con este archivo aislado, que una ejecución válida falla o que los roles desplegados tienen permisos incorrectos. Los siguientes hallazgos son **mejoras de robustez o de cobertura**, con condiciones concretas.

| ID | Prioridad | Archivo / línea relativa | Condición concreta | Consecuencia | Certeza y clasificación | Prueba mínima propuesta |
|---|---|---|---|---|---|---|
| U5-C02-01 | Media | `tools/ejecutar_pruebas.py:116–138`, `167`, `229`, `298`, `332` | Los ajustes de logging se consultan únicamente desde una conexión de `bootstrap_user`. Si las conexiones de `app_web` o `admin_datos` tienen ajustes efectivos distintos por configuración de rol, de rol/base o por inicialización de conexión, la precondición del bootstrap puede aprobar aunque las conexiones que reciben credenciales registren parámetros. | La comprobación no garantiza por sí sola la afirmación de que los parámetros sensibles no se registran en las sesiones utilizadas por las pruebas. También podría acreditar una configuración de auditoría que no sea la efectiva en la sesión auditada. | **Mejora de robustez.** La diferencia entre la sesión comprobada y las utilizadas es demostrable. La existencia de configuraciones diferentes y cualquier filtración efectiva son **condicionadas**, no confirmadas. | En una instancia desechable, establecer un ajuste de logging diferente para uno de los logins, reconectar y comparar `pg_settings` desde bootstrap y desde ese login, sin enviar credenciales de negocio. La precondición debería detectar la diferencia antes de ejecutar consultas sensibles. |
| U5-C02-02 | Media | `tools/ejecutar_pruebas.py:140–160`, `256–259` | En `phase_incident`, el intento de escalamiento se envía a `expect_error` sin `savepoint` ni transacción explícita que lo revierta. Si el SQL realiza un `GRANT` de membresía y, por una regresión de permisos, tiene éxito, `expect_error` detecta el éxito inesperado **después** de ejecutarlo. | Bajo autocommit, la membresía podría quedar persistida precisamente cuando la prueba descubre el fallo. La excepción también impide llegar a la comprobación posterior de membresía. | **Mejora de robustez ante una prueba negativa que falla.** La ausencia de contención explícita es visible; la persistencia está **condicionada** al SQL de `incident_attempt_escalation` y a la semántica transaccional de `Connection`, no recibidos aquí. | En una instancia desechable y con roles de prueba, permitir deliberadamente la operación equivalente y ejecutar el rechazo esperado. Comprobar desde una segunda conexión si quedó la membresía. La variante contenida en una transacción con reversión debería fallar la verificación sin dejarla aplicada. |
| U5-C02-03 | Media | `tools/ejecutar_pruebas.py:344–345`, `371–378` | Las pruebas positivas de `fn_resetear_password` consideran suficiente que la llamada no falle; para los límites de 12 y 72 bytes, comprueban solamente que exista una fila de resultado. No verifican que la contraseña nueva autentique al usuario. | Una implementación regresiva que conserve las validaciones de entrada y de usuario inexistente, pero omita actualizar la contraseña, podría superar estas comprobaciones. Una llamada `SELECT` a una función escalar puede devolver una fila aunque su efecto funcional sea incorrecto. | **Mejora de cobertura.** La ausencia de una aserción del efecto es demostrable. Que la función real tenga ese defecto es **condicionado** y no se afirma. | Dentro de la misma transacción, restablecer una contraseña aleatoria válida y comprobar mediante la función de autenticación que esa contraseña devuelve el ID esperado. Mantener el `ROLLBACK` final y no exportar la contraseña ni el hash. Repetir para ambos límites válidos. |

### Controles Existentes Reconocidos

- `expect_error` comprueba SQLSTATE concretos, no simplemente la presencia de cualquier excepción. En las pruebas con savepoints, revierte también operaciones que hubieran tenido éxito inesperadamente.
- Las fases de auditoría, permisos y defaults contienen bloques `finally` con `ROLLBACK`.
- Se distinguen las conexiones reales de `app_web` y `admin_datos` de las pruebas de grupos realizadas mediante bootstrap y `SET LOCAL ROLE`.
- La autenticación de negocio comprueba rechazo de tres contraseñas incorrectas, aceptación de la correcta e identidad SQL inalterada.
- La lectura masiva verifica columnas y cantidad de filas recibidas, descarta el resultado y no vuelca sus valores a la evidencia.
- Las comprobaciones de defaults crean objetos con los roles creadores correspondientes. Para funciones, inspeccionan las ACL de `PUBLIC` y ensayan rechazos efectivos de ejecución.
- El permiso temporal `CREATE` de `rol_funciones` se concede dentro de la transacción de pruebas y se comprueba su ausencia después del rollback.
- Se prueban contraseñas nulas, límites inválidos, un caso multibyte y usuario inexistente, además de los límites válidos.
- La evidencia distingue los intentos registrados por auditoría de la entrega efectiva de filas y declara que no demuestra extracción externa ni intención maliciosa.

## 3. Límites Y Dependencias

**Dependencias no recibidas en esta continuación**
- `libpq_client.py`: no puede verificarse aquí el autocommit, la gestión de transacciones al cerrar conexiones, el enlace de parámetros, la configuración efectiva de conexión ni el saneamiento de los atributos de las excepciones volcados a evidencia.
- `sql/auditoria_test.sql` y `sql/simulacro_incidente.sql`: sus sentencias se cargan por nombre, pero no están reproducidas en este adjunto. Las observaciones sobre su contenido concreto son condicionadas.
- `roles.sql`, funciones de autenticación y restablecimiento, triggers y esquema: no se revalidan desde este archivo. La revisión anterior indicada por el contexto debe interpretarse conjuntamente, sin atribuirle comprobaciones adicionales.
- Configuración efectiva de PostgreSQL y evidencias originales: no están adjuntas; no se acredita que los prerrequisitos hayan sido satisfechos en una ejecución real.

**Limitaciones explícitas, no defectos**
- La matriz se presenta como mínima y declara que no sustituye la comparación completa de ACL con la especificación. No corresponde interpretar su aprobación como demostración exhaustiva del mínimo privilegio.
- El rollback no recupera valores consumidos por secuencias ni elimina logs. `phase_audit` lo declara expresamente.
- El incidente declara `containment_executed=False`; no simula una contención operativa completa.
- La comparación de cantidades antes y después no demuestra igualdad de todo el contenido. En este laboratorio, el rollback es el control principal de reversión; los conteos son una comprobación adicional.
- Las comparaciones de cantidades y la selección de fixtures presuponen datos suficientemente estables durante la prueba. La actividad concurrente podría producir fallos de verificación sin implicar una regresión de permisos.

La revisión fue exclusivamente estática sobre el texto recibido: **no utilicé herramientas, no ejecuté pruebas ni modifiqué archivos**. No acredita las pruebas históricas ni aprobación humana.

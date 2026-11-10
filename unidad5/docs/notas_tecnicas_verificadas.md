# Referencias y precisiones técnicas

Se consultó la documentación primaria de PostgreSQL 17 y pgAudit el 21/10/2026.

- `ALTER DEFAULT PRIVILEGES` afecta objetos futuros creados por el rol indicado, no corrige los existentes. El `REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC` debe aplicarse globalmente para cada creador; un `REVOKE` limitado a un esquema no elimina el permiso global predeterminado. [Documentación oficial](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html).
- Los privilegios de tabla, columna y membresía son distintos. Una membresía puede heredar permisos sin habilitar `SET ROLE` ni `ADMIN OPTION`; la propiedad sigue otorgando capacidades que un simple `REVOKE` de tabla no elimina. [GRANT](https://www.postgresql.org/docs/17/sql-grant.html).
- Una función `SECURITY DEFINER` necesita un `search_path` seguro, referencias calificadas y permisos de ejecución restringidos; debe revocarse el permiso público en la misma transacción que la crea. [CREATE FUNCTION](https://www.postgresql.org/docs/17/sql-createfunction.html).
- Los parámetros de log no ocultan secretos escritos como literales SQL. `log_parameter_max_length=0` y `log_parameter_max_length_on_error=0` se combinan aquí con parámetros enlazados; en Windows el control del archivo corresponde a las ACL, porque `log_file_mode` se ignora. [Configuración de logs](https://www.postgresql.org/docs/17/runtime-config-logging.html).
- Se usa SCRAM para las conexiones de PostgreSQL; esa identidad del motor es distinta de la autenticación de un usuario de Food Store. [Autenticación por contraseña](https://www.postgresql.org/docs/17/auth-password.html).
- La guía menciona detalle fila por fila con pgAudit. La extensión registra auditoría de sesión y objeto; `pgaudit.log_rows` agrega cantidades de filas, no los valores `OLD` y `NEW` de cada una. Para un historial de valores se requiere una solución adicional, por ejemplo disparadores de auditoría protegidos o CDC. [Proyecto oficial pgAudit](https://github.com/pgaudit/pgaudit).

Estas precisiones se aplican al diseño y a la lectura de la evidencia; una consulta registrada no demuestra por sí sola entrega de todas sus filas ni exfiltración fuera del servidor.

-- Parte B: aplicar como administrador del laboratorio, fuera de una transaccion.
-- logging_collector=on y stderr,jsonlog ya se fijan al crear el cluster privado.
-- all incluye SELECT para que la lectura masiva de C sea visible en el log.
ALTER SYSTEM SET log_connections='on';
ALTER SYSTEM SET log_disconnections='on';
ALTER SYSTEM SET log_statement='all';
ALTER SYSTEM SET log_min_error_statement='error';
ALTER SYSTEM SET log_parameter_max_length='0';
ALTER SYSTEM SET log_parameter_max_length_on_error='0';
SELECT pg_catalog.pg_reload_conf();
-- Verificar estos valores en una CONEXION NUEVA antes de las pruebas.

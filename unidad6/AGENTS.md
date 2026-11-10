# Instrucciones del laboratorio U6

- Para la consulta de generación de OpenCode: leer SPEC_U6.md antes de
  proponer scripts y responder sin herramientas ni ejecución. El operador
  revisará y probará con sus herramientas. No inventar métricas o resultados.
- PowerShell 7, PostgreSQL 17 nativo en Windows. Parámetros HostName, Port,
  DbUser, PgBin, WorkDir; nunca usar $Host/$HOME como variables propias.
- Conexiones con -w, PGPASSFILE externo y PGCONNECT_TIMEOUT. No contraseñas
  en scripts, prompts o logs. No cargar .env, perfiles ni datos personales.
- Base principal literal foodstore. Crear sólo foodstore_restore_test con
  createdb --template=template0. Si existe, abortar; nunca DROP/--clean/--create.
- Verificar inmediatamente LASTEXITCODE de cada ejecutable. psql -X con
  ON_ERROR_STOP=1. Error nativo o validación falsa => exit 1 y log FAILED.
- Backup -Fc con nombre UTC fechado único, archivo .partial hasta éxito;
  luego validar TOC con pg_restore --list, tamaño y SHA-256, mover sin sobrescribir
  a .dump y guardar manifiesto JSON. Logs y dump fuera del repositorio.
- Seleccionar último respaldo completado mediante manifiesto exitoso y
  comprobar tamaño/hash; no elegir un parcial por su fecha. No sobrescribir.
- Health: tamaño, numbackends/transacciones, pg_stat_user_tables y consultas
  activas. No mostrar datos de usuarios ni SQL con credenciales o literales.
- Maintenance: observar configuración autovacuum y estado antes de la acción;
  ANALYZE puntual sólo con decisión justificada. Sin VACUUM FULL ni cambios
  de autovacuum globales. Distinguir estimaciones de COUNT real.
- Modelo real: public.categoria(2), producto(50000), usuario(20001),
  pedido(225000), detalle_pedido(499997). usuario equivale a cliente; no crear
  otra tabla ni eliminar columnas. Son conteos de U5 a verificar, no resultados U6.
- detalle tiene PK(pedido_id,producto_id), cantidad y precio_unitario;
  subtotal GENERATED. pedido.total deriva de detalles. U4 agregó FNBC y MV
  diaria; TP5 tiene MV mensual; U5 agregó datos_anon y funciones DEFINER.
- Conteos e invalidaciones deben producir JSON de agregados únicamente;
  compararlos de forma ejecutable con línea base anterior al backup.
- RTO: Stopwatch justo antes de createdb, detener tras validación SQL y
  comparaciones exitosas. Preflight fuera del intervalo. RPO usa inicio del
  backup y principio del ensayo, nunca la hora de cierre como si fuera snapshot.
- pg_restore --no-owner --no-privileges --exit-on-error -d destino. No afirmar
  que recupera roles/ACL: los DEFINER cambian de dueño; el restaurador debe
  aislar la base y revocar conexión/esquemas/EXECUTE públicos sin reabrirla
  a app_web. No ejecutar roles.sql U5 sobre estos nombres distintos.
- Entrega: PDF único con SPEC e informe breve separados de los anexos.
  No programar tareas reales ni enviar a terceros.

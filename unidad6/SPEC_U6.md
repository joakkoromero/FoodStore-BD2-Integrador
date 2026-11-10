# SPEC_U6 - Mantenimiento de Food Store

Integrantes: Exequiel Arancibia y Joaquin Romero. PostgreSQL 17; Windows.

## Alcance y reglas

Continuar la base acumulada U1-U5 en una copia privada llamada `foodstore`.
Conservar usuario (equivalente a cliente de la guía), catálogo, pedidos,
detalle, índices, vistas, materializadas y extensión FNBC. El origen U5 se
conserva. El ensayo sólo crea `foodstore_restore_test`; abortar si ya existe.
No eliminar ni reemplazar foodstore; no usar DROP, --clean ni --create al
restaurar. Operar en loopback con pg_dump/pg_restore 17 y autenticación SCRAM.
Las claves se obtienen mediante PGPASSFILE privado con ACL restringida,
nunca desde el código, argv, logs entregados ni adjuntos de IA.

| Tarea | Frecuencia propuesta | Condición de éxito y evidencia |
|---|---|---|
| Respaldo custom | Diaria, 02:00 | pg_dump sale 0, archivo fechado no vacío, TOC legible y log; publicar .dump sólo al completar; conservar SHA-256. |
| Salud | Diaria, 02:15 | Ejecutar health_check.sql con ON_ERROR_STOP: tamaño, conexiones, tablas y consultas activas. |
| Mantenimiento | Semanal, domingo 03:00 | Revisar autovacuum/ANALYZE y tuplas muertas; justificar ANALYZE puntual por la observación de la copia. Sin VACUUM FULL periódico. |
| Restauración de prueba | Semanal, domingo 03:30 | Base nueva validada: cinco conteos iguales a la línea base, productos/detalles inválidos 0; fallo implica salida no cero. |

## Medición y aceptación

RPO previsto <=24 h con respaldo diario exitoso; RTO previsto <=120 s en
este laboratorio. Medir RTO con reloj monotónico inmediatamente antes de
createdb y hasta finalizar las validaciones. Antigüedad observada al inicio
del ensayo desde el inicio del respaldo: referencia conservadora del corte,
no prueba de pérdida real ni recuperación a un instante (PITR).
Registrar horarios UTC y UTC-03, tiempos, tamaños, hashes y resultados.
Comparar además huellas completas de las tablas para verificar conservación.
La programación es propuesta: primero ejecutar manualmente y comprobar fallos.

## Entrega y revisión

Un único informe_u6.pdf con esta especificación (<=1 página), informe
post-incidente (<=1 página), evidencias y anexos con fuentes completos.
Incluir fuentes extraíbles como adjuntos del PDF; omitir dump y datos privados.
OpenCode recibe SPEC y AGENTS sin datos; conservar prompt/respuesta, revisar
cada comando y probar antes de aceptar. Distinguir revisión automática de
la intervención humana. La restauración sin owners/ACL no certifica recuperar
la política de roles U5: la copia descartable no se habilita a la aplicación.

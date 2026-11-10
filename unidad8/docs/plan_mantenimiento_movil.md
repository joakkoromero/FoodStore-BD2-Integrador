# Extensión del plan U6: PostgreSQL, MongoDB y tablets

Propuesta operativa para el proyecto; no se instaló una tarea programada nueva.

| Elemento | Respaldo y frecuencia propuesta | Prueba de restauración y responsable |
|---|---|---|
| PostgreSQL oficial | Backup custom diario y antes de cambios; custodia privada fuera del repositorio. Mantener el objetivo U6 RPO<=24h y RTO<=120s bajo las condiciones ensayadas, no como garantía universal. | Semanal, administrador de datos: restaurar en otra base aislada, comparar conteos/huellas y validar esquema, índices, reglas y permisos. Una restauración sin owners/ACL no reconstruye por sí sola la seguridad U5. |
| SQLite de tablet | Copia consistente con la API backup de SQLite al cierre de turno y antes de migraciones. Conservar borradores, ítems, UUID y cola; el catálogo es reconstruible. Proteger el archivo con permisos del sistema operativo. | En otra ruta: integrity_check=ok, foreign_key_check vacío y comparación de borradores/solicitudes. Responsable: encargado de la feria con soporte. |
| MongoDB U7 | Versionar el esquema, consultas y exportación EJSON del subconjunto experimental sin datos personales. Si se usa operativamente, respaldar la colección con la política correspondiente. | Reconstruir la colección aislada y repetir conteos/IDs de consultas frente a la fuente. Responsable: administrador. No promover la copia documental a autoridad de stock o ventas. |

## Si se restaura un PostgreSQL más viejo

1. El administrador informa el evento y bloquea temporalmente la sincronización de ventas reales; conserva evidencia de las colas.
2. Todas las tablets invalidan sus cachés e instantáneas y descargan un catálogo completo nuevo, incluidas lápidas. No depende de un umbral de antigüedad ni de la hora del teléfono.
3. Se conservan borradores y UUID históricos; soporte reconcilia con el servidor qué solicitudes fueron realmente procesadas antes de reenviar. Una respuesta verde previa basada en un catálogo anterior no se reutiliza como confirmación.
4. Se vuelve a validar precio, disponibilidad y stock. En producción, UUID único y creación de venta pertenecen a la misma transacción PostgreSQL. Este TP no implementa esa venta.

## Conflictos y rechazos

Durante la feria, el encargado revisa la cola al recuperar conexión y cada quince minutos; al cierre de turno no debe quedar una solicitud sin tratamiento. CONFLICTO de precio se consulta al cliente y genera otro UUID tras aceptar, conservando el anterior. RECHAZADO se corrige según stock, disponibilidad o baja y sólo se reenvía un borrador coherente. Soporte/administrador revisa diariamente los casos no resueltos; no hay aprobación automática por antigüedad ni cambio manual del stock para forzar un verde.

## Evidencia de continuidad

En U6 se ensayó restauración aislada con RTO observado de 11,350 s; no equivale a una garantía para otra máquina o volumen. Antes de U8 se ejecutó nuevamente el script probado de backup U6: SUCCESS, 8.224.005 bytes, manifiesto y huellas iguales antes/después. Los dos laboratorios U8 produjeron además backups custom privados antes de su fixture; sus metadatos están en la evidencia. Los dumps no forman parte del ZIP.

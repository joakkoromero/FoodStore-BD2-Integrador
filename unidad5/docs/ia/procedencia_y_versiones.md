# Procedencia y versiones de las consultas

Los metadatos guardan los SHA-256 de los bytes del prompt, la respuesta y los adjuntos al momento de cada consulta real. No se recalculan retrospectivamente para hacer coincidir una versión posterior de un archivo.

Los archivos bajo `docs/ia/` y el contexto inicial de planificación se conservan sin conversión automática de finales de línea en Git. Esto permite mantener los bytes originales de las respuestas, incluidos sus finales CRLF cuando corresponde. Los demás fuentes usan LF de forma consistente.

En la consulta `bc` los adjuntos `sql/auditoria_test.sql` y `sql/simulacro_incidente.sql` eran los borradores previos a la respuesta. Luego se integró la propuesta recibida y se aplicaron las correcciones documentadas en `bc_validacion_tecnica.md`. Por eso los hashes originales de esos adjuntos no deben compararse con el SQL final como si fueran la misma versión; la respuesta conservada y la nota de validación distinguen las etapas. Los metadatos originales permanecen sin modificar.

Las respuestas completas provienen del campo de texto de los eventos reales de OpenCode, sin inventar resultados ni transcribir razonamiento interno. Los eventos de transporte y diagnósticos originales se guardan fuera del repositorio. El intento inicial de D que falló por el sandbox quedó identificado como fallido; no se presenta como respuesta del modelo.

Las revisiones técnicas posteriores se identifican como asistencia automática de Codex. La aprobación humana y la decisión de contención no se deducen de que un programa o una consulta de IA haya terminado correctamente.

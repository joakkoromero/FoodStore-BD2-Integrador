# Declaración de Uso de Inteligencia Artificial - TP Unidad 8

**Equipo identificado:** Exequiel Arancibia / Joaquin Romero. **Proyecto:** Food Store. **Asignatura:** Bases de Datos II, UTN. **Fecha del laboratorio:** 10 de noviembre de 2026.

Esta declaración registra de forma trazable la asistencia utilizada. No contiene firmas simuladas, no acredita lectura humana de cada línea por ambos integrantes y no afirma que se haya realizado el ensayo presencial.

| Herramienta | Uso efectivo | Alcance de la revisión |
|---|---|---|
| Kiro, modo Plan | Dos respuestas reales: borrador y especificaciones corregidas. | Codex contrastó el modelo real y pidió corregir claves, snapshot, UPSERT, pruebas y alcance del review. Codex conservó las respuestas por Copy Message As Markdown y Save As, y extrajo los tres documentos finales; no se atribuye escritura automática de archivos a Kiro. |
| OpenCode 1.18.23, modelo openai/gpt-6.1-sol, agente Build | Generación completa del esquema, pruebas, semáforo, fixture/vista, validaciones y runner a partir de los tres documentos de Kiro. | Se conservaron texto original, seis archivos originales, hashes, tiempos y commit anterior a ejecutar. |
| OpenCode, agente Plan | Revisión de las fuentes de todas las unidades, y revisión U8 antes y después de correcciones. | Los adjuntos grandes se dividieron sin perder líneas. Primeros reviews parciales se completaron con continuaciones; no se confunde status completed con cobertura completa. |
| Codex | Organización, integración técnica, lectura de código, correcciones, pruebas reales, comparación de resultados y preparación de archivos. | Revisión técnica automatizada, identificada como tal. Incluye comprobaciones independientes y visuales; no se presenta como firma o revisión humana del equipo. |

Se enviaron a las herramientas externas únicamente contexto técnico y fuentes saneadas con autorización del usuario. No se enviaron contraseñas, filas de usuarios, volcados PostgreSQL ni datos personales reales. Los borradores y productos de feria son ficticios; SQLite contiene sólo un identificador numérico de usuario de prueba.

Las propuestas se contrastaron con documentación oficial y ejecución real. Se aceptaron controles pertinentes, se corrigieron problemas comprobados y se descartaron afirmaciones que no describían el estado acumulado actual, conservando su alcance y la evidencia. Las decisiones detalladas están en `review_hallazgos.md`, los registros en `bitacora_ia.md` y `ia/`, y las pruebas en `evidencias/`.

Las entregas anteriores y la base oficial no se modificaron. La corrección relacional adicional se aplicó y comprobó únicamente en las copias U8. La responsabilidad académica y la defensa de las decisiones corresponden al equipo; el guion permite preparar esa instancia sin atribuirle una realización que el agente no observó.

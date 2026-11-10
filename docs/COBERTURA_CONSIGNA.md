# Cobertura de la consigna del TPI

Esta tabla remite a evidencias concretas; no sustituye la lectura del informe, los scripts ni la validación humana. Los antecedentes históricos conservan sus bytes y fechas.

| N.º | Condición | Fuentes/evidencia | Resultado y alcance |
|---|---|---|---|
| 1 | FNBC sobre dependencias reales | `unidad4/tp_fnbc_control_lote.sql`; `complementos/migracion_fnbc/migrar.sql` | LD→R y R→D; claves LD/LR; RD y LR en FNBC; unión sin pérdida. LD→R requiere salvaguarda conjunta. |
| 2 | Migración reversible especificada en Kiro | `docs/kiro_migracion/requirements.md`; `docs/kiro_migracion/design.md`; `docs/kiro_migracion/tasks.md`; `complementos/migracion_fnbc/RESULTADOS.md`; `docs/evidencias_tpi/migracion_fnbc.json` | Kiro anterior al Build; mismo cuerpo SQL en prueba/confirmación. ROLLBACK comprobado desde otra conexión. Down conserva cambios posteriores y checkpoint; error P7501 también revierte DDL. |
| 3 | Desnormalización controlada | `unidad4/tp_desnormalizacion_top_categorias.sql`; `unidad4/reversion_desnormalizacion.sql` | Materializada diaria con actualización controlada y comprobación contra agregación base. Medianas históricas 173,044 ms y 0,095 ms; se documenta el coste de refresh. |
| 4 | Roles y mínimo privilegio | `unidad5/sql/roles.sql`; `unidad5/docs/evidencias/a_comparacion_exacta.json` | Ocho roles, 44 ACL exactas y tres membresías esperadas. Permisos puntuales; sin ampliar lectura general. |
| 5 | Auditoría e incidente reconstruido | `unidad5/docs/informe_auditoria.md`; `unidad5/docs/informe_incidente.md` | Log nativo saneado, intentos rechazados y simulacro reconstruido. Contención propuesta condicional; no ejecutada automáticamente. |
| 6 | Auditoría IA y decisión humana | `unidad5/docs/ia/a_revision_respuesta.md`; `docs/DECISIONES_REVIEW.json` | Tres riesgos residuales conservados y dos alternativas amplias descartadas. Ratificación real se registra en REVISION_HUMANA; no se simulan firmas. |
| 7 | Mantenimiento y programación comprobados | `unidad6/SPEC_U6.md`; `complementos/mantenimiento_programado/README.md`; `complementos/mantenimiento_programado/evidencias/scheduler_ejecucion.json` | Backup diario registrado y disparado por horario, resultado 0, tareas rutinarias históricas. La tarea temporal fue retirada. OpenCode Build/Plan y correcciones conservados. |
| 8 | Desastre, RTO y post-incidente | `unidad6/docs/informe_post_incidente.md`; `complementos/mantenimiento_programado/informe_post_incidente_tpi.md`; `complementos/mantenimiento_programado/evidencias/restauracion_tpi_resultado.json` | RTO histórico 11,350 s; nuevo 13,430 s sobre el último backup programado. Conteos/huellas coincidentes. Fuente y restauración histórica preservadas. |
| 9 | Dominio documental y consultas verificadas | `unidad7/consultas_mongodb.js`; `unidad7/pedidos_migrados.ejson`; `unidad7/docs/evidencias/validacion.json` | Cinco pedidos existentes y siete líneas; importes Decimal128, validadores y consultas. Alias ficticios y datos saneados. |
| 10 | Comparación documental/relacional | `unidad7/consultas_postgresql.sql`; `unidad7/docs/evidencias/validacion.json`; `unidad7/README.md` | ENTREGADO y producto 1 coinciden en ambos motores. PostgreSQL conserva la autoridad transaccional; no se inventa un benchmark. |
| 11 | SQLite con Kiro y OpenCode | `unidad8/README.md`; `unidad8/movil/schema_sqlite.sql` | Specs genuinas anteriores al Build, SQLite STRICT y enteros para dinero. Se conserva la base móvil de prueba. |
| 12 | Conflictos de sincronización | `unidad8/README.md`; `unidad8/docs/evidencias/segunda_ejecucion` | Dos corridas semánticas, C1–C7 y siete bordes. Nueve solicitudes: dos conflictos, cuatro rechazos y tres aprobaciones simuladas; sin ventas reales. |
| 13 | Review completo y decisiones por hallazgo | `unidad8/docs/review_hallazgos.json`; `docs/DECISIONES_REVIEW.json` | 83 fuentes anteriores y siete finales U8. 43 grupos/64 referencias más cinco decisiones de seguridad y 14 hallazgos de complementos, cada uno con fundamento y evidencia. |
| 14 | Capa completa, Git y defensa | `README.md`; `docs/DUIA_INTEGRADOR.md`; `docs/BITACORA_INTEGRADOR.md`; `docs/GUIA_DEFENSA_INTEGRADOR.md`; `PROCEDENCIA_UNIDADES.json` | Tres motores, fuentes versionadas, mantenimiento, trazabilidad de IA y guion de defensa. Git técnico local completo; no atribuye commits técnicos a los alumnos. |

## Condiciones transversales

- Las pruebas nuevas se ejecutaron en copias y con respaldo previo; la fuente permaneció intacta según sus huellas comprobadas.
- Se preservan prompts/specs, respuestas originales, correcciones atribuidas a Codex y reviews previos a los ensayos. Las aclaraciones no se atribuyen retroactivamente a Kiro u OpenCode.
- No se distribuyen respaldos con filas personales, archivos de autenticación ni contraseñas. Los datos compartidos con IA son los contextos técnicos y fuentes saneadas autorizados.
- La confirmación humana del integrador se registra con su alcance real. No acredita automáticamente una lectura de cada línea ni una defensa oral de ambos integrantes.
- La restauración aislada sin owners/ACL no habilita una recuperación productiva de seguridad. La sincronización móvil es una simulación.

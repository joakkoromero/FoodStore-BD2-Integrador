# Integración técnica de Codex después del review Plan U8

Las fuentes originales de OpenCode permanecen intactas bajo docs/ia/generacion_archivos_originales y en el commit bcee3624. Estas correcciones son de Codex, posteriores a la lectura completa y al review OpenCode Plan. No son una validación humana del equipo.

| Referencia | Decisión y cambio | Verificación prevista/real |
|---|---|---|
| review_u8_pre/U8-01 | Aceptar como robustez condicional: proteger ACL explícitamente antes del primer diagnóstico o dump; abortar si falla. No se afirma exposición previa. | Revisar ACL efectiva de la carpeta privada y archivos después del laboratorio. |
| Matiz de U8-01 | La respuesta Plan ubica soporte Windows de mode=0700 en Python3.13; la documentación oficial indica backport en3.12.4. No es correcto generalizar a todo Python3.12 ni afirmar un defecto del runtime actual. | https://docs.python.org/3.12/library/os.html#os.mkdir y versión real registrada por el runner. |
| review_u8_pre/U8-02 | Corregir el alcance de la prueba: además de conteo de pedidos, comparar huellas completas de pedido y detalle, y suma/huella de stock de todo el catálogo de la copia. Las huellas se calculan en PostgreSQL; sólo salen agregados. | Comparación baseline/final en 20_validar_no_ventas.sql y aserciones del runner. |
| review_u8_pre/U8-03 | Omitir el CONFLICTO histórico artificial C6. C2 conserva dos solicitudes producidas por el semáforo, suficientes para demostrar que no hay UNIQUE global por borrador. | Dos UUID C2 y bloqueo real de segundo PENDIENTE. |
| Observación previa Codex / contraste Plan | Cambiar maintenance-db a postgres como simplificación de conexión; no se etiqueta la variante anterior como bug. Otras sesiones en el template siguen impidiendo copiarlo. | createdb real exit0 al preparar laboratorio. |
| QA manual de lectura Codex | Corregir comentario de bordes: se usa una copia SQLite en memoria mediante backup(), no SAVEPOINT. | Sólo comentario; mecanismo original conservado. |

El semáforo procesa los pendientes por lote: la primera ejecución actualiza todos los PENDIENTE y las llamadas posteriores consultan resultados ya persistidos. No se presentan esas consultas posteriores como transiciones individuales nuevas.

## Corrección relacional posterior al hallazgo TP2

El review OpenCode TP2 señaló que el trigger heredado sólo valida UPDATE de estado. En la copia U8 se comprobó mediante INSERT CONFIRMADO sin detalle, aceptado y luego revertido. Se agregó postgresql/30_corregir_estado_inicial.sql, de autoría técnica Codex, para exigir PENDIENTE al insertar, conservando el trigger de transiciones existente. Se probó rechazo23514 tras la corrección y aceptación de un INSERT PENDIENTE; ambas transacciones se revirtieron. Ninguna entrega anterior ni la fuente foodstore se modificó.

El helper operacional de QA inicialmente esperaba P0001 al borrar un detalle final; el servidor devolvió23514. Se corrigió esa expectativa al código real y se conservaron pruebas exitosas con rollback y cinco huellas idénticas. No fue un fallo del esquema o del laboratorio de la tablet.

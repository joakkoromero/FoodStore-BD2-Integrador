# Aclaraciones tecnicas previas a generar codigo

Autor: Codex, asistencia tecnica automatizada. Fecha: 10/11/2026.
No son palabras de Kiro ni una revision humana. Los tres documentos extraidos
de Kiro se conservan fielmente; estas decisiones se entregan como entrada
adicional a OpenCode Build y Plan ANTES de implementar y ejecutar el complemento.

1. La respuesta real de Kiro contiene un inicio incompleto de requirements
   seguido de un reinicio completo. Se selecciona el ultimo bloque completo
   de cada nombre. El archivo integro, incluido el fragmento, permanece en
   especificaciones_finales_kiro.md; proveniencia_final.json documenta rangos
   y hashes. No se reescribio el texto de los bloques seleccionados.
2. La Fase 8 de design conserva por error la frase "DROP VIEW" inmediatamente
   antes de ordenar renombrar esa misma vista. La implementacion DEBE omitir
   el DROP y usar SOLO ALTER VIEW RENAME para archivar la vista normalizada.
   No se ejecutara DROP ni CASCADE en este complemento.
3. Al migrar, la tabla operativa inicial puede renombrarse como
   control_legacy_pre_migracion antes de crear la vista con su nombre original.
   Se conserva ademas el checkpoint independiente de tres filas. Los objetos
   anteriores se archivan sin borrado y sin tocar el esquema public.
4. El UPDATE valido de la prueba de restricciones se acepta dentro de una
   transaccion y se revierte expresamente, para que no contamine la prueba
   concurrente. La palabra "confirmado" de Task 5 no se implementa como un
   COMMIT persistente de ese test. Los cambios validos persistentes que
   producen cuatro filas se confirman solamente en la fase posterior prevista.
5. Se implementa search_path=pg_catalog y referencias completamente
   calificadas, mas restrictivo que el path con tpi_migracion de Kiro.
6. El checkpoint se protege contra DML posterior a su carga. La guardia
   compartida incorpora un estado de ciclo: tras el down se desactiva y
   posteriores escrituras sobre RD/LR se rechazan con 25006. Asi los archivos
   del ensayo quedan fuera de la interfaz activa y no divergen por DML.
   Esto no pretende restringir a un superusuario que cambie el propio DDL.
7. Las pruebas concurrentes usan conexiones independientes y observacion real
   de bloqueo con limite de tiempo. Un error inesperado aborta el ensayo y
   revierte transacciones abiertas; no se oculta por una captura generica.
8. Se reutiliza el mismo archivo/cuerpo de migracion para ROLLBACK y COMMIT,
   guardando su SHA256. El down se prueba primero con error inyectado y
   ROLLBACK, y luego se confirma. Debe conservar las cuatro filas actuales,
   el checkpoint de tres, las cinco huellas de public y la fuente oficial.

Las decisiones complementan el contrato de pruebas de
complementos/migracion_fnbc/ y se someten al review real antes de ejecutar.

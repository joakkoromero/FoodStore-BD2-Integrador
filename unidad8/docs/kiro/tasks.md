# Tareas U8 – Food Store SQLite (Arancibia / Romero)

Task 1: Congelar especificaciones

Guardar requirements.md, design.md y tasks.md en docs/kiro/. Registrar sha256 y
fecha de cada archivo. Anotar en bitácora que estos archivos son autoría de
Codex/Kiro y aún no constituyen evidencia de ejecución de código.
Demo: tres archivos en docs/kiro/, hashes verificables, bitácora con entrada
inicial.

Task 2: Preparar copia PostgreSQL y fixture

Respaldar foodstore privadamente y verificar por conteo y hash. Crear
foodstore_u8_arancibia_romero desde template sin DROP ni reemplazar la fuente.
Verificar que foodstore sigue intacto (hash pre/post de al menos cinco tablas).
Insertar productos "U8-FERIA-*". Crear vista v_snapshot_movil con el mapeo
correcto (producto_id=p.id, precio*100 BIGINT, disponible derivado, baja por
producto.eliminado OR categoria.eliminado). Exportar snapshot_inicial.csv.
Demo: conteo de fixture, CSV con cabecera correcta, hashes de foodstore sin
cambios.

Task 3: Generar esquema SQLite con OpenCode Build

OpenCode Build genera movil/schema_sqlite.sql a partir de design.md. Leer el
script antes de ejecutarlo. Crear SQLite desde cero; verificar PRAGMA
integrity_check=ok, PRAGMA foreign_keys=1, cinco tablas presentes, índice
parcial en cola_sync.
Demo: salida de verificaciones sin errores; base vacía lista para datos.

Task 4: Generar e integrar importación de snapshot

OpenCode Build genera el script de importación. Leer antes de ejecutar.
Importar snapshot_inicial.csv a snapshot_servidor; convertir t/f con control
de formato; propagar a producto_cache con UPSERT ON CONFLICT DO UPDATE.
Verificar v_catalogo_disponible oculta eliminados.
Demo: SELECT COUNT(*) en producto_cache; fila eliminada visible en cache y
ausente de la vista.

Task 5: Pruebas de atomicidad C1 y C7

OpenCode Build genera movil/pruebas_sqlite.sql. Leer antes de ejecutar.
C1-COMMIT: borrador + ítems + PENDIENTE; verificar filas. C1-ROLLBACK: mismo
flujo con ROLLBACK; verificar cero filas. C7-cantidad: header válido + ítem
cantidad=0; verificar ROLLBACK completo (header tampoco persiste). C7-fk: header
válido + producto_id inexistente; verificar ROLLBACK completo. UUIDs con formato
válido; sin datos personales.
Demo: salidas SELECT antes/después de cada transacción documentadas.

Task 6: Semáforo — preparación administrativa y casos C2 a C6

Preparación en la copia: modificar precio de un producto fixture (C2), marcar
eliminado en otro (C4). Estos cambios los ejecuta el operador explícitamente, no
el semáforo. OpenCode Build genera movil/semaforo.sql. Revisar con OpenCode Plan
antes de ejecutar. Ejecutar en orden: C3, C4, C5, C2, C2-aceptar, mixto
rojo/amarillo, borrador vacío. Ejecutar C6: C6-PK (UUID duplicado), C6-semáforo
(re-evaluar UUID ya evaluado, verificar igualdad estado/motivo), C6-PENDIENTE
(segunda PENDIENTE misma id_local), C6-histórico (segunda entrada CONFLICTO).
Demo: tabla cola_sync con todas las filas; estados y motivos correctos; ninguna
escritura en PostgreSQL.

Task 7: Verificar conservación de PostgreSQL

Comparar conteo de pedidos y stock fixture en la copia antes y después de las
pruebas. Calcular hashes de al menos cinco tablas de foodstore antes y después.
Verificar que snapshot_servidor es de solo lectura en el flujo de semáforo.
Documentar explícitamente: SIMULADO_APROBADO ≠ venta; ninguna transacción de
venta fue creada en PostgreSQL.
Demo: tabla comparativa de conteos y hashes; afirmación de no-escritura
fundamentada en ausencia de logs de modificación.

Task 8: Review OpenCode Plan, correcciones y segunda ejecución

Congelar trabajo en rama review-final. OpenCode Plan revisa TODOS los scripts
disponibles de la cursada por unidades; si un adjunto se trunca, dividir y
continuar. El informe desarrolla como mínimo tres hallazgos de al menos dos
unidades; al menos uno descartado con fundamentación y prueba. Cada hallazgo
registra decisión: aceptado, corregido o descartado. Corregir en commits
separados. Reproducir desde SQLite vacío y comparar evidencia de primera y
segunda ejecución.
Demo: rama review-final, log de commits, dos salidas comparadas, registro de
hallazgos con decisiones reales.

Task 9: Artefactos finales

Mapa PostgreSQL/MongoDB/SQLite. Extensión del plan U6 según design.md sección 5.
Bitácora de IA con al menos tres entradas reales (fecha, herramienta, resultado).
DUIA de la cátedra. README con estructura del proyecto. Informe máximo seis
páginas. ZIP food-store/ con base SQLite y archivos requeridos; verificación
real de entradas y bytes; scan sin secretos ni datos personales (verificación
de contenido, no solo comando shell). Guion de defensa de diez minutos; el
ensayo real lo realiza el equipo en clase y no se simula aquí.
Demo: ZIP verificado por contenido; hashes documentados; bitácora con al menos
tres entradas reales.

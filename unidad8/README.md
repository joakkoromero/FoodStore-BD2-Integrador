# Food Store - Trabajo Práctico Unidad 8

**Equipo:** Exequiel Arancibia / Joaquin Romero. **Asignatura:** Bases de Datos II, UTN. **Entrega:** un ZIP con esta carpeta `food-store/`.

La tablet consulta un catálogo local y guarda borradores. El semáforo sólo simula la validación: **SIMULADO_APROBADO no es una venta ni una reserva de stock**. PostgreSQL sigue siendo la autoridad sobre precio, stock y ventas. MongoDB conserva el subconjunto documental de pedidos experimentado en U7.

## Archivos principales

- `docs/informe.pdf`: resolución de las consignas, hasta seis páginas.
- `movil/schema_sqlite.sql`, `pruebas_sqlite.sql`, `semaforo.sql`: esquema, pruebas y evaluación local.
- `movil/servidor_snapshot.csv` y `foodstore_movil.db`: instantánea final y base de la tablet de la primera ejecución completa.
- `postgresql/10_fixture_y_snapshot.sql`: catálogo ficticio en una copia y vista de exportación.
- `postgresql/20_validar_no_ventas.sql`: lecturas para comparar pedidos, detalles y stock de la copia.
- `postgresql/30_corregir_estado_inicial.sql`: corrección del hallazgo TP2, aplicada sólo a las copias U8 y probada.
- `tools/reproducir.py`: ejecutor generado con OpenCode Build y revisado; usa Python estándar y clientes PostgreSQL.
- `docs/kiro/`: propuesta inicial, respuestas originales y tres especificaciones finales extraídas sin reescritura, con hashes.
- `docs/review_hallazgos.md` y `.json`: decisiones técnicas finales de la revisión completa; reemplazan como conclusión las matrices de propuestas `review_historicos.*` y `review_u5_u6_u7.*`, que se conservan como trazabilidad.
- `docs/evidencias/`: salidas reales, comandos, huellas, estados, errores y segunda ejecución.
- `docs/ia/`, `bitacora_ia.md`, `DUIA.md`, `defensa.md`: procedencia de la asistencia, decisiones y guion para el equipo.
- `.git/`: historial técnico local y rama `review-final`, sin remoto ni credenciales.

## Precondiciones para crear todo desde cero

1. Una instancia de laboratorio PostgreSQL **17.11**, con la base acumulada **foodstore** de los trabajos anteriores. Este TP continúa su esquema y datos: no contiene un dump de usuarios ni reconstruye la cursada completa desde cero. La entidad del cliente se llama `usuario`; `producto` no tiene `disponible`, por lo que se deriva de `stock > 0`.
2. Clientes `psql`, `createdb` y `pg_dump` de PostgreSQL 17; Python **3.12+** cuyo módulo SQLite sea **3.37+**. La ejecución registrada usó Python 3.12.14 y SQLite 3.53.1. No requiere instalar paquetes Python, una app de celular o un servidor SQLite.
3. Configurar externamente `PGHOST`, `PGPORT`, `PGUSER` y **uno** de `PGPASSWORD` o `PGPASSFILE`, con un administrador del laboratorio. El passfile, si se usa, debe permitir las conexiones a `postgres`, `foodstore` y `foodstore_u8_arancibia_romero`. No incluir esas claves en el proyecto ni en la línea de comandos.
4. La base destino `foodstore_u8_arancibia_romero` debe estar ausente. No debe haber otras sesiones conectadas a `foodstore` cuando se copie el template. El programa aborta ante un destino existente; no lo elimina ni lo reemplaza.

## Orden de reproducción

La entrega contiene resultados ya generados. Para repetirlos, conservá esta carpeta y prepará otra carpeta nueva **sólo con las fuentes**, sin copiar `.db`, CSV ni evidencias anteriores. Ejemplo en PowerShell, situado en la carpeta entregada:

```powershell
$origen = (Get-Location).Path
$destino = Join-Path (Split-Path $origen -Parent) 'food-store-repro-01'
if (Test-Path -LiteralPath $destino) { throw 'Elegir otro destino nuevo' }
$fuentes = @(
 'movil/schema_sqlite.sql', 'movil/pruebas_sqlite.sql', 'movil/semaforo.sql',
 'postgresql/10_fixture_y_snapshot.sql', 'postgresql/20_validar_no_ventas.sql',
 'postgresql/30_corregir_estado_inicial.sql', 'tools/reproducir.py'
)
foreach ($rel in $fuentes) {
 $archivo = Join-Path $destino $rel
 New-Item -ItemType Directory -Force -Path (Split-Path $archivo -Parent) | Out-Null
 Copy-Item -LiteralPath (Join-Path $origen $rel) -Destination $archivo
}
Set-Location -LiteralPath $destino
```

Con la conexión externa configurada y un directorio privado **nuevo**, ejecutá:

```powershell
python tools/reproducir.py --pg-bin 'C:/Program Files/PostgreSQL/17/bin' --database foodstore_u8_arancibia_romero --private-dir 'C:/FoodStore_privado/corrida01'
```

Adaptá únicamente la ruta de los clientes y la carpeta privada. El ejecutor, en orden:

1. Comprueba versiones y ausencia del destino; obtiene cinco huellas agregadas de la fuente sin exportar filas personales.
2. Crea la copia, protege la carpeta privada y genera un respaldo custom **antes** del fixture. El dump y los diagnósticos completos quedan fuera de este proyecto.
3. Inserta cuatro productos de feria inventados y exporta CSV reales con `psql \copy`.
4. Crea SQLite vacía, activa y verifica claves foráneas, importa el CSV y hace UPSERT de la caché. Las bajas se conservan como lápidas.
5. Ejecuta las sentencias reales de `pruebas_sqlite.sql`, incluyendo COMMIT, ROLLBACK y los errores esperados C7; después los casos C2-C6 y siete bordes. El semáforo trabaja por lote sobre pendientes; no se conecta a PostgreSQL.
6. Compara conteos y huellas de pedidos/detalles, el stock global y las cinco huellas de la fuente. Escribe `docs/evidencias/reproduccion_u8.json` y `.txt`, CSV y la SQLite final. Termina con código 0 si pasan las comprobaciones.

Luego aplicá la corrección del review, en esa misma copia:

```powershell
& 'C:/Program Files/PostgreSQL/17/bin/psql.exe' -X -w -v ON_ERROR_STOP=1 -d foodstore_u8_arancibia_romero -f postgresql/30_corregir_estado_inicial.sql
```

Esa guarda exige que un pedido nazca PENDIENTE; no crea ventas ni cambia datos de `foodstore`. Las transiciones existentes se conservan. Los comandos y resultados de las pruebas de regresión están en `docs/evidencias/review_bd_*.json`: cada prueba usa BEGIN/ROLLBACK y comprueba cinco tablas sin cambios. El INSERT con identidad automática de la prueba de app puede avanzar únicamente la secuencia de la copia pese al rollback; no se afirma conservación de todo el clúster.

## Si la copia ya existe y se quiere una segunda ejecución

Conservá la copia anterior mediante un nombre nuevo y libre, desde `postgres` y sin sesiones en el destino. Ejemplo exclusivamente para la copia de laboratorio U8:

```sql
ALTER DATABASE foodstore_u8_arancibia_romero
RENAME TO foodstore_u8_conservada_para_repro;
```

Usá otra carpeta de proyecto sólo con fuentes y otro directorio privado, y repetí el orden anterior. No ejecutes el comando sobre `foodstore`. El cambio de nombre no borra datos y falla si el nombre reservado ya existe.

Así se comprobó esta entrega: se conservó la primera como `foodstore_u8_run01_conservada`, se creó de nuevo la copia canónica y se repitió desde SQLite vacía. Hubo los mismos resultados semánticos; UUID, horas y bytes de las dos SQLite pueden diferir. La corrección `30_...` se aplicó y probó también en la **segunda copia canónica final**. La base de la tablet entregada sigue siendo la primera, cuyo hash se verifica con su evidencia; la segunda está archivada y claramente identificada en `docs/evidencias/segunda_ejecucion/`.

## Lectura rápida de las evidencias

- Siete casos obligatorios C1-C7 y siete bordes correctos en ambas ejecuciones; nueve solicitudes finales: dos CONFLICTO, cuatro RECHAZADO y tres SIMULADO_APROBADO.
- Caché de cuatro productos; Agua queda como lápida y no aparece en el catálogo.
- Copia: 225.000 pedidos; stock global 5.000.038, sin cambios por la simulación. Pedidos y detalles tienen huellas iguales antes/después. La fuente conserva sus cinco huellas completas.
- Review en motor: DELETE de un último detalle final se rechaza **23514**; UPDATE total bajo app_web se rechaza **42501**; INSERT CONFIRMADO vacío del administrador se aceptaba y se revirtió; tras la corrección se rechaza **23514**, mientras PENDIENTE sigue permitido con administrador bootstrap y app.
- Los campos de fecha fijos de los borradores son datos de prueba; nunca resuelven conflictos. Las instantáneas llevan la hora real de PostgreSQL.

## Historial y defensa

```powershell
git branch --list review-final
git log --oneline --all
git status --short
```

Los commits registran por separado especificaciones anteriores al código, generación original, correcciones y cierre documental. La identidad técnica es Codex; no se atribuyen commits a los estudiantes. No se publica un repositorio remoto.

La generación y las comprobaciones automatizadas se declaran en `docs/DUIA.md`. El equipo tiene el guion de diez minutos y debe poder explicar los scripts y realizar la instancia presencial; no se afirma que ese ensayo o una revisión humana de cada línea hayan ocurrido por intervención del agente.

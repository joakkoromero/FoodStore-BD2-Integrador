# Food Store - TPI, segunda entrega parcial

Equipo: Exequiel Arancibia / Joaquin Romero. Bases de Datos II, UTN. Unidades 4 a 8. Fecha de integración: 10/11/2026.

Este repositorio reúne las fuentes y evidencias ya ejecutadas de las unidades 4 a 8. Los archivos históricos conservan sus bytes; no se presenta la compilación del integrador como una nueva ejecución de sus experimentos. La autoría técnica asistida y la procedencia de cada componente se declaran en la bitácora y DUIA.

## Lectura y estructura

| Carpeta | Contenido principal | Entrada de lectura |
|---|---|---|
| `unidad4/` | Extensión FNBC de control de lotes, materializada diaria, salvaguardas y reversión. | `LEEME.txt`, PDF histórico y `evidencias/`. |
| `unidad5/` | Roles/ACL, auditoría, incidente simulado, anonimización y especificación Kiro. | `README.md`, `docs/informe_roles.md`, `docs/informe_auditoria.md`, `docs/informe_incidente.md`. |
| `unidad6/` | Scripts de backup/restauración, salud/mantenimiento e informe post-incidente. | `SPEC_U6.md`, `docs/resolucion.md`, `docs/informe_post_incidente.md`, `docs/informe_u6.pdf`. |
| `unidad7/` | Proyección documental de cinco pedidos en MongoDB y consultas equivalentes PostgreSQL. | `README.md`, `docs/evidencias/validacion.json`, `output/pdf/TP_U7_FoodStore_Arancibia_Romero.pdf`. |
| `unidad8/` | SQLite, CSV de servidor, semáforo, casos/conflictos, especificación Kiro y review acumulado. | `README.md`, `docs/informe.pdf`, `docs/review_hallazgos.md`. |

PostgreSQL es la autoridad sobre clientes, productos, pedidos, precios y stock. MongoDB conserva el subconjunto documental experimental U7. SQLite prepara borradores offline y simula su validación: `SIMULADO_APROBADO` no crea una venta ni reserva stock.

## Precondiciones y resguardo

La reproducción exacta continúa el Food Store acumulado U1-U3 y los antecedentes TP4/TP5. La entidad cliente de la guía se implementa como `public.usuario`. No se reemplazó el modelo por un ejemplo mínimo nuevo.

Se requiere un entorno aislado PostgreSQL 17.11 (cumple 16+), clientes de la misma versión, Python 3.12+ y SQLite 3.37+; el ensayo usó Python 3.12.14/SQLite 3.53.1. U6 requiere Windows y PowerShell 7.5+; se ejecutó con 7.6.5. U7 usó MongoDB 8.0.34 y mongosh 2.14.1. Los binarios de los motores no se incluyen.

El operador aporta privadamente su respaldo del checkpoint acumulado correspondiente, su instancia de pruebas y sus credenciales. Los dumps y archivos de autenticación están excluidos de la entrega para proteger los datos y las credenciales almacenadas. Se conservan manifiestos, hashes y salidas que permiten verificar lo actuado sin distribuir filas personales.

Antes de repetir una etapa se debe leer su SQL/código, preparar una copia nueva y un respaldo previo cuando corresponda, configurar autenticación externa y revisar el objetivo exacto de cada comando. Ningún comando de este README se ejecutó automáticamente al compilar el TPI. No se debe aplicar toda la historia de migraciones sobre la base final como si fuera una instalación vacía: cada etapa parte de un checkpoint distinto.

`unidad5/docs/ia/a_revision_adjuntos/04_esquema_heredado_sin_datos.sql` conserva un esquema sin filas, usado como contexto de review. Es un antecedente DDL, no un bootstrap autosuficiente de datos, roles o resultados históricos.

## Orden por etapa

### 1. Unidad 4: copia heredada, FNBC y desnormalización

Se parte del respaldo pre-TP4 y se incorporan los índices TP4, índices/vistas TP5 y la actividad de prueba del día. El orden histórico fue:

1. `antecedentes/indices_tp4.sql`.
2. `antecedentes/indices_tp5.sql` y `antecedentes/views_tp5.sql`.
3. `01_actividad_del_dia.sql`.
4. `tp_fnbc_control_lote.sql`.
5. `tp_desnormalizacion_top_categorias.sql`.
6. Verificadores y evidencias en `reproduccion/` y `evidencias/`.

Usar `psql -X -v ON_ERROR_STOP=1` y la conexión privada a la copia elegida. Los scripts que crean objetos no se deben reaplicar sin revisar sus guardas de existencia y el estado de la copia.

El `00_reconstruir_base.ps1` se conserva sin cambios como antecedente: exige el respaldo original pre-TP4 y un SHA256 concreto. Ese dump no se redistribuye en este TPI. Por ello, el wrapper histórico no es un instalador autónomo del paquete actual ni acepta un respaldo cualquiera sólo por renombrarlo. Si se dispone de un checkpoint propio equivalente, debe restaurarse en otra base mediante el procedimiento privado del operador y validarse antes de continuar. La extensión FNBC y las decisiones de caché se explican en el informe técnico.

Los verificadores Python U4 contienen aserciones; deben ejecutarse sin `-O` ni `PYTHONOPTIMIZE`. La reversión documentada es `reversion_desnormalizacion.sql`, sólo sobre la copia de práctica y tras leer sus efectos. No se usa sobre la fuente original.

### 2. Unidad 5: laboratorio de seguridad desde la copia U4

Seguir `unidad5/README.md`, sección «Reproducción desde una copia U4». Su preparador acepta un respaldo externo y crea un runtime nuevo fuera del repositorio; rechaza uno existente. La secuencia comprobada fue:

1. `tools/preparar_laboratorio.py` con `--source-dump`, `--runtime` nuevo y puerto local.
2. Configurar `U5_SECRET_FILE` hacia el archivo privado generado, sin incluirlo en Git.
3. Cuenta sintética; anonimización D con `--bootstrap`; huellas antes.
4. `tools/instalar_seguridad.py`; pruebas `permissions` y `defaults`.
5. Anonimización sin bootstrap, matriz y captura de permisos.
6. Activación de auditoría; pruebas `audit` e `incident`.
7. Huellas después y rotación de log.

Los SQL B/C son catálogos parametrizados ejecutados por el orquestador: no enviar el archivo entero a `psql`. Las claves se cargan antes de registrar sentencias sensibles. El log nativo permanece privado; sólo se entrega su copia saneada. No se ejecutó contención automática sobre usuarios, red ni roles.

### 3. Unidad 6: mantenimiento y restauración contra reloj

Se continúa una copia de la base U5 llamada `foodstore`, manteniendo el origen. Leer `unidad6/SPEC_U6.md` y `docs/resolucion.md`. Configurar `PGPASSFILE` protegido y un directorio de trabajo privado fuera del repositorio.

1. Comprobar salud y ventana sin escrituras; ejecutar `backup_foodstore.ps1` con los parámetros de conexión/cliente/directorio y `-ConfirmNoWrites`.
2. El script debe terminar 0, publicar dump y manifiesto SUCCESS, y conservar hashes/conteos coherentes.
3. Ejecutar `restore_test.ps1` sobre un destino `foodstore_restore_test` inexistente. Selecciona el último respaldo con manifiesto válido, mide con reloj monotónico y verifica antes de declarar éxito.
4. Ejecutar salud/mantenimiento con `ON_ERROR_STOP=1` según la política descrita; contrastar con `docs/evidencias/`.

El simulacro conservado observó RTO 11,350 s y antigüedad de copia 31,808 s. Es un resultado de ese laboratorio, no una promesa para otro volumen/equipo. La restauración sin owners/ACL no restablece por sí misma la seguridad U5; su copia aislada no se habilita a la aplicación. Los horarios recurrentes se propusieron, pero no se instaló una tarea programada en aquella entrega.

### 4. Unidad 7: documentos y consultas cruzadas

Se consulta la base acumulada `foodstore` sin modificarla. Desde `unidad7/`, ejecutar `consultas_postgresql.sql` con `psql -X -v ON_ERROR_STOP=1`, usando la autenticación externa del operador. La exportación toma pedidos existentes 1 a 5 en una transacción REPEATABLE READ READ ONLY.

En una instancia MongoDB aislada y autenticada, ejecutar `consultas_mongodb.js` desde esa misma carpeta, junto a `pedidos_migrados.ejson`. Las credenciales se suministran por el mecanismo local del operador, sin pegarlas en archivos, URI o argumentos publicados. El script utiliza sólo `foodstore_u7.pedidos`, no elimina colecciones y aborta si una colección existente difiere de la muestra.

Contrastar `docs/evidencias/validacion.json`: ENTREGADO -> `[1,2,3,4]`; producto 1 -> `[1,3,5]`, iguales en ambos motores. Mongo además devuelve `[3,4]` para total >3000. Los importes históricos son Decimal128. La comparación es funcional y estructural; no se midió un benchmark que justifique sustituir PostgreSQL.

### 5. Unidad 8: SQLite y simulación de sincronización

Leer `unidad8/README.md`. La entrega conserva una SQLite ya probada; para repetir los casos, crear otra carpeta nueva sólo con estas siete fuentes y un directorio privado nuevo:

- `movil/schema_sqlite.sql`, `movil/pruebas_sqlite.sql`, `movil/semaforo.sql`.
- `postgresql/10_fixture_y_snapshot.sql`, `postgresql/20_validar_no_ventas.sql`, `postgresql/30_corregir_estado_inicial.sql`.
- `tools/reproducir.py`.

No ejecutar el runner dentro de esta entrega congelada: genera CSV, SQLite y evidencias. La fuente debe ser la base acumulada `foodstore`; el destino `foodstore_u8_arancibia_romero` debe estar ausente. Configurar `PGHOST`, `PGPORT`, `PGUSER` y autenticación privada según el README de U8.

El runner crea una copia, hace un backup privado antes del fixture, inserta cuatro productos ficticios, exporta CSV y ejecuta C1-C7 más siete bordes. Luego se aplica SQL30 en la misma copia y se comprueba el review. No borra ni reemplaza el destino y no crea ventas. Si se repite, se conserva la copia previa renombrándola a un nombre libre y se usan carpetas nuevas.

Dos ejecuciones completas dieron la misma semántica: nueve solicitudes, 2 CONFLICTO / 4 RECHAZADO / 3 SIMULADO_APROBADO. La base entregada es la primera, con hash conservado; la segunda se archiva en `unidad8/docs/evidencias/segunda_ejecucion/`. UUID, horas y bytes pueden diferir entre corridas.

## Historial, procedencia y revisión humana

El Git del TPI debe ser único, con identidad técnica explícita. Las unidades copiadas no contienen repositorios `.git` anidados. Los SHA256 del manifiesto de procedencia relacionan cada archivo original con su copia exacta; los commits históricos citados en los informes no deben atribuirse retroactivamente al nuevo repositorio o a los alumnos.

Los generadores de informes y empaquetadores históricos se preservan como fuentes revisadas, no como comandos para volver a empaquetar el integrador. Sus rutas de salida y supuestos Git corresponden a cada entrega original. Los informes históricos también pueden referir respaldos excluidos por privacidad: esta explicación del TPI aclara ese alcance sin cambiar sus bytes.

El review U8 conserva 83 fuentes anteriores y siete finales, 43 grupos y 64 referencias con decisión técnica. La autoridad de esa matriz es Codex, no una firma humana. La ratificación humana del integrador se registra sólo tras revisión efectiva de las fuentes, fundamentos y evidencias; no se completa automáticamente a nombre del equipo. La defensa oral y su ensayo corresponden a los integrantes. Los guiones entregados son material para prepararla, no evidencia de una actividad ya realizada.

Voy a revisar los tres archivos incluidos, usando líneas relativas a cada archivo. Separaré los fallos demostrables para esta muestra de los riesgos condicionados de reproducción y trazabilidad, sin ejecutar nada ni usar herramientas.

## Resultado

**No identifico un fallo funcional demostrable para la muestra congelada de cinco pedidos y siete líneas.** Las consultas y el modelo son coherentes con el alcance indicado. Identifico dos riesgos condicionados de robustez y trazabilidad; no prueban que la ejecución documentada ni el PDF entregado sean incorrectos.

La revisión abarca los tres archivos completos presentes en el bundle. No ejecuté pruebas, utilicé herramientas ni modifiqué archivos. Las referencias siguientes son **líneas relativas a cada archivo**, contando el comentario inicial de saneamiento como línea 1, no líneas del Markdown contenedor.

## Inventario Completo

| Archivo | Alcance revisado | Estado |
|---|---|---|
| `consultas_mongodb.js` | Lectura EJSON, selección de base, creación y modificación de colección, validador, carga, comparación de contenido, índices, consultas a–d, pruebas negativas y cierre. | Revisado íntegramente. Sin fallo confirmado para la muestra; una observación condicionada sobre efectos de las pruebas negativas. |
| `consultas_postgresql.sql` | Configuración de `psql`, transacción de solo lectura, exportación documental, fechas y tipos EJSON, consultas equivalentes b/c y control de integridad del origen. | Revisado íntegramente. Sin hallazgos funcionales confirmados para el alcance declarado. |
| `tools/generar_informe.py` | Dependencias y fuentes tipográficas, composición de las cinco páginas, contenido, identificación de commit, adjuntos, comprobaciones del PDF, manifiesto y salida de verificación. | Revisado íntegramente, no excluido por ser auxiliar. Una observación condicionada sobre identificación de las fuentes mediante Git. |

El bundle contiene esos **tres archivos de código**. `pedidos_migrados.ejson`, `README.md`, `docs/ia/consulta_respuesta.md`, `docs/evidencias/*` y el PDF son referencias o entradas del código, **no contenido adicional incluido para inspeccionar**. No atribuyo a esos archivos una revisión que no se realizó.

## Hallazgos

Prioridad **P3: baja**, mejora de robustez o trazabilidad. No hay hallazgos P1/P2 demostrables con el material proporcionado.

| ID | Prioridad | Archivo / líneas relativas | Condición concreta | Consecuencia | Certeza | Prueba mínima propuesta, no ejecutada |
|---|---|---|---|---|---|---|
| U7-01 | P3 | `consultas_mongodb.js:78–94`, especialmente `89–90` | Una inserción de prueba negativa resulta aceptada inesperadamente. El script lanza una excepción después de `insertOne()`, sin eliminar el documento insertado. | La prueba detecta el fallo, pero deja su escritura en la colección. Una reproducción posterior se detendrá por diferencia frente al EJSON; la comprobación final tampoco llega a ejecutarse. | **Confirmable por el flujo de control**, condicionado a una aceptación inesperada. No demuestra que el validador actual acepte esos casos. | En una copia desechable del laboratorio y del script, debilitar exclusivamente la regla monetaria para que se acepte `total_incoherente`. Comprobar que el script falla y que queda `_id: Long('900000001')`. No hacerlo sobre las fuentes congeladas ni la colección de evidencia. |
| U7-02 | P3 | `tools/generar_informe.py:186–188`; incorporación de adjuntos en `201–217` | Se genera el informe con cambios sin confirmar en los archivos fuente respecto de `HEAD`. `git rev-parse --short HEAD` solo comprueba que existe un commit; no comprueba que los archivos adjuntados coincidan con él. | El texto «Commit de fuentes» puede identificar una revisión distinta de los bytes efectivamente adjuntados. El manifiesto conserva los hashes de esos bytes, pero no acredita su correspondencia con el commit mencionado. | **Ausencia de comprobación confirmada**; una discrepancia efectiva depende del estado Git, no incluido. Los controles externos declarados pueden cubrirla para la entrega congelada. | En una copia temporal del repositorio, modificar un comentario de una fuente sin hacer commit y generar el informe. Comparar el commit mostrado con el contenido y hash del adjunto: el generador no debería detectar esa divergencia mediante sus comprobaciones actuales. |

Ninguna de estas observaciones exige reabrir los scripts congelados para validar retrospectivamente los resultados declarados. Son condiciones que conviene distinguir si se reutiliza el procedimiento.

## Comprobaciones Estáticas

**Modelo, tipos y fechas**
- `consultas_postgresql.sql:16–40` exporta los identificadores como `$numberLong`, cantidades como `$numberInt` e importes desde texto como `$numberDecimal`. No aparece una conversión intermedia de dinero a coma flotante binaria.
- El precio exportado procede de `detalle_pedido.precio_unitario`, no del precio actual del catálogo. El nombre procede de `producto` y se presenta correctamente como nombre al migrar, no como dato histórico.
- `cliente` contiene únicamente `usuario_id` y un alias construido. La entidad relacional utilizada es `usuario`.
- `consultas_postgresql.sql:10,18` configura UTC y representa fechas con milisegundos. Eso es coherente con la precisión declarada para estos cinco pedidos. **No corresponde señalar pérdida submilisegundo en esta muestra**, porque el contexto descarta esas fracciones. La comprobación independiente del tipo SQL de `fecha` requeriría el esquema, que no está incluido.

**Validación y Consultas**
- `consultas_mongodb.js:15–44` combina tipos y dominios con igualdad de total, coherencia de subtotales y ausencia de productos repetidos dentro de cada pedido. La unicidad global de `_id` queda a cargo de MongoDB.
- La validación no pretende reproducir claves foráneas ni toda la política relacional. Esa diferencia está expresamente declarada y no constituye un defecto de esta migración.
- Las consultas SQL b/c restringen explícitamente los IDs a `1–5`. El `EXISTS` de producto devuelve cada pedido una sola vez, igual que el filtro documental sobre `lineas.producto_id`.
- El filtro monetario usa `$gt` y `Decimal128`, coherentes con un umbral estricto de `3000.00`.
- Los valores concretos de las pruebas negativas dependen del primer documento congelado. No son pruebas genéricas para cualquier exportación, pero esa generalidad no es un requisito aquí.

**Reproducción y Efectos**
- La transacción PostgreSQL es `REPEATABLE READ READ ONLY`. No se observan escrituras al origen.
- La reproducción MongoDB no es de solo lectura: puede crear colección, insertar la muestra, reaplicar el validador, crear índices e intentar inserciones negativas. Esos efectos están acotados a la colección de laboratorio.
- Para una colección con contenido coincidente, el script evita repetir la carga. Ante contenido diferente, falla en lugar de reemplazarlo. La comparación serializada es estricta y sensible al orden; con la entrada congelada y ordenada no constituye un fallo demostrado.
- `collMod` no valida retroactivamente toda una colección por sí solo. Aquí existe además la comparación con la exportación congelada; no hay base para afirmar que permanecieron documentos inválidos.

**PDF y Adjuntos**
- El generador comprueba desbordamientos de párrafos, tablas y bloques de código; exige cinco páginas y vuelve a abrir el PDF final.
- Comprueba cantidad de adjuntos y hashes de los contenidos extraídos contra los archivos que acaba de adjuntar. Eso aporta una comprobación concreta de integridad del empaquetado.
- `validacion.json` se carga en `tools/generar_informe.py:32`, pero `data` no se utiliza después. Las cifras y afirmaciones del cuerpo están escritas en el generador. **No demuestra un error en este informe congelado**, pero significa que generarlo no contrasta automáticamente su texto con esa evidencia.
- El archivo de verificación deja `visual_qa` como `pendiente`. Las comprobaciones estructurales no certifican legibilidad, ausencia de superposición ni apariencia visual.
- No señalo rutas, nombres o literales saneados como defectos reales.

## Límites

- Esta revisión no certifica las versiones instaladas, resultados b/c, códigos de rechazo, conservación del origen ni hashes originales. Esos resultados se toman como contexto declarado, no como pruebas ejecutadas aquí.
- Sin EJSON, esquema SQL, evidencias, repositorio y PDF final no puede verificarse independientemente su correspondencia completa.
- No se evaluó rendimiento ni sincronización, ni se exigió equivalencia de todas las reglas relacionales.
- **Conclusión estática:** no encuentro un impedimento técnico confirmado para el cierre de esta entrega acotada. Los dos hallazgos son condicionados y no invalidan por sí mismos los controles de ejecución y congelamiento descritos.

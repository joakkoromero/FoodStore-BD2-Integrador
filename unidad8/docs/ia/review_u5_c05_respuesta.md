## 1. Inventario Exhaustivo

| Archivo recibido | Alcance revisado | Estado |
|---|---|---|
| `outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\verificar_privacidad.py` | Archivo completo: importaciones, ejecución de Git, obtención del inventario privado, inspección de archivos y objetos Git, extracción de PDF y generación de evidencia. | Revisión estática completa; dos observaciones detalladas abajo. Sin ejecución. |

El adjunto contiene **un solo archivo fuente**, visible hasta `main()` y el cierre del bloque. **No se observa truncamiento.** El último archivo completamente visible es `verificar_privacidad.py`. El Markdown contenedor no se cuenta como un segundo archivo fuente.

Las líneas siguientes son **relativas al archivo Python**, contando el comentario `# COPIA SANEADA...` como línea 1; no son las líneas del Markdown.

## 2. Hallazgos

| ID | Prioridad / tipo | Archivo y líneas | Condición concreta | Consecuencia | Certeza | Prueba mínima propuesta |
|---|---|---|---|---|---|---|
| U5-C05-01 | P2 · Defecto de vigencia de evidencia | `verificar_privacidad.py:25-65`, especialmente `57-64` | Existe un `docs/evidencias/privacidad_entrega.json` de una ejecución satisfactoria y una ejecución posterior falla antes de escribir el nuevo resultado, por ejemplo por una coincidencia privada o un error de lectura. No hay invalidación previa ni registro del resultado fallido. | El JSON anterior permanece con `passed: true`. Un consumidor que consulte únicamente ese archivo puede interpretar como vigente un éxito anterior, aunque el intento más reciente haya fallado. | **Demostrable por el flujo del código.** La interpretación errónea por otro proceso está condicionada a cómo consuma la evidencia; no se acredita que haya ocurrido. | En una copia local de prueba, conservar una evidencia satisfactoria y provocar un fallo controlado sin usar secretos reales. Verificar que el proceso falla pero el JSON conserva el contenido y la fecha anteriores. |
| U5-C05-02 | P3 · Mejora de robustez | `verificar_privacidad.py:46-48` | Hay un archivo rastreado eliminado del directorio de trabajo, pero su eliminación todavía no está registrada en el índice. `git ls-files --cached` sigue devolviendo su nombre y `read_bytes()` intenta abrirlo. | Se produce `FileNotFoundError` y se interrumpe la verificación antes de completar el recorrido de objetos Git y emitir evidencia nueva. No produce un falso éxito del proceso, pero impide completar el análisis en ese estado válido del repositorio. | **Demostrable bajo esa condición.** El adjunto no demuestra que el repositorio de entrega esté en ese estado. | En un repositorio temporal, registrar un archivo y luego eliminarlo solo del directorio de trabajo. Ejecutar el verificador original con configuración de prueba y comprobar la interrupción en la lectura. |

En el primer caso, una corrección debería permitir distinguir **último intento** de **última ejecución satisfactoria**, conservando la historia si corresponde. En el segundo, conviene definir explícitamente si ese estado debe rechazarse con un diagnóstico controlado o si se deben recorrer solo los archivos existentes, manteniendo la inspección del contenido conservado en Git.

## Controles Existentes

- **Fallo cerrado ante coincidencias:** una coincidencia del inventario o de los patrones BCRYPT/SCRAM interrumpe el proceso antes de generar una evidencia satisfactoria.
- **Cobertura adicional del historial:** no se limita al directorio de trabajo; solicita todos los objetos disponibles mediante `--batch-all-objects` y revisa sus contenidos obtenidos con `--batch`.
- **Inspección de PDF en dos niveles:** revisa los bytes y, para contenidos que comienzan con `%PDF-`, también el texto extraído.
- **Diagnósticos propios sin valores privados:** los mensajes definidos para coincidencias y fallos de Git no incluyen el valor detectado.
- **Alcance declarado:** tanto el docstring como el JSON aclaran que el análisis complementa otros controles y no demuestra anonimización completa.
- **Trazabilidad básica:** la evidencia incluye fecha UTC y contadores. Esto ayuda a identificar una evidencia antigua, aunque no resuelve por sí solo el hallazgo U5-C05-01.

## 3. Límites Y Dependencias

- **Dependencias no adjuntas:** `secret_inventory`, `BCRYPT` y `SCRAM` de `anonimizar_log.py`, y `load_secrets` y `REPOSITORY_ROOT` de `libpq_client.py`. Su comportamiento se considera condicionado; aquí no se vuelve a acreditar su contenido ni se les atribuyen fallos.
- **Cobertura deliberadamente acotada:** la búsqueda depende del inventario conocido, de coincidencias literales y de los dos patrones importados. No garantiza detectar variantes, codificaciones, secretos desconocidos ni otros formatos de credenciales.
- **PDF:** la extracción de texto no equivale a OCR ni a una inspección exhaustiva de imágenes, adjuntos u otros elementos internos. Es una limitación del alcance, no un defecto demostrado de esta implementación.
- **Archivos ignorados:** los archivos ignorados y no rastreados quedan fuera de la enumeración del directorio de trabajo. Si integran el paquete final, su cobertura dependerá del análisis complementario mencionado por el propio script.
- **Recursos:** el contenido de todos los objetos se captura en memoria antes de recorrerlo (`50-56`). Esto limita la escalabilidad según el tamaño del repositorio, pero no hay evidencia de un problema efectivo en esta entrega.
- **PostgreSQL y Unidad 5:** este helper no verifica ACL, separación de owners, funciones `SECURITY DEFINER` ni comportamiento de roles. No permite confirmar ni refutar las pruebas originales conservadas.
- **Sin validación dinámica:** no se ejecutaron comandos, pruebas locales ni pruebas de motor. Las pruebas de la tabla son propuestas. Esta continuación se interpreta junto con las revisiones anteriores y no acredita pruebas históricas ni aprobación humana.

**Inventario Y Cobertura**
Fuentes de implementacion revisadas completas, usando la numeracion del archivo fuente:

| Fuente | Adjunto | Lineas cubiertas |
|---|---|---|
| `preparar.sql` | `07_preparar.sql` | 1-187 |
| `migrar.sql` | `08_migrar.sql` | 1-216 |
| `revertir.sql` | `09_revertir.sql` | 1-200 |
| `reproducir.py` | `10_reproducir_01.md` y `11_reproducir_02.md` | 1-740 y 741-1480 |
| `preparar_proveniencia.py` | `12_preparar_proveniencia.py` | 1-86 |
| `README.md` | `13_README.md` | 1-75 |

Para `reproducir.py`, los rangos son continuos, sin huecos ni solapamientos, hasta la ultima linea 1480. La sentencia interrumpida al final del primer fragmento continua en el segundo; no falta texto entre ambos.

Tambien revise completos los documentos de contexto y contrato:

| Adjunto | Lineas cubiertas |
|---|---|
| `01_requirements.md` | 1-55 |
| `02_design.md` | 1-64 |
| `03_tasks.md` | 1-119 |
| `04_ACLARACIONES_CODEX.md` | 1-42 |
| `05_DECISIONES_PREVIAS.md` | 1-35 |
| `06_CONTRATO_PRUEBAS.json` | 1-190 |
| `14_plan_cobertura_fuentes.json` | 1-41 |

Esta cobertura corresponde al texto adjunto. No use herramientas, no ejecute codigo y no verifique los hashes contra archivos del disco.

**Hallazgo Bloqueante**
### 1. Alta: Los nombres de SAVEPOINT con SQLSTATE son rechazados por el propio runner

**Ubicacion:** `reproducir.py:630-631`, llamadas en `858-860` y `1292-1295`. Los primeros nombres afectados se definen en `849-855`.

**Causa:** `expected_error()` valida el nombre con:

```python
re.fullmatch(r"[a-z_]+", name)
```

Sin embargo, `constraints()` le pasa `key.lower()` para claves como:

```text
R_duplicate_23505
LR_duplicate_23505
```

El resultado `r_duplicate_23505` contiene digitos. La validacion falla antes de crear el SAVEPOINT o ejecutar el INSERT esperado.

**Ejemplo reproducible sobre la copia prevista, por inspeccion estatica:** al llegar a `constraints()` con la migracion confirmada y las tres filas iniciales, el UPDATE valido se acepta y se revierte correctamente. A continuacion, el primer caso negativo llama a `expected_error()` con `r_duplicate_23505`, que produce `LaboratoryError("unsafe_savepoint")`. No llega a comprobarse el SQLSTATE 23505.

El ensayo termina en `FAILED` antes de concurrencia, cambios confirmados y down. Ademas, corregir solamente los nombres de `constraints()` no basta: las pruebas finales pasan nombres como `rd_insert_rejected_25006`, que tienen el mismo problema.

**Correccion minima:** permitir digitos despues del primer caracter del identificador:

```python
re.fullmatch(r"[a-z_][a-z0-9_]*", name)
```

Esto acepta los nombres internos existentes sin permitir espacios, separadores SQL ni identificadores que comiencen con digitos. No requiere cambiar los casos ni sus claves de evidencia.

**Evaluacion Del Resto**
No identifique otro defecto bloqueante demostrable en el texto revisado. En particular, la implementacion refleja correctamente estas decisiones:

- **Destino y preparacion:** comprueba el nombre exacto de base, exige esquema inicialmente ausente y valida bilateralmente las tres filas fuente antes de crear objetos. El runner envuelve la preparacion en una transaccion.
- **Checkpoint:** carga tres filas antes de instalar el trigger; posteriormente rechaza INSERT, UPDATE, DELETE y TRUNCATE con 25006. Se vuelven a comprobar filas y hash.
- **Precondicion negativa:** inserta la tupla invalida en la tabla operativa y ejecuta el cuerpo real de migracion. La validacion `R→D` ocurre antes de crear objetos normalizados y produce 23514.
- **Migracion:** reutiliza el mismo cuerpo SQL cargado para ROLLBACK y COMMIT, conserva la tabla inicial por renombrado y verifica equivalencia mediante `EXCEPT ALL` bilateral.
- **Integridad:** las PK/FK corresponden a RD/LR. Los escenarios negativos estan construidos para distinguir duplicados locales, FK inexistentes y colisiones LD a traves del JOIN, una vez corregido el bloqueo del runner.
- **Guardia y snapshots:** ambas tablas comparten el UPDATE de `turno` en BEFORE STATEMENT. La validacion posterior usa funciones VOLATILE y consulta el JOIN. La estrategia es coherente con READ COMMITTED; el conflicto 40001 en niveles superiores se documenta sin presentarlo como prueba ejecutada.
- **Concurrencia:** cada escritor crea y cierra su propia conexion dentro de su hilo. Un tercer backend observa tanto `Lock` como la presencia de A en `pg_blocking_pids(B)` antes de liberar el COMMIT de A. El resultado de B se comprueba por SQLSTATE, no por codigo de salida. La limpieza del recorrido exitoso ocurre en otra transaccion confirmada.
- **Fixtures:** el UPDATE valido previo termina revertido. Los cambios persistentes que producen cuatro filas se realizan despues de concurrencia.
- **Down:** bloquea RD/LR antes de capturar el JOIN actual, comprueba las cuatro filas contra el snapshot confirmado y reconstruye desde esa captura, no desde el checkpoint. Usa renombrados, sin DROP ni CASCADE.
- **Archivo y error inyectado:** la desactivacion del ciclo y el error P7501 ocurren despues de reconstruccion y renombrados. Se verifica desde una conexion nueva que el ROLLBACK restaura catalogo, vista, nombres, cuatro filas y ciclo activo. Tras el down confirmado, los triggers rechazan escrituras en RD/LR con 25006.
- **Errores y privacidad:** no hay `assert` eliminable con `-O`; las negativas inspeccionan `DatabaseError.sqlstate`. Las capturas generales de nivel superior registran fallo, no exito. Las huellas se calculan dentro de PostgreSQL sin exportar filas personales.

**Limites Y Condiciones**
Estos puntos no son defectos adicionales de la implementacion actual:

- **Respaldo:** se verifica un dump custom existente, su manifiesto `SUCCESS`, nombre, bytes, SHA256 y orden temporal. Se revalida el mismo respaldo fuente antes de cada fase; no se genera un respaldo actualizado del estado de cuatro filas ni se demuestra restaurabilidad mediante el hash. El README explicita esta diferencia.
- **Ejecucion fallida:** el runner no deshace COMMIT anteriores ni garantiza retirar fixtures ya confirmados si falla posteriormente. Por ejemplo, un fallo durante concurrencia puede dejar R803 auxiliar confirmado. No debe reintentarse suponiendo estado inicial limpio; el README ya exige copia nueva y no limpieza silenciosa.
- **Cliente U5:** las llamadas concuerdan con la API declarada en `DECISIONES_PREVIAS.md`. El archivo `unidad5/tools/libpq_client.py` no esta adjunto, por lo que no revise su implementacion ni su carga de `libpq.dll`. La puerta de proveniencia exige que permanezca sin cambios entre los commits indicados.
- **Proveniencia:** el codigo verifica hashes, commits y enlaces de artefactos; esta lectura no certifica que esos artefactos existan o sean validos en el repositorio. Tampoco interpreta `completed` como aprobacion tecnica o humana.
- **Compatibilidad:** no observe incompatibilidades estaticas adicionales con PostgreSQL 17 o Python 3.12. La compatibilidad efectiva sigue pendiente de ejecucion controlada, incluida la biblioteca cliente.
- **Alcance de proteccion:** las huellas no son una auditoria universal del cluster. Los triggers no impiden que un propietario privilegiado altere el DDL o que se manipule directamente la guardia; esa frontera de privilegios esta expresamente documentada.

**Dictamen**
**No recomiendo ejecutar esta version:** el hallazgo 1 impide completar el contrato de pruebas.

La correccion es localizada. Tras aplicarla, deben actualizarse los hashes, los fragmentos afectados y la cobertura, y realizarse una nueva revision Plan de las fuentes finales antes de ejecutar. Esta consulta es una revision tecnica automatizada, no una aprobacion humana del equipo.

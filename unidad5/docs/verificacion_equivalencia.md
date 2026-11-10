# Parte D - Protección de datos y equivalencia de agregados

Food Store - Unidad 5 - Base de Datos II. Exequiel Arancibia y Joaquin Romero.

La reconstrucción final, posterior a la Parte A y registrada el **22/10/2026 a las 16:46:53, zona UTC-03**, construyó una copia de **20.001 usuarios** y verificó **dos grupos**, con **cero diferencias en ambos sentidos**. Las evidencias actuales son [d_ejecucion_psql.txt](d_ejecucion_psql.txt), [d_equivalencia.json](d_equivalencia.json) y [d_resultados_lado_a_lado.md](d_resultados_lado_a_lado.md); el SQL completo está en [usuario_anon.sql](../sql/usuario_anon.sql). La tabla resultante pertenece a `rol_propietario` y `rol_reportes` tiene SELECT efectivo comprobado.

El SQL de construcción y comparación fue propuesto en una consulta real a **OpenCode 1.18.23**, con el modelo seleccionado explícitamente `openai/gpt-6.1-sol`, a partir de un contexto de esquema sanitizado, sin registros de usuarios. El prompt, la respuesta completa y los metadatos se conservan en `ia/d_prompt.txt`, `ia/d_respuesta.md` e `ia/d_metadatos.json`. Después de A, Codex integró `SET LOCAL ROLE rol_propietario` y el uso del esquema ya configurado; esa adaptación técnica no se atribuye a la respuesta original de OpenCode. La persona solicitante dio conformidad al cierre y pidió el ZIP para subirlo a la plataforma después de recibir el resumen A–E y la propuesta de revisión. El alcance consta en [validacion_humana.md](validacion_humana.md): esa conformidad no acredita lectura exhaustiva ni validación individual de ambos integrantes, y los controles automáticos conservan su autoría técnica.

## 1. Construcción de la copia independiente

Se creó `datos_anon.usuario_anon` con exactamente seis columnas: `folio`, `nombre`, `apellido`, `email`, `mes_alta` y `eliminado`. La copia no conserva una columna de ID original, la fecha y hora exactas de alta, contraseñas, hashes ni teléfonos reales; no modifica `public.usuario`.

Durante la construcción se obtiene `row_number() OVER (ORDER BY id)` y se usa su resultado para formar nombres del tipo `Persona00001`, el apellido constante `Laboratorio` y correos del tipo `persona00001@example.invalid`. La longitud del número es `GREATEST(5, length(folio::text))`, por lo que no se trunca cuando supera cinco dígitos; el ID de origen se usa únicamente para ordenar esa construcción y no se persiste en una tabla de correspondencias.

El mes conservado se obtiene con esta expresión, que respeta la zona del negocio antes de agrupar:

```sql
date_trunc(
    'month',
    created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
)::date
```

La reconstrucción de la copia y sus verificaciones se ejecutan dentro de `BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ` y `COMMIT`. Esto conserva el mismo snapshot de la fuente durante toda la transacción; si se detectan diferencias, la afirmación del script lanza una excepción y evita confirmar la reconstrucción. El reemplazo se limita a la copia de laboratorio, sin `CASCADE` y dentro de esa transacción.

La conexión técnica de preparación ejecuta el SQL, pero dentro de la transacción cambia al creador previsto mediante `SET LOCAL ROLE rol_propietario`; no se otorgó membresía de ese propietario a los logins de aplicación. La ejecución final registra `modo_ejecucion = propietario`, `propietario_tabla = rol_propietario` y `rol_reportes_select = true`. Así se comprobó la reconstrucción bajo el creador cuyos defaults permiten SELECT a reportes en `datos_anon`, además de la migración explícita de la copia preexistente que ya había realizado A.

La evidencia registra la misma SHA-256 para el archivo fuente y los bytes efectivos enviados a psql, sin una sustitución de rol en el modo normal:

```text
7e49e29525feecb9914cd8d540dfa32b8f2bef53c7fd6f98464f0158a51150a9
```

### Dos momentos reales y reproducción

La ejecución inicial del **21/10/2026 a las 13:54:59, UTC-03**, anterior a A, se conserva por separado en [d_bootstrap_equivalencia.json](evidencias/d_bootstrap_equivalencia.json) y [d_bootstrap_ejecucion_psql.txt](evidencias/d_bootstrap_ejecucion_psql.txt). También obtuvo 20.001 usuarios, dos grupos y diferencias 0/0; no se la presenta como una prueba de permisos de roles finales todavía inexistentes.

Para reproducir ese orden desde un laboratorio recién preparado:

1. Ejecutar `python tools/ejecutar_anonimizacion.py --bootstrap` únicamente en la preparación previa a A. Ese modo explícito sustituye la única línea de cambio de rol por la creación del esquema de copia y registra el SQL efectivo utilizado.
2. Aplicar la Parte A, con su migración de propietario y REVOKE/GRANT explícitos sobre la copia ya existente. Los defaults afectan objetos futuros del creador configurado, no corrigen retroactivamente una tabla anterior.
3. Ejecutar `python tools/ejecutar_anonimizacion.py` sin `--bootstrap`. Este es el modo final realizado: reconstruye bajo `rol_propietario`, vuelve a comparar el contenido agregado y verifica propietario y permiso SELECT de reportes.

Si se conservan ambos momentos en una reproducción nueva, deben archivarse las evidencias iniciales antes de ejecutar el modo normal, que escribe los archivos actuales `d_*`. El rol de reportes es NOLOGIN: la comprobación de su privilegio no implica que se haya iniciado sesión directamente con él.

## 2. Consultas equivalentes solicitadas a OpenCode

`usuario` no tiene un atributo de rol de negocio: los roles LOGIN de PostgreSQL son identidades diferentes. Por eso la comparación utiliza **mes local de alta y marca de eliminación**, sin inventar una columna `rol`.

Consulta sobre la tabla real, cuyo resultado solo contiene agregados:

```sql
SELECT
    date_trunc(
        'month',
        created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
    )::date AS mes_alta,
    eliminado,
    count(*) AS cantidad
FROM public.usuario
GROUP BY
    date_trunc(
        'month',
        created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
    )::date,
    eliminado
ORDER BY mes_alta, eliminado;
```

Consulta equivalente sobre la copia:

```sql
SELECT mes_alta, eliminado, count(*) AS cantidad
FROM datos_anon.usuario_anon
GROUP BY mes_alta, eliminado
ORDER BY mes_alta, eliminado;
```

A OpenCode se le proporcionó únicamente el esquema sanitizado para generar estas consultas. Las salidas conservadas después de ejecutarlas contienen agregados; para una revisión posterior con IA se limita la información a esos agregados revisados, sin enviar filas reales ni la tabla de usuarios completa.

## 3. Resultados reales y comprobación de equivalencia

| Mes local de alta | Eliminado | Cantidad en usuario real | Cantidad en usuario_anon | Coincide |
|---|---|---:|---:|---|
| 2026-09-01 | false | 20.000 | 20.000 | Sí |
| 2026-10-01 | false | 1 | 1 | Sí |
| **Total** | | **20.001** | **20.001** | **Sí** |

En la salida original de `psql`, `f` representa `false`. Las dos consultas devuelven las mismas filas, agrupamientos y conteos; la comparación lado a lado mediante `FULL OUTER JOIN` también marca `coincide = t` en ambos grupos.

La auditoría aplica `EXCEPT ALL` en ambos sentidos para detectar tanto grupos o conteos faltantes como sobrantes. Una versión autocontenida de ese control, equivalente al ejecutado, es:

```sql
WITH origen AS (
    SELECT
        date_trunc(
            'month',
            created_at AT TIME ZONE 'America/Argentina/Buenos_Aires'
        )::date AS mes_alta,
        eliminado,
        count(*) AS cantidad
    FROM public.usuario
    GROUP BY 1, 2
), copia AS (
    SELECT mes_alta, eliminado, count(*) AS cantidad
    FROM datos_anon.usuario_anon
    GROUP BY 1, 2
)
SELECT 'origen_menos_copia' AS sentido, count(*) AS diferencias
FROM (TABLE origen EXCEPT ALL TABLE copia) d
UNION ALL
SELECT 'copia_menos_origen', count(*)
FROM (TABLE copia EXCEPT ALL TABLE origen) d;
```

| Sentido de la comparación | Diferencias reales |
|---|---:|
| origen_menos_copia | 0 |
| copia_menos_origen | 0 |

En el script final ejecutado, las diferencias se almacenan temporalmente y se muestran: la salida fue **`(0 rows)`**. El bloque `DO` comprueba su inexistencia y lanza `RAISE EXCEPTION` si encuentra alguna; el registro muestra `BEGIN`, `SET`, `INSERT 0 20001`, `DO` y luego `COMMIT`, sin error. La tabla temporal se elimina al confirmar y no forma parte de la copia entregada.

Además, el verificador contrastó la huella de los **20.000 usuarios heredados** y confirmó que permanecen intactos; el usuario adicional corresponde a la cuenta del laboratorio U5. El control final más amplio de [conservacion_after.json](evidencias/conservacion_after.json), comparado con [conservacion_before.json](evidencias/conservacion_before.json), registra `same_as_before = true` para conteos y huellas ordenadas de las cinco tablas de negocio, incluidas las 20.001 filas actuales de usuario. Esto comprueba conservación del contenido observado, por separado de la equivalencia de agregados y de los permisos.

### Alcance y límites de la transformación

El correlativo es determinista para el mismo snapshot y orden por ID, pero no constituye un identificador estable frente a cualquier modificación de la fuente: las altas pueden agregar nuevas posiciones y los borrados pueden desplazar las posteriores. Si los IDs de origen forman un rango denso que comienza en uno, el folio puede incluso coincidir numéricamente con el ID; quitar una columna llamada `id` no elimina esa posibilidad de vinculación.

Por eso esta técnica se trata como una copia desidentificada de laboratorio, con posibles propiedades de pseudonimización, y **no como una demostración de anonimización irreversible**. `mes_alta` y `eliminado` siguen siendo cuasiidentificadores; un grupo de una sola persona, como el de octubre en esta prueba, puede facilitar inferencias al combinarlo con información externa. La igualdad comprobada acredita solamente los agregados definidos, no ausencia de reidentificación ni equivalencia de cualquier consulta posible sobre los datos.

## 4. Información que no debe salir hacia un asistente de IA

Las contraseñas, hashes de autenticación y credenciales de acceso de Food Store no deben enviarse a un asistente de IA. Tampoco deben salir nombres, correos, teléfonos ni ventas vinculadas a una persona sin una transformación y minimización adecuadas al uso previsto. Para trabajar con IA se prefieren esquemas sin registros, datos sintéticos o agregados revisados, evaluando también el riesgo de grupos pequeños y cuasiidentificadores.

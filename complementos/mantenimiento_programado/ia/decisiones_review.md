# Decisiones técnicas del complemento

Autor del contraste: Codex. Revisión automatizada; no equivale a firma ni revisión humana del equipo. La respuesta original de cada consulta se conserva sin reescritura.

## SCH-01

El primer SPEC no enumeraba el contrato interno del manifiesto; Build adoptó explícitamente un esquema supuesto, incompatible con los campos U6 reales.

**Decisión técnica: corregido.** El consumidor nuevo ahora usa database/file/size/sha256/startUtc/endUtc, subdirectorio backups y baseline de cinco MD5 de32 caracteres. No se modificó U6 ni se fabricaron manifiestos.

Evidencia: `SPEC_SCHEDULER.md`, `run_backup_job.ps1`, `ia/generacion_original/run_backup_job.ps1`.

## SCH-02

La propuesta requería DACL protegida incluso cuando la herencia sólo concedía los tres SID autorizados. El PGPASSFILE anterior tiene herencia y tres entradas privadas.

**Decisión técnica: corregido.** Se validan todas las concesiones efectivas, permitiendo herencia de esos mismos SID; no se cambian permisos ni contenidos del PGPASSFILE.

Evidencia: `run_backup_job.ps1`, `README.md`.

## SCH-03

El consumidor no comprobaba previamente backups/logs existentes antes de delegar escrituras al backend opaco.

**Decisión técnica: corregido.** Se requieren y verifican ambos directorios privados y sus cadenas antes de ejecutar U6 y justo antes de delegar. No se reparan ACL ajenas. No se observó una exposición real.

Evidencia: `run_backup_job.ps1`, `ia/scheduler_plan_respuesta.md`.

## SCH-04

Inventarios recursivos de JSON fuera del directorio contractual de manifiestos.

**Decisión técnica: corregido.** Ambos inventarios se limitan a logs/*.manifest.json, sin recursión ni JSON de terceros.

Evidencia: `run_backup_job.ps1`, `ia/scheduler_plan_respuesta.md`.

## SCH-05

El patrón estricto de basename no estaba declarado en el primer contrato adjunto.

**Decisión técnica: corregido.** Se confirmó localmente el patrón real New-RunToken de U6 y se agregó explícitamente a SPEC; se conserva la validación acotada. La corrección es del contrato/documentación, no de un nombre U6 defectuoso.

Evidencia: `SPEC_SCHEDULER.md`, `ia/scheduler_plan_respuesta.md`.

## SCH-06

Comprobación de reparse points/Git en ancestros sin verificar ACL capaces de sustituir objetos protegidos.

**Decisión técnica: corregido.** Validación de propietarios y derechos efectivos peligrosos de ancestros, distinguiendo lectura/tránsito y ACE InheritOnly. Excepción TrustedInstaller sólo para ancestros del sistema; destinos privados mantienen lista restringida. El entorno observado no mostró derechos de sustitución a terceros.

Evidencia: `run_backup_job.ps1`, `SPEC_SCHEDULER.md`, `ia/scheduler_plan_final_respuesta.md`.

## SCH-07

Fallo real 0x8004131A por declaración UTF-8 al pasar un BSTR a RegisterTask. **Decisión técnica: corregido.** Se eliminó solamente XmlDeclaration de un clon del DOM para COM; el archivo original sigue UTF-8. MicroPlan completo de 336 líneas aprobado antes de repetir; registro y ejecución real posteriores correctos. El verificador operativo de Codex tuvo además un fallo separado al exigir un campo predeterminado omitido por Windows; se corrigió por comparación CIM, sin cambiar scripts nuevos ni culpar a OpenCode.

Cierre: el Plan completo leyó747 líneas del runner, 332 del creador y 47 del XML sin truncamiento y aprobó el ensayo controlado; la microrevisión posterior leyó el creador final de 336 líneas. Las evidencias reales están en `../evidencias/`. Esto no acredita aprobación humana del equipo.

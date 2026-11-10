**Dictamen**
No identifiqué en los cinco adjuntos un defecto concreto que impida el ensayo controlado conforme al contrato suministrado. **El hallazgo previo sobre sustitución desde ancestros quedó resuelto en el código revisado**, dentro del alcance declarado: identidades autorizadas confiables y ausencia de modificaciones concurrentes por esas identidades.

La revisión es estática, sobre el texto completo incluido en el mensaje. No usé herramientas, ejecuté código ni contrasté fuentes U6 o condiciones del equipo.

**Corrección De Ancestros**
En `02_run_backup_job.ps1`:

- **Recorrido completo:** `Assert-PathChain` examina el destino existente y asciende hasta la raíz, rechazando reparse points y ubicaciones Git, incluido el marcador `.git` de un worktree (líneas **53–110**).
- **Propietarios confiables:** cada directorio de la cadena debe tener propietario perteneciente a la lista admitida (líneas **73–77**). La lista incorpora usuario actual, SYSTEM, Administradores y el SID de TrustedInstaller resuelto localmente (líneas **325–335**).
- **Permisos de sustitución:** para identidades ajenas se rechazan `Delete`, `DeleteSubdirectoriesAndFiles`, `ChangePermissions`, `TakeOwnership` y `WriteData` (líneas **78–95**). En directorios, `WriteData` corresponde a crear archivos; `CreateDirectories` aislado no está incluido en esa máscara.
- **Aplicabilidad de las ACE:** las ACE `InheritOnly` no se consideran derechos sobre el directorio actual; lectura y tránsito por sí solos no provocan el rechazo (líneas **85–87**).
- **OWNER RIGHTS:** en ancestros se vincula al propietario confiable (líneas **89–94**). En los destinos privados continúa la regla más restrictiva: únicamente cuando el propietario es el usuario actual (líneas **153–161**).

Una precisión terminológica: esto es una **comprobación conservadora de ACE Allow aplicables**, no un cálculo integral de acceso efectivo de Windows que combine grupos y ACE Deny. No descuenta concesiones peligrosas porque otra ACE pudiera denegarlas. Esa diferencia puede producir rechazos conservadores, pero no constituye una omisión de protección que bloquee por diseño el ensayo descrito.

La excepción de TrustedInstaller no amplía las identidades admitidas para los propios destinos privados: `Assert-PrivateItem` vuelve a comprobar propietario y concesiones con la lista estrecha (líneas **126–163**).

**Controles Conservados**

| Control | Verificación estática |
|---|---|
| Destinos internos | Se exige que `backups` y `logs` existan y sean privados antes de U6 (**runner 434–443**), y se revalidan inmediatamente antes de delegar (**543–552**). No se crean ni reparan automáticamente. |
| Ventana y sesiones | Ventana UTC futura de hasta 60 minutos (**166–196, 427–428**); consulta de otras sesiones cliente y rechazo ante resultado distinto de cero o error (**502–532**). Se conserva expresamente que es una observación, no un cerrojo (**543–545**). |
| Proceso hijo y secretos | U6 se invoca mediante `pwsh` hijo con `-NoLogo -NoProfile -NonInteractive` y `-ConfirmNoWrites` después de los controles (**554–569**). Se eliminan las variables heredadas `PG*` y se establece un entorno explícito, incluido `PGPASSFILE` y timeout (**220–229, 467–476**). No se incorpora la contraseña a argv. |
| Manifiesto | Ambos inventarios se limitan a `logs/*.manifest.json`, sin recursión (**538–541, 579–580**). Se exige exactamente un SUCCESS nuevo con inicio compatible con el comienzo del job y tiempos válidos (**601–624**). |
| Dump y baseline | Se verifica contrato de metadatos, basename restringido, privacidad del dump, tamaño y SHA256 (**626–689**). El baseline exige las claves estipuladas, conteos no negativos, invalidaciones cero y MD5 minúsculos de 32 caracteres (**293–318**). |
| Errores y resultados | Código del proceso capturado tras su terminación (**253–260**) y comprobado tras cada invocación. Resultado mediante `CreateNew` (**268–290**). Fallos, incluida una escritura fallida, terminan con código 1, sin fabricar SUCCESS (**707–746**). |
| Calendario | Primer disparo explícito con offset y futuro; por defecto, próximo horario 02:00 UTC−03 (**creador 146–182**). Calendario diario con intervalo 1 (**230–234; XML 7–17**). |
| Token y registro | SID del usuario actual, `InteractiveToken`, `LeastPrivilege` (**creador 212, 226–229**). Registro oficial con `TASK_CREATE=2`, sin actualizar una tarea existente, sin contraseña y con tipo de inicio interactivo (**298–312**). |
| Settings | Se conservan `IgnoreNew`, límite de diez minutos, sin despertar, sin inicio a demanda, batería permitida y sin reintentos configurados (**creador 205–209, 238–249; XML 26–39**). |

El README mantiene separados la propuesta diaria, el ensayo temporal y un servicio permanente. La espera del disparo horario, exportación y saneamiento de evidencia, conservación de hashes y retirada exclusiva de la tarea temporal siguen siendo pasos operativos documentados, **no acciones acreditadas como realizadas** (`05_README.md`, **29–35**).

**Lectura Completa**

| Adjunto | Líneas leídas | Última línea | Truncamiento |
|---|---:|---|---|
| `01_SPEC_SCHEDULER.md` | 1–33 | Párrafo «Protección de ancestros ante sustitución», terminado en «administradores del equipo.» | No |
| `02_run_backup_job.ps1` | 1–747 | `}` | No |
| `03_crear_tarea_diaria.ps1` | 1–332 | `}` | No |
| `04_tarea_diaria.template.xml` | 1–47 | `</Task>` | No |
| `05_README.md` | 1–37 | Párrafo sobre el segundo Plan, terminado en «ni se afirma exposición real.» | No |

**Límites**
Este dictamen no acredita ACL reales, disponibilidad, registro de una tarea ni ejecución exitosa. Tampoco convierte el chequeo de sesiones en un bloqueo del negocio. Los administradores autorizados, los cambios concurrentes y la disponibilidad del equipo permanecen como límites explícitos, no como hallazgos nuevos.

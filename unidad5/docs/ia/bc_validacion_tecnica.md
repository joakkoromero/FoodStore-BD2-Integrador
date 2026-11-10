# Revisión técnica de la propuesta real de OpenCode para B y C

La respuesta completa realmente recibida se conserva sin modificar en
`bc_respuesta.md`. Sus dos bloques SQL se extrajeron como base de
`sql/auditoria_test.sql` y `sql/simulacro_incidente.sql`.

Esta revisión y los ajustes siguientes fueron realizados con Codex antes de
la ejecución. No se atribuyen a una persona. Posteriormente se completaron
Kiro, la instalación y las pruebas reales: B aprobó 10 eventos y C aprobó 11,
según `../evidencias/audit_resultados.json` e `incident_resultados.json`.
La validación humana se registra por separado; esta nota no la sustituye.

| Observación sobre la respuesta recibida | Corrección o integración aplicada |
|---|---|
| Recomienda elegir un producto apto para dos unidades, pero el SELECT propuesto no filtra stock ni baja lógica. | Se agregó `eliminado=FALSE AND stock>=2`; el cliente usa el precio obtenido del catálogo y se detiene si no hay un producto apto. |
| Pide comprobar exactamente una fila afectada por INSERT/UPDATE, pero las sentencias propuestas de detalle y confirmación no devuelven filas. La interfaz libpq de este repositorio no expone `PQcmdTuples`. | Se agregó `RETURNING` y se comprobaron la cardinalidad y los valores booleanos/estado antes de registrar el resultado. No se toma un simple comando exitoso como prueba de modificación de una fila. |
| Reordena BEGIN y SELECT en el catálogo. Ese cambio por sí solo no cambia el orden real de un cliente que elige las sentencias por nombre. | Se modificó también la orquestación Python para ejecutar BEGIN antes de la lectura y conservar ROLLBACK en finally. |
| Devuelve id y estado inicial y condiciona la confirmación a PENDIENTE. | Se adoptó la propuesta y se exige un único pedido inicialmente PENDIENTE; el identificador permanece solo en memoria. |
| Advierte correctamente que usar parámetros no impide que una configuración registre sus valores. | El cliente comprueba ambos parámetros de longitud en cero antes de enviar correo/clave. B y C exigen además logging de conexiones, desconexiones, todas las sentencias y errores. |
| Advierte correctamente que ROLLBACK no recupera valores IDENTITY ni borra el log. | La evidencia distingue conteos de filas restaurados de valores de secuencia consumidos. No se promete restaurar la secuencia. |
| Presenta la reutilización de la consulta de membresía como una precisión faltante. | Se mejoraron los comentarios SQL, pero el cliente anterior ya realizaba ambas comprobaciones desde otra conexión en autocommit. Se registra como mejora documental, no como un error funcional descubierto. |
| Distingue correctamente autenticación de negocio y sesión PostgreSQL, y limita lo que prueba el log nativo. | Se verifica el rol de base antes y después de `fn_autenticar`; el conteo real de filas se acredita por el cliente y no se atribuye al log nativo. |

No se identificó en esta respuesta una propuesta de `GRANT ALL` ni una membresía
administrativa que el equipo haya tenido que rechazar. No se inventa ese caso
para la bitácora: la revisión de permisos de la Parte A debe documentar lo que
su interacción real produzca.

La comprobación estática usa `work/unidad5/check_tools_offline.py` durante la
elaboración: AST Python, catálogo SQL, enlace de parámetros con libpq simulado y
escaneo de ejemplos en memoria. Esa comprobación no abre conexiones ni acredita
que los roles o el incidente ya hayan funcionado.

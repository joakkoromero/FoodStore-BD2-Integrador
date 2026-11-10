# Revisión técnica automática de la especificación Kiro

Autor de esta revisión: Codex. No constituye validación humana de los
integrantes. Los documentos de Kiro se conservan literalmente; estas notas
son precisiones para su implementación y verificación posteriores.

## Procedencia y orden

| Documento real de Kiro | Marca de la respuesta exportada (UTC) |
|---|---|
| Borrador original de requisitos | 2026-10-22 17:46:46.519 |
| Revisión intermedia de requisitos | 2026-10-22 17:55:53.461 |
| Requisitos finales | 2026-10-22 17:59:48.630 |
| Diseño | 2026-10-22 18:02:27.319 |

Las respuestas fueron generadas antes de la implementación A. El contenido
proviene de **Export Chat** de la aplicación Kiro, no de una simulación de
su autoría. Se extrajo únicamente el mensaje visible del asistente, operación
`Say`; no se incluyen razonamientos internos, metadatos de cuenta ni cargas
de herramientas. Cada archivo `*_procedencia.json` registra marcas y SHA-256.
Los ZIP originales permanecen fuera del repositorio, en el trabajo privado.

## Correcciones reales conservadas

1. El contexto inicial tenía una frase ambigua sobre la propiedad de las
   funciones protegidas y luego una regla más específica para rol_funciones.
   Se aclaró esa ambigüedad. El primer borrador de Kiro asignaba las mismas
   funciones a dos propietarios; una revisión intermedia aún clasificaba
   recalcular_total_pedido de ambas formas. Los requisitos finales y el diseño
   asignan los cuatro puentes exclusivamente a rol_funciones como DEFINER.
2. Kiro añadió SELECT sobre pedido y detalle_pedido para soporte sin que lo
   necesitara el alcance acordado. Codex rechazó esa ampliación por mínimo
   privilegio y pidió la corrección real: soporte queda limitado a contacto
   de usuario y UPDATE telefono. Se conserva el texto anterior como evidencia.
3. Se precisaron SET FALSE, los tres objetos autorizados de reportes y el
   carácter previsto de las pruebas. No se atribuyeron resultados de pruebas
   ni aprobaciones humanas a Kiro.

## Control del alcance final

Las matrices finales distinguen lectura y escritura de app, soporte y
reportes; excluyen credenciales, total/subtotal derivados y DELETE de
pedido/usuario. No conceden membresía de propietarios a logins, ni tablas
propias a rol_funciones. Los cuatro DEFINER son fn_autenticar,
fn_resetear_password, recalcular_total_pedido y u4_refrescar_ventas.
Las demás funciones heredadas, incluido el serializador U4, permanecen
INVOKER de rol_propietario. Se conserva el comportamiento mensual TP5.

También se contempla la migración explícita de usuario_anon ya existente,
la reconstrucción posterior bajo el creador correcto, los defaults por
esquema y TEMP técnico sólo para rol_propietario en la base del laboratorio.

## Precisiones que debe resolver la implementación

- El diseño dejó pendiente el retorno y los errores de fn_resetear_password.
  La integración técnica de Codex fija retorno void y longitud de la nueva
  contraseña entre 12 y 72 bytes. La implementación debe probar autorización,
  usuario inexistente y límites; esta definición posterior no se atribuye a
  Kiro ni se presenta aquí como prueba ejecutada.
- Se prioriza la matriz final más estrecha de soporte: exactamente seis
  columnas (id, nombre, apellido, email, telefono, eliminado), sin created_at.
  Cualquier contexto preliminar o prueba que contemplara siete columnas se
  ajustará a esas seis, en lugar de ampliar el permiso.
- Aplicar USAGE de esquemas y CONNECT a la base únicamente donde se
  necesiten. Quitar CREATE y TEMP heredados de PUBLIC y cualquier permiso
  previo que contradiga las matrices; la ausencia de un GRANT nuevo no
  elimina un privilegio heredado.
- Aplicar defaults de funciones para los roles creadores reales, además de
  los REVOKE explícitos de funciones existentes. Probarlos con objetos
  creados efectivamente por cada propietario; los defaults de otro creador
  no los sustituyen.
- El evento de autenticación puede escribirse en el log sin crear una tabla
  de auditoría ni ampliar INSERT a rol_funciones. El registro no debe
  contener correo, contraseña ni hash; los secretos se pasan parametrizados.
- Conservar todos los triggers realmente inventariados, incluidos los
  disparadores U4 en producto y categoria, además de pedido y detalle. Los
  nombres resumidos en el diseño no sustituyen el inventario de la base.
  La expresión de Kiro «sin modificación» se interpreta como conservación
  de reglas de negocio y enlaces de triggers; admite cambiar la propiedad,
  SECURITY DEFINER y la cualificación de nombres que el propio diseño exige.
- La conservación de filas heredadas se demuestra con huellas de contenido
  antes y después. El conteo mencionado por Kiro es una comprobación
  complementaria: por sí solo no detecta modificaciones que preserven filas.
- La reconstrucción D debe comprobar nuevamente equivalencia bajo snapshot,
  además de defaults. Los grants por columnas/objetos no aíslan filas por
  cliente del negocio; no se debe atribuirles esa protección.

Estas precisiones no autorizan ampliar la matriz de privilegios. Las pruebas
previstas se ejecutarán después de implementar y sus resultados se guardarán
como evidencia separada de esta especificación.

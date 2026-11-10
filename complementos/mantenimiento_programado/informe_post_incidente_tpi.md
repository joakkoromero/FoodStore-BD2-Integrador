# Informe post-incidente - Recuperación del TPI

Food Store | Complemento del 10/11/2026 | Ejecución técnica asistida por Codex.

## Respaldo programado y situación simulada

Se ensayó una tarea DIARIA real del Programador de Windows, con primer disparo de laboratorio a las 14:37:41 UTC-03. Se usó el token interactivo actual y nivel limitado, sin contraseña guardada ni inicio manual. LastTaskResult=0 y el resumen verificó SUCCESS. Después se deshabilitó y retiró únicamente esa tarea; no se presenta un servicio productivo permanente.

El último respaldo custom de foodstore empezó a las 14:37:48,617 y se publicó a las 14:37:53,822 UTC-03: 8.224.005 bytes, TOC verificado y SHA256 `8067e36dca81ea6b8c5a870d1bddc2927634a33aad842d22d96bf09c1bd82b19`. El dump permaneció privado. La ventana sin escritores se coordinó; el preflight de sesiones no se presenta como bloqueo automático del negocio.

## Recuperación contra reloj

Se preservó la copia de prueba anterior por RENAME a foodstore_restore_test_u6_conservada_20261110, comprobando identidad por OID, ausencia de sesiones y nombre destino libre. No se borró ni reemplazó la principal. El script U6 intacto creó una foodstore_restore_test nueva desde el mismo último manifiesto programado.

El ensayo comenzó a las 14:38:07,691 UTC-03. RTO monotónico desde antes de createdb hasta aislamiento, restore y comparación: **13,4303715 s**, inferior al objetivo de 120 s. Antigüedad de referencia desde el inicio de pg_dump: **19,0739065 s**, inferior a 24 h. Es una cota temporal conservadora, no pérdida real medida ni recuperación PITR. Estas medidas del 10/11 no reemplazan las históricas U6 del 03/11 (11,350 s y 31,808 s).

## Validación y alcance

Categorías 2; usuarios 20.001; productos 50.000; pedidos 225.000; detalles 499.997. Los cinco conteos y huellas completas coincidieron con el manifiesto; productos/detalles inválidos 0/0. Las cinco tablas fuente y los cuatro archivos U6 reutilizados permanecieron iguales. El restore usa --no-owner --no-privileges y está aislado: **no recupera la política de roles/ACL U5 ni habilita la aplicación**.

## Problemas, decisiones y mejora

Se corrigió la declaración de codificación del XML pasado a COM y se revisó el cambio mediante microrevisión Plan antes de repetir. Un verificador de Codex exigió un nodo RunLevel que Windows omitía al exportar; se contrastó el valor Limited real de CIM y se preservó la omisión en la copia saneada. Los intentos fallidos y sus retiros quedaron registrados, sin respaldo fabricado ni cambio de filas fuente.

Para operación continua: responsables de ventana, monitorización y retención; copia cifrada externa y restauración periódica en destino nuevo. Las revisiones técnicas de IA y Codex no constituyen firma ni lectura humana del equipo.

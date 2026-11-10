# Aclaraciones previas a la generación Build

Aclaraciones técnicas de Codex posteriores a la respuesta final de Kiro (no son una reescritura de las specs):
1. Si tasks.md describe preparar el fixture antes de la tarea Build, interpretar el orden correcto como: conservar specs, generar TODOS los scripts en esta respuesta Build, leerlos, respaldar y recién entonces ejecutar la preparación y los casos. Ya se probó un respaldo previo real de foodstore mediante el script U6, sin modificar filas.
2. Aunque disponible se deriva de stock>0 en PostgreSQL, el semáforo deberá comprobar explícitamente snapshot_servidor.disponible, normalizado desde t/f, además de existencia, baja y stock.
3. No usar la hora del dispositivo ni un umbral temporal como autoridad. Tras una restauración del servidor hay que invalidar todas las cachés/instantáneas y reconciliar UUIDs y colas antes del reenvío; esto se documentará en el plan y no agrega ventas a la simulación.
4. La demostración de ausencia de escrituras combina SQL local sin conexión a PostgreSQL y comparaciones reales de stock/pedidos/huellas de fuente; no basta afirmar ausencia de logs. Los cambios de precio C2 y baja C4 son preparaciones administrativas explícitas en la copia.
5. Tanto id_local como solicitud_uuid deben tener formato UUID válido en los datos de prueba. Proteger una sola PENDIENTE por borrador, sin prohibir los intentos históricos. El caso vacío es un borde negativo consciente de laboratorio.

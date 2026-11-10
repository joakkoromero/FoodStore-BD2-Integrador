# Revisión del borrador original de Kiro

Revisión técnica realizada por Codex antes de generar los scripts U8 con OpenCode. No representa una validación humana del equipo. El texto original permanece íntegro en `borrador_original_kiro.md`; su hash y la forma real de guardado constan en `borrador_proveniencia.json`.

| ID | Propuesta del borrador | Problema comprobado en la especificación o el modelo real | Corrección solicitada a Kiro |
|---|---|---|---|
| K-01 | LEFT JOIN de los ítems contra producto_cache | El semáforo debe comparar con la instantánea nueva snapshot_servidor; la caché puede conservar filas antiguas ausentes de ella. | Comparar contra snapshot_servidor y tratar la ausencia como rojo. |
| K-02 | p.producto_id y JOIN categoria USING(categoria_id) | En PostgreSQL las PK reales son producto.id y categoria.id; sólo producto tiene categoria_id. La vista propuesta no compila. | p.id AS producto_id y JOIN categoria c ON c.id=p.categoria_id. |
| K-03 | INSERT OR REPLACE con la afirmación de que no borra filas referenciadas | REPLACE en SQLite elimina la fila en conflicto antes de insertar; puede violar la FK o disparar acciones de borrado. | UPSERT con ON CONFLICT(producto_id) DO UPDATE, conservando las filas y lápidas. |
| K-04 | Review de mínimo dos unidades | El TP pide revisar todos los scripts de la cursada. El mínimo de dos unidades sólo limita los tres hallazgos que se desarrollan. | Revisar todas las unidades, registrar cada hallazgo y desarrollar al menos tres de dos unidades. |
| K-05 | REQ-02 no enuncia cantidad superior al stock | El caso C3 y el diseño sí lo mencionan, pero falta el criterio rojo explícito en el requisito EARS. | Incluir cantidad > snapshot_servidor.stock entre las condiciones rojas. |
| K-06 | Task 5 prueba precio negativo y producto inexistente | El TP exige cantidad cero y producto inexistente, ambos sin filas nuevas tras rollback. | Probar obligatoriamente cantidad=0 y FK inexistente; precio negativo puede agregarse. |
| K-07 | Preparar fixture en Task 2 antes de la generación Build de Task 3 | La secuencia debe especificar primero y generar después todos los scripts de implementación. | Congelar los tres documentos, generar todos los scripts con OpenCode Build, leerlos y recién entonces preparar/ejecutar el laboratorio. |

Se conservarán también la respuesta corregida y los tres archivos finales, sin reemplazar esta evidencia inicial ni presentar sus ejemplos SQL como scripts ya ejecutados. La prueba de C6 con varios intentos históricos se demuestra naturalmente mediante el conflicto C2 y su nueva solicitud tras aceptar el precio, sin inventar resultados de simulación anteriores.

Fuentes técnicas contrastadas: esquema real de PostgreSQL consultado en modo de sólo lectura; consigna U8 y parada 5 del apunte; documentación oficial de [SQLite REPLACE](https://www.sqlite.org/lang_conflict.html) y [claves foráneas](https://www.sqlite.org/foreignkeys.html).

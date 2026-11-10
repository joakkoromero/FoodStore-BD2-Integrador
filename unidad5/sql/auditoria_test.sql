-- Parte B: catalogo de sentencias parametrizadas para PostgreSQL 17.
-- Base: propuesta real OpenCode conservada en docs/ia/bc_respuesta.md.
-- Ajustes tecnicos posteriores: stock apto y RETURNING para probar filas.
-- Ejecutar mediante el cliente Python:
-- python tools/ejecutar_pruebas.py --phase audit
--
-- No ejecutar este archivo completo en psql. El cliente selecciona cada
-- sentencia por su marcador y enlaza los parametros con PQexecParams.
-- Ejecutar toda la prueba en una misma conexion real de app_web.
-- Los permisos propuestos son precondiciones por verificar, no hechos.
--
-- El cliente debe disponer de un usuario de prueba valido y elegir un
-- producto apto para agregar dos unidades. No compartir sus identificadores
-- ni los valores de las filas en la evidencia.
-- Los ids IDENTITY se generan al insertar; no se invocan secuencias.
-- Una conexion PostgreSQL fallida se prueba desde Python, no mediante SQL.

-- name: audit_begin
BEGIN;

-- name: audit_catalog_read
SELECT id,precio,stock
FROM public.producto
WHERE eliminado=FALSE AND stock>=2
ORDER BY id
LIMIT 3;

-- name: audit_insert_order
-- $1: id del usuario de prueba.
-- El cliente conserva el id devuelto y comprueba estado = PENDIENTE.
INSERT INTO public.pedido(usuario_id,fecha,forma_pago)
VALUES ($1::bigint,CURRENT_TIMESTAMP,'EFECTIVO'::public.forma_pago)
RETURNING id,estado;

-- name: audit_insert_detail
-- $1: id del pedido recien creado.
-- $2: id del producto elegido.
-- $3: precio unitario obtenido del catalogo.
INSERT INTO public.detalle_pedido(
    pedido_id,producto_id,cantidad,precio_unitario
)
VALUES ($1::bigint,$2::bigint,1,$3::numeric)
RETURNING cantidad=1 AS linea_creada;

-- name: audit_update_detail
-- Ejecutar mientras el pedido sigue PENDIENTE.
-- $1: id del pedido; $2: id del producto.
UPDATE public.detalle_pedido
SET cantidad=cantidad+1
WHERE pedido_id=$1::bigint AND producto_id=$2::bigint
RETURNING cantidad;

-- name: audit_confirm_order
-- Ejecutar solo despues de insertar y modificar el detalle.
-- $1: id del pedido.
UPDATE public.pedido
SET estado='CONFIRMADO'
WHERE id=$1::bigint AND estado='PENDIENTE'
RETURNING estado='CONFIRMADO' AS confirmado;

-- name: audit_order_total_invariant
-- $1: id del pedido.
SELECT p.total IS NOT DISTINCT FROM COALESCE(SUM(d.subtotal),0)
       AS total_correcto
FROM public.pedido p
LEFT JOIN public.detalle_pedido d ON d.pedido_id=p.id
WHERE p.id=$1::bigint
GROUP BY p.total;

-- name: audit_rollback
-- Ejecutar tambien ante errores, mientras la conexion siga disponible.
ROLLBACK;

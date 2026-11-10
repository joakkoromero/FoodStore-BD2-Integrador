-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Food Store - Unidad 7 - Arancibia / Romero
-- Ejecutar con psql -X -v ON_ERROR_STOP=1 -d foodstore -f consultas_postgresql.sql
-- Solo lectura. Las comparaciones usan exactamente la muestra migrada [1,2,3,4,5].
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL TIME ZONE 'UTC';

-- 1 y 2: exportacion Extended JSON canonico. No se exportan nombres,
-- apellidos, email, telefono ni hash de usuario. El alias es una etiqueta.
SELECT jsonb_build_object('tipo','migracion','documentos',jsonb_agg(doc ORDER BY id))
FROM (
  SELECT p.id, jsonb_build_object(
    '_id',jsonb_build_object('$numberLong',p.id::text),
    'fecha',jsonb_build_object('$date',to_char(p.fecha,'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')),
    'estado',p.estado::text,
    'forma_pago',p.forma_pago::text,
    'total',jsonb_build_object('$numberDecimal',p.total::text),
    'cliente',jsonb_build_object(
      'usuario_id',jsonb_build_object('$numberLong',u.id::text),
      'alias','Cliente '||u.id::text),
    'lineas',(
      SELECT jsonb_agg(jsonb_build_object(
        'producto_id',jsonb_build_object('$numberLong',d.producto_id::text),
        'nombre_al_migrar',pr.nombre,
        'cantidad',jsonb_build_object('$numberInt',d.cantidad::text),
        'precio_unitario',jsonb_build_object('$numberDecimal',d.precio_unitario::text),
        'subtotal',jsonb_build_object('$numberDecimal',d.subtotal::text)
      ) ORDER BY d.producto_id)
      FROM public.detalle_pedido d
      JOIN public.producto pr ON pr.id=d.producto_id
      WHERE d.pedido_id=p.id)
  ) AS doc
  FROM public.pedido p
  JOIN public.usuario u ON u.id=p.usuario_id
  WHERE p.id IN (1,2,3,4,5)
) s;

-- 5b: pedidos ENTREGADO en la muestra.
SELECT jsonb_build_object('tipo','b_estado','estado','ENTREGADO',
  'cantidad',count(*),'ids',jsonb_agg(id ORDER BY id))
FROM public.pedido
WHERE id IN (1,2,3,4,5) AND estado='ENTREGADO';

-- 5c: EXISTS devuelve cada pedido una vez, aunque contenga varias lineas.
SELECT jsonb_build_object('tipo','c_producto','producto_id',1,
  'cantidad',count(*),'ids',jsonb_agg(p.id ORDER BY p.id))
FROM public.pedido p
WHERE p.id IN (1,2,3,4,5) AND EXISTS (
  SELECT 1 FROM public.detalle_pedido d
  WHERE d.pedido_id=p.id AND d.producto_id=1
);

-- Control de integridad de origen: cantidades/precios, subtotales y total.
SELECT jsonb_build_object('tipo','integridad_origen',
  'pedidos',count(*),'lineas',sum(n),
  'pedidos_total_incorrecto',count(*) FILTER(WHERE total<>suma),
  'lineas_invalidas',sum(invalidas))
FROM (
  SELECT p.id,p.total,count(*) AS n,sum(d.subtotal) AS suma,
    count(*) FILTER(WHERE d.cantidad<=0 OR d.precio_unitario<=0
      OR d.subtotal<>d.cantidad*d.precio_unitario) AS invalidas
  FROM public.pedido p
  JOIN public.detalle_pedido d ON d.pedido_id=p.id
  WHERE p.id IN (1,2,3,4,5)
  GROUP BY p.id,p.total
) s;
COMMIT;

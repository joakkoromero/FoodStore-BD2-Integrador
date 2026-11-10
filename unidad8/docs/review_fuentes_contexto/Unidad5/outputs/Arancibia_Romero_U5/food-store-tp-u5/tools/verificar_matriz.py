# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Compare real explicit business ACLs with the final Kiro matrix."""
import json
from datetime import datetime, timezone
from libpq_client import Connection, load_secrets, REPOSITORY_ROOT


def main():
    expected = set()
    def add(role, table, privilege, columns=None, schema='public'):
        for column in columns or ['<table>']:
            expected.add((role, schema, table, column, privilege, 'f'))
    for table in ('categoria', 'producto', 'pedido', 'detalle_pedido'):
        add('rol_app_lectura', table, 'SELECT')
    add('rol_app_lectura', 'usuario', 'SELECT', ['id','nombre','apellido','email','telefono','eliminado','created_at'])
    add('rol_app_escritura', 'pedido', 'INSERT', ['usuario_id','fecha','forma_pago'])
    add('rol_app_escritura', 'pedido', 'UPDATE', ['estado','forma_pago','eliminado'])
    add('rol_app_escritura', 'detalle_pedido', 'INSERT', ['pedido_id','producto_id','cantidad','precio_unitario'])
    add('rol_app_escritura', 'detalle_pedido', 'UPDATE', ['cantidad','precio_unitario'])
    add('rol_app_escritura', 'detalle_pedido', 'DELETE')
    add('rol_soporte', 'usuario', 'SELECT', ['id','nombre','apellido','email','telefono','eliminado'])
    add('rol_soporte', 'usuario', 'UPDATE', ['telefono'])
    for table in ('mv_facturacion_categoria_mes','mv_u4_ventas_categoria_dia'):
        add('rol_reportes', table, 'SELECT')
    add('rol_reportes', 'usuario_anon', 'SELECT', schema='datos_anon')
    add('rol_funciones', 'usuario', 'SELECT', ['id','email','contrasena','eliminado'])
    add('rol_funciones', 'usuario', 'UPDATE', ['contrasena'])
    add('rol_funciones', 'detalle_pedido', 'SELECT', ['pedido_id','subtotal'])
    add('rol_funciones', 'pedido', 'SELECT', ['id'])
    add('rol_funciones', 'pedido', 'UPDATE', ['total'])
    add('rol_funciones', 'mv_u4_ventas_categoria_dia', 'MAINTAIN')
    secret = load_secrets()
    with Connection(secret['bootstrap_user'], application_name='u5_exact_acl') as db:
        result = db.execute("""
WITH acl AS (
 SELECT c.relowner,n.nspname,c.relname,'<table>'::text AS columna,
        a.grantee,a.privilege_type,a.is_grantable
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 CROSS JOIN LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
 WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m','S')
 UNION ALL
 SELECT c.relowner,n.nspname,c.relname,t.attname,a.grantee,a.privilege_type,a.is_grantable
 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 JOIN pg_catalog.pg_attribute t ON t.attrelid=c.oid
 CROSS JOIN LATERAL pg_catalog.aclexplode(t.attacl) a
 WHERE n.nspname IN ('public','datos_anon') AND t.attnum>0 AND NOT t.attisdropped
)
SELECT CASE WHEN grantee=0 THEN 'PUBLIC' ELSE pg_catalog.pg_get_userbyid(grantee) END,
       nspname,relname,columna,privilege_type,is_grantable
FROM acl WHERE grantee<>relowner ORDER BY 1,2,3,4,5
""")
        actual = set(result.rows)
        memberships = set(db.execute("""
SELECT mbr.rolname,par.rolname,m.admin_option,m.inherit_option,m.set_option
FROM pg_catalog.pg_auth_members m
JOIN pg_catalog.pg_roles mbr ON mbr.oid=m.member
JOIN pg_catalog.pg_roles par ON par.oid=m.roleid
WHERE mbr.rolname IN ('app_web','admin_datos','rol_app_lectura','rol_app_escritura',
 'rol_soporte','rol_reportes','rol_propietario','rol_funciones')
""").rows)
        expected_memberships = {('app_web','rol_app_lectura','f','t','f'),
            ('app_web','rol_app_escritura','f','t','f'),('admin_datos','rol_soporte','f','t','f')}
    evidence = {'fecha_utc': datetime.now(timezone.utc).isoformat(),
        'expected_explicit_business_acl_entries': len(expected),
        'actual_explicit_business_acl_entries': len(actual),
        'missing': sorted(expected-actual), 'unexpected': sorted(actual-expected),
        'missing_memberships': sorted(expected_memberships-memberships),
        'unexpected_memberships': sorted(memberships-expected_memberships),
        'source': 'Final Kiro requirements/design plus documented Codex precision; actual catalog ACLs',
        'note': 'Owner implicit privileges excluded; column ACLs and table ACLs compared separately. No RLS isolation claimed.'}
    evidence['passed'] = not any(evidence[k] for k in ('missing','unexpected','missing_memberships','unexpected_memberships'))
    target = REPOSITORY_ROOT/'docs'/'evidencias'/'a_comparacion_exacta.json'
    target.parent.mkdir(exist_ok=True)
    target.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'exact_acl_matrix_passed': evidence['passed'], 'entries': len(actual),
                      'missing':len(evidence['missing']), 'unexpected':len(evidence['unexpected'])}))
    if not evidence['passed']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()

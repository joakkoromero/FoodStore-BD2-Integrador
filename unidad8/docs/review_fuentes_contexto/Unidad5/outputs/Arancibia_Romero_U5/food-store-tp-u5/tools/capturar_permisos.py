# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Capture the actual role, column, membership and default ACL evidence."""
from pathlib import Path
import json
import os
import subprocess

from libpq_client import Connection, load_secrets, REPOSITORY_ROOT

ROLE_NAMES=('rol_app_lectura','rol_app_escritura','rol_soporte','rol_reportes',
            'app_web','admin_datos','rol_propietario','rol_funciones')

QUERIES={
 'atributos':"""SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,
    rolreplication,rolbypassrls FROM pg_catalog.pg_roles
    WHERE rolname=ANY($1::text[]) ORDER BY rolname""",
 'tablas':"""SELECT grantor,grantee,table_schema,table_name,privilege_type,is_grantable
    FROM information_schema.role_table_grants
    WHERE grantee=ANY($1::text[]) AND table_schema IN ('public','datos_anon')
    ORDER BY grantee,table_schema,table_name,privilege_type""",
 'columnas':"""SELECT grantee,table_schema,table_name,column_name,privilege_type,is_grantable
    FROM information_schema.role_column_grants
    WHERE grantee=ANY($1::text[]) AND table_schema IN ('public','datos_anon')
    ORDER BY grantee,table_schema,table_name,column_name,privilege_type""",
 'membresias':"""SELECT member.rolname AS miembro, parent.rolname AS rol,
    m.admin_option,m.inherit_option,m.set_option
    FROM pg_catalog.pg_auth_members m
    JOIN pg_catalog.pg_roles member ON member.oid=m.member
    JOIN pg_catalog.pg_roles parent ON parent.oid=m.roleid
    WHERE member.rolname=ANY($1::text[]) ORDER BY 1,2""",
 'funciones':"""SELECT n.nspname,p.proname,pg_get_function_identity_arguments(p.oid),
    r.rolname AS propietario,p.prosecdef,p.proconfig::text,p.proacl::text
    FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    JOIN pg_catalog.pg_roles r ON r.oid=p.proowner
    WHERE n.nspname='public' ORDER BY p.proname""",
 'defaults':"""SELECT pg_catalog.pg_get_userbyid(defaclrole) AS creador,
    COALESCE(n.nspname,'<global>') AS esquema,defaclobjtype,defaclacl::text
    FROM pg_catalog.pg_default_acl d
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid=d.defaclnamespace
    ORDER BY 1,2,3""",
 'propietarios':"""SELECT n.nspname,c.relname,c.relkind,r.rolname AS propietario
    FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    JOIN pg_catalog.pg_roles r ON r.oid=c.relowner
    WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m','S')
    ORDER BY 1,2""",
 'acl_tablas_catalogo':"""SELECT n.nspname,c.relname,
    CASE WHEN a.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS beneficiario,
    a.privilege_type,a.is_grantable
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    CROSS JOIN LATERAL aclexplode(COALESCE(c.relacl,acldefault('r',c.relowner))) a
    WHERE n.nspname IN ('public','datos_anon') AND c.relkind IN ('r','p','v','m')
    ORDER BY 1,2,3,4""",
 'esquemas_efectivos':"""SELECT r.rolname,n.nspname,
    has_schema_privilege(r.oid,n.oid,'USAGE') AS puede_usar,
    has_schema_privilege(r.oid,n.oid,'CREATE') AS puede_crear
    FROM pg_roles r CROSS JOIN pg_namespace n
    WHERE r.rolname=ANY($1::text[]) AND n.nspname IN ('public','datos_anon','crypto')
    ORDER BY 1,2""",
 'base_efectivos':"""SELECT rolname,
    has_database_privilege(oid,current_database(),'CONNECT') AS puede_conectar,
    has_database_privilege(oid,current_database(),'CREATE') AS puede_crear_esquemas,
    has_database_privilege(oid,current_database(),'TEMPORARY') AS puede_crear_temporales
    FROM pg_roles WHERE rolname=ANY($1::text[]) ORDER BY 1""",
}


def main():
    private=load_secrets()
    evidence=REPOSITORY_ROOT/'docs'/'evidencias'
    evidence.mkdir(exist_ok=True)
    environment=os.environ.copy()
    for key in ('PGHOSTADDR','PGSERVICE','PGSERVICEFILE','PGOPTIONS'):
        environment.pop(key,None)
    environment['PGPASSWORD']=private['bootstrap_password']
    environment['PGCLIENTENCODING']='UTF8'
    environment['PGAPPNAME']='u5_acl_psql'
    base=[r'C:\Program Files\PostgreSQL\17\bin\psql.exe','-X',
        '--host',private['host'],'--port',str(private['port']),
        '--dbname',private['database'],'--username',private['bootstrap_user'],
        '--set','ON_ERROR_STOP=1']
    for command,filename in [('\\du','a_psql_du.txt'),('\\ddp','a_psql_ddp.txt')]:
        result=subprocess.run(base+['--command',command],env=environment,
            capture_output=True,text=True,encoding='utf-8',errors='replace',check=False)
        if result.returncode:
            raise RuntimeError('Role/default capture failed; no raw errors exported')
        (evidence/filename).write_text(result.stdout,encoding='utf-8')
    outputs={}
    with Connection(private['bootstrap_user'],application_name='u5_acl_capture') as db:
        for name,sql in QUERIES.items():
            params=['{'+','.join(ROLE_NAMES)+'}'] if '$1' in sql else None
            rows=db.execute(sql,params)
            outputs[name]={'columnas':rows.columns,'filas':rows.rows}
        timestamp=db.scalar('SELECT current_timestamp::text')
    target=evidence/'a_permisos.json'
    target.write_text(json.dumps({'fecha':timestamp,'origen':'Consultas reales PostgreSQL',
        'evidencia':outputs},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for name,content in outputs.items():
        lines=['\t'.join(content['columnas'])]
        lines += ['\t'.join('NULL' if v is None else str(v) for v in row) for row in content['filas']]
        (evidence/f'a_{name}.tsv').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    print('Captured actual roles, table/column privileges, memberships and default ACLs.')


if __name__=='__main__': main()

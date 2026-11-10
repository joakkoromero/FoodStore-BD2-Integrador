# Fuentes saneadas para revisión estática: Unidad5

No ejecutar estas copias. Los literales personales/de carga se sustituyeron por placeholders; las comprobaciones en motor usarán las fuentes originales locales. Señalar archivo/línea y distinguir errores confirmables de hipótesis.

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\capturar_permisos.py

SHA256 original: f7836ae8c389dfc0a0b596da333f3551985a537f577cca64319ff5cc404f1e52
SHA256 saneado: ac9424b927c142bdcd8d399cfd4cd0bd3201444850d360b078b796ac850db4a2

`````py
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

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\crear_cuenta_prueba.py

SHA256 original: 30c4d0c5724830691c0b8bdd6b14b5dcf0d99ec268f8e8620beb2546b537e664
SHA256 saneado: 7ea96340b8e774165167d49bff33a0b73b492c88113254420c4e1463ce48584b

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Add one synthetic business account without changing inherited user records.

Run only during private bootstrap (log_statement=none, error statements=panic).
Secrets are bound parameters. No password/hash or personal row is printed.
"""
from pathlib import Path
import json

from libpq_client import Connection, load_secrets


def main():
    secret = load_secrets()
    with Connection(secret["bootstrap_user"], application_name="u5_setup_fixture") as db:
        if db.scalar("SHOW log_statement") != "none":
            raise RuntimeError("Create the account before enabling statement logging")
        db.execute("BEGIN")
        try:
            db.execute("CREATE SCHEMA IF NOT EXISTS crypto")
            db.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA crypto")
            existing = db.scalar("SELECT id FROM public.usuario WHERE email=$1::text", [secret["business_email"]])
            if existing is not None:
                raise RuntimeError("Synthetic account already exists; refusing to change it")
            old_count = db.scalar("SELECT count(*) FROM public.usuario")
            old_hash = db.scalar("SELECT md5(string_agg(row_to_json(u)::text,'|' ORDER BY id)) FROM public.usuario u")
            added = db.scalar("""INSERT INTO public.usuario
                (nombre,apellido,email,contrasena,telefono,created_at)
                VALUES ('Cuenta','Laboratorio',$1::text,
                    crypto.crypt($2::text,crypto.gen_salt('bf',10)),NULL,current_timestamp)
                RETURNING id""", [secret["business_email"], secret["business_password"]])
            unchanged = db.scalar("""SELECT md5(string_agg(row_to_json(u)::text,'|' ORDER BY id))
                FROM public.usuario u WHERE id <> $1::bigint""", [added])
            if old_hash != unchanged:
                raise RuntimeError("Inherited-user fingerprint changed")
            db.execute("COMMIT")
        except Exception:
            db.execute("ROLLBACK")
            raise
    evidence = {"usuarios_heredados":int(old_count),"cuentas_sinteticas_agregadas":1,
                "usuarios_totales":int(old_count)+1,"huella_heredada_antes":old_hash,
                "huella_heredada_despues":unchanged,"conservacion_verificada":old_hash==unchanged,
                "clave": "Aleatoria y privada; no incluida en esta evidencia"}
    target = Path(__file__).resolve().parents[1]/"docs"/"continuidad_verificada.json"
    target.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print("Synthetic account created; inherited-user fingerprint unchanged.")


if __name__ == "__main__":
    main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\ejecutar_anonimizacion.py

SHA256 original: f3673a1526c29ee348b5af191d7beb9230c44817ccb8ee3754119bf9c2adfe36
SHA256 saneado: 32e309c32bb073189dc328693adca0454be6b0eaf883936c00765ff1660148c8

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Execute and capture Part D; exported evidence contains aggregates only."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

from libpq_client import Connection, load_secrets

ROOT=Path(__file__).resolve().parents[1]
GROUP_REAL="""SELECT date_trunc('month',created_at AT TIME ZONE
 'America/Argentina/Buenos_Aires')::date AS mes_alta,eliminado,count(*) AS cantidad
 FROM public.usuario GROUP BY 1,2"""
GROUP_ANON="""SELECT mes_alta,eliminado,count(*) AS cantidad
 FROM datos_anon.usuario_anon GROUP BY 1,2"""


def effective_sql(source: str, *, bootstrap: bool) -> str:
    """Adapt only the unique creator line for explicit pre-A preparation."""
    creator_line=re.compile(r'^[ \t]*SET[ \t]+LOCAL[ \t]+ROLE[ \t]+rol_propietario;[ \t]*\r?$',
                            re.MULTILINE | re.IGNORECASE)
    if len(creator_line.findall(source))!=1:
        raise RuntimeError('Part D SQL must contain one unambiguous creator line')
    if bootstrap:
        return creator_line.sub('CREATE SCHEMA IF NOT EXISTS datos_anon;',source,count=1)
    return source


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bootstrap',action='store_true',
        help='Explicit pre-A mode: create the anonymous schema as bootstrap instead of SET LOCAL ROLE')
    args=parser.parse_args()
    secret=load_secrets()
    sql=ROOT/'sql'/'usuario_anon.sql'
    if not sql.is_file(): raise RuntimeError('Part D SQL is missing')
    source_bytes=sql.read_bytes()
    sqltext=effective_sql(source_bytes.decode('utf-8-sig'),bootstrap=args.bootstrap).encode('utf-8')
    environment=os.environ.copy()
    for key in ('PGHOSTADDR','PGSERVICE','PGSERVICEFILE','PGOPTIONS'):
        environment.pop(key,None)
    environment['PGPASSWORD']=secret['bootstrap_password']
    environment['PGCLIENTENCODING']='UTF8'
    environment['PGAPPNAME']='u5_anonymize_psql'
    command=[r'C:\Program Files\PostgreSQL\17\bin\psql.exe','-X',
        '--host',secret['host'],'--port',str(secret['port']),
        '--dbname',secret['database'],'--username',secret['bootstrap_user'],
        '--set','ON_ERROR_STOP=1','--file','-']
    # A byte payload preserves the exact effective SQL whose SHA-256 is
    # recorded, without Windows text-pipe newline conversion or a temp SQL file.
    completed=subprocess.run(command,env=environment,capture_output=True,
        input=sqltext,shell=False,check=False)
    # No raw errors are exported or printed. The SQL deliberately selects
    # only aggregates; the captured stdout is an actual psql execution.
    if completed.returncode:
        raise RuntimeError('Part D SQL failed; no evidence of success was generated')
    (ROOT/'docs'/'d_ejecucion_psql.txt').write_bytes(completed.stdout)
    with Connection(secret['bootstrap_user'],host=secret['host'],port=secret['port'],
                    dbname=secret['database'],application_name='u5_equivalencia') as db:
        db.execute('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ')
        real=db.execute(GROUP_REAL+' ORDER BY 1,2')
        anon=db.execute(GROUP_ANON+' ORDER BY 1,2')
        diffs=db.execute('WITH origen AS ('+GROUP_REAL+'), copia AS ('+GROUP_ANON+''')
          SELECT 'origen_menos_copia' AS sentido,count(*) AS diferencias FROM
            (TABLE origen EXCEPT ALL TABLE copia) x
          UNION ALL
          SELECT 'copia_menos_origen',count(*) FROM
            (TABLE copia EXCEPT ALL TABLE origen) x''')
        before_hash=json.loads((ROOT/'docs'/'continuidad_verificada.json').read_text(encoding='utf-8'))['huella_heredada_antes']
        now_hash=db.scalar("SELECT md5(string_agg(row_to_json(u)::text,'|' ORDER BY id)) FROM public.usuario u WHERE id<=20000")
        timestamp=db.scalar('SELECT current_timestamp::text')
        counts=[int(db.scalar('SELECT count(*) FROM '+name)) for name in ('public.usuario','datos_anon.usuario_anon')]
        columns=db.execute("SELECT column_name FROM information_schema.columns WHERE table_schema='datos_anon' AND table_name='usuario_anon' ORDER BY ordinal_position").rows
        table_owner=db.scalar("SELECT pg_catalog.pg_get_userbyid(relowner) FROM pg_catalog.pg_class WHERE oid='datos_anon.usuario_anon'::regclass")
        reports_exist=db.scalar("SELECT EXISTS(SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='rol_reportes')")=='t'
        reports_select=(db.scalar("SELECT pg_catalog.has_table_privilege('rol_reportes','datos_anon.usuario_anon','SELECT')")=='t'
                        if reports_exist else None)
        db.execute('COMMIT')
    if real.rows!=anon.rows or any(int(row[1])!=0 for row in diffs.rows) or now_hash!=before_hash:
        raise RuntimeError('Part D equivalence/conservation gate failed')
    expected_owner=secret['bootstrap_user'] if args.bootstrap else 'rol_propietario'
    if table_owner!=expected_owner or (not args.bootstrap and reports_select is not True):
        raise RuntimeError('Part D creator/reporting privilege gate failed')
    evidence={'fecha':timestamp,'columnas_agregadas':real.columns,
        'resultado_real':real.rows,'resultado_anon':anon.rows,
        'diferencias_except_all':diffs.rows,'conteos':counts,
        'columnas_copia':[x[0] for x in columns],
        'usuarios_heredados_intactos':now_hash==before_hash,
        'equivalencia_verificada':True,'sql_ejecutado_realmente':True,
        'modo_ejecucion':'bootstrap' if args.bootstrap else 'propietario',
        'sql_fuente_sha256':hashlib.sha256(source_bytes).hexdigest(),
        'sql_efectivo_sha256':hashlib.sha256(sqltext).hexdigest(),
        'propietario_tabla':table_owner,'rol_reportes_existe':reports_exist,
        'rol_reportes_select':reports_select}
    (ROOT/'docs'/'d_equivalencia.json').write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    rows=['| Mes local de alta | Eliminado | Usuario real | Usuario anon | Coincide |',
          '|---|---|---:|---:|---|']
    for left,right in zip(real.rows,anon.rows):
        rows.append(f'| {left[0]} | {left[1]} | {left[2]} | {right[2]} | Sí |')
    (ROOT/'docs'/'d_resultados_lado_a_lado.md').write_text('\n'.join(rows)+'\n',encoding='utf-8')
    print(f'Part D verified: {counts[0]} users; {len(real.rows)} groups; differences 0/0.')


if __name__=='__main__': main()

`````


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

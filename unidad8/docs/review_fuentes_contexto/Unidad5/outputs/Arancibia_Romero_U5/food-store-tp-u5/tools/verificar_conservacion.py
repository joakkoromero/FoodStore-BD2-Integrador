# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Compare complete inherited business tables without exporting their rows."""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
from pathlib import Path

from libpq_client import Connection, load_secrets, REPOSITORY_ROOT

TABLES = {'categoria': 'id', 'producto': 'id', 'usuario': 'id',
          'pedido': 'id', 'detalle_pedido': 'pedido_id,producto_id'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('before', 'after'), required=True)
    parser.add_argument('--evidence-dir', type=Path,
                        help='Fresh evidence directory for an independent reproduction')
    args = parser.parse_args()
    secret = load_secrets()
    directory = args.evidence_dir or REPOSITORY_ROOT/'docs'/'evidencias'
    target = directory/('conservacion_'+args.phase+'.json')
    if target.exists():
        raise RuntimeError('Existing conservation evidence must not be overwritten')
    evidence = {'phase': args.phase, 'started_at_utc': datetime.now(timezone.utc).isoformat(),
                'method': 'count plus MD5 of ordered, complete row JSON digests; no source rows exported',
                'tables': {}}
    with Connection(secret['bootstrap_user'], application_name='u5_conservation') as db:
        db.execute('BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY')
        db.execute("SET LOCAL TimeZone='America/Argentina/Buenos_Aires'")
        db.execute("SET LOCAL DateStyle='ISO,YMD'")
        for table, order in TABLES.items():
            # Table and column names are fixed above, never supplied by the user.
            row = db.execute('SELECT count(*)::text, pg_catalog.md5('
                "pg_catalog.string_agg(pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY "
                +order+')) FROM public.'+table+' AS t').rows[0]
            evidence['tables'][table] = {'rows': int(row[0]), 'ordered_complete_row_md5': row[1]}
        db.execute('COMMIT')
    if args.phase == 'after':
        before = json.loads(target.with_name('conservacion_before.json').read_text(encoding='utf-8'))
        evidence['same_as_before'] = evidence['tables'] == before['tables']
        if not evidence['same_as_before']:
            raise RuntimeError('Business content changed; stop and investigate before packaging')
    evidence['finished_at_utc'] = datetime.now(timezone.utc).isoformat()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(evidence, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'phase': args.phase, 'tables_checked': len(TABLES),
                      'same_as_before': evidence.get('same_as_before'), 'source_rows_exported': False}))


if __name__ == '__main__':
    main()

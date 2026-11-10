# Fuentes saneadas para revisión estática: Unidad5

No ejecutar estas copias. Los literales personales/de carga se sustituyeron por placeholders; las comprobaciones en motor usarán las fuentes originales locales. Señalar archivo/línea y distinguir errores confirmables de hipótesis.

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\empaquetar_entrega.py

SHA256 original: f2fcbf7535573d07868bc0155510d1d6928326fcc3a0bab96cef8e834bdd375b
SHA256 saneado: 8136677d5b0fde0e68a1850116dc43b48c32b82c1b4fb63a143d9af462316480

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Package the deliverable and its complete Git history, then verify the ZIP.

Run --dry-run before delivery. No database or network connection is made.
The manifest covers every archived file except the manifest itself.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
PREFIX = 'food-store-tp-u5'
MANIFEST = PREFIX + '/MANIFIESTO_ENTREGA.json'
REQUIRED = (
    'sql/roles.sql', 'sql/auditoria_test.sql', 'sql/simulacro_incidente.sql',
    'sql/usuario_anon.sql', 'docs/kiro_roles_spec/requirements.md',
    'docs/kiro_roles_spec/design.md', 'docs/informe_auditoria.md',
    'docs/informe_roles.md', 'docs/continuidad_y_alcance.md',
    'docs/evidencias/a_psql_du.txt', 'docs/evidencias/a_tablas.tsv',
    'docs/evidencias/a_columnas.tsv', 'docs/evidencias/a_permisos.json',
    'docs/log_auditoria_prueba.txt', 'docs/log_simulacro_anonimizado.txt',
    'docs/informe_incidente.md', 'docs/verificacion_equivalencia.md',
    'docs/ia/c_reconstruccion_prompt.txt', 'docs/ia/c_reconstruccion_respuesta.md',
    'docs/ia/c_reconstruccion_metadatos.json',
    'BITACORA.md', 'README.md', 'docs/TP_U5_FoodStore_Arancibia_Romero.pdf',
)
EXCLUDED_PARTS = {
    '__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache', '.cache',
    '.venv', 'venv', 'node_modules', 'private', 'privado', 'privados',
    'runtime', 'logs_privados', '.opencode',
}
EXCLUDED_SUFFIXES = {'.pyc', '.pyo', '.dump', '.raw', '.pem', '.key', '.p12', '.pfx'}
SECRET_PATTERNS = (
    rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    rb'\b(?:sk-proj-|sk-)[A-Za-z0-9_-]{24,}\b',
    rb'\b(?:ghp_|gho_|ghs_|github_pat_)[A-Za-z0-9_]{24,}\b',
    rb'\bAKIA[0-9A-Z]{16}\b',
    rb'(?i)\b(?:postgres(?:ql)?|https?)://[^\s/:]+:[^\s/@]+@',
    rb'(?im)^\s*(?:PGPASSWORD|OPENAI_API_KEY|ANTHROPIC_API_KEY|AWS_SECRET_ACCESS_KEY)\s*=\s*["\']?[^\s"\'<>]{8,}',
    rb'(?i)SCRAM-SHA-256\$[0-9]+:[A-Za-z0-9+/=]+\$',
)


def git(*arguments, data=None, repo=None, allowed=(0,)):
    env = os.environ.copy()
    env['GIT_OPTIONAL_LOCKS'] = '0'
    result = subprocess.run(['git', '-C', str(repo or ROOT), *arguments], input=data,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, check=False)
    if result.returncode not in allowed:
        # Keep diagnostics free of file content, credentials and remote URLs.
        raise RuntimeError('Git verification failed: ' + arguments[0])
    return result.stdout


def excluded_name(name):
    parts = PurePosixPath(name).parts
    folded = [part.casefold() for part in parts]
    if any(part in EXCLUDED_PARTS for part in folded): return True
    basename = folded[-1] if folded else ''
    return (basename == '.env' or basename.startswith('.env.')
            or 'secret' in basename or basename in ('.pgpass', 'pgpass.conf')
            or Path(basename).suffix in EXCLUDED_SUFFIXES
            or basename.endswith(('.zip', '.partial')))


def scan_content(data, label):
    if any(re.search(pattern, data) for pattern in SECRET_PATTERNS):
        raise RuntimeError('Potential credential detected; review locally: ' + label)


def check_git_history():
    """Scan decoded objects, including unreachable objects shipped in .git."""
    listing = git('cat-file', '--batch-all-objects',
                  '--batch-check=%(objectname) %(objecttype) %(objectsize)')
    objects = []
    for row in listing.decode('ascii').splitlines():
        oid, kind, size = row.split()
        if int(size) > 50_000_000:
            raise RuntimeError('Git object exceeds the delivery review limit')
        objects.append(oid)
    raw = git('cat-file', '--batch', data=('\n'.join(objects)+'\n').encode('ascii'))
    offset = 0
    for oid in objects:
        end = raw.index(b'\n', offset)
        header = raw[offset:end].split()
        if len(header) != 3 or header[0].decode('ascii') != oid:
            raise RuntimeError('Unexpected Git object stream')
        size = int(header[2]);start = end+1
        scan_content(raw[start:start+size], 'Git object ' + oid[:12])
        offset = start+size+1
    # A formerly committed private file would also be shipped in Git history.
    for row in git('rev-list', '--objects', '--all').decode('utf-8', 'replace').splitlines():
        if ' ' in row and excluded_name(row.split(' ', 1)[1]):
            raise RuntimeError('Excluded material is present in Git history; review locally')
    return len(objects)


def inventory():
    git_dir = ROOT / '.git'
    if not git_dir.is_dir() or git_dir.is_symlink():
        raise RuntimeError('Delivery requires a standalone repository with a .git directory')
    if (git_dir/'shallow').exists() or (git_dir/'objects/info/alternates').exists():
        raise RuntimeError('Git history depends on incomplete or external objects')
    git('fsck', '--full')
    work = set(git('ls-files', '--cached', '--others', '--exclude-standard', '-z')
               .decode('utf-8').split('\0')) - {''}
    encoded = ('\0'.join(sorted(work))+'\0').encode('utf-8')
    ignored = set(git('check-ignore', '--no-index', '--stdin', '-z', data=encoded,
                      allowed=(0, 1)).decode('utf-8').split('\0')) - {''}
    names = {name for name in work-ignored if not excluded_name(name)}
    for path in git_dir.rglob('*'):
        relative = path.relative_to(ROOT).as_posix()
        if path.is_symlink(): raise RuntimeError('Symlink found in Git metadata')
        if path.name.endswith('.lock'):
            raise RuntimeError('Git operation is active; package after it finishes')
        # Hooks are executable local settings, not project history.
        if path.is_file() and not relative.startswith('.git/hooks/'):
            names.add(relative)
    if 'MANIFIESTO_ENTREGA.json' in names:
        raise RuntimeError('The manifest must be generated only inside the archive')
    for name in sorted(names):
        path = ROOT / name
        if path.is_symlink() or not path.is_file():
            raise RuntimeError('A delivery entry is missing or is a symlink: ' + name)
        if not path.resolve().is_relative_to(ROOT.resolve()):
            raise RuntimeError('Delivery entry is outside the repository')
    return sorted(names)


def verify_archive(path, expected_head=None):
    with ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)): raise RuntimeError('Duplicate archive entries')
        if sum(info.file_size for info in archive.infolist()) > 250_000_000:
            raise RuntimeError('Archive exceeds the delivery review limit')
        for name in names:
            parts = PurePosixPath(name).parts
            if (not parts or parts[0] != PREFIX or '..' in parts
                    or '\\' in name or name.startswith('/')
                    or any(':' in part or part.endswith((' ', '.')) for part in parts)):
                raise RuntimeError('Unsafe archive member')
        if archive.testzip() is not None: raise RuntimeError('ZIP CRC verification failed')
        manifest = json.loads(archive.read(MANIFEST))
        expected = {PREFIX+'/'+entry['path']: entry for entry in manifest['files']}
        if set(names) != set(expected) | {MANIFEST}:
            raise RuntimeError('Archive content does not match the manifest')
        for name, entry in expected.items():
            data = archive.read(name)
            if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
                raise RuntimeError('Archive SHA-256 verification failed: ' + name)
        if expected_head and manifest['git_head'] != expected_head:
            raise RuntimeError('Archive HEAD differs from the reviewed repository')
        # Extract only after names and every byte have been verified. This does
        # not execute project code or hooks and does not contact a remote.
        with tempfile.TemporaryDirectory(prefix='foodstore-verify-',dir=path.resolve().parent) as temporary:
            archive.extractall(temporary)
            restored = Path(temporary) / PREFIX
            git('fsck', '--full', repo=restored)
            head = git('rev-parse', 'HEAD', repo=restored).decode().strip()
            count = int(git('rev-list', '--all', '--count', repo=restored).decode())
            if head != manifest['git_head'] or count != manifest['git_commit_count']:
                raise RuntimeError('Restored Git history differs from the manifest')
    return {'files': len(expected), 'git_head': head, 'git_commit_count': count,
            'manifest_hashes_verified': True, 'restored_git_verified': True}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path,
                        default=ROOT.parent/'Arancibia_Romero_TP_U5_repositorio.zip')
    parser.add_argument('--dry-run', action='store_true', help='Check inputs without writing a ZIP')
    parser.add_argument('--verify', type=Path, help='Verify an existing archive without creating one')
    args = parser.parse_args(argv)
    if args.verify:
        print(json.dumps(verify_archive(args.verify), ensure_ascii=False, indent=2));return
    names = inventory()
    missing = [name for name in REQUIRED if name not in names]
    dirty = bool(git('status', '--porcelain', '--untracked-files=all').strip())
    objects = check_git_history()
    entries = []
    for name in names:
        data = (ROOT/name).read_bytes()
        if not name.startswith('.git/objects/'):
            scan_content(data, name)
        entries.append({'path': name, 'bytes': len(data),
                        'sha256': hashlib.sha256(data).hexdigest()})
    head = git('rev-parse', 'HEAD').decode().strip()
    count = int(git('rev-list', '--all', '--count').decode())
    if args.dry_run:
        print(json.dumps({'dry_run': True, 'archive_created': False,
                          'files_selected': len(entries), 'git_objects_reviewed': objects,
                          'git_commit_count': count, 'clean_worktree': not dirty,
                          'missing_required': missing,
                          'ready': not missing and not dirty}, ensure_ascii=False, indent=2))
        return
    if missing: raise RuntimeError('Required deliverables are missing: ' + ', '.join(missing))
    if dirty: raise RuntimeError('Commit the completed deliverables before packaging')
    target = args.output.resolve()
    if target.is_relative_to(ROOT.resolve()):
        raise RuntimeError('Write the archive outside the repository')
    if target.exists(): raise FileExistsError('Output already exists; choose a new output name')
    target.parent.mkdir(parents=True, exist_ok=True)
    manifest = {'format_version': 1, 'repository': PREFIX,
                'created_utc': datetime.now(timezone.utc).isoformat(),
                'git_head': head, 'git_commit_count': count,
                'git_objects_reviewed': objects,
                'exclusions': ['Git-ignored files (including tracked ignored paths)',
                               'Private material and caches', '.git/hooks', 'ZIP outputs'],
                'credential_check': 'Known credential patterns in files and all decoded Git objects',
                'files': entries}
    handle, temporary = tempfile.mkstemp(prefix=target.stem+'-', suffix='.partial', dir=target.parent)
    os.close(handle);temporary = Path(temporary)
    try:
        with ZipFile(temporary, 'w', ZIP_DEFLATED, compresslevel=9) as archive:
            for entry in entries:
                archive.write(ROOT/entry['path'], PREFIX+'/'+entry['path'])
            archive.writestr(MANIFEST, json.dumps(manifest, ensure_ascii=False, indent=2)+'\n')
        verification = verify_archive(temporary, head)
        temporary.rename(target)
    finally:
        if temporary.exists(): temporary.unlink()
    print(json.dumps({'output': str(target), 'sha256': hashlib.sha256(target.read_bytes()).hexdigest(),
                      **verification}, ensure_ascii=False, indent=2))


if __name__ == '__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\generar_informe_pdf.py

SHA256 original: f5250335e88650fb234aa0f723d8c8d1ca0c2508a9fc0eb10335f064c82102e0
SHA256 saneado: 4dbc172245ef001484bbbe4dc6ab5a88225acab8bbb5d92e33b79dc785bba336

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Render the verified Markdown reports as a complementary, readable PDF.

SQL sources, complete AI transcripts, Git history and machine evidence remain
in the repository. This document does not replace those reproducible sources.
"""
from __future__ import annotations

import argparse
import re
import textwrap
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak,
    Preformatted,
)

ROOT = Path(__file__).resolve().parents[1]
BLUE = colors.HexColor('#153956')
TEAL = colors.HexColor('#087F8C')
PALE = colors.HexColor('#EDF4F7')
INK = colors.HexColor('#243443')
WIDTH = A4[0]-100


def table_cells(line):
    """Split a Markdown row without treating escaped/code pipes as borders."""
    line=line.strip()
    if line.startswith('|'): line=line[1:]
    if line.endswith('|') and not line.endswith('\\|'): line=line[:-1]
    cells=[];current=[];in_code=False;i=0
    while i<len(line):
        char=line[i]
        if char=='\\' and i+1<len(line) and line[i+1]=='|':
            current.append('|');i+=2;continue
        if char=='`': in_code=not in_code
        if char=='|' and not in_code:
            cells.append(''.join(current).strip());current=[]
        else: current.append(char)
        i+=1
    cells.append(''.join(current).strip())
    return cells


def starts_block(line):
    line=line.lstrip()
    return (line.startswith(('#','|','```','~~~','- ','* '))
            or bool(re.match(r'^\d+[.)]\s+',line))
            or line in ('---','***'))


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,
                        help='Explicit PDF destination for review or final delivery')
    args=parser.parse_args(argv)
    for name, filename in [('Arial','arial.ttf'),('ArialBold','arialbd.ttf'),
                           ('Consolas','consola.ttf')]:
        pdfmetrics.registerFont(TTFont(name, 'C:/Windows/Fonts/'+filename))
    pdfmetrics.registerFontFamily('Arial',normal='Arial',bold='ArialBold')
    styles = {
        'title': ParagraphStyle('title',fontName='ArialBold',fontSize=26,leading=31,textColor=BLUE,spaceAfter=18),
        'h1': ParagraphStyle('h1',fontName='ArialBold',fontSize=17,leading=21,textColor=BLUE,spaceAfter=12,keepWithNext=True),
        'h2': ParagraphStyle('h2',fontName='ArialBold',fontSize=12,leading=16,textColor=TEAL,spaceBefore=12,spaceAfter=7,keepWithNext=True),
        'body': ParagraphStyle('body',fontName='Arial',fontSize=10,leading=14.1,textColor=INK,spaceAfter=8,splitLongWords=True),
        'small': ParagraphStyle('small',fontName='Arial',fontSize=8.1,leading=10.8,textColor=INK,spaceAfter=5),
        'cell': ParagraphStyle('cell',fontName='Arial',fontSize=8.4,leading=11,textColor=INK,splitLongWords=True),
        'headcell': ParagraphStyle('headcell',fontName='ArialBold',fontSize=8.4,leading=11,textColor=colors.white,splitLongWords=True),
        'code': ParagraphStyle('code',fontName='Consolas',fontSize=8,leading=10.6,textColor=INK,spaceAfter=0),
    }
    story=[]

    def markup(value):
        value=escape(value)
        value=re.sub(r'\[([^\]]+)\]\(([^)]+)\)',r'\1 (\2)',value)
        value=re.sub(r'\*\*([^*]+)\*\*',r'<b>\1</b>',value)
        value=re.sub(r'`([^`]+)`',r'<font name="Consolas">\1</font>',value)
        return value

    def paragraph(value,sty='body'):
        story.append(Paragraph(markup(value),styles[sty]))

    def code(lines):
        wrapped=[]
        for line in lines:
            wrapped.extend(textwrap.wrap(line,width=100,replace_whitespace=False,
                           break_long_words=True,break_on_hyphens=False,subsequent_indent='  ') or [''])
        # Individual lines let the page engine split long SQL/log blocks.
        for line in wrapped:
            story.append(Preformatted(line,styles['code']))
        story.append(Spacer(1,8))

    def table(rows):
        cells=[[Paragraph(markup(x),styles['headcell' if i==0 else 'cell'])
                for x in row] for i,row in enumerate(rows)]
        n=len(cells[0])
        widths=[WIDTH/n]*n
        if n==3: widths=[WIDTH*.29,WIDTH*.31,WIDTH*.40]
        t=Table(cells,colWidths=widths,repeatRows=1,hAlign='LEFT',splitInRow=0)
        t.setStyle(TableStyle([
            ('BACKGROUND',(0,0),(-1,0),BLUE),('VALIGN',(0,0),(-1,-1),'TOP'),
            ('ROWBACKGROUNDS',(0,1),(-1,-1),[colors.white,PALE]),
            ('LEFTPADDING',(0,0),(-1,-1),7),('RIGHTPADDING',(0,0),(-1,-1),7),
            ('TOPPADDING',(0,0),(-1,-1),6),('BOTTOMPADDING',(0,0),(-1,-1),6),
            ('LINEBELOW',(0,0),(-1,0),.5,TEAL),
        ]))
        story.extend([t,Spacer(1,9)])

    def markdown(path):
        lines=path.read_text(encoding='utf-8-sig').splitlines()
        i=0
        while i<len(lines):
            line=lines[i].strip()
            if not line:
                i+=1;continue
            fence=re.match(r'^(`{3,}|~{3,})',line)
            if fence:
                delimiter=fence.group(1);block=[];i+=1
                close=re.compile(r'^'+re.escape(delimiter[0])+'{'+str(len(delimiter))+r',}\s*$')
                while i<len(lines) and not close.fullmatch(lines[i].strip()):
                    block.append(lines[i]);i+=1
                if i==len(lines):
                    raise ValueError(f'Unclosed code fence in {path}')
                code(block);i+=1;continue
            if line.startswith('|'):
                rows=[]
                while i<len(lines) and lines[i].strip().startswith('|'):
                    cells=table_cells(lines[i])
                    if not all(re.fullmatch(r':?-{3,}:?',x) for x in cells): rows.append(cells)
                    i+=1
                if rows and len({len(row) for row in rows})==1: table(rows)
                else:
                    for row in rows: paragraph(' / '.join(row),'small')
                continue
            if line.startswith('#'):
                level=len(line)-len(line.lstrip('#'))
                paragraph(line.lstrip('#').strip(),'h1' if level==1 else 'h2')
                i+=1;continue
            if line.startswith(('- ','* ')) or re.match(r'^\d+[.)]\s+',line):
                paragraph(line);i+=1;continue
            if line in ('---','***'):
                i+=1;continue
            block=[line];i+=1
            while i<len(lines) and lines[i].strip() and not starts_block(lines[i]):
                block.append(lines[i].strip());i+=1
            paragraph(' '.join(block))

    paragraph('TECNICATURA UNIVERSITARIA EN PROGRAMACIÓN','small')
    story.append(Spacer(1,25))
    paragraph('Administración y seguridad de Food Store','title')
    paragraph('Trabajo práctico - Unidad 5 | Base de Datos II','h2')
    paragraph('Exequiel Arancibia · Joaquin Romero')
    paragraph('Ciclo lectivo 2026 · PostgreSQL 17.11')
    story.append(Spacer(1,16))
    paragraph('Roles, auditoría, reconstrucción de incidentes y protección de datos personales. Resolución sobre la base acumulada de los TP1 a TP5 y la Unidad 4.')
    paragraph('Este informe acompaña al repositorio entregado como ZIP. Allí se incluyen SQL, herramientas, respuestas completas de IA, resultados de ejecución e historial Git. Las credenciales y los logs originales se conservan fuera del repositorio.')
    sections=[
        ('Continuidad con los trabajos anteriores','docs/continuidad_y_alcance.md'),
        ('Parte A - Especificación y permisos','docs/informe_roles.md'),
        ('Parte B - Auditoría','docs/informe_auditoria.md'),
        ('Parte C - Simulacro e interpretación','docs/informe_incidente.md'),
        ('Parte D - Anonimización y equivalencia','docs/verificacion_equivalencia.md'),
        ('Parte E - Bitácora de IA','BITACORA.md'),
        ('Conformidad de cierre','docs/validacion_humana.md'),
        ('Ejecución y archivos de entrega','README.md'),
    ]
    for title,filename in sections:
        path=ROOT/filename
        if not path.is_file(): raise FileNotFoundError(f'Required report missing: {filename}')
        story.append(PageBreak())
        paragraph(title,'small')
        markdown(path)

    def footer(canvas,doc):
        canvas.saveState()
        canvas.setStrokeColor(colors.HexColor('#D3E0E7'))
        canvas.line(50,43,A4[0]-50,43)
        canvas.setFont('Arial',8)
        canvas.setFillColor(INK)
        canvas.drawString(50,29,'Food Store · Unidad 5 · Arancibia / Romero')
        canvas.drawRightString(A4[0]-50,29,str(doc.page))
        canvas.restoreState()

    target=args.output or ROOT/'docs'/'TP_U5_FoodStore_Arancibia_Romero.pdf'
    target=target.resolve()
    target.parent.mkdir(parents=True,exist_ok=True)
    SimpleDocTemplate(str(target),pagesize=A4,rightMargin=50,leftMargin=50,
        topMargin=48,bottomMargin=57,title='TP Unidad 5 - Food Store',
        author='Exequiel Arancibia; Joaquin Romero').build(story,onFirstPage=footer,onLaterPages=footer)
    print(target)


if __name__=='__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\instalar_seguridad.py

SHA256 original: 6aa6c76a273693740a8dd5d9f79f6dd363d6999b51ba2640e67ffce1ae1dca3b
SHA256 saneado: 35dff13d7f32e442b7e390b18f4cd684f307b6ad2aa5e51f3feee4f24e07e82f

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Apply the planned role SQL without publishing database login passwords.

Requires the actual Kiro requirements/design and a completed roles.sql.
Run during private bootstrap, then enable the audit configuration separately.
"""
from pathlib import Path

from libpq_client import Connection, load_secrets, password_for_role

ROOT=Path(__file__).resolve().parents[1]


def main():
    required=[ROOT/'docs/kiro_roles_spec'/name for name in ('requirements.md','design.md')]
    required.append(ROOT/'sql/roles.sql')
    if not all(path.is_file() for path in required):
        raise RuntimeError('Actual Kiro specification and role SQL are required before installation')
    secret=load_secrets()
    with Connection(secret['bootstrap_user'],application_name='u5_security_install') as db:
        if db.scalar('SHOW log_statement')!='none' or db.scalar('SHOW log_min_error_statement')!='panic':
            raise RuntimeError('Install during private bootstrap before statement/error-statement logging')
        # Avoid SQL context output in the unlikely event password setup fails.
        # No errors are printed by this client. Reconnect before auditing.
        db.execute("SET log_error_verbosity='terse'")
        db.execute((ROOT/'sql/roles.sql').read_text(encoding='utf-8-sig'))
        db.execute('BEGIN')
        try:
            db.execute("SELECT pg_catalog.set_config('u5.app_password',$1::text,true)",[password_for_role('app_web',secret)])
            db.execute("SELECT pg_catalog.set_config('u5.admin_password',$1::text,true)",[password_for_role('admin_datos',secret)])
            db.execute("""DO $private_setup$
            BEGIN
              EXECUTE pg_catalog.format('ALTER ROLE app_web PASSWORD %L',
                  pg_catalog.current_setting('u5.app_password'));
              EXECUTE pg_catalog.format('ALTER ROLE admin_datos PASSWORD %L',
                  pg_catalog.current_setting('u5.admin_password'));
            END
            $private_setup$""")
            db.execute('COMMIT')
        except Exception:
            db.execute('ROLLBACK')
            raise
    print('Role SQL applied; random login passwords remain private. Enable audit next.')


if __name__=='__main__': main()

`````

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\libpq_client.py

SHA256 original: 750c981c5d49303301e9a08566daede5f667fdc5afebc0f570013a52e20bd2ef
SHA256 saneado: b2c36289f9f3063bcc17d6bf20cf2f962e90a1dd6896344d5c635827358aa97f

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Small libpq client for the isolated Food Store U5 laboratory.

Importing this module opens no connection. Bind authentication/reset secrets as
parameters: execute(sql, params=[...]) uses PQexecParams, not SQL interpolation.
No query text, parameter value, raw server error, or result row is printed.
"""

from __future__ import annotations

import ctypes
from datetime import date, datetime
import json
import os
from pathlib import Path
import re
from typing import NamedTuple, Sequence


LIBPQ_PATH = Path(r"C:\Program Files\PostgreSQL\17\bin\libpq.dll")
REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 55605
DEFAULT_DATABASE = "foodstore_u5_arancibia_romero"


class ConfigurationError(RuntimeError):
    """Invalid local configuration; messages never include secret values."""


class DatabaseError(RuntimeError):
    """Sanitized database failure. SQLSTATE is observed, never guessed."""

    def __init__(self, *, operation: str, sqlstate: str | None = None,
                 status: str = "UNKNOWN", classification: str = "database_error"):
        self.operation = operation
        self.sqlstate = sqlstate
        self.status = status
        self.classification = classification
        super().__init__(
            f"Database operation failed: operation={operation}; "
            f"status={status}; sqlstate={sqlstate or 'unavailable'}; "
            f"classification={classification}"
        )


class ConnectionFailure(DatabaseError):
    """Connection/handshake failed; no PGresult SQLSTATE is available."""


class QueryResult(NamedTuple):
    columns: list[str]
    rows: list[tuple[str | None, ...]]
    status: str
    sqlstate: str | None

    def __repr__(self) -> str:
        # An accidental print(result) must not dump all usuario records.
        return (
            f"QueryResult(columns={self.columns!r}, row_count={len(self.rows)}, "
            f"status={self.status!r}, sqlstate={self.sqlstate!r})"
        )


def default_secrets_path() -> Path:
    explicit = os.environ.get("U5_SECRET_FILE")
    if explicit:
        return Path(explicit).expanduser().resolve()
    sibling = REPOSITORY_ROOT.parent / "food-store-tp-u5-runtime" / "secrets.json"
    if sibling.is_file():
        return sibling.resolve()
    for ancestor in Path(__file__).resolve().parents:
        candidate = ancestor / "work" / "unidad5" / "private" / "secrets.json"
        if candidate.is_file():
            return candidate.resolve()
    raise ConfigurationError("Private secrets file unavailable; set U5_SECRET_FILE")


def load_secrets(path: str | os.PathLike | None = None) -> dict:
    """Read private runtime data, refusing a secrets file inside this repo.

    Preferred shape: {"roles": {"app_web": "...", "admin_datos": "..."},
    "app_auth": {"email": "...", "password": "..."}}.
    A role value may also be {"password": "..."}. Values are never logged.
    """
    selected = Path(path).expanduser().resolve() if path else default_secrets_path()
    if selected.is_relative_to(REPOSITORY_ROOT):
        raise ConfigurationError("Runtime secrets must remain outside the Git repository")
    try:
        content = json.loads(selected.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise ConfigurationError("Unable to read the private runtime secrets file") from None
    if not isinstance(content, dict):
        raise ConfigurationError("Private runtime secrets must be a JSON object")
    return content


def password_for_role(user: str, secrets: dict) -> str:
    """Support the preferred roles mapping and a flat role-to-password map."""
    roles = secrets.get("roles", {})
    value = roles.get(user) if isinstance(roles, dict) else None
    if value is None:
        value = secrets.get(user)
    if isinstance(value, dict):
        value = value.get("password")
    if not isinstance(value, str) or not value:
        raise ConfigurationError("No password configured for the requested laboratory role")
    return value


_LIBPQ = None


def _library():
    global _LIBPQ
    if _LIBPQ is not None:
        return _LIBPQ
    if os.name != "nt" or not hasattr(os, "add_dll_directory"):
        raise ConfigurationError("This laboratory client requires Windows and PostgreSQL 17 libpq")
    if not LIBPQ_PATH.is_file():
        raise ConfigurationError("PostgreSQL 17 libpq.dll was not found at the configured location")
    try:
        # Dependencies are resolved only while loading this DLL. The directory
        # handle is closed afterward; loaded modules retain their references.
        with os.add_dll_directory(str(LIBPQ_PATH.parent)):
            lib = ctypes.CDLL(str(LIBPQ_PATH))
    except OSError:
        raise ConfigurationError("Unable to load PostgreSQL 17 libpq and its dependencies") from None
    pointer = ctypes.c_void_p
    char_array = ctypes.POINTER(ctypes.c_char_p)
    lib.PQconnectdbParams.argtypes = [char_array, char_array, ctypes.c_int]
    lib.PQconnectdbParams.restype = pointer
    lib.PQstatus.argtypes = [pointer]
    lib.PQstatus.restype = ctypes.c_int
    lib.PQerrorMessage.argtypes = [pointer]
    lib.PQerrorMessage.restype = ctypes.c_char_p
    lib.PQfinish.argtypes = [pointer]
    lib.PQfinish.restype = None
    lib.PQexec.argtypes = [pointer, ctypes.c_char_p]
    lib.PQexec.restype = pointer
    lib.PQexecParams.argtypes = [
        pointer, ctypes.c_char_p, ctypes.c_int,
        ctypes.POINTER(ctypes.c_uint), char_array,
        ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int), ctypes.c_int,
    ]
    lib.PQexecParams.restype = pointer
    lib.PQresultStatus.argtypes = [pointer]
    lib.PQresultStatus.restype = ctypes.c_int
    lib.PQresultErrorField.argtypes = [pointer, ctypes.c_int]
    lib.PQresultErrorField.restype = ctypes.c_char_p
    lib.PQntuples.argtypes = [pointer]
    lib.PQntuples.restype = ctypes.c_int
    lib.PQnfields.argtypes = [pointer]
    lib.PQnfields.restype = ctypes.c_int
    lib.PQfname.argtypes = [pointer, ctypes.c_int]
    lib.PQfname.restype = ctypes.c_char_p
    lib.PQgetisnull.argtypes = [pointer, ctypes.c_int, ctypes.c_int]
    lib.PQgetisnull.restype = ctypes.c_int
    lib.PQgetlength.argtypes = [pointer, ctypes.c_int, ctypes.c_int]
    lib.PQgetlength.restype = ctypes.c_int
    lib.PQgetvalue.argtypes = [pointer, ctypes.c_int, ctypes.c_int]
    lib.PQgetvalue.restype = pointer
    lib.PQclear.argtypes = [pointer]
    lib.PQclear.restype = None
    _LIBPQ = lib
    return lib


_STATUS = {
    0: "PGRES_EMPTY_QUERY", 1: "PGRES_COMMAND_OK", 2: "PGRES_TUPLES_OK",
    3: "PGRES_COPY_OUT", 4: "PGRES_COPY_IN", 5: "PGRES_BAD_RESPONSE",
    6: "PGRES_NONFATAL_ERROR", 7: "PGRES_FATAL_ERROR", 8: "PGRES_COPY_BOTH",
    9: "PGRES_SINGLE_TUPLE", 10: "PGRES_PIPELINE_SYNC",
    11: "PGRES_PIPELINE_ABORTED", 12: "PGRES_TUPLES_CHUNK",
}


def _encoded(value) -> bytes | None:
    if value is None:
        return None
    if isinstance(value, bool):
        value = "true" if value else "false"
    elif isinstance(value, (date, datetime)):
        value = value.isoformat()
    encoded = value if isinstance(value, bytes) else str(value).encode("utf-8")
    if b"\x00" in encoded:
        raise ConfigurationError("NUL bytes are not accepted in text parameters")
    return encoded


def _connection_classification(message: bytes | None) -> str:
    # Classify internally, then discard the raw message. No account, endpoint,
    # supplied password, or connection string is included in the exception.
    lowered = (message or b"").decode("utf-8", errors="replace").lower()
    if "password authentication failed" in lowered:
        return "password_authentication_failed"
    if "no password supplied" in lowered:
        return "password_required"
    if "no pg_hba.conf entry" in lowered:
        return "connection_policy_rejected"
    if any(term in lowered for term in ("connection refused", "could not connect", "timeout expired")):
        return "network_or_server_unavailable"
    return "connection_or_authentication_failed"


class Connection:
    """A synchronous, single-owner connection to the isolated local U5 DB."""

    def __init__(self, user: str, password: str | None = None, *,
                 host: str | None = None, port: int | None = None,
                 dbname: str | None = None, application_name: str = "u5_tool",
                 connect_timeout: int = 10,
                 secret_file: str | os.PathLike | None = None):
        self._conn = None
        self._lib = _library()
        runtime = {}
        if password is None or host is None or port is None or dbname is None:
            runtime = load_secrets(secret_file)
        if password is None:
            password = password_for_role(user, runtime)
        host = host if host is not None else runtime.get("host", DEFAULT_HOST)
        port = port if port is not None else runtime.get("port", DEFAULT_PORT)
        dbname = dbname if dbname is not None else runtime.get("dbname", runtime.get("database", DEFAULT_DATABASE))
        if not isinstance(host, str) or not host or not isinstance(dbname, str) or not dbname:
            raise ConfigurationError("Runtime host and database must be nonempty strings")
        try:
            port = int(port)
        except (TypeError, ValueError):
            raise ConfigurationError("Runtime port must be a valid TCP port") from None
        if not 1 <= port <= 65535:
            raise ConfigurationError("Runtime port must be a valid TCP port")
        fields = {
            "host": host, "port": str(port), "dbname": dbname, "user": user,
            "password": password, "application_name": application_name,
            "connect_timeout": str(connect_timeout), "client_encoding": "UTF8",
        }
        keys = (ctypes.c_char_p*(len(fields)+1))(*[_encoded(k) for k in fields], None)
        values = (ctypes.c_char_p*(len(fields)+1))(*[_encoded(v) for v in fields.values()], None)
        conn = self._lib.PQconnectdbParams(keys, values, 0)
        if not conn:
            raise ConnectionFailure(operation="connect", status="NO_CONNECTION", classification="connection_allocation_failed")
        if self._lib.PQstatus(conn) != 0:
            classification = _connection_classification(self._lib.PQerrorMessage(conn))
            self._lib.PQfinish(conn)
            raise ConnectionFailure(operation="connect", status="CONNECTION_BAD", classification=classification)
        self._conn = conn

    @property
    def closed(self) -> bool:
        return self._conn is None

    def execute(self, sql: str, params: Sequence | None = None) -> QueryResult:
        if self.closed:
            raise DatabaseError(operation="query", status="CLOSED", classification="closed_connection")
        if not isinstance(sql, str) or "\x00" in sql:
            raise ConfigurationError("SQL must be text without NUL bytes")
        encoded_sql = sql.encode("utf-8")
        if params is None:
            result = self._lib.PQexec(self._conn, encoded_sql)
        else:
            if isinstance(params, (str, bytes, bytearray)):
                raise ConfigurationError("Parameters must be a sequence of separate values")
            encoded_values = [_encoded(value) for value in params]
            values = (ctypes.c_char_p*len(encoded_values))(*encoded_values)
            result = self._lib.PQexecParams(
                self._conn, encoded_sql, len(encoded_values), None,
                values, None, None, 0,
            )
        if not result:
            raise DatabaseError(operation="query", status="NO_RESULT", classification="no_result_or_connection_failure")
        try:
            status_code = self._lib.PQresultStatus(result)
            status = _STATUS.get(status_code, f"PGRES_STATUS_{status_code}")
            state_raw = self._lib.PQresultErrorField(result, ord("C"))
            sqlstate = state_raw.decode("ascii", errors="replace") if state_raw else None
            if sqlstate and not re.fullmatch(r"[0-9A-Z]{5}", sqlstate):
                sqlstate = None
            if status_code not in (0, 1, 2):
                if status_code in (3, 4, 8):
                    # COPY is outside this wrapper's contract. Closing prevents
                    # the connection being reused while COPY is still active.
                    self.close()
                raise DatabaseError(operation="query", sqlstate=sqlstate, status=status)
            field_count = self._lib.PQnfields(result)
            columns = [(self._lib.PQfname(result, index) or b"").decode("utf-8")
                       for index in range(field_count)]
            rows = []
            for row in range(self._lib.PQntuples(result)):
                values = []
                for column in range(field_count):
                    if self._lib.PQgetisnull(result, row, column):
                        values.append(None)
                    else:
                        pointer = self._lib.PQgetvalue(result, row, column)
                        length = self._lib.PQgetlength(result, row, column)
                        values.append(ctypes.string_at(pointer, length).decode("utf-8"))
                rows.append(tuple(values))
            return QueryResult(columns, rows, status, sqlstate)
        finally:
            self._lib.PQclear(result)

    def scalar(self, sql: str, params: Sequence | None = None) -> str | None:
        result = self.execute(sql, params)
        return result.rows[0][0] if result.rows and result.columns else None

    def close(self) -> None:
        if self._conn is not None:
            connection, self._conn = self._conn, None
            self._lib.PQfinish(connection)

    def __enter__(self):
        if self.closed:
            raise DatabaseError(operation="context", status="CLOSED", classification="closed_connection")
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()
        return False

    def __del__(self):
        if getattr(self, "_conn", None) is not None:
            self.close()

`````


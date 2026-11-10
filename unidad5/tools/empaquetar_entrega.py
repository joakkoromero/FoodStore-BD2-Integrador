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

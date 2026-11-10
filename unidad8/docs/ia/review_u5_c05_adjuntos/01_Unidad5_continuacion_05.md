# Fuentes saneadas para revisión estática: Unidad5

No ejecutar estas copias. Los literales personales/de carga se sustituyeron por placeholders; las comprobaciones en motor usarán las fuentes originales locales. Señalar archivo/línea y distinguir errores confirmables de hipótesis.

## outputs\Arancibia_Romero_U5\food-store-tp-u5\tools\verificar_privacidad.py

SHA256 original: 0aeb0f38f950f5e902d14946483f971aef832f0dc0edb7c84aa82404cee1d1d5
SHA256 saneado: ec76a600030458e1a6fcdb643edcae28abe71fb4b9ff40a1a271250b9473621e

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Scan deliverable files and decoded Git objects for known private values.

Complements the package pattern scan; does not certify complete anonymization.
The private inventory and any matching value are never printed or exported.
"""
import io
import json
from datetime import datetime, timezone
import subprocess

from anonimizar_log import secret_inventory, BCRYPT, SCRAM
from libpq_client import load_secrets, REPOSITORY_ROOT


def git(*args, data=None):
    result = subprocess.run(['git','-C',str(REPOSITORY_ROOT),*args],input=data,
                            capture_output=True,check=False)
    if result.returncode:
        raise RuntimeError('Unable to inspect repository; no diagnostic values exported')
    return result.stdout


def main():
    private = load_secrets()
    values = secret_inventory(private)
    email = private.get('business_email') or private.get('app_auth',{}).get('email')
    if email:
        values.append(email)
    encoded = [value.encode('utf-8') for value in set(values)]
    checked_pdfs = 0
    def check(data):
        nonlocal checked_pdfs
        if any(value in data for value in encoded):
            raise RuntimeError('Private inventory match found; inspect locally before delivery')
        text = data.decode('utf-8',errors='replace')
        if BCRYPT.search(text) or SCRAM.search(text):
            raise RuntimeError('Credential verifier pattern found; inspect locally before delivery')
        if data.startswith(b'%PDF-'):
            from pypdf import PdfReader
            extracted = '\n'.join(page.extract_text() for page in PdfReader(io.BytesIO(data)).pages)
            if any(value in extracted for value in values) or BCRYPT.search(extracted) or SCRAM.search(extracted):
                raise RuntimeError('Private match found in PDF text; inspect locally before delivery')
            checked_pdfs += 1
    names = set(git('ls-files','--cached','--others','--exclude-standard','-z').decode('utf-8').split('\0'))-{''}
    for name in names:
        check((REPOSITORY_ROOT/name).read_bytes())
    objects = git('cat-file','--batch-all-objects','--batch-check=%(objectname)').splitlines()
    payload = git('cat-file','--batch',data=b'\n'.join(objects)+b'\n')
    offset = 0
    for oid in objects:
        end = payload.index(b'\n',offset)
        size = int(payload[offset:end].split()[2])
        check(payload[end+1:end+1+size])
        offset = end+1+size+1
    evidence = {'checked_at_utc':datetime.now(timezone.utc).isoformat(),
        'worktree_files_scanned':len(names),'decoded_git_objects_scanned':len(objects),
        'pdf_payloads_text_scanned':checked_pdfs,
        'known_private_inventory_matches':0,'bcrypt_scram_verifier_matches':0,
        'private_inventory_exported':False,'passed':True,
        'scope':'Known private values and credential verifier patterns; complementary to package pattern scan, not a proof of irreversible anonymity'}
    target = REPOSITORY_ROOT/'docs'/'evidencias'/'privacidad_entrega.json'
    target.write_text(json.dumps(evidence,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(evidence,ensure_ascii=False))


if __name__ == '__main__':
    main()

`````

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

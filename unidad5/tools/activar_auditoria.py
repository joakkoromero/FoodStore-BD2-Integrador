"""Activate the Part B settings outside a transaction and verify a new session."""
from libpq_client import Connection,load_secrets,REPOSITORY_ROOT
import json
import time


def main():
    private=load_secrets()
    with Connection(private['bootstrap_user'],application_name='u5_audit_config') as db:
        # ALTER SYSTEM cannot run inside a transaction. Each named statement
        # here is static SQL from the delivered configuration file.
        text=(REPOSITORY_ROOT/'sql/configurar_auditoria.sql').read_text(encoding='utf-8')
        text='\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('--'))
        for statement in text.split(';'):
            if statement.strip(): db.execute(statement)
    expected={'logging_collector':'on','log_connections':'on',
        'log_disconnections':'on','log_statement':'all','log_min_error_statement':'error',
        'log_parameter_max_length':'0','log_parameter_max_length_on_error':'0'}
    keys=list(expected)+['log_destination','log_line_prefix','password_encryption',
        'log_timezone','timezone','listen_addresses','port','log_directory','log_filename']
    # Reload is asynchronous. Retry a new session briefly; never claim that
    # pg_reload_conf() alone proves the settings became active.
    for attempt in range(10):
        with Connection(private['bootstrap_user'],application_name='u5_audit_config_verify') as db:
            values={key:db.scalar('SHOW '+key) for key in keys}
            ready=all(values[k]==v for k,v in expected.items())
            if ready:
                values['server_version']=db.scalar('SHOW server_version')
                values['verified_at']=db.scalar('SELECT current_timestamp::text')
                break
        time.sleep(0.2)
    else:
        raise RuntimeError('Audit configuration did not take effect in a new session')
    (REPOSITORY_ROOT/'docs/configuracion_auditoria.json').write_text(
        json.dumps(values,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Audit settings verified in a new connection.')


if __name__=='__main__': main()

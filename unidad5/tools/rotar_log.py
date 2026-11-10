"""Rotate the private server JSON log, preserving the source for capture."""
import json
import time
from libpq_client import Connection, load_secrets


def main():
    secret = load_secrets()
    with Connection(secret['bootstrap_user'], application_name='u5_rotate_log') as db:
        query = 'SELECT pg_catalog.pg_current_logfile($1::text)'
        before = db.scalar(query, ['jsonlog'])
        requested = db.scalar('SELECT pg_catalog.pg_rotate_logfile()')
        if requested != 't':
            raise RuntimeError('Server did not accept log rotation')
        for attempt in range(20):
            time.sleep(0.1)
            after = db.scalar(query, ['jsonlog'])
            if before != after:
                break
        else:
            raise RuntimeError('Rotation not observed; source may still be active')
    print(json.dumps({'previous_json_log':before,'current_json_log':after,
                      'rotation_observed':True}))


if __name__ == '__main__':
    main()

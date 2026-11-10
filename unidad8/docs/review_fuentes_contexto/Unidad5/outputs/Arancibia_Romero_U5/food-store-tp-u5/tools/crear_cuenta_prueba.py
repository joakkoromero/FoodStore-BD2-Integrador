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

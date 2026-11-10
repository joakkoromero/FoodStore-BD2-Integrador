# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Run real U5 role/audit/incident checks after roles.sql has been applied.

Importing this module runs nothing. Authentication/reset parameters use libpq
binds. Evidence contains roles, timestamps, counts, booleans and SQLSTATE only;
it never contains a business email, password, hash, raw error or usuario row.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import secrets as random_secrets
import sys

from libpq_client import (
    Connection, ConnectionFailure, DatabaseError, ConfigurationError,
    DEFAULT_HOST, DEFAULT_PORT, DEFAULT_DATABASE, REPOSITORY_ROOT, load_secrets,
)


class VerificationFailure(RuntimeError):
    """A deliberately non-sensitive verification failure."""


PUBLIC_USER_COLUMNS = ["id", "nombre", "apellido", "eliminado", "created_at"]
CONTACT_COLUMNS = ["id", "nombre", "apellido", "email", "telefono", "eliminado"]
GROUP_ROLES = ["rol_app_lectura", "rol_app_escritura", "rol_soporte", "rol_reportes"]
LOGIN_ROLES = ["app_web", "admin_datos"]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def ensure(condition: bool, label: str) -> None:
    if not condition:
        raise VerificationFailure(label)


def bool_value(value) -> bool:
    ensure(value in {"t", "f", "true", "false", True, False}, "Unexpected boolean result")
    return value in {"t", "true", True}


def load_queries(filename: str) -> dict[str, str]:
    text = (REPOSITORY_ROOT/"sql"/filename).read_text(encoding="utf-8")
    result = {}
    current = None
    lines = []
    for line in text.splitlines():
        marker = re.fullmatch(r"\s*--\s*name:\s*([a-z0-9_]+)\s*", line)
        if marker:
            if current:
                result[current] = "\n".join(lines).strip()
            current, lines = marker.group(1), []
        elif current and not line.lstrip().startswith("--"):
            lines.append(line)
    if current:
        result[current] = "\n".join(lines).strip()
    ensure(bool(result) and all(result.values()), "SQL catalog is missing named statements")
    return result


class Harness:
    def __init__(self, *, secret_file=None, evidence_dir=None):
        self.secret_file = secret_file
        self.private = load_secrets(secret_file)
        self.bootstrap_user = self.private.get("bootstrap_user", "u5_bootstrap")
        self.app_user = self.private.get("app_user", "app_web")
        self.admin_user = self.private.get("admin_user", "admin_datos")
        ensure(self.app_user == "app_web" and self.admin_user == "admin_datos", "Unexpected laboratory login role configuration")
        self.evidence_dir = Path(evidence_dir or REPOSITORY_ROOT/"docs"/"evidencias").resolve()
        self.evidence_dir.mkdir(parents=True, exist_ok=True)
        self.current_evidence = None

    def connect(self, user: str, application: str, password=None) -> Connection:
        return Connection(
            user, password, application_name=application, secret_file=self.secret_file,
            host=self.private.get("host", DEFAULT_HOST),
            port=self.private.get("port", DEFAULT_PORT),
            dbname=self.private.get("dbname", self.private.get("database", DEFAULT_DATABASE)),
        )

    def credentials(self) -> tuple[str, str]:
        auth = self.private.get("app_auth", {})
        email = self.private.get("business_email") or auth.get("email")
        password = self.private.get("business_password") or auth.get("password")
        ensure(isinstance(email, str) and isinstance(password, str) and bool(email) and bool(password), "Business authentication fixture is not configured")
        return email, password

    def record(self, step: str, actor: str, **safe_fields) -> None:
        ensure(self.current_evidence is not None, "No active evidence phase")
        self.current_evidence["events"].append({
            "timestamp_utc": utc_now(), "step": step, "actor": actor, **safe_fields,
        })

    def fixture_id(self, bootstrap: Connection) -> str:
        email, _ = self.credentials()
        value = bootstrap.scalar("SELECT id FROM public.usuario WHERE email=$1::text AND eliminado=FALSE;", [email])
        ensure(value is not None and value.isdigit(), "Business authentication fixture was not found")
        return value

    def counts(self, bootstrap: Connection) -> dict:
        result = bootstrap.execute("""
SELECT (SELECT count(*) FROM public.usuario),
       (SELECT count(*) FROM public.pedido),
       (SELECT count(*) FROM public.detalle_pedido);
""")
        return dict(zip(("usuario", "pedido", "detalle_pedido"), map(int, result.rows[0])))

    def verify_logging_prerequisites(self, phase: str) -> None:
        # Check before sending any email/password parameter. These names and
        # setting values are configuration metadata, not business-user data.
        with self.connect(self.bootstrap_user, "u5_logging_verifier") as bootstrap:
            result = bootstrap.execute("""
SELECT name,setting FROM pg_catalog.pg_settings
WHERE name IN ('log_parameter_max_length','log_parameter_max_length_on_error',
               'log_statement','log_connections','log_disconnections',
               'log_min_error_statement') ORDER BY name;
""")
            settings = dict(result.rows)
        ensure(settings.get("log_parameter_max_length") == "0"
               and settings.get("log_parameter_max_length_on_error") == "0",
               "Parameter logging must be disabled before credential checks")
        if phase in {"audit", "incident"}:
            ensure(settings.get("log_statement") == "all"
                   and settings.get("log_connections") == "on"
                   and settings.get("log_disconnections") == "on"
                   and settings.get("log_min_error_statement") == "error",
                   "Native audit logging is not configured for the requested phase")
        self.current_evidence["runtime_logging"] = settings
        self.record("logging_prerequisites_verified", self.bootstrap_user,
                    bind_parameters_logged=False, credential_checks_started=False)

    def expect_error(self, connection: Connection, *, name: str, actor: str,
                     sql: str, expected: str, params=None, savepoint=False) -> None:
        if savepoint:
            connection.execute("SAVEPOINT u5_expected_rejection;")
        observed = None
        try:
            result = connection.execute(sql, params)
            del result
        except DatabaseError as error:
            observed = error.sqlstate
            if observed != expected:
                self.record(name, actor, expected_sqlstate=expected, observed_sqlstate=observed,
                            rejection_verified=False)
            ensure(observed == expected, "Unexpected SQLSTATE in permission verification")
        finally:
            if savepoint:
                connection.execute("ROLLBACK TO SAVEPOINT u5_expected_rejection;")
                connection.execute("RELEASE SAVEPOINT u5_expected_rejection;")
        self.record(name, actor, expected_sqlstate=expected, observed_sqlstate=observed,
                    rejection_verified=observed == expected)
        ensure(observed == expected, "An operation requiring rejection unexpectedly succeeded")

    def phase_audit(self) -> dict:
        queries = load_queries("auditoria_test.sql")
        with self.connect(self.bootstrap_user, "u5_audit_verifier") as bootstrap:
            before = self.counts(bootstrap)
            business_id = self.fixture_id(bootstrap)
            with self.connect(self.app_user, "u5_audit_test") as app:
                app.execute(queries["audit_begin"])
                try:
                    catalog = app.execute(queries["audit_catalog_read"])
                    ensure(bool(catalog.rows), "No active product has sufficient stock for the reversible fixture")
                    product_id, catalog_price = catalog.rows[0][:2]
                    self.record("read_catalog", self.app_user, rows_received=len(catalog.rows), columns=catalog.columns)
                    del catalog
                    order = app.execute(queries["audit_insert_order"], [business_id])
                    ensure(len(order.rows) == 1 and len(order.rows[0]) == 2
                           and order.rows[0][0].isdigit() and order.rows[0][1] == "PENDIENTE",
                           "Order INSERT did not return one identity in the initial pending state")
                    order_id = order.rows[0][0]
                    self.record("insert_pending_order", self.app_user, successful=True,
                                rows_inserted=len(order.rows), initial_state_pending=True)
                    del order
                    inserted = app.execute(queries["audit_insert_detail"], [order_id, product_id, catalog_price])
                    ensure(len(inserted.rows) == 1 and bool_value(inserted.rows[0][0]), "Detail INSERT did not create the expected row")
                    self.record("insert_detail", self.app_user, successful=True, rows_inserted=len(inserted.rows))
                    del inserted
                    updated = app.execute(queries["audit_update_detail"], [order_id, product_id])
                    ensure(len(updated.rows) == 1 and updated.rows[0][0] == "2", "Detail UPDATE did not change the expected row")
                    self.record("update_pending_detail", self.app_user, successful=True, rows_updated=len(updated.rows))
                    del updated
                    ensure(bool_value(app.scalar(queries["audit_order_total_invariant"], [order_id])), "Inherited order-total invariant failed")
                    self.record("inherited_total_verified", self.app_user, invariant_holds=True)
                    confirmed = app.execute(queries["audit_confirm_order"], [order_id])
                    ensure(len(confirmed.rows) == 1 and bool_value(confirmed.rows[0][0]), "Order state UPDATE did not confirm the expected row")
                    self.record("valid_state_transition", self.app_user, successful=True, rows_updated=len(confirmed.rows))
                    del confirmed
                finally:
                    app.execute(queries["audit_rollback"])
                    self.record("rollback_test_data", self.app_user, rolled_back=True)
            after = self.counts(bootstrap)
            ensure(before == after, "Audit test left persistent source rows")
            self.record("source_counts_preserved", self.bootstrap_user, before=before, after=after)
        wrong = random_secrets.token_urlsafe(32)
        try:
            bad = self.connect(self.app_user, "u5_audit_failed_login", wrong)
        except ConnectionFailure as error:
            ensure(error.classification == "password_authentication_failed",
                   "Invalid-login probe failed for a reason other than password authentication")
            self.record("postgresql_login_failed", self.app_user, failure_type=type(error).__name__,
                        classification=error.classification, observed_sqlstate=error.sqlstate,
                        sqlstate_source="No PGresult is available during handshake; inspect the actual server log")
        else:
            bad.close()
            raise VerificationFailure("The deliberately invalid PostgreSQL login unexpectedly succeeded")
        return {"counts_before": before, "counts_after": after,
                "data_rolled_back": True, "postgresql_failed_login_verified": True,
                "identity_sequence_values_restored": False,
                "note": "ROLLBACK removes the test rows but does not recover consumed identity values or delete audit logs. Native statement logs record attempts, including rolled-back work. No user rows are exported."}

    def phase_incident(self) -> dict:
        queries = load_queries("simulacro_incidente.sql")
        email, password = self.credentials()
        with self.connect(self.bootstrap_user, "u5_verifier_incident") as bootstrap:
            expected_count = int(bootstrap.scalar("SELECT count(*) FROM public.usuario;"))
            expected_id = self.fixture_id(bootstrap)
            before_member = bool_value(bootstrap.scalar(queries["incident_membership_check"]))
            ensure(not before_member, "Privilege model already grants the forbidden administrative membership")
            self.record("membership_before", self.bootstrap_user, administrative_membership=False)
            with self.connect(self.app_user, "u5_incident") as app:
                actor = app.execute("SELECT session_user,current_user;").rows[0]
                ensure(actor == (self.app_user, self.app_user), "Incident is not executing under the intended low-privilege login")
                self.record("database_actor_verified", self.app_user, session_role=actor[0], current_role=actor[1])
                for attempt in range(1, 4):
                    wrong = random_secrets.token_urlsafe(32)
                    while wrong == password:
                        wrong = random_secrets.token_urlsafe(32)
                    accepted = app.scalar(queries["incident_authenticate"], [email, wrong])
                    ensure(accepted is None, "A deliberately invalid business password was accepted")
                    self.record("business_authentication", self.app_user, attempt=attempt, accepted=False)
                accepted = app.scalar(queries["incident_authenticate"], [email, password])
                ensure(accepted == expected_id, "The correct business credential was not accepted for the fixture")
                self.record("business_authentication", self.app_user, attempt=4, accepted=True)
                actor_after = app.execute("SELECT session_user,current_user;").rows[0]
                ensure(actor_after == actor, "Business authentication unexpectedly changed the database role")
                self.record("database_actor_after_business_auth", self.app_user,
                            session_role=actor_after[0], current_role=actor_after[1], role_unchanged=True)
                mass = app.execute(queries["incident_bulk_read"])
                received_count = len(mass.rows)
                columns = list(mass.columns)
                ensure(columns == PUBLIC_USER_COLUMNS and "contrasena" not in columns, "Bulk SELECT projected an unexpected or credential column")
                ensure(received_count == expected_count, "Bulk SELECT did not actually retrieve the complete authorized projection")
                self.record("bulk_read_received_and_discarded", self.app_user,
                            rows_received=received_count, expected_rows=expected_count,
                            columns=columns, credential_column_present=False, user_values_exported=False)
                del mass
                self.expect_error(app, name="administrative_membership_escalation",
                                  actor=self.app_user, sql=queries["incident_attempt_escalation"], expected="42501")
            after_member = bool_value(bootstrap.scalar(queries["incident_membership_check"]))
            ensure(not after_member, "Forbidden administrative membership appeared after the attempted escalation")
            self.record("membership_after", self.bootstrap_user, administrative_membership=False)
        return {"failed_business_authentications": 3, "successful_business_authentications": 1,
                "rows_received": received_count, "expected_rows": expected_count,
                "escalation_sqlstate": "42501", "membership_before": before_member,
                "membership_after": after_member, "user_values_exported": False,
                "containment_executed": False,
                "evidence_limit": "The client proves the received-row count; the native SELECT log alone does not prove row delivery, off-host extraction or malicious intent."}

    def permission_snapshot(self, bootstrap: Connection) -> dict:
        roles = GROUP_ROLES+LOGIN_ROLES+["rol_propietario", "rol_funciones"]
        result = bootstrap.execute("""
SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls
FROM pg_catalog.pg_roles WHERE rolname=ANY($1::text[]) ORDER BY rolname;
""", ["{"+",".join(roles)+"}"])
        ensure(len(result.rows) == len(roles), "One or more specified roles are missing")
        snapshot = []
        for row in result.rows:
            name, canlogin, *dangerous = row
            ensure(not any(bool_value(v) for v in dangerous), "A laboratory role has a forbidden administrative attribute")
            ensure(bool_value(canlogin) == (name in LOGIN_ROLES), "Unexpected LOGIN attribute")
            snapshot.append(dict(zip(result.columns, [name, bool_value(canlogin)]+[bool_value(v) for v in dangerous])))
        for login in LOGIN_ROLES:
            for owner in ("rol_propietario", "rol_funciones"):
                ensure(not bool_value(bootstrap.scalar("SELECT pg_catalog.pg_has_role($1::name,$2::name,'MEMBER');", [login, owner])), "An application login inherits a protected owner role")
        return {"roles": snapshot}

    def phase_permissions(self) -> dict:
        """Behavior matrix based on the final Kiro specification and review.

        Run after the actual generated requirements/design and roles.sql have
        been reviewed. The full ACL dump/exact specification comparison remains
        an additional deliverable; these tests do not replace that comparison.
        """
        with self.connect(self.bootstrap_user, "u5_permissions_verifier") as bootstrap:
            snapshot = self.permission_snapshot(bootstrap)
            sequence_last = bootstrap.scalar("SELECT last_value::bigint FROM public.pedido_id_seq;")
            business_id = self.fixture_id(bootstrap)
            missing_business_id = bootstrap.scalar("SELECT (COALESCE(MAX(id),0)+1)::text FROM public.usuario;")
        with self.connect(self.app_user, "u5_permissions_app") as app:
            app.execute("BEGIN;")
            try:
                for label, sql in (
                    ("deny_user_credentials_read", "SELECT contrasena FROM public.usuario LIMIT 1;"),
                    ("deny_user_star_read", "SELECT * FROM public.usuario LIMIT 1;"),
                    ("deny_user_credentials_update", "UPDATE public.usuario SET contrasena=contrasena WHERE FALSE;"),
                    ("deny_user_delete", "DELETE FROM public.usuario WHERE FALSE;"),
                    ("deny_order_delete", "DELETE FROM public.pedido WHERE FALSE;"),
                    ("deny_derived_order_total_update", "UPDATE public.pedido SET total=total WHERE FALSE;"),
                    ("deny_admin_set_role", "SET ROLE admin_datos;"),
                    ("deny_owner_set_role", "SET ROLE rol_propietario;"),
                    ("deny_inherited_group_set_role", "SET ROLE rol_app_lectura;"),
                    ("deny_role_creation", "CREATE ROLE u5_unexpected_role_probe NOLOGIN;"),
                ):
                    self.expect_error(app, name=label, actor=self.app_user, sql=sql, expected="42501", savepoint=True)
                for privilege in ("USAGE", "SELECT", "UPDATE"):
                    allowed = bool_value(app.scalar("SELECT pg_catalog.has_sequence_privilege(current_user,'public.pedido_id_seq',$1::text);", [privilege]))
                    ensure(not allowed, "Direct identity-sequence privilege is broader than specified")
                    self.record("identity_sequence_acl", self.app_user, privilege=privilege, allowed=False)
                self.expect_error(app, name="deny_direct_nextval", actor=self.app_user,
                                  sql="SELECT pg_catalog.nextval('public.pedido_id_seq'::regclass);", expected="42501", savepoint=True)
                self.expect_error(app, name="deny_direct_setval", actor=self.app_user,
                                  sql="SELECT pg_catalog.setval('public.pedido_id_seq'::regclass,$1::bigint,TRUE);",
                                  params=[sequence_last], expected="42501", savepoint=True)
                self.expect_error(app, name="deny_password_reset_function", actor=self.app_user,
                                  sql="SELECT public.fn_resetear_password($1::bigint,$2::text);",
                                  params=[business_id, self.credentials()[1]], expected="42501", savepoint=True)
                for column in ("subtotal",):
                    allowed = bool_value(app.scalar("SELECT pg_catalog.has_column_privilege(current_user,'public.detalle_pedido',$1::text,'UPDATE');", [column]))
                    ensure(not allowed, "Generated detail value is directly writable by the application")
                    self.record("deny_generated_column_acl", self.app_user, column=column, allowed=False)
            finally:
                app.execute("ROLLBACK;")
        with self.connect(self.admin_user, "u5_permissions_admin") as admin:
            admin.execute("BEGIN;")
            try:
                read = admin.execute("SELECT id,nombre,apellido,email,telefono,eliminado FROM public.usuario LIMIT 1;")
                ensure(read.columns == CONTACT_COLUMNS, "Support received columns outside its final specification")
                self.record("support_contact_read", self.admin_user, rows_received=len(read.rows), columns=read.columns)
                del read
                contact_update = admin.execute("UPDATE public.usuario SET telefono=telefono WHERE FALSE RETURNING 1;")
                ensure(not contact_update.rows, "The empty support UPDATE unexpectedly changed rows")
                self.record("support_contact_update", self.admin_user, successful=True,
                            rows_updated=len(contact_update.rows))
                del contact_update
                admin.execute("SELECT public.fn_resetear_password($1::bigint,$2::text);", [business_id, self.credentials()[1]])
                self.record("admin_password_reset_allowed", self.admin_user, successful=True, rolled_back=True)
                for label, sql in (
                    ("deny_support_hash_read", "SELECT contrasena FROM public.usuario LIMIT 1;"),
                    ("deny_support_created_at_read", "SELECT created_at FROM public.usuario LIMIT 1;"),
                    ("deny_support_user_delete", "DELETE FROM public.usuario WHERE FALSE;"),
                    ("deny_support_order_read", "SELECT id FROM public.pedido LIMIT 1;"),
                    ("deny_support_other_column_update", "UPDATE public.usuario SET nombre=nombre WHERE FALSE;"),
                    ("deny_support_email_update", "UPDATE public.usuario SET email=email WHERE FALSE;"),
                    ("deny_support_owner_set_role", "SET ROLE rol_propietario;"),
                    ("deny_support_function_owner_set_role", "SET ROLE rol_funciones;"),
                ):
                    self.expect_error(admin, name=label, actor=self.admin_user,
                                      sql=sql, expected="42501", savepoint=True)
                self.expect_error(admin, name="reset_missing_user_rejected", actor=self.admin_user,
                                  sql="SELECT public.fn_resetear_password($1::bigint,$2::text);",
                                  params=[missing_business_id, self.credentials()[1]],
                                  expected="P0002", savepoint=True)
                for label, invalid in (
                    ("reset_password_null_rejected", None),
                    ("reset_password_11_bytes_rejected", random_secrets.token_urlsafe(16)[:11]),
                    ("reset_password_73_bytes_rejected", random_secrets.token_urlsafe(64)[:73]),
                    ("reset_password_multibyte_74_bytes_rejected", "\u00e9"*37),
                ):
                    self.expect_error(admin, name=label, actor=self.admin_user,
                                      sql="SELECT public.fn_resetear_password($1::bigint,$2::text);",
                                      params=[business_id, invalid], expected="22023", savepoint=True)
                for byte_length in (12, 72):
                    boundary = random_secrets.token_urlsafe(64)[:byte_length]
                    reset = admin.execute("SELECT public.fn_resetear_password($1::bigint,$2::text);",
                                          [business_id, boundary])
                    ensure(len(reset.rows) == 1, "A valid password boundary was not accepted")
                    self.record("reset_password_boundary_allowed", self.admin_user,
                                password_bytes=byte_length, successful=True, rolled_back=True)
                    del reset, boundary
            finally:
                admin.execute("ROLLBACK;")
        with self.connect(self.bootstrap_user, "u5_permissions_groups") as bootstrap:
            for role in GROUP_ROLES:
                bootstrap.execute("BEGIN;")
                try:
                    bootstrap.execute("SET LOCAL ROLE "+role+";")
                    if role == "rol_app_lectura":
                        result = bootstrap.execute("SELECT id,nombre,apellido,eliminado,created_at FROM public.usuario LIMIT 1;")
                        self.record("reader_projection_allowed", role, rows_received=len(result.rows), columns=result.columns)
                        del result
                        self.expect_error(bootstrap, name="reader_write_denied", actor=role,
                                          sql="UPDATE public.producto SET stock=stock WHERE FALSE;", expected="42501", savepoint=True)
                    elif role == "rol_app_escritura":
                        allowed = bool_value(bootstrap.scalar("SELECT pg_catalog.has_column_privilege(current_user,'public.pedido','usuario_id','INSERT');"))
                        ensure(allowed, "Writer group lacks its scoped order INSERT")
                        self.record("writer_scoped_insert_acl", role, allowed=True)
                        ensure(not bool_value(bootstrap.scalar("SELECT pg_catalog.has_column_privilege(current_user,'public.pedido','total','UPDATE');")), "Writer group directly controls a derived total")
                    elif role == "rol_soporte":
                        result = bootstrap.execute("SELECT email,telefono FROM public.usuario LIMIT 1;")
                        self.record("support_group_contact_read", role, rows_received=len(result.rows), columns=result.columns)
                        del result
                    elif role == "rol_reportes":
                        count = int(bootstrap.scalar("SELECT count(*) FROM public.mv_u4_ventas_categoria_dia;"))
                        self.record("reports_aggregate_read", role, rows_received=1, aggregate_groups=count)
                        self.expect_error(bootstrap, name="reports_base_user_read_denied", actor=role,
                                          sql="SELECT id FROM public.usuario LIMIT 1;", expected="42501", savepoint=True)
                    self.expect_error(bootstrap, name="group_user_hash_read_denied", actor=role,
                                      sql="SELECT contrasena FROM public.usuario LIMIT 1;", expected="42501", savepoint=True)
                finally:
                    bootstrap.execute("ROLLBACK;")
            for role in GROUP_ROLES+LOGIN_ROLES:
                for table in ("lote", "deposito", "responsable_deposito", "lote_responsable", "control_lote_almacen"):
                    allowed = bool_value(bootstrap.scalar("SELECT pg_catalog.has_table_privilege($1::name,$2::text,'SELECT');", [role, "public."+table]))
                    ensure(not allowed, "An application/report/support role can access the protected FNBC extension")
                self.record("fnbc_extension_not_granted", role, protected_objects_checked=5, allowed=False)
        return {**snapshot, "minimum_behavioral_matrix_verified": True,
                "all_test_mutations_rolled_back": True,
                "note": "Group behavior uses bootstrap SET LOCAL ROLE, clearly distinguished from actual app_web/admin_datos login connections."}

    def verify_function_defaults(self, bootstrap: Connection) -> list[dict]:
        """Probe real creator defaults inside the caller's rolled-back transaction.

        rol_funciones gets CREATE only for this transaction, solely to create a
        harmless probe as the actual role. ROLLBACK removes the grant and all
        functions; this does not broaden the persistent implementation policy.
        """
        probes = [
            (self.bootstrap_user, "u5_default_probe_fn_bootstrap"),
            ("rol_propietario", "u5_default_probe_fn_propietario"),
            ("rol_funciones", "u5_default_probe_fn_funciones"),
        ]
        observations = []
        for creator, name in probes:
            bootstrap.execute("RESET ROLE;")
            signature = "public."+name+"()"
            ensure(bootstrap.scalar("SELECT pg_catalog.to_regprocedure($1::text);", [signature]) is None,
                   "A default-function probe already exists")
            if creator == "rol_funciones":
                ensure(not bool_value(bootstrap.scalar(
                    "SELECT pg_catalog.has_schema_privilege('rol_funciones','public','CREATE');")),
                    "The function owner unexpectedly has persistent CREATE on public")
                bootstrap.execute("GRANT CREATE ON SCHEMA public TO rol_funciones;")
            if creator != self.bootstrap_user:
                # Both alternative role names and every function name above are
                # fixed test identifiers, never configuration/user input.
                bootstrap.execute("SET LOCAL ROLE "+creator+";")
            bootstrap.execute("CREATE FUNCTION public."+name+"() RETURNS integer "
                              "LANGUAGE sql SET search_path=pg_catalog AS 'SELECT 1';")
            bootstrap.execute("RESET ROLE;")
            public_execute = int(bootstrap.scalar("""
SELECT count(*) FROM pg_catalog.pg_proc p,
LATERAL pg_catalog.aclexplode(COALESCE(p.proacl,pg_catalog.acldefault('f',p.proowner))) a
WHERE p.oid=$1::regprocedure AND a.grantee=0 AND a.privilege_type='EXECUTE';
""", [signature]))
            ensure(public_execute == 0, "A creator retains global PUBLIC EXECUTE on future functions")
            checked_roles = []
            for role in GROUP_ROLES+LOGIN_ROLES:
                allowed = bool_value(bootstrap.scalar(
                    "SELECT pg_catalog.has_function_privilege($1::name,$2::text,'EXECUTE');",
                    [role, signature]))
                ensure(not allowed, "A future function is executable by an unapproved business role")
                bootstrap.execute("SET LOCAL ROLE "+role+";")
                self.expect_error(bootstrap, name="future_function_execution_denied", actor=role,
                                  sql="SELECT public."+name+"();", expected="42501", savepoint=True)
                bootstrap.execute("RESET ROLE;")
                checked_roles.append(role)
            observation = {"creator_role": creator, "public_execute_entries": public_execute,
                           "denied_roles": checked_roles,
                           "temporary_create_grant": creator == "rol_funciones"}
            observations.append(observation)
            self.record("future_function_creator_default", self.bootstrap_user, **observation)
        return observations

    def phase_defaults(self) -> dict:
        with self.connect(self.bootstrap_user, "u5_defaults_verifier") as bootstrap:
            bootstrap.execute("BEGIN;")
            try:
                ensure(bootstrap.scalar("SELECT to_regclass('public.u5_default_probe_restricted');") is None,
                       "A default-privilege probe object already exists")
                ensure(bootstrap.scalar("SELECT to_regclass('datos_anon.u5_default_probe_anonymous');") is None,
                       "A default-privilege probe object already exists")
                bootstrap.execute("SET LOCAL ROLE rol_propietario;")
                bootstrap.execute("CREATE TABLE public.u5_default_probe_restricted(marker integer);")
                bootstrap.execute("CREATE TABLE datos_anon.u5_default_probe_anonymous(marker integer);")
                bootstrap.execute("RESET ROLE;")
                for role in GROUP_ROLES+LOGIN_ROLES:
                    for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE"):
                        allowed = bool_value(bootstrap.scalar("SELECT pg_catalog.has_table_privilege($1::name,'public.u5_default_probe_restricted',$2::text);", [role, privilege]))
                        ensure(not allowed, "A future public table exposes broader default privileges")
                        self.record("future_public_table_default", role, privilege=privilege, allowed=False)
                        anonymous = bool_value(bootstrap.scalar("SELECT pg_catalog.has_table_privilege($1::name,'datos_anon.u5_default_probe_anonymous',$2::text);", [role, privilege]))
                        expected = role == "rol_reportes" and privilege == "SELECT"
                        ensure(anonymous == expected, "A future anonymous table does not match the reporting-only default policy")
                        self.record("future_anonymous_table_default", role, privilege=privilege, allowed=anonymous)
                public_entries = int(bootstrap.scalar("""
SELECT count(*) FROM pg_catalog.pg_class c,
LATERAL pg_catalog.aclexplode(COALESCE(c.relacl,pg_catalog.acldefault('r',c.relowner))) a
WHERE c.oid IN ('public.u5_default_probe_restricted'::regclass,
               'datos_anon.u5_default_probe_anonymous'::regclass)
  AND a.grantee=0;
"""))
                ensure(public_entries == 0, "Future probe tables retain PUBLIC grants")
                bootstrap.execute("SET LOCAL ROLE rol_reportes;")
                received = int(bootstrap.scalar("SELECT count(*) FROM datos_anon.u5_default_probe_anonymous;"))
                ensure(received == 0, "Anonymous probe unexpectedly contains data")
                self.record("future_anonymous_table_select_works", "rol_reportes", rows_received=1, aggregate_count=0)
                bootstrap.execute("RESET ROLE;")
                function_defaults = self.verify_function_defaults(bootstrap)
            finally:
                bootstrap.execute("ROLLBACK;")
            remaining = int(bootstrap.scalar("""
SELECT count(*) FROM pg_catalog.pg_class
WHERE relname IN ('u5_default_probe_restricted','u5_default_probe_anonymous');
"""))
            ensure(remaining == 0, "Default-privilege probes were not rolled back")
            remaining_functions = int(bootstrap.scalar("""
SELECT count(*) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.proname IN ('u5_default_probe_fn_bootstrap',
  'u5_default_probe_fn_propietario','u5_default_probe_fn_funciones');
"""))
            ensure(remaining_functions == 0, "Default-function probes were not rolled back")
            function_owner_create_after = bool_value(bootstrap.scalar(
                "SELECT pg_catalog.has_schema_privilege('rol_funciones','public','CREATE');"))
            ensure(not function_owner_create_after, "The temporary function-owner CREATE grant persisted")
        return {"creator_role": "rol_propietario", "future_public_default": "deny application access",
                "future_anonymous_default": "rol_reportes SELECT only", "public_grants": 0,
                "probe_objects_remaining": remaining, "function_defaults": function_defaults,
                "probe_functions_remaining": remaining_functions,
                "function_owner_create_after": function_owner_create_after, "rolled_back": True,
                "temporary_probe_grant": "Only transaction-scoped CREATE on public for rol_funciones; removed by ROLLBACK"}

    def run_phase(self, phase: str) -> dict:
        evidence = {"phase": phase, "status": "running", "started_at_utc": utc_now(),
                    "events": [], "private_values_exported": False}
        self.current_evidence = evidence
        try:
            self.verify_logging_prerequisites(phase)
            evidence["result"] = getattr(self, "phase_"+phase)()
            evidence["status"] = "passed"
        except DatabaseError as error:
            evidence.update(status="failed", failure={"type": type(error).__name__,
                            "sqlstate": error.sqlstate, "classification": error.classification,
                            "operation": error.operation, "status": error.status})
            raise
        except Exception as error:
            evidence.update(status="failed", failure={"type": type(error).__name__,
                            "reason": str(error) if isinstance(error, VerificationFailure) else "Local verification could not complete"})
            raise
        finally:
            evidence["finished_at_utc"] = utc_now()
            path = self.evidence_dir/(phase+"_resultados.json")
            path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
            self.current_evidence = None
        return {"phase": phase, "status": evidence["status"], "events": len(evidence["events"])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--phase", required=True, choices=("audit", "incident", "permissions", "defaults", "all"))
    parser.add_argument("--secrets", type=Path, help="Private runtime JSON outside Git")
    parser.add_argument("--evidence-dir", type=Path, help="Public evidence directory; contains counts/roles/results only")
    args = parser.parse_args()
    try:
        harness = Harness(secret_file=args.secrets, evidence_dir=args.evidence_dir)
        phases = ("permissions", "defaults", "audit", "incident") if args.phase == "all" else (args.phase,)
        summaries = [harness.run_phase(phase) for phase in phases]
    except (ConfigurationError, VerificationFailure, DatabaseError):
        print(json.dumps({"status": "failed", "reason": "Verification stopped; inspect the sanitized phase evidence"}), file=sys.stderr)
        return 1
    except Exception:
        print(json.dumps({"status": "failed", "reason": "Local verification could not complete"}), file=sys.stderr)
        return 1
    print(json.dumps({"status": "passed", "phases": summaries}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

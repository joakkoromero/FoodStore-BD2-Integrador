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

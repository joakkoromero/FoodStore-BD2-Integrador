# Fuentes saneadas para revisión estática: Unidad6

No ejecutar estas copias. Los literales personales/de carga se sustituyeron por placeholders; las comprobaciones en motor usarán las fuentes originales locales. Señalar archivo/línea y distinguir errores confirmables de hipótesis.

## outputs\Arancibia_Romero_U6\food-store-tp-u6\tools\opencode_consulta.py

SHA256 original: 7baa7379b6d90be470ef62d393744e588b1997e7ae3ab79fa40191690b49b1c6
SHA256 saneado: 8f5ae01928127a6d906190551ef9b8b3539a85c34e57caac20e6226482932d73

`````py
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
"""Run an actual, tool-denied OpenCode consultation and retain its provenance.

Only supply material already sanitized for disclosure. The complete event stream
and diagnostic output are stored outside this repository; the repository receives
the exact prompt, answer text, and non-secret run metadata. This program does not
execute generated SQL and does not represent technical review as human approval.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


REPOSITORY = Path(__file__).resolve().parents[1]
TASK_ROOT = Path(__file__).resolve().parents[4]
DEFAULT_EXECUTABLE = Path(
    r"C:\Users\ASPIRE LITE 16\AppData\Roaming\npm\node_modules\opencode-ai\bin\opencode.exe"
)
DEFAULT_MODEL = "openai/gpt-6.1-sol"


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
    except ValueError:
        return False
    return True


def parse_events(raw: str) -> tuple[list[dict], list[str]]:
    events, unparsable = [], []
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            unparsable.append(line)
        else:
            if isinstance(event, dict):
                events.append(event)
            else:
                unparsable.append(line)
    return events, unparsable


def extract_answer(events: list[dict]) -> str:
    chunks = []
    for event in events:
        if event.get("type") != "text":
            continue
        part = event.get("part", {})
        text = part.get("text") if isinstance(part, dict) else None
        if isinstance(text, str) and text.strip():
            chunks.append(text)
    return "\n\n".join(chunks).strip()


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prefix", required=True,
                        help="Artifact label, for example d or a_revision")
    parser.add_argument("--prompt-file", type=Path, required=True)
    parser.add_argument("--file", dest="attachments", type=Path,
                        action="append", default=[],
                        help="Previously sanitized context attachment; repeatable")
    parser.add_argument("--executable", type=Path, default=DEFAULT_EXECUTABLE)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--working-dir", type=Path,
                        default=TASK_ROOT / "work/unidad6/opencode")
    parser.add_argument("--output-dir", type=Path,
                        default=REPOSITORY / "docs/ia")
    parser.add_argument("--private-dir", type=Path,
                        default=TASK_ROOT / "work/unidad6/private/opencode")
    parser.add_argument("--timeout", type=int, default=600)
    parser.add_argument("--retry-failed", action="store_true",
                        help="Retry an unsuccessful consultation, preserving its metadata privately")
    return parser.parse_args()


def main() -> int:
    args = arguments()
    if not re.fullmatch(r"[a-z][a-z0-9_]*", args.prefix):
        raise SystemExit("Invalid artifact prefix")
    if is_within(args.private_dir, REPOSITORY):
        raise SystemExit("Raw events must be stored outside the deliverable repository")
    if not args.executable.is_file() or not args.prompt_file.is_file():
        raise SystemExit("Missing executable or prompt file")
    for attachment in args.attachments:
        if not attachment.is_file():
            raise SystemExit("A sanitized attachment does not exist")
    if args.timeout < 1:
        raise SystemExit("Timeout must be positive")

    prompt = args.prompt_file.read_text(encoding="utf-8")
    if not prompt.strip():
        raise SystemExit("Empty prompt")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.private_dir.mkdir(parents=True, exist_ok=True)
    args.working_dir.mkdir(parents=True, exist_ok=True)
    prompt_output = args.output_dir / f"{args.prefix}_prompt.txt"
    answer_output = args.output_dir / f"{args.prefix}_respuesta.md"
    metadata_output = args.output_dir / f"{args.prefix}_metadatos.json"
    prior_attempts = []
    if any(path.exists() for path in (answer_output, metadata_output)):
        if not args.retry_failed or answer_output.exists() or not metadata_output.exists():
            raise SystemExit("Answer/metadata already exist; use a new prefix for a new consultation")
        previous = json.loads(metadata_output.read_text(encoding="utf-8"))
        if previous.get("status") != "failed":
            raise SystemExit("A completed consultation cannot be retried under the same prefix")
        prior_attempts = previous.get("prior_failed_attempts", []) + [{
            key: previous.get(key) for key in (
                "started_at_utc", "finished_at_utc", "returncode", "timed_out",
                "event_count", "error_event_count", "raw_jsonl_sha256", "status"
            )
        }]
        failed_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
        (args.private_dir / f"{args.prefix}_{failed_id}_previous_metadata.json").write_text(
            json.dumps(previous, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    if prompt_output.resolve() != args.prompt_file.resolve():
        prompt_output.write_text(prompt, encoding="utf-8")

    # Feed immutable byte-for-byte snapshots, so later SQL corrections cannot
    # replace the evidence of what the assistant actually received.
    snapshots = []
    if args.attachments:
        attachment_dir = args.output_dir / f"{args.prefix}_adjuntos"
        attachment_dir.mkdir(parents=True, exist_ok=True)
        for index, original in enumerate(args.attachments, 1):
            snapshot = attachment_dir / f"{index:02d}_{original.name}"
            source = original.read_bytes()
            if snapshot.exists() and snapshot.read_bytes() != source:
                raise SystemExit("An existing attachment snapshot differs; use a new consultation prefix")
            if not snapshot.exists():
                snapshot.write_bytes(source)
            snapshots.append((original, snapshot))

    environment = os.environ.copy()
    environment["OPENCODE_CONFIG_CONTENT"] = json.dumps({"permission": "deny"})
    version = subprocess.run(
        [str(args.executable), "--version"], env=environment,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        shell=False, timeout=30, check=False,
    )
    if version.returncode != 0:
        raise SystemExit("Unable to read installed OpenCode version")
    command = [str(args.executable), "run", prompt, "--pure", "--agent", "plan",
               "--format", "json", "--model", args.model,
               "--dir", str(args.working_dir.resolve())]
    for original, snapshot in snapshots:
        command.extend(["--file", str(snapshot.resolve())])

    started = utc_now()
    identifier = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    raw_output = args.private_dir / f"{args.prefix}_{identifier}.jsonl"
    raw_errors = args.private_dir / f"{args.prefix}_{identifier}.stderr.txt"
    timed_out = False
    try:
        completed = subprocess.run(
            command, env=environment, capture_output=True, text=True,
            encoding="utf-8", errors="replace", shell=False,
            timeout=args.timeout, check=False,
        )
        stdout, stderr, returncode = (
            completed.stdout, completed.stderr, completed.returncode
        )
    except subprocess.TimeoutExpired as error:
        timed_out = True
        stdout = error.stdout or ""
        stderr = error.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode("utf-8", errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode("utf-8", errors="replace")
        returncode = None
    raw_output.write_text(stdout, encoding="utf-8")
    raw_errors.write_text(stderr, encoding="utf-8")
    events, invalid = parse_events(stdout)
    answer = extract_answer(events)
    errors = [event for event in events if event.get("type") == "error"]
    tool_events = [event for event in events
                   if event.get("type") in {"tool_use", "tool"}]
    successful = returncode == 0 and bool(answer) and not errors and not timed_out
    if answer:
        answer_output.write_text(answer + "\n", encoding="utf-8")
    attachments = []
    for original, snapshot in snapshots:
        item = {"name": original.name, "sha256": sha256(snapshot)}
        if is_within(snapshot, REPOSITORY):
            item["repository_path"] = snapshot.resolve().relative_to(REPOSITORY).as_posix()
        if is_within(original, REPOSITORY):
            item["source_path_at_consultation"] = original.resolve().relative_to(REPOSITORY).as_posix()
        attachments.append(item)
    metadata = {
        "tool": "OpenCode",
        "installed_version": version.stdout.strip(),
        "requested_model": args.model,
        "agent": "plan", "pure": True,
        "permission_config": {"permission": "deny"},
        "started_at_utc": started, "finished_at_utc": utc_now(),
        "prompt_sha256": sha256(prompt_output),
        "attachments": attachments,
        "returncode": returncode, "timed_out": timed_out,
        "event_count": len(events), "unparsed_line_count": len(invalid),
        "error_event_count": len(errors), "tool_event_count": len(tool_events),
        "answer_sha256": sha256(answer_output) if answer_output.exists() else None,
        "raw_jsonl_sha256": sha256(raw_output),
        "raw_event_storage": "Private work directory outside deliverable repository",
        "status": "completed" if successful else "failed",
        "prior_failed_attempts": prior_attempts,
        "sql_executed": False,
        "human_validation": "Pending; this consultation does not establish human approval",
    }
    metadata_output.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    # Never print raw output, errors, authentication material, or environment.
    print(json.dumps({"prefix": args.prefix, "status": metadata["status"],
                      "model": args.model, "event_count": len(events),
                      "answer_characters": len(answer)}, ensure_ascii=False))
    return 0 if successful else 1


if __name__ == "__main__":
    sys.exit(main())

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\tools\ps_common.ps1

SHA256 original: bc5a4e87493312e4954d2e4849d756576fe6566c0256e902b4d770f1add81392
SHA256 saneado: f2ae054f5a0c31e696a9834978f27b4ff9e0b28d4ebf50c3f88ec5e6e906761b

`````ps1
# COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
# La estructura se conserva; literales personales/de carga pueden ser placeholders.
# Funciones comunes factorizadas de la propuesta real OpenCode u6_generacion.
# Integracion/revision automatica Codex; no equivalen a prueba de ejecucion.
foreach ($key in @('PGHOSTADDR','PGSERVICE','PGSERVICEFILE','PGOPTIONS','PGPASSWORD')) {
    Remove-Item -LiteralPath "Env:$key" -ErrorAction SilentlyContinue
}
$env:PGCLIENTENCODING = 'UTF8'
function Log([string]$Text) {
    $line = "$([DateTimeOffset]::UtcNow.ToString('o')) $Text"
    if ($null -ne $log) { $log.WriteLine($line) }
    [Console]::Error.WriteLine($line)
}
function New-Writer([string]$Path) {
    $stream = [IO.File]::Open($Path, 'CreateNew', 'Write', 'None')
    [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
}
function Assert-Private([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Ruta redirigida.' }
    $allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
    foreach ($ace in (Get-Acl -LiteralPath $Path).Access) {
        $sid = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if ($ace.AccessControlType -eq 'Allow' -and $sid -notin $allowed) { throw 'ACL no privada.' }
    }
    $parent = if ($item.PSIsContainer) { $item } else { $item.Directory }
    for ($d=$parent; $null -ne $d; $d=$d.Parent) {
        if (($d.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            (Test-Path -LiteralPath (Join-Path $d.FullName '.git'))) {
            throw 'Material privado dentro de Git o ruta redirigida.'
        }
    }
}
function Pg([string]$Name, [string[]]$Arguments) {
    $output = & (Join-Path $PgBin "$Name.exe") @Arguments 2>$null
    $code = $LASTEXITCODE
    if ($code -ne 0) { Log "FAILED native=$Name code=$code"; throw "${Name}: codigo $code" }
    $output
}
function Assert-Baseline($Value) {
    $tables = @('categoria','producto','usuario','pedido','detalle_pedido')
    $sets = @{ counts=$tables; fingerprints=$tables; invalid=@('productos','detalles') }
    if ($Value -isnot [Collections.IDictionary] -or $Value.Count -ne 3) { throw 'JSON base invalido.' }
    foreach ($section in $sets.Keys) {
        $part = $Value[$section]
        if ($part -isnot [Collections.IDictionary] -or $part.Count -ne $sets[$section].Count) {
            throw 'Claves invalidas.'
        }
        foreach ($key in $sets[$section]) {
            if (-not $part.Contains($key)) { throw 'Falta clave.' }
            $v = $part[$key]
            if ($section -eq 'fingerprints') {
                if ($v -isnot [string] -or $v -cnotmatch '^[0-9a-f]{32}$') { throw 'Huella invalida.' }
            } elseif (($v -isnot [long] -and $v -isnot [int]) -or $v -lt 0 -or
                      ($section -eq 'invalid' -and $v -ne 0)) { throw 'Conteo o integridad invalidos.' }
        }
    }
}
function Assert-Isolation([string[]]$PsqlArguments, [string]$RoleLiterals) {
    $check = @'
SELECT (d.datconnlimit=0 AND NOT EXISTS (
 SELECT 1 FROM pg_catalog.pg_roles r WHERE r.rolname IN (__LITERALS__)
 AND (pg_catalog.has_database_privilege(r.rolname,d.datname,'CONNECT')
   OR pg_catalog.has_database_privilege(r.rolname,d.datname,'TEMPORARY'))
) AND NOT EXISTS (
 SELECT 1 FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_namespace n
 WHERE r.rolname IN (__LITERALS__) AND n.nspname !~ '^pg_'
 AND n.nspname<>'information_schema'
 AND (pg_catalog.has_schema_privilege(r.rolname,n.oid,'USAGE')
   OR pg_catalog.has_schema_privilege(r.rolname,n.oid,'CREATE'))
) AND NOT EXISTS (
 SELECT 1 FROM pg_catalog.pg_roles r CROSS JOIN pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE r.rolname IN (__LITERALS__) AND n.nspname !~ '^pg_'
 AND n.nspname<>'information_schema'
 AND pg_catalog.has_function_privilege(r.rolname,p.oid,'EXECUTE')
))::int FROM pg_catalog.pg_database d WHERE d.datname=current_database();
'@
    $check = $check.Replace('__LITERALS__',$RoleLiterals)
    if ((Pg 'psql' ($PsqlArguments + @('-c',$check)) | Out-String).Trim() -ne '1') {
        throw 'Aislamiento final no verificado.'
    }
}
function New-RunToken {
    $stamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ',
        [Globalization.CultureInfo]::InvariantCulture)
    "$stamp`_$([guid]::NewGuid().ToString('N'))"
}
function Assert-Clients([string[]]$Names) {
    foreach ($name in $Names) {
        $version = Pg $name @('--version') | Out-String
        if ($version -notmatch '\(PostgreSQL\) 17(?:\.|\s|$)') { throw 'Se requieren clientes 17.' }
    }
}
function Read-BackupManifest {
    $candidates = @(foreach ($file in Get-ChildItem -LiteralPath $LogDir -Filter '*.manifest.json' -File) {
        Assert-Private $file.FullName
        $m = Get-Content -LiteralPath $file.FullName -Raw |
            ConvertFrom-Json -AsHashtable -DateKind String
        if ($m.status -ceq 'SUCCESS') {
            $end = [DateTimeOffset]::ParseExact($m.endUtc,'o',[Globalization.CultureInfo]::InvariantCulture)
            [pscustomobject]@{ Manifest=$m; End=$end }
        }
    })
    if ($candidates.Count -eq 0) { throw 'No hay manifiesto exitoso.' }
    $chosen = $candidates | Sort-Object End -Descending | Select-Object -First 1
    $m = $chosen.Manifest
    $start = [DateTimeOffset]::ParseExact($m.startUtc,'o',[Globalization.CultureInfo]::InvariantCulture)
    if ($m.database -cne 'foodstore' -or $start.Offset -ne [TimeSpan]::Zero -or
        $chosen.End.Offset -ne [TimeSpan]::Zero -or $chosen.End -lt $start -or
        $chosen.End -gt [DateTimeOffset]::UtcNow) { throw 'Metadatos temporales invalidos.' }
    $pattern = '^foodstore_[0-9]{8}T[0-9]{13}Z_[0-9a-f]{32}\.dump$'
    if ($m.file -isnot [string] -or $m.file -cnotmatch $pattern) { throw 'Nombre no permitido.' }
    if (($m.size -isnot [long] -and $m.size -isnot [int]) -or $m.size -le 0 -or
        $m.sha256 -isnot [string] -or $m.sha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'Tamano o hash invalido.'
    }
    Assert-Baseline $m.baseline
    $dump = Join-Path $BackupDir $m.file
    Assert-Private $dump
    $hash = (Get-FileHash -LiteralPath $dump -Algorithm SHA256).Hash.ToLowerInvariant()
    if ((Get-Item -LiteralPath $dump).Length -ne $m.size -or $hash -cne $m.sha256) {
        throw 'Respaldo alterado.'
    }
    Pg 'pg_restore' @('--list',$dump) | Out-Null
    [pscustomobject]@{ Manifest=$m; Start=$start; Dump=$dump }
}

`````

## outputs\Arancibia_Romero_U6\food-store-tp-u6\validaciones.sql

SHA256 original: 8198129eaf53a1e96e432a02c0659f5c4eb7d094de2e05ad9deb022e1cb53849
SHA256 saneado: e94a54cf47471f2bf6f5ccd2b60ca6d7a4c4ddcb89cdf7622b1b2d1bc3e185e3

`````sql
-- COPIA SANEADA PARA CODE REVIEW; NO EJECUTAR.
-- La estructura se conserva; literales personales/de carga pueden ser placeholders.
-- Unidad 6 - Food Store. Exequiel Arancibia / Joaquin Romero.
-- Implementacion tecnica: Codex. Ejecutar con psql -X -w -A -t
-- -v ON_ERROR_STOP=1 -d foodstore[..._restore_test] -f validaciones.sql.
-- stdout: UN objeto JSON con counts, fingerprints, invalid. Sin filas ni PII.
-- La guia llama cliente a la entidad que aqui conserva public.usuario.
\set ON_ERROR_STOP on
\set QUIET 1
\pset pager off

BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY;
SET LOCAL search_path = pg_catalog;
SET LOCAL TIME ZONE 'America/Argentina/Buenos_Aires';
SET LOCAL DateStyle = 'ISO, YMD';
SET LOCAL application_name = 'u6_validaciones';

DO $base_correcta$
BEGIN
    IF pg_catalog.current_database() NOT IN ('foodstore','foodstore_restore_test') THEN
        RAISE EXCEPTION USING ERRCODE = '22023',
            MESSAGE = 'validaciones.sql requiere foodstore o foodstore_restore_test';
    END IF;
END
$base_correcta$;

-- Una instantanea por ejecucion evita mezclar conteos de varios instantes.
-- El orquestador debe evitar escritores entre baseline y snapshot del dump,
-- o compartir expresamente un snapshot exportado. Este archivo no lo presume.
-- Las huellas siguen U5: MD5 de la concatenacion ordenada de MD5 de cada fila
-- completa en JSON. Son checksums de conservacion, no anonimato ni firma.
-- Se fija zona/DateStyle para que timestamps tengan la misma representacion.
WITH categorias AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.categoria AS t
), productos AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.count(*) FILTER (WHERE t.precio < 0 OR t.stock < 0) AS invalidos,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.producto AS t
), usuarios AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.usuario AS t
), pedidos AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),'' ORDER BY t.id),'')) AS huella
    FROM public.pedido AS t
), detalles AS (
    SELECT pg_catalog.count(*) AS n,
           pg_catalog.count(*) FILTER (WHERE t.cantidad <= 0 OR t.precio_unitario < 0) AS invalidos,
           pg_catalog.md5(COALESCE(pg_catalog.string_agg(
               pg_catalog.md5(pg_catalog.row_to_json(t)::text),''
               ORDER BY t.pedido_id,t.producto_id),'')) AS huella
    FROM public.detalle_pedido AS t
)
SELECT pg_catalog.jsonb_build_object(
    'counts', pg_catalog.jsonb_build_object(
        'categoria',c.n,'producto',pr.n,'usuario',u.n,'pedido',pe.n,'detalle_pedido',d.n),
    'fingerprints', pg_catalog.jsonb_build_object(
        'categoria',c.huella,'producto',pr.huella,'usuario',u.huella,
        'pedido',pe.huella,'detalle_pedido',d.huella),
    'invalid', pg_catalog.jsonb_build_object('productos',pr.invalidos,'detalles',d.invalidos)
) AS validacion
FROM categorias AS c CROSS JOIN productos AS pr CROSS JOIN usuarios AS u
CROSS JOIN pedidos AS pe CROSS JOIN detalles AS d;

COMMIT;

-- No agregar metadata variable a este JSON: los scripts registran fecha/base
-- y comparan los cinco counts/fingerprints y los dos ceros de forma explicita.
-- precio, stock, cantidad y precio_unitario son NOT NULL en el modelo real;
-- las condiciones invalid conservan exactamente los controles de la guia.

`````

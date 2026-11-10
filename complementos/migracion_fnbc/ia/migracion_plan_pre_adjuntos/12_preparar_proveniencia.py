"""Codex reproducibility helper: create a real review index; never opens a DB."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SPEC_COMMIT = "89f81022a2c103493d501b43e951eade62dde34f"
SOURCE_NAMES = ("preparar.sql", "migrar.sql", "revertir.sql", "reproducir.py",
                "README.md", "preparar_proveniencia.py")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def record(path):
    path = path.resolve(strict=True)
    if not path.is_relative_to(ROOT) or not path.is_file():
        raise ValueError("Review path outside repository")
    return {"path": path.relative_to(ROOT).as_posix(), "sha256": sha(path)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--plan-prefix", default="migracion_plan_pre")
    parser.add_argument("--coverage", type=Path,
                        default=HERE / "ia/plan_cobertura_fuentes.json")
    parser.add_argument("--permitir-ejecucion-tecnica", action="store_true")
    args = parser.parse_args()
    if not args.permitir_ejecucion_tecnica:
        raise ValueError("Read the real Plan findings before setting the technical decision")
    if not args.plan_prefix.replace("_", "").isalnum():
        raise ValueError("Unsafe Plan prefix")
    completed = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "HEAD"],
                               capture_output=True, check=True, text=True)
    head = completed.stdout.strip()
    coverage_path = args.coverage
    if not coverage_path.is_absolute():
        coverage_path = ROOT / coverage_path
    coverage = json.loads(coverage_path.read_text(encoding="utf-8"))
    sources = {record(HERE / name)["path"]: sha(HERE / name)
               for name in SOURCE_NAMES}
    if coverage.get("reviewed_sources_sha256") != sources:
        raise ValueError("Plan coverage does not match the exact current source bytes")
    def bundle(prefix):
        directory = HERE / "ia"
        result = {kind: record(directory / (prefix + suffix))
                  for kind, suffix in (("prompt", "_prompt.txt"),
                                       ("answer", "_respuesta.md"),
                                       ("metadata", "_metadatos.json"))}
        metadata = json.loads((ROOT / result["metadata"]["path"]).read_text(encoding="utf-8"))
        if not (metadata.get("status") == "completed" and metadata.get("pure") is True
                and metadata.get("permission_config") == {"permission": "deny"}
                and metadata.get("tool_event_count") == 0
                and metadata.get("error_event_count") == 0):
            raise ValueError("Actual OpenCode consultation is not completed/pure/zero-tools")
        return result
    index = {
        "code_commit_before_execution": head,
        "kiro_spec_commit": SPEC_COMMIT,
        "kiro_specs": [record(ROOT / "docs/kiro_migracion" / name)
                       for name in ("requirements.md", "design.md", "tasks.md")],
        "codex_prebuild_notes": [record(ROOT / "docs/kiro_migracion/ACLARACIONES_CODEX.md"),
                                record(HERE / "DECISIONES_PREVIAS.md"),
                                record(HERE / "CONTRATO_PRUEBAS.json")],
        "build": bundle("migracion_build"),
        "plan": bundle(args.plan_prefix),
        "plan_coverage": record(coverage_path),
        "technical_decision_codex": "allow_execution",
        "human_review_claimed": False,
    }
    destination = args.output.resolve()
    destination.parent.mkdir(parents=True, exist_ok=True)
    with destination.open("x", encoding="utf-8", newline="\n") as handle:
        json.dump(index, handle, ensure_ascii=True, indent=2)
        handle.write("\n")
    print("Review index created from existing real artifacts; no database connection.")


if __name__ == "__main__":
    main()

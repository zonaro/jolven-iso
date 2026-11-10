"""Small, read-only Nobara ISO preflight tool.

No mounting, extraction, privilege elevation or execution of untrusted data.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

from .remaster import RemasterError, prerequisites, remaster_iso
from .overlay import OverlayError
from .profile import ProfileError
from .extras import ExtrasError

EDITIONS = {"official", "gnome", "kde", "steam-htpc", "steam-handheld"}
EXTRAS = {"sunshine", "retroarch", "uzdoom", "eden", "cemu", "openrgb"}
HASH_PATTERN = re.compile(r"^[a-fA-F0-9]{64}$")
COLOR_PATTERN = re.compile(r"^#[a-fA-F0-9]{6}$")
SECRET_KEY_PATTERN = re.compile(
    r"(^|[_-])(api[_-]?key|password|credential|secret|token|private[_-]?key)($|[_-])",
    re.IGNORECASE,
)


class PreflightError(ValueError):
    """Unsupported or unsafe input."""


def iso9660_signature(path: Path) -> bool:
    """ISO-9660 primary volume descriptor begins at sector 16."""
    with path.open("rb") as stream:
        stream.seek(16 * 2048 + 1)
        return stream.read(5) == b"CD001"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def check_iso(path: Path) -> dict:
    if not path.is_file() or path.suffix.lower() != ".iso":
        raise PreflightError("Informe um arquivo .iso existente.")
    if not iso9660_signature(path):
        raise PreflightError("Não parece uma imagem ISO-9660 válida.")
    return {"path": str(path.resolve()), "bytes": path.stat().st_size, "iso9660": True}


def verify_iso(path: Path, expected_sha256: str) -> dict:
    metadata = check_iso(path)
    if not HASH_PATTERN.fullmatch(expected_sha256):
        raise PreflightError("SHA-256 esperado deve conter 64 caracteres hexadecimais.")
    actual = sha256_file(path)
    metadata["actual_sha256"] = actual
    metadata["matches_supplied_sha256"] = actual == expected_sha256.lower()
    metadata["provenance_verified"] = False
    if not metadata["matches_supplied_sha256"]:
        raise PreflightError("SHA-256 divergente: arquivo não corresponde ao valor esperado.")
    return metadata


def reject_secret_keys(value: object, location: str = "root") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if not isinstance(key, str):
                raise PreflightError(f"Chave não textual em {location}")
            if SECRET_KEY_PATTERN.search(key):
                raise PreflightError(f"Credenciais não podem ser salvas no projeto: {location}.{key}")
            reject_secret_keys(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_secret_keys(child, f"{location}[{index}]")


def validate_project(data: dict) -> dict:
    if not isinstance(data, dict):
        raise PreflightError("Projeto deve ser um objeto JSON.")
    reject_secret_keys(data)
    if data.get("schema_version") != 1 or data.get("distribution") != "nobara":
        raise PreflightError("Versão de projeto ou distribuição incompatível.")
    if data.get("edition") not in EDITIONS:
        raise PreflightError("Edição Nobara não suportada.")
    if data.get("jolven_session") is not True:
        raise PreflightError("Jolven Session deve permanecer selecionada.")
    extras = data.get("extras")
    if not isinstance(extras, list) or any(not isinstance(x, str) or x not in EXTRAS for x in extras):
        raise PreflightError("Lista de aplicativos extras não é válida.")
    appearance = data.get("appearance")
    if not isinstance(appearance, dict) or not isinstance(appearance.get("theme"), str):
        raise PreflightError("Aparência inválida.")
    if not COLOR_PATTERN.fullmatch(appearance.get("accent_hex", "")):
        raise PreflightError("Cor deve estar no formato #RRGGBB.")
    src = data.get("source_iso")
    expected = data.get("expected_sha256")
    calculated = data.get("source_sha256")
    if not isinstance(src, str) or not src:
        raise PreflightError("Caminho da ISO ausente.")
    if not isinstance(expected, str) or not isinstance(calculated, str):
        raise PreflightError("Hash SHA-256 ausente.")
    if not HASH_PATTERN.fullmatch(expected) or calculated.lower() != expected.lower():
        raise PreflightError("Hash do projeto não confere com o esperado.")
    # Reject unexpected fields rather than inadvertently accepting embedded secrets.
    allowed = {
        "schema_version", "distribution", "edition", "source_iso",
        "source_sha256", "expected_sha256", "jolven_session", "extras", "appearance",
    }
    if set(data) != allowed or set(appearance) != {"theme", "accent_hex"}:
        raise PreflightError("Projeto contém campos desconhecidos.")
    return data


def plan_project(path: Path) -> dict:
    try:
        project = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise PreflightError(f"Não foi possível ler projeto JSON: {exc}") from exc
    project = validate_project(project)
    verification = verify_iso(Path(project["source_iso"]), project["expected_sha256"])
    return {
        "status": "preflight_only",
        "compose_available": False,
        "distribution": "nobara",
        "edition": project["edition"],
        "jolven_session": True,
        "requested_extras": sorted(set(project["extras"])),
        "appearance": project["appearance"],
        "source": verification,
        "notes": [
            "O hash foi comparado com o valor fornecido pelo usuário, não autenticado via catálogo oficial.",
            "O programa ainda não modifica nem produz imagens ISO.",
            "Credenciais não são aceitas em arquivos de projeto.",
        ],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Jolven ISO preflight, sem remasterização")
    commands = parser.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect", help="Inspecionar metadados básicos ISO-9660")
    inspect.add_argument("--iso", type=Path, required=True)
    verify = commands.add_parser("verify", help="Conferir SHA-256 informado")
    verify.add_argument("--iso", type=Path, required=True)
    verify.add_argument("--sha256", required=True)
    plan = commands.add_parser("plan", help="Validar JSON e gerar plano somente-leitura")
    plan.add_argument("--project", type=Path, required=True)
    commands.add_parser("requirements", help="Requisitos do compositor Linux experimental")
    compose = commands.add_parser("compose", help="Gerar ISO experimental sem validação de boot")
    compose.add_argument("--project", type=Path, required=True)
    compose.add_argument("--jolven-archive", type=Path, required=True)
    compose.add_argument("--jolven-sha256", required=True)
    compose.add_argument("--output", type=Path, required=True)
    compose.add_argument("--workspace-dir", type=Path,
      help="Linux filesystem workspace, e.g. /tmp on WSL2")
    compose.add_argument("--experimental", action="store_true")
    compose.add_argument("--accept-unverified-provenance", action="store_true",
      help="Confirmo que obtive ISO e checksum de uma fonte oficial confiável")
    options = parser.parse_args(argv)
    try:
        if options.command == "inspect":
            result = check_iso(options.iso)
        elif options.command == "verify":
            result = verify_iso(options.iso, options.sha256)
        elif options.command == "plan":
            result = plan_project(options.project)
        elif options.command == "requirements":
            result = prerequisites()
        else:
            if not options.accept_unverified_provenance:
                raise PreflightError(
                    "Composição requer confirmação explícita da procedência do SHA oficial."
                )
            if not options.experimental:
                raise PreflightError(
                    "Remasterização ainda sem testes reais: use --experimental."
                )
            project = plan_project(options.project)
            result = remaster_iso(
                Path(project["source"]["path"]), options.output,
                jolven_archive=options.jolven_archive,
                jolven_sha256=options.jolven_sha256,
                appearance=project['appearance'],
                extras=project['requested_extras'],
                workspace_dir=options.workspace_dir,
                experimental=True,
            )
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (OSError, PreflightError, OverlayError, RemasterError, ProfileError, ExtrasError) as exc:
        print(f"Erro: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

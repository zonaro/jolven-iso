"""Optional application selection, staged for setup on installed Nobara.

No silent package installation during ISO build or live boot. The local user
chooses when to run the included privileged installer after disk install.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

# Candidate DNF package names, NOT availability guarantees. Only install
# after an exact repoquery match against the target machine's enabled repos.
PACKAGES = {
    "sunshine": "sunshine",
    "retroarch": "retroarch",
    "uzdoom": "uzdoom",
    "eden": "eden",
    "cemu": "cemu",
    "openrgb": "openrgb",
}
PLAN = "usr/share/jolven-iso/optional-packages.json"
SCRIPT = "usr/libexec/jolven-iso-install-extras"

_INSTALLER = r'''#!/usr/bin/python3
"""Interactive post-install helper; never runs automatically in live boot."""
import json
import os
import subprocess
import sys
from pathlib import Path

PLAN = Path("/usr/share/jolven-iso/optional-packages.json")
ALLOWED = {"sunshine", "retroarch", "uzdoom", "eden", "cemu", "openrgb"}

def run(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True, check=False)

def main():
    if os.geteuid() != 0:
        print("Execute após instalar o Nobara: sudo /usr/libexec/jolven-iso-install-extras",
              file=sys.stderr)
        return 77
    if not PLAN.is_file():
        print("Nenhum pacote opcional selecionado.")
        return 0
    requested = json.loads(PLAN.read_text(encoding="utf-8"))
    if not isinstance(requested, list) or any(
        not isinstance(pkg, str) or pkg not in ALLOWED for pkg in requested
    ):
        print("Plano de extras corrompido; instalação recusada.", file=sys.stderr)
        return 2
    requested = sorted(set(requested))
    if not requested:
        print("Sem pacotes opcionais selecionados.")
        return 0
    print("Aplicativos solicitados:", ", ".join(requested))
    if "--yes" not in sys.argv[1:]:
        try:
            response = input("Consultar os repositórios Nobara e instalar disponíveis? [s/N] ")
        except EOFError:
            return 1
        if response.strip().lower() not in ("s", "sim", "y", "yes"):
            print("Cancelado.")
            return 1
    outcomes = {}
    for package in requested:
        if run(["rpm", "-q", package]).returncode == 0:
            outcomes[package] = "already_installed"
            continue
        result = run(["dnf", "repoquery", "--available", "--qf", "%{name}", package])
        if result.returncode or package not in result.stdout.splitlines():
            print(f"{package}: indisponível nos repositórios habilitados.")
            outcomes[package] = "unavailable"
            continue
        result = run(["dnf", "install", "-y", package])
        outcomes[package] = "installed" if result.returncode == 0 else "failed"
    status = Path("/var/lib/jolven-iso/extras-status.json")
    status.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    status.write_text(json.dumps(outcomes, indent=2) + "\n", encoding="utf-8")
    print("Resultado:", json.dumps(outcomes, ensure_ascii=False))
    return 1 if "failed" in outcomes.values() else 0

if __name__ == "__main__":
    raise SystemExit(main())
'''


class ExtrasError(ValueError):
    pass


def write_optional_extras(root: Path, extras: list[str]) -> dict:
    if not isinstance(extras, list) or any(
        not isinstance(x, str) or x not in PACKAGES for x in extras
    ):
        raise ExtrasError("Requested extras contain unsupported package names.")
    selected = sorted(set(extras))
    if not selected:
        return {"requested": [], "helper": None}
    root = root.resolve(strict=True)
    if not (root / "usr").is_dir():
        raise ExtrasError("Not a Linux root filesystem.")
    for rel in (PLAN, SCRIPT):
        target = root / rel
        for path in (target, *target.parents):
            if path == root.parent:
                break
            if path.is_symlink():
                raise ExtrasError("Refusing to write extras through symlinks.")
        if target.exists():
            raise ExtrasError("Refusing to overwrite an existing extras payload.")
    manifest = root / PLAN
    executable = root / SCRIPT
    manifest.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    executable.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    manifest.write_text(json.dumps(selected, indent=2) + "\n", encoding="utf-8")
    executable.write_text(_INSTALLER, encoding="utf-8")
    os.chmod(manifest, 0o644)
    os.chmod(executable, 0o755)
    return {
        "requested": selected,
        "helper": "/" + SCRIPT,
        "execution": "manual_post_install_consent_required",
        "availability": "checked_against_target_dnf_repositories_at_runtime",
    }

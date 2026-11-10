"""Stage optional software setup for new Nobara installations.

The live ISO has no silent package installs. The user explicitly approves an
onboarding dialog after installing GNOME/KDE, and polkit authenticates DNF or
Flatpak changes. Steam sessions keep their autologin untouched; an application
menu entry offers manual setup from a desktop session.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

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
FIRST_RUN = "usr/libexec/jolven-iso-first-run"
AUTOSTART = "etc/xdg/autostart/jolven-iso-setup.desktop"
LAUNCHER = "usr/share/applications/jolven-iso-setup.desktop"

_INSTALLER = r'''#!/usr/bin/python3
"""Interactive post-install helper, never automatically run as root."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

PLAN = Path("/usr/share/jolven-iso/optional-packages.json")
ALLOWED = {"sunshine", "retroarch", "uzdoom", "eden", "cemu", "openrgb"}
FLATPAK = {
    "sunshine": "dev.lizardbyte.app.Sunshine",
    "retroarch": "org.libretro.RetroArch",
    "eden": "dev.eden_emu.eden",
    "cemu": "info.cemu.Cemu",
    "openrgb": "org.openrgb.OpenRGB",
}

def run(cmd):
    try:
        return subprocess.run(cmd, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True, check=False)
    except OSError:
        return None

def available_dnf(package):
    result = run(["dnf", "repoquery", "--available", "--qf", "%{name}", package])
    return result is not None and result.returncode == 0 and (
        package in result.stdout.splitlines()
    )

def available_flatpak(app_id):
    if shutil.which("flatpak") is None:
        return False
    result = run(["flatpak", "remote-info", "--system", "flathub", app_id])
    return result is not None and result.returncode == 0

def main():
    if os.geteuid() != 0:
        print("Execute após instalar Nobara: sudo /usr/libexec/jolven-iso-install-extras",
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
        return 0
    print("Aplicativos solicitados:", ", ".join(requested))
    if "--yes" not in sys.argv[1:]:
        try:
            response = input(
                "Consultar repositórios Nobara e instalar disponíveis? [s/N] "
            )
        except EOFError:
            return 1
        if response.strip().lower() not in ("s", "sim", "y", "yes"):
            print("Cancelado.")
            return 1

    outcomes = {}
    for package in requested:
        installed_rpm = run(["rpm", "-q", package])
        if installed_rpm is not None and installed_rpm.returncode == 0:
            outcomes[package] = "already_installed"
            continue
        if available_dnf(package):
            result = run(["dnf", "install", "-y", package])
            outcomes[package] = (
                "installed_dnf" if result is not None and
                result.returncode == 0 else "failed_dnf"
            )
            continue
        app_id = FLATPAK.get(package)
        if app_id and available_flatpak(app_id):
            installed = run(["flatpak", "info", "--system", app_id])
            if installed is not None and installed.returncode == 0:
                outcomes[package] = "already_installed_flatpak"
                continue
            result = run([
                "flatpak", "install", "--system", "--assumeyes", "flathub", app_id
            ])
            outcomes[package] = (
                "installed_flatpak" if result is not None and
                result.returncode == 0 else "failed_flatpak"
            )
        else:
            outcomes[package] = "unavailable"
            print(f"{package}: indisponível no DNF/Flathub habilitados.")

    status = Path("/var/lib/jolven-iso/extras-status.json")
    status.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    status.write_text(
        json.dumps(outcomes, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8"
    )
    print("Resultado:", json.dumps(outcomes, ensure_ascii=False))
    return 1 if any(v.startswith("failed_") for v in outcomes.values()) else 0

if __name__ == "__main__":
    raise SystemExit(main())
'''

_FIRST_RUN = r'''#!/usr/bin/python3
"""Consent-first desktop onboarding. No installer process in the live ISO."""
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

PLAN = Path("/usr/share/jolven-iso/optional-packages.json")
MARKER = Path.home() / ".config/jolven-iso/first-run-seen"
HELPER = "/usr/libexec/jolven-iso-install-extras"


def on_live_system():
    try:
        cmdline = Path("/proc/cmdline").read_text(encoding="utf-8")
    except OSError:
        return False
    return "root=live:" in cmdline or "rd.live.image" in cmdline or "liveimg" in cmdline


def ask_user(programs):
    text = (
        "Esta edição personalizada do Nobara inclui um plano opcional para "
        + ", ".join(programs)
        + ". Deseja instalar agora pelo DNF/Flatpak? "
        "Será solicitada autenticação administrativa."
    )
    if shutil.which("zenity"):
        return subprocess.run(
            ["zenity", "--question", "--title=Configurar Jolven",
             "--ok-label=Instalar", "--cancel-label=Depois",
             "--text", text], check=False,
        ).returncode == 0
    if shutil.which("kdialog"):
        return subprocess.run(
            ["kdialog", "--title", "Configurar Jolven", "--yesno", text],
            check=False,
        ).returncode == 0
    # On Steam-only sessions without dialog helpers, leave onboarding
    # available through the application menu or manual CLI instead.
    return None


def main():
    if os.geteuid() == 0 or on_live_system() or not PLAN.is_file():
        return 0
    force = "--force" in sys.argv[1:]
    if MARKER.exists() and not force:
        return 0
    requested = json.loads(PLAN.read_text(encoding="utf-8"))
    if not isinstance(requested, list) or not requested:
        return 0
    accepted = ask_user([str(x) for x in requested])
    if accepted is None:
        return 0
    MARKER.parent.mkdir(parents=True, exist_ok=True)
    # A declined prompt should not haunt the user on every login.
    if not accepted:
        MARKER.write_text("deferred\n", encoding="utf-8")
        return 0
    if not shutil.which("pkexec"):
        print("Polkit is unavailable; use the optional setup app later.",
              file=sys.stderr)
        return 69
    result = subprocess.run(["pkexec", HELPER, "--yes"], check=False).returncode
    if result == 0:
        MARKER.write_text("accepted\n", encoding="utf-8")
    return result


if __name__ == "__main__":
    raise SystemExit(main())
'''

_AUTOSTART_DESKTOP = """[Desktop Entry]
Type=Application
Name=Configurar aplicativos opcionais do Jolven
Comment=Pergunta uma vez após a instalação do Nobara
Exec=/usr/libexec/jolven-iso-first-run
OnlyShowIn=GNOME;KDE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
"""

_LAUNCHER_DESKTOP = """[Desktop Entry]
Type=Application
Name=Configurar aplicativos do Jolven
Comment=Instalar apps opcionais escolhidos na ISO
Exec=/usr/libexec/jolven-iso-first-run --force
Categories=Settings;Utility;
Terminal=false
"""


class ExtrasError(ValueError):
    pass


def _check_safe(root: Path, rel: str) -> Path:
    target = root / rel
    current = root
    for component in Path(rel).parts:
        current /= component
        if current.is_symlink():
            raise ExtrasError("Refusing to write through symlinks.")
    if target.exists():
        raise ExtrasError(f"Refusing to overwrite existing file: {rel}")
    return target


def write_optional_extras(root: Path, extras: list[str]) -> dict:
    if not isinstance(extras, list) or any(
        not isinstance(x, str) or x not in PACKAGES for x in extras
    ):
        raise ExtrasError("Unknown optional package requested.")
    selected = sorted(set(extras))
    if not selected:
        return {"requested": [], "helper": None}
    root = root.resolve(strict=True)
    if not (root / "usr").is_dir():
        raise ExtrasError("Not a Linux root filesystem.")
    payload = {
        PLAN: (json.dumps(selected, indent=2) + "\n", 0o644),
        SCRIPT: (_INSTALLER, 0o755),
        FIRST_RUN: (_FIRST_RUN, 0o755),
        AUTOSTART: (_AUTOSTART_DESKTOP, 0o644),
        LAUNCHER: (_LAUNCHER_DESKTOP, 0o644),
    }
    targets = {name: _check_safe(root, name) for name in payload}
    for rel, (content, mode) in payload.items():
        target = targets[rel]
        target.parent.mkdir(parents=True, exist_ok=True)
        fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(content)
        os.chmod(target, mode)
    return {
        "requested": selected,
        "helper": "/" + SCRIPT,
        "onboarding": "/" + FIRST_RUN,
        "autostart": "GNOME/KDE only; skip live boot and Steam sessions",
        "execution": "first_login_user_consent_with_polkit",
        "availability": "DNF/Flathub availability verified on installed system",
    }

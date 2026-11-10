"""System-wide GSettings defaults for the Jolven appearance profile.

A compiled gschema.override changes only defaults for new users and does not
overwrite existing user values. No credentials/tokens are permitted here.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

THEMES = {"Jolven": "jolven", "Adwaita": "adwaita", "Custom": "jolven"}
COLOR = re.compile(r"^#[0-9a-fA-F]{6}$")
SCHEMA_DIR = Path("usr/share/glib-2.0/schemas")
OVERRIDE = "99_jolven_iso.gschema.override"


class ProfileError(ValueError):
    pass


def render_override(appearance: dict) -> str:
    if not isinstance(appearance, dict) or set(appearance) != {"theme", "accent_hex"}:
        raise ProfileError("Appearance keys must be exactly theme and accent_hex.")
    slug = THEMES.get(appearance["theme"])
    accent = appearance["accent_hex"]
    if slug is None or not isinstance(accent, str) or not COLOR.fullmatch(accent):
        raise ProfileError("Unknown theme or invalid #RRGGBB accent.")
    return (
        "[io.github.zonaro.Jolven]\n"
        f"theme-slug='{slug}'\n"
        f"theme-accent-custom='{accent.upper()}'\n"
    )


def apply_appearance(root: Path, appearance: dict) -> str:
    """Requires compiled Jolven GSettings schema inside the root."""
    root = root.resolve(strict=True)
    location = root / SCHEMA_DIR
    current = root
    for component in SCHEMA_DIR.parts:
        current = current / component
        if current.is_symlink():
            raise ProfileError(
                "Refusing to compile schemas through a filesystem symlink."
            )
    if not location.is_dir():
        raise ProfileError("Root lacks GLib schemas directory.")
    name = "io.github.zonaro.Jolven.gschema.xml"
    if not (location / name).exists():
        raise ProfileError("Jolven GSettings XML missing from the archive.")
    override = location / OVERRIDE
    if override.is_symlink():
        raise ProfileError("Refusing to write through a symbolic link.")
    content = render_override(appearance)
    if override.exists() and override.read_text(encoding="utf-8") != content:
        raise ProfileError("Existing unmanaged profile override found.")
    override.write_text(content, encoding="utf-8")
    # Compile in the staged root; never set user dconf/gsettings or run the app.
    completed = subprocess.run(
        ["glib-compile-schemas", str(location)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, check=False,
    )
    if completed.returncode:
        override.unlink(missing_ok=True)
        raise ProfileError(
            "Could not compile GSettings schema defaults: "
            + completed.stdout[-600:]
        )
    return "/" + str(SCHEMA_DIR / OVERRIDE)

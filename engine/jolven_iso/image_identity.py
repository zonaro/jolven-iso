"""Nobara root filesystem identity gate.

ISO-9660 and user-provided hashes alone cannot prove an image is Nobara.
This check rejects Fedora/other distros before we inject or replace files.
It does not authenticate the publisher; that still needs the official catalog.
"""
from __future__ import annotations

import re
from pathlib import Path


class IdentityError(ValueError):
    """The staged image does not identify as a compatible Nobara system."""


_EDITION_NAMES = {
    "official": "Official",
    "gnome": "GNOME",
    "kde": "KDE",
    "steam-htpc": "Steam-HTPC",
    "steam-handheld": "Steam-Handheld",
}

_OFFICIAL_NAME = re.compile(
    r"^Nobara-(?P<release>\d+)-(?P<edition>Official|GNOME|KDE|"
    r"Steam-HTPC|Steam-Handheld)-(?P<date>\d{4}-\d{2}-\d{2})\.iso$"
)


def parse_official_filename(filename: str) -> dict | None:
    """Infer a published filename. Renamed local files cannot be authenticated."""
    match = _OFFICIAL_NAME.fullmatch(filename)
    return match.groupdict() if match else None


def check_selected_edition(filename: str, edition: str) -> dict:
    """A recognizable upstream filename must not contradict the user's edition."""
    if edition not in _EDITION_NAMES:
        raise IdentityError("Unknown Nobara edition.")
    parsed = parse_official_filename(filename)
    if parsed is not None and parsed["edition"] != _EDITION_NAMES[edition]:
        raise IdentityError(
            f"Selected {edition} does not match the source ISO "
            f"({parsed['edition']})."
        )
    return {
        "filename_matches_official_pattern": parsed is not None,
        "edition_matches_filename": parsed is not None,
        "publisher_authenticated": False,
    }


def parse_os_release(text: str) -> dict[str, str]:
    """Parse simple freedesktop os-release key/value lines, no shell expansion."""
    result: dict[str, str] = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            continue
        value = value.strip()
        if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
            value = value[1:-1]
        result[key] = value
    return result


def inspect_nobara_root(root: Path) -> dict:
    """Fail closed unless /etc/os-release explicitly identifies Nobara."""
    release = root / "etc/os-release"
    # /etc/os-release is usually a link to ../usr/lib/os-release.
    if release.is_symlink():
        link = release.readlink()
        # Absolute links are absolute *inside* the staged Linux root,
        # not paths in the build host. Relative links remain relative.
        if link.is_absolute():
            target = (root / str(link).lstrip("/")).resolve()
        else:
            target = (release.parent / link).resolve()
        if not target.is_relative_to(root.resolve()):
            raise IdentityError("os-release points outside staged Linux root.")
        release = target
    elif not release.is_file():
        release = root / "usr/lib/os-release"
    if not release.is_file() or release.stat().st_size > 16_384:
        raise IdentityError("Nobara os-release is absent or oversized.")
    values = parse_os_release(release.read_text(encoding="utf-8"))
    if values.get("ID") != "nobara":
        raise IdentityError(
            "The staged root does not identify as Nobara (ID=nobara)."
        )
    version = values.get("VERSION_ID")
    if not version or not version.isdecimal():
        raise IdentityError("Nobara VERSION_ID is missing or invalid.")
    if int(version) < 44:
        raise IdentityError("This builder supports Nobara 44 and newer only.")
    return {"distribution": "nobara", "version_id": version}

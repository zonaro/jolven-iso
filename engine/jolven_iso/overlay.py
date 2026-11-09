"""Offline, strictly scoped Jolven installation into a mounted Linux root.

The caller must verify the source Nobara ISO and must provide a Jolven archive
with an independently known SHA-256. No network, DNF, or shell here.
"""
from __future__ import annotations

import hashlib
import io
import os
import tarfile
from pathlib import Path, PurePosixPath

SESSION = """[Desktop Entry]
Name=Jolven Session
Comment=Console-style gaming session powered by Jolven
Exec=/usr/bin/jolven-session
TryExec=/usr/bin/jolven-session
Type=Application
X-Jolven-Managed=true
"""

REQUIRED = {
    "usr/bin/jolven",
    "usr/bin/jolven-session",
    "usr/libexec/jolven-game-mode-setup",
}
SESSION_PATH = "usr/share/wayland-sessions/io.github.zonaro.Jolven.GameMode.desktop"
MAX_ARCHIVE_BYTES = 2500 * 1024 * 1024
MAX_MEMBERS = 100_000


class OverlayError(ValueError):
    """Invalid or unsafe Jolven release archive."""


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _safe_path(name: str) -> PurePosixPath:
    if not name or name.startswith("/") or "\x00" in name:
        raise OverlayError("Absolute/empty path in Jolven archive.")
    p = PurePosixPath(name)
    if ".." in p.parts or not p.parts or p.parts[0] != "usr":
        raise OverlayError("Archive entry escapes the usr/ prefix.")
    return p


def inspect_archive(archive: Path, expected_sha: str) -> list[tarfile.TarInfo]:
    if not archive.is_file() or archive.stat().st_size > MAX_ARCHIVE_BYTES:
        raise OverlayError("Jolven archive absent or too large.")
    if len(expected_sha) != 64 or any(c not in "0123456789abcdef" for c in expected_sha.lower()):
        raise OverlayError("Invalid Jolven archive SHA-256.")
    if file_sha256(archive) != expected_sha.lower():
        raise OverlayError("Jolven release checksum mismatch.")
    try:
        with tarfile.open(archive, "r:gz") as tar:
            members = tar.getmembers()
            if len(members) > MAX_MEMBERS:
                raise OverlayError("Jolven archive has too many entries.")
            total = 0
            names = set()
            for member in members:
                path = _safe_path(member.name)
                if not (member.isfile() or member.isdir()):
                    raise OverlayError("Links, devices and special files are not allowed.")
                if member.mode & 0o7000:
                    raise OverlayError("Setuid/setgid/sticky entries are forbidden.")
                if str(path) in names:
                    raise OverlayError("Duplicate archive path.")
                names.add(str(path))
                total += member.size
                if total > MAX_ARCHIVE_BYTES:
                    raise OverlayError("Jolven archive extraction exceeds size limit.")
            if not REQUIRED.issubset(names):
                raise OverlayError("Jolven release lacks required system executables.")
            return members
    except (tarfile.TarError, OSError) as exc:
        raise OverlayError("Invalid Jolven tar.gz release.") from exc


def _no_symlink_parents(target: Path, root: Path) -> None:
    """Refuse an existing symlink anywhere under root, even from ISO content."""
    relative = target.relative_to(root)
    current = root
    for piece in relative.parts:
        current = current / piece
        if current.is_symlink():
            raise OverlayError("Cannot write through symlink in root filesystem.")


def install_jolven(root: Path, archive: Path, expected_sha: str) -> dict:
    """Inject files. Call on a disposable, mounted/staged *copy* only."""
    root = root.resolve(strict=True)
    if not root.is_dir() or not (root / "usr").is_dir():
        raise OverlayError("Not a Linux root filesystem (usr/ missing).")
    members = inspect_archive(archive, expected_sha)
    for item in members:
        target = root.joinpath(*_safe_path(item.name).parts)
        _no_symlink_parents(target, root)
        if target.exists() and not target.is_dir() and item.isdir():
            raise OverlayError("Archive directory would replace an existing file.")
    session = root / SESSION_PATH
    _no_symlink_parents(session, root)
    if session.exists() and session.read_text(encoding="utf-8") != SESSION:
        raise OverlayError("Cannot replace a foreign Wayland session definition.")
    with tarfile.open(archive, "r:gz") as tar:
        for member in members:
            target = root.joinpath(*_safe_path(member.name).parts)
            if member.isdir():
                target.mkdir(mode=0o755, parents=True, exist_ok=True)
            else:
                target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
                stream = tar.extractfile(member)
                if stream is None:
                    raise OverlayError("Unable to read Jolven release entry.")
                with target.open("wb") as output:
                    for block in iter(lambda: stream.read(1024 * 1024), b""):
                        output.write(block)
                os.chmod(target, member.mode & 0o755 or 0o644)
    session.parent.mkdir(parents=True, exist_ok=True)
    session.write_text(SESSION, encoding="utf-8")
    os.chmod(session, 0o644)
    return {
        "jolven_archive_sha256": expected_sha.lower(),
        "installed_entries": len(members),
        "jolven_session": "/" + SESSION_PATH,
        "login_manager": "GDM/SDDM via XDG wayland-sessions; autologin unchanged",
        "runtime_dependency_check": "pending system validation",
    }

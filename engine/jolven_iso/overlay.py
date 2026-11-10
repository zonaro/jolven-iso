"""Offline, guarded Jolven installation into a disposable Linux root filesystem.

The caller must verify Nobara's ISO and the Jolven artifact SHA-256 first.
No network, shell execution or package manager is involved. Symlinks in
Jolven's Meson-produced usr/ tree are supported only when they stay in /usr.
"""
from __future__ import annotations

import hashlib
import os
import posixpath
import re
import stat
import tarfile
from pathlib import Path, PurePosixPath

SESSION = """[Desktop Entry]
Name=Jolven Session
Comment=Console-style gaming session powered by Jolven
Exec=/usr/bin/jolven-session
TryExec=/usr/bin/jolven-session
Type=Application
DesktopNames=Jolven
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
    """Invalid Jolven artifact or unsafe destination root."""


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _safe_path(name: str) -> PurePosixPath:
    if not name or name.startswith("/") or "\x00" in name:
        raise OverlayError("Absolute/empty path in Jolven archive.")
    path = PurePosixPath(name)
    if ".." in path.parts or not path.parts or path.parts[0] != "usr":
        raise OverlayError("Archive entry escapes usr/.")
    return path


def _safe_link(member: tarfile.TarInfo) -> None:
    """A link may be relative or absolute but must point inside /usr."""
    if not member.issym():
        return
    link = member.linkname
    if not link or "\x00" in link or "\\" in link:
        raise OverlayError("Invalid link target in Jolven archive.")
    path = _safe_path(member.name)
    target = posixpath.normpath(
        link.lstrip("/") if link.startswith("/")
        else posixpath.join(str(path.parent), link)
    )
    if not (target == "usr" or target.startswith("usr/")):
        raise OverlayError("Jolven archive link escapes /usr.")


def inspect_archive(archive: Path, expected_sha: str) -> list[tarfile.TarInfo]:
    if not archive.is_file() or archive.stat().st_size > MAX_ARCHIVE_BYTES:
        raise OverlayError("Jolven artifact absent or too large.")
    if not re.fullmatch(r"[a-fA-F0-9]{64}", expected_sha):
        raise OverlayError("Invalid SHA-256.")
    if file_sha256(archive) != expected_sha.lower():
        raise OverlayError("Jolven artifact SHA-256 mismatch.")
    try:
        with tarfile.open(archive, "r:gz") as tar:
            members = tar.getmembers()
            if len(members) > MAX_MEMBERS:
                raise OverlayError("Excessive archive entries.")
            names: set[str] = set()
            links: set[str] = set()
            total = 0
            for member in members:
                path = _safe_path(member.name)
                # Allow relative symlinks to other /usr paths, not hardlinks,
                # devices, FIFOs, xattrs or special filesystem nodes.
                if not (member.isfile() or member.isdir() or member.issym()):
                    raise OverlayError("Hardlinks/devices/special files not allowed.")
                if member.mode & 0o7000:
                    raise OverlayError("Setuid/setgid/sticky entries forbidden.")
                key = str(path)
                if key in names:
                    raise OverlayError("Duplicate archive entry.")
                names.add(key)
                if member.issym():
                    _safe_link(member)
                    links.add(key)
                total += member.size
                if total > MAX_ARCHIVE_BYTES:
                    raise OverlayError("Artifact expands beyond size limit.")
            for entry in names:
                parts = PurePosixPath(entry).parts
                if any("/".join(parts[:i]) in links for i in range(1, len(parts))):
                    raise OverlayError("Files cannot be nested under archive symlinks.")
            if not REQUIRED.issubset(names):
                raise OverlayError("Jolven archive missing required executables.")
            for member in members:
                if str(_safe_path(member.name)) in REQUIRED and not member.isfile():
                    raise OverlayError("Required executables must be regular files.")
            return members
    except (tarfile.TarError, OSError) as exc:
        raise OverlayError("Invalid Jolven tar.gz archive.") from exc


def _checked_target(root: Path, name: str) -> Path:
    path = _safe_path(name)
    target = root.joinpath(*path.parts)
    current = root
    for part in path.parts:
        current = current / part
        if current.is_symlink():
            raise OverlayError("Refusing to write through filesystem symlink.")
    return target


def _matches_existing(target: Path, item: tarfile.TarInfo, tar: tarfile.TarFile) -> bool:
    if item.isdir():
        return target.is_dir() and not target.is_symlink()
    if item.issym():
        return target.is_symlink() and os.readlink(target) == item.linkname
    if not target.is_file() or target.is_symlink():
        return False
    stream = tar.extractfile(item)
    if stream is None:
        return False
    source_hash = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        source_hash.update(chunk)
    return source_hash.hexdigest() == file_sha256(target)


def install_jolven(root: Path, archive: Path, expected_sha: str) -> dict:
    """Stage a verified Jolven artifact. Refuse foreign file replacement."""
    root = root.resolve(strict=True)
    if not root.is_dir() or not (root / "usr").is_dir():
        raise OverlayError("Not a Linux root filesystem (usr/ missing).")
    members = inspect_archive(archive, expected_sha)
    session = _checked_target(root, SESSION_PATH)
    if session.exists() or session.is_symlink():
        if session.is_symlink() or session.read_text(encoding="utf-8") != SESSION:
            raise OverlayError("Refusing to replace foreign Wayland session.")
    with tarfile.open(archive, "r:gz") as tar:
        # All collisions and paths checked before ANY write to avoid
        # partial changes on predictable filesystem conflicts.
        for item in members:
            target = _checked_target(root, item.name)
            if target.exists() or target.is_symlink():
                if not _matches_existing(target, item, tar):
                    raise OverlayError(f"Existing foreign file conflicts: {item.name}")
        for item in members:
            target = _checked_target(root, item.name)
            if item.isdir():
                target.mkdir(mode=0o755, parents=True, exist_ok=True)
                continue
            target.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
            if target.exists() or target.is_symlink():
                continue
            if item.issym():
                os.symlink(item.linkname, target)
                continue
            input_file = tar.extractfile(item)
            if input_file is None:
                raise OverlayError("Cannot read archive entry.")
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as output:
                for block in iter(lambda: input_file.read(1024 * 1024), b""):
                    output.write(block)
            os.chmod(target, item.mode & 0o777)
    session.parent.mkdir(parents=True, exist_ok=True)
    if not session.exists():
        fd = os.open(session, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(SESSION)
    return {
        "jolven_archive_sha256": expected_sha.lower(),
        "installed_entries": len(members),
        "jolven_session": "/" + SESSION_PATH,
        "login_manager": "GDM/SDDM via XDG wayland-sessions; autologin unchanged",
        "runtime_dependency_check": "pending system validation",
    }

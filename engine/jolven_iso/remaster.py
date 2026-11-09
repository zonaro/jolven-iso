"""Experimental Linux-only Nobara LiveISO remaster.

Requires explicit root, official ISO whose checksum was checked, a separately
verified Jolven usr/ tarball, and acceptance of unsigned/untested output.
Not exposed in the Flutter UI until boot/install checks pass.
"""
from __future__ import annotations

import contextlib
import os
import platform
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from .overlay import install_jolven, OverlayError, file_sha256


class RemasterError(RuntimeError):
    """Cannot safely rebuild this image/layout."""


TOOL_NAMES = (
    "xorriso", "unsquashfs", "mksquashfs", "mount", "umount",
    "e2fsck", "resize2fs", "truncate",
)


def _run(args: list[str], *, accepted: tuple[int, ...] = (0,)) -> str:
    result = subprocess.run(
        args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        check=False,
    )
    if result.returncode not in accepted:
        raise RemasterError(
            f"Command {args[0]} failed ({result.returncode}): "
            f"{result.stdout[-1500:]}"
        )
    return result.stdout


def prerequisites() -> dict:
    """Show exactly which requirements are missing, without modifying host."""
    missing = [name for name in TOOL_NAMES if shutil.which(name) is None]
    return {
        "platform": platform.system(),
        "must_be_root": True,
        "missing_tools": missing,
        "ready_for_experimental_compose":
            platform.system() == "Linux" and os.geteuid() == 0 and not missing,
    }


def _compression(squash: Path) -> tuple[str, int]:
    output = _run(["unsquashfs", "-s", str(squash)])
    match = re.search(r"Compression\s+([a-z0-9]+)", output, re.IGNORECASE)
    block = re.search(r"Block size\s+(\d+)", output, re.IGNORECASE)
    if not match or not block:
        raise RemasterError("Cannot identify original squashfs compression.")
    compression = match.group(1).lower()
    if compression not in {"gzip", "xz", "zstd", "lz4", "lzo"}:
        raise RemasterError("Unsupported squashfs compression.")
    return compression, int(block.group(1))


@contextlib.contextmanager
def _mounted_ext4(image: Path, mountpoint: Path):
    """Only on a disposable copy. Caller must already be privileged."""
    # Repair and expand a *copy* to accommodate Jolven binaries and metadata.
    _run(["e2fsck", "-f", "-p", str(image)], accepted=(0, 1))
    _run(["truncate", "-s", "+1024M", str(image)])
    _run(["resize2fs", str(image)])
    mountpoint.mkdir(parents=True)
    _run(["mount", "-o", "loop,rw,nosuid,nodev", str(image), str(mountpoint)])
    try:
        yield mountpoint
    finally:
        _run(["umount", str(mountpoint)])


def _required_runtime_present(root: Path) -> None:
    """M1/M2 fail closed instead of promising a session without Gamescope."""
    required_files = [
        root / "usr/bin/gamescope",
        root / "usr/bin/python3",
    ]
    missing = [str(p.relative_to(root)) for p in required_files if not p.exists()]
    if missing:
        raise RemasterError(
            "The official ISO lacks mandatory runtime executables: "
            + ", ".join(missing)
            + ". Dependency installation via Nobara DNF is not implemented yet."
        )


def remaster_iso(
    source: Path,
    destination: Path,
    *,
    jolven_archive: Path,
    jolven_sha256: str,
    experimental: bool = False,
) -> dict:
    """Copy and patch LiveOS/squashfs.img while replaying ISO boot metadata.

    This function is **not** evidence of a bootable/installable output.
    """
    if not experimental:
        raise RemasterError("Pass --experimental to acknowledge missing QA.")
    state = prerequisites()
    if not state["ready_for_experimental_compose"]:
        raise RemasterError("Linux root and tools required: " + str(state))
    if not source.is_file() or source.resolve() == destination.resolve():
        raise RemasterError("Invalid source or same input/output path.")
    if destination.exists():
        raise RemasterError("Destination already exists; refusing overwrite.")
    if destination.suffix.lower() != ".iso":
        raise RemasterError("Output must have a .iso extension.")
    if not destination.parent.is_dir():
        raise RemasterError("Destination directory is missing.")
    free = shutil.disk_usage(destination.parent).free
    if free < source.stat().st_size * 3 + 2 * 1024**3:
        raise RemasterError("Insufficient disk space for temporary image.")
    with tempfile.TemporaryDirectory(
        prefix="jolven-remaster-", dir=destination.parent
    ) as temp:
        workspace = Path(temp)
        squash = workspace / "squashfs.img"
        _run([
            "xorriso", "-osirrox", "on", "-indev", str(source),
            "-extract", "/LiveOS/squashfs.img", str(squash),
        ])
        compression, block_size = _compression(squash)
        extracted = workspace / "squash"
        _run(["unsquashfs", "-d", str(extracted), str(squash)])
        nested = extracted / "LiveOS/rootfs.img"
        if nested.is_file():
            with _mounted_ext4(nested, workspace / "mounted") as root:
                _required_runtime_present(root)
                details = install_jolven(root, jolven_archive, jolven_sha256)
        elif (extracted / "usr").is_dir():
            _required_runtime_present(extracted)
            details = install_jolven(
                extracted, jolven_archive, jolven_sha256,
            )
        else:
            raise RemasterError(
                "Unsupported Nobara LiveOS layout: no rootfs.img or usr/."
            )
        patched = workspace / "patched-squashfs.img"
        _run([
            "mksquashfs", str(extracted), str(patched), "-noappend",
            "-comp", compression, "-b", str(block_size),
        ])
        pending = workspace / "jolven-output.iso"
        _run([
            "xorriso", "-indev", str(source), "-outdev", str(pending),
            "-map", str(patched), "/LiveOS/squashfs.img",
            "-boot_image", "any", "replay", "-end",
        ])
        if not pending.is_file() or pending.stat().st_size < 32773:
            raise RemasterError("No valid ISO output produced.")
        with pending.open("rb") as stream:
            stream.seek(16 * 2048 + 1)
            if stream.read(5) != b"CD001":
                raise RemasterError("Output is missing ISO-9660 signature.")
        output_sha = file_sha256(pending)
        os.replace(pending, destination)
        return {
            "status": "experimental_unverified_iso",
            "output": str(destination),
            "sha256": output_sha,
            "source_sha256": file_sha256(source),
            "jolven": details,
            "security": "Secure Boot compatibility NOT verified",
            "tests": "must boot and install on every Nobara edition before release",
        }

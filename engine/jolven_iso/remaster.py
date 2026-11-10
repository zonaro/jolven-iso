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
import time
from pathlib import Path

from .overlay import install_jolven, file_sha256
from .profile import apply_appearance
from .extras import write_optional_extras
from .audit import audit_iso
from .image_identity import inspect_nobara_root, parse_official_filename


class RemasterError(RuntimeError):
    """Cannot safely rebuild this image/layout."""


TOOL_NAMES = (
    "xorriso", "unsquashfs", "mksquashfs", "mount", "umount",
    "e2fsck", "resize2fs", "truncate", "glib-compile-schemas",
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
    """Read-only diagnostics for root loop-mount or non-root libguestfs/FUSE."""
    missing = [name for name in TOOL_NAMES if shutil.which(name) is None]
    root_mode = platform.system() == "Linux" and os.geteuid() == 0
    user_mount_tools = ("guestmount", "guestunmount")
    missing_guest = [
        name for name in user_mount_tools if shutil.which(name) is None
    ]
    fuse_device = os.path.exists("/dev/fuse") and os.access(
        "/dev/fuse", os.R_OK | os.W_OK
    )
    rootless = platform.system() == "Linux" and not missing_guest and fuse_device
    return {
        "platform": platform.system(),
        "must_be_root": not rootless,
        "mount_backend": "loop-root" if root_mode else (
            "libguestfs-fuse" if rootless else "unavailable"
        ),
        "missing_tools": missing,
        "missing_rootless_tools": missing_guest,
        "fuse_device_accessible": fuse_device,
        "rootless_ext4_available": rootless,
        "ready_for_experimental_compose":
            platform.system() == "Linux"
            and not missing
            and (root_mode or rootless),
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
    """Mount a disposable ext4 image, using libguestfs/FUSE without root.

    Unmount and wait for libguestfs worker to exit before packing the image.
    Never operate on an active virtual machine disk image.
    """
    _run(["e2fsck", "-f", "-p", str(image)], accepted=(0, 1))
    _run(["truncate", "-s", "+1024M", str(image)])
    _run(["resize2fs", str(image)])
    mountpoint.mkdir(parents=True)
    if os.geteuid() == 0:
        _run(["mount", "-o", "loop,rw,nosuid,nodev", str(image), str(mountpoint)])
        try:
            yield mountpoint
        finally:
            _run(["umount", str(mountpoint)])
        return

    worker_file = mountpoint.parent / "guestmount.pid"
    _run([
        "guestmount", "--format=raw", "--rw", "-a", str(image),
        "-m", "/dev/sda", "-o", f"uid={os.getuid()},gid={os.getgid()}",
        "--pid-file", str(worker_file), str(mountpoint),
    ])
    try:
        yield mountpoint
    finally:
        try:
            _run(["guestunmount", str(mountpoint)])
        finally:
            if worker_file.exists():
                try:
                    worker_pid = int(worker_file.read_text().strip())
                except ValueError as exc:
                    raise RemasterError("Invalid guestmount worker PID") from exc
                for _ in range(75):
                    try:
                        os.kill(worker_pid, 0)
                    except ProcessLookupError:
                        break
                    time.sleep(0.2)
                else:
                    raise RemasterError(
                        "libguestfs worker did not exit; image cannot be reused safely."
                    )

def _required_runtime_present(root: Path) -> None:
    """M1/M2 fail closed instead of promising a session without Gamescope."""
    required_files = [
        root / "usr/bin/gamescope",
        root / "usr/bin/python3",
    ]
    missing = [str(p.relative_to(root)) for p in required_files if not p.exists() and not p.is_symlink()]
    runtime_libraries = ("libgtk-4.so.1", "libadwaita-1.so.0")
    library_roots = (root / "usr/lib64", root / "usr/lib")
    for library in runtime_libraries:
        if not any(
            candidate.exists() or candidate.is_symlink()
            for folder in library_roots
            for candidate in folder.glob(library + "*")
        ):
            missing.append("shared library " + library)
    if missing:
        raise RemasterError(
            "The Nobara ISO lacks mandatory Jolven runtime dependencies: "
            + ", ".join(missing)
            + ". Install these in a verified system image before distributing "
              "it; automatic DNF installation into the ISO is not certified."
        )


def remaster_iso(
    source: Path,
    destination: Path,
    *,
    jolven_archive: Path,
    jolven_sha256: str,
    appearance: dict | None = None,
    extras: list[str] | None = None,
    workspace_dir: Path | None = None,
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
    staging_parent = workspace_dir or destination.parent
    if not staging_parent.is_dir():
        raise RemasterError("Workspace directory does not exist.")
    free = shutil.disk_usage(staging_parent).free
    if free < source.stat().st_size * 3 + 2 * 1024**3:
        raise RemasterError("Insufficient disk space for temporary image.")
    if staging_parent != destination.parent and (
        shutil.disk_usage(destination.parent).free < source.stat().st_size + 1024**3
    ):
        raise RemasterError("Insufficient disk space in output directory.")
    with tempfile.TemporaryDirectory(
        prefix="jolven-remaster-", dir=staging_parent
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
                identity = inspect_nobara_root(root)
                _required_runtime_present(root)
                details = install_jolven(root, jolven_archive, jolven_sha256)
                if appearance is not None:
                    details['appearance_defaults'] = apply_appearance(root, appearance)
                details['optional_packages'] = write_optional_extras(root, extras or [])
        elif (extracted / "usr").is_dir():
            if os.geteuid() != 0:
                raise RemasterError(
                    "A direct squashfs root requires root-owned metadata. "
                    "Rootless support currently needs LiveOS/rootfs.img."
                )
            identity = inspect_nobara_root(extracted)
            _required_runtime_present(extracted)
            details = install_jolven(
                extracted, jolven_archive, jolven_sha256,
            )
            if appearance is not None:
                details['appearance_defaults'] = apply_appearance(extracted, appearance)
            details['optional_packages'] = write_optional_extras(extracted, extras or [])
        else:
            raise RemasterError(
                "Unsupported Nobara LiveOS layout: no rootfs.img or usr/."
            )
        published_name = parse_official_filename(source.name)
        if published_name is not None and (
            published_name["release"] != identity["version_id"]
        ):
            raise RemasterError(
                "ISO filename release and staged Nobara root VERSION_ID differ."
            )
        patched = workspace / "patched-squashfs.img"
        squash_args = [
            "mksquashfs", str(extracted), str(patched), "-noappend",
            "-comp", compression, "-b", str(block_size), "-processors", "2",
        ]
        if os.geteuid() != 0:
            # The outer squashfs contains the ext4 image. Rootless extraction
            # maps ownership to the host user; restore root metadata.
            squash_args.append("-all-root")
        _run(squash_args)
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
        audit = audit_iso(source, pending)
        output_sha = file_sha256(pending)
        if os.stat(workspace).st_dev == os.stat(destination.parent).st_dev:
            os.replace(pending, destination)
        else:
            # WSL2: work on Linux ext4, then atomically publish on /mnt/c.
            partial_dest = destination.with_name(
                f".{destination.name}.partial.{os.getpid()}"
            )
            try:
                with pending.open("rb") as source_stream, partial_dest.open("xb") as target_stream:
                    shutil.copyfileobj(source_stream, target_stream, 1024 * 1024)
                    target_stream.flush()
                    os.fsync(target_stream.fileno())
                if destination.exists():
                    raise RemasterError("Output created concurrently; refusing overwrite.")
                os.replace(partial_dest, destination)
            finally:
                partial_dest.unlink(missing_ok=True)
        return {
            "status": "experimental_unverified_iso",
            "output": str(destination),
            "sha256": output_sha,
            "source_sha256": file_sha256(source),
            "jolven": details,
            "source_root_identity": identity,
            "structural_audit": audit,
            "security": "Secure Boot compatibility NOT verified",
            "tests": "must boot and install on every Nobara edition before release",
        }

"""Read-only ISO metadata audit.

Confirms xorriso preserved the source volume id and the optical boot catalog
when remastering. These checks are NOT proof of an installable/bootable OS.
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path


class AuditError(ValueError):
    pass


def _pvd(path: Path) -> tuple[str, int]:
    if not path.is_file() or path.stat().st_size < 32774:
        raise AuditError("ISO missing or too small.")
    with path.open("rb") as stream:
        stream.seek(16 * 2048 + 1)
        if stream.read(5) != b"CD001":
            raise AuditError("ISO-9660 primary descriptor not found.")
        stream.seek(16 * 2048 + 40)
        volume = stream.read(32).decode("ascii", errors="replace").strip()
    return volume, path.stat().st_size


def _report(path: Path) -> dict:
    process = subprocess.run(
        ["xorriso", "-indev", str(path), "-report_el_torito", "plain",
         "-report_system_area", "plain"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, check=False,
    )
    if process.returncode != 0:
        raise AuditError("xorriso cannot inspect ISO: " + process.stdout[-900:])
    output = process.stdout
    boot_images = sum(
        1 for line in output.splitlines()
        if re.search(r"El Torito boot img\s*:", line)
    )
    has_catalog = bool(re.search(r"El Torito catalog\s*:", output))
    sys_match = re.search(r"System area summary\s*:\s*(.*)", output)
    sys_area = sys_match.group(1).strip() if sys_match else ""
    return {
        "boot_images": boot_images,
        "has_catalog": has_catalog,
        "system_area": sys_area,
        "has_mbr": bool(re.search(r"\bMBR\b", sys_area, re.IGNORECASE)),
        "has_gpt": bool(re.search(r"\bGPT\b", sys_area, re.IGNORECASE)),
    }


def audit_iso(source: Path, output: Path) -> dict:
    original_volume, original_size = _pvd(source)
    output_volume, output_size = _pvd(output)
    if original_volume != output_volume:
        raise AuditError("Source and output ISO volume ids differ.")
    original = _report(source)
    rebuilt = _report(output)
    if original["has_catalog"] != rebuilt["has_catalog"]:
        raise AuditError("Optical boot catalog was lost or unexpectedly added.")
    if original["boot_images"] != rebuilt["boot_images"]:
        raise AuditError("El Torito boot image count changed.")
    if original["has_mbr"] and not rebuilt["has_mbr"]:
        raise AuditError("MBR system area lost.")
    if original["has_gpt"] and not rebuilt["has_gpt"]:
        raise AuditError("GPT system area lost.")
    return {
        "volume_id": original_volume,
        "source_bytes": original_size,
        "output_bytes": output_size,
        "optical_boot_images": original["boot_images"],
        "optical_boot_catalog_preserved": True,
        "mbr_preserved_if_present": True,
        "gpt_preserved_if_present": True,
        "boot_verified": False,
        "installation_verified": False,
    }

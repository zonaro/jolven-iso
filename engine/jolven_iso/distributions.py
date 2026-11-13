"""Conservative source-distribution catalog for the ISO builder.

This is *not* proof of source authenticity or an ISO remastering adapter.
Only Nobara has an experimental compose path; other official ISO families
remain inspect-only until their layouts, installers and persistence are tested.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class DistributionProfile:
    identifier: str
    display_name: str
    family: str
    layout_hint: str
    official_url: str
    compose_status: str

    def as_dict(self) -> dict[str, str | bool]:
        return {
            "id": self.identifier,
            "name": self.display_name,
            "family": self.family,
            "layout_hint": self.layout_hint,
            "official_url": self.official_url,
            "inspection_available": True,
            "compose_status": self.compose_status,
            "boot_tested": False,
            "install_tested": False,
        }


PROFILES = {
    "nobara": DistributionProfile(
        "nobara", "Nobara", "fedora", "LiveOS/squashfs.img",
        "https://nobaraproject.org/", "experimental_unverified",
    ),
    "fedora": DistributionProfile(
        "fedora", "Fedora", "fedora", "LiveOS/squashfs.img",
        "https://fedoraproject.org/", "not_implemented",
    ),
    "ubuntu": DistributionProfile(
        "ubuntu", "Ubuntu", "debian", "casper/filesystem*.squashfs",
        "https://ubuntu.com/download/desktop", "not_implemented",
    ),
    "cachyos": DistributionProfile(
        "cachyos", "CachyOS", "arch", "ArchISO-derived; inspect exact edition",
        "https://cachyos.org/download/", "not_implemented",
    ),
    "biglinux": DistributionProfile(
        "biglinux", "BigLinux", "manjaro", "Manjaro-derived; inspect exact live layout",
        "https://www.biglinux.com.br/", "not_implemented",
    ),
}


def profile(identifier: str) -> DistributionProfile:
    """Look up an allowlisted distribution. Never guess from filename."""
    try:
        return PROFILES[identifier]
    except KeyError as exc:
        raise ValueError("Unsupported distribution profile: " + identifier) from exc


def list_profiles() -> list[dict[str, str | bool]]:
    return [value.as_dict() for value in PROFILES.values()]

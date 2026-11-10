import hashlib
import io
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from jolven_iso.overlay import OverlayError, SESSION_PATH, install_jolven


def make_tar(path, entries):
    with tarfile.open(path, "w:gz") as archive:
        for name, data in entries.items():
            info = tarfile.TarInfo(name)
            info.mode = 0o755 if name.startswith("usr/bin/") else 0o644
            info.size = len(data)
            archive.addfile(info, io.BytesIO(data))
    return hashlib.sha256(path.read_bytes()).hexdigest()


class OverlayTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "root"
        (self.root / "usr").mkdir(parents=True)
        self.archive = Path(self.tmp.name) / "jolven.tar.gz"
        self.entries = {
            "usr/bin/jolven": b"#!/bin/sh\n",
            "usr/bin/jolven-session": b"#!/bin/sh\n",
            "usr/libexec/jolven-game-mode-setup": b"#!/bin/sh\n",
        }

    def test_valid_archive_registers_session(self):
        digest = make_tar(self.archive, self.entries)
        report = install_jolven(self.root, self.archive, digest)
        self.assertEqual(report["installed_entries"], 3)
        session = self.root / SESSION_PATH
        self.assertIn("Exec=/usr/bin/jolven-session", session.read_text())
        self.assertTrue((self.root / "usr/bin/jolven").exists())

    def test_python_abi_match_is_required_before_writing(self):
        entries = {
            **self.entries,
            "usr/lib/python3.15/site-packages/cartridges/shared.py": b"x = 1",
        }
        digest = make_tar(self.archive, entries)
        with self.assertRaisesRegex(OverlayError, "Python ABI 3.15"):
            install_jolven(self.root, self.archive, digest)
        self.assertFalse((self.root / "usr/bin/jolven").exists())
        (self.root / "usr/lib/python3.15").mkdir(parents=True)
        report = install_jolven(self.root, self.archive, digest)
        self.assertEqual(report["python_site_packages_versions"], ["3.15"])

    def test_wrong_hash_refuses_extraction(self):
        make_tar(self.archive, self.entries)
        with self.assertRaises(OverlayError):
            install_jolven(self.root, self.archive, "0" * 64)

    def test_path_traversal_refused(self):
        digest = make_tar(self.archive, {**self.entries, "usr/../../escape": b"no"})
        with self.assertRaises(OverlayError):
            install_jolven(self.root, self.archive, digest)

    def test_symlink_target_refused(self):
        (self.root / "usr/bin").symlink_to(Path(self.tmp.name), target_is_directory=True)
        digest = make_tar(self.archive, self.entries)
        with self.assertRaises(OverlayError):
            install_jolven(self.root, self.archive, digest)

    def test_relative_symlink_within_usr_allowed(self):
        with tarfile.open(self.archive, "w:gz") as tar:
            for name, data in self.entries.items():
                info = tarfile.TarInfo(name)
                info.mode = 0o755
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            info = tarfile.TarInfo("usr/bin/jolven-alias")
            info.type = tarfile.SYMTYPE
            info.linkname = "jolven"
            tar.addfile(info)
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        install_jolven(self.root, self.archive, digest)
        self.assertTrue((self.root / "usr/bin/jolven-alias").is_symlink())
        self.assertEqual((self.root / "usr/bin/jolven-alias").readlink(), Path("jolven"))

    def test_absolute_link_outside_usr_refused(self):
        with tarfile.open(self.archive, "w:gz") as tar:
            for name, data in self.entries.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            link = tarfile.TarInfo("usr/bin/escape")
            link.type = tarfile.SYMTYPE
            link.linkname = "/etc/shadow"
            tar.addfile(link)
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        with self.assertRaises(OverlayError):
            install_jolven(self.root, self.archive, digest)
        self.assertFalse((self.root / "usr/bin/jolven").exists())

    def test_archive_cannot_write_through_own_symlinks(self):
        with tarfile.open(self.archive, "w:gz") as tar:
            for name, data in self.entries.items():
                info = tarfile.TarInfo(name)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            link = tarfile.TarInfo("usr/share/alias")
            link.type = tarfile.SYMTYPE
            link.linkname = "../bin"
            tar.addfile(link)
            nested = tarfile.TarInfo("usr/share/alias/evil")
            nested.size = 4
            tar.addfile(nested, io.BytesIO(b"evil"))
        digest = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        with self.assertRaises(OverlayError):
            install_jolven(self.root, self.archive, digest)

    def test_foreign_file_is_preserved_without_partial_install(self):
        (self.root / "usr/bin").mkdir(parents=True)
        existing = self.root / "usr/bin/jolven"
        existing.write_text("another application")
        digest = make_tar(self.archive, self.entries)
        with self.assertRaises(OverlayError):
            install_jolven(self.root, self.archive, digest)
        self.assertEqual(existing.read_text(), "another application")
        self.assertFalse((self.root / "usr/bin/jolven-session").exists())

    def test_foreign_session_not_overwritten(self):
        session = self.root / SESSION_PATH
        session.parent.mkdir(parents=True)
        session.write_text("foreign session")
        digest = make_tar(self.archive, self.entries)
        with self.assertRaises(OverlayError):
            install_jolven(self.root, self.archive, digest)
        self.assertEqual(session.read_text(), "foreign session")


if __name__ == "__main__":
    unittest.main()

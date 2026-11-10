import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from jolven_iso.remaster import (
    RemasterError, _mounted_ext4, prerequisites, remaster_iso,
)


class RemasterTests(unittest.TestCase):
    def test_preflight_does_not_touch_host(self):
        report = prerequisites()
        self.assertIn("missing_tools", report)
        self.assertIn("ready_for_experimental_compose", report)

    def test_rootless_diagnostics_are_explicit(self):
        with patch("jolven_iso.remaster.os.geteuid", return_value=1000), \
             patch("jolven_iso.remaster.platform.system", return_value="Linux"), \
             patch("jolven_iso.remaster.shutil.which", return_value="/usr/bin/tool"), \
             patch("jolven_iso.remaster.os.path.exists", return_value=True), \
             patch("jolven_iso.remaster.os.access", return_value=True):
            report = prerequisites()
        self.assertTrue(report["rootless_ext4_available"])
        self.assertFalse(report["must_be_root"])
        self.assertEqual(report["mount_backend"], "libguestfs-fuse")

    def test_rootless_mount_is_unmounted_before_repack(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            image = root / "rootfs.img"
            image.write_bytes(b"test only")
            commands = []
            def record(args, **kwargs):
                commands.append(args[0])
                return ""
            with patch("jolven_iso.remaster.os.geteuid", return_value=1000), \
                 patch("jolven_iso.remaster._run", side_effect=record):
                with _mounted_ext4(image, root / "mount"):
                    self.assertEqual(commands[-1], "guestmount")
            self.assertEqual(commands[-1], "guestunmount")

    def test_missing_runtime_libraries_block_broken_jolven_session(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "usr/bin").mkdir(parents=True)
            (root / "usr/bin/gamescope").write_text("#!/bin/sh")
            (root / "usr/bin/python3").write_text("#!/bin/sh")
            with self.assertRaisesRegex(RemasterError, "libgtk-4.so.1"):
                _required_runtime_present(root)
            (root / "usr/lib64").mkdir(parents=True)
            (root / "usr/lib64/libgtk-4.so.1").write_bytes(b"fake")
            (root / "usr/lib64/libadwaita-1.so.0").write_bytes(b"fake")
            _required_runtime_present(root)

    def test_experimental_flag_required_before_any_filesystem_operation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            original = root / "original.iso"
            output = root / "result.iso"
            original.write_bytes(b"placeholder")
            with self.assertRaisesRegex(RemasterError, "experimental"):
                remaster_iso(
                    original,
                    output,
                    jolven_archive=root / "missing.tar.gz",
                    jolven_sha256="a" * 64,
                )
            self.assertEqual(original.read_bytes(), b"placeholder")
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()

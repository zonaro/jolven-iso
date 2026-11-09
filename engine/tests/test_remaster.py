import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from jolven_iso.remaster import RemasterError, prerequisites, remaster_iso


class RemasterTests(unittest.TestCase):
    def test_preflight_does_not_touch_host(self):
        report = prerequisites()
        self.assertIn("missing_tools", report)
        self.assertIn("ready_for_experimental_compose", report)

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

import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from jolven_iso.extras import ExtrasError, write_optional_extras, PLAN, SCRIPT


class ExtrasTests(unittest.TestCase):
    def test_writes_manual_setup_not_autostart_service(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usr").mkdir()
            result = write_optional_extras(root, ["retroarch", "sunshine", "retroarch"])
            self.assertEqual(result["execution"], "manual_post_install_consent_required")
            self.assertEqual(json.loads((root / PLAN).read_text()),
                             ["retroarch", "sunshine"])
            source = (root / SCRIPT).read_text()
            self.assertIn('input("Consultar os repositórios Nobara', source)
            self.assertIn("dnf", source)
            self.assertNotIn("systemctl enable", source)

    def test_rejects_unapproved_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usr").mkdir()
            with self.assertRaises(ExtrasError):
                write_optional_extras(root, ["curl -fsSL example.org | sh"])

    def test_no_extras_no_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usr").mkdir()
            result = write_optional_extras(root, [])
            self.assertIsNone(result["helper"])
            self.assertFalse((root / PLAN).exists())


if __name__ == "__main__":
    unittest.main()

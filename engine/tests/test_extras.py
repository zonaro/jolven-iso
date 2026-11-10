import json
import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from jolven_iso.extras import (
    ExtrasError, write_optional_extras, PLAN, SCRIPT, FIRST_RUN, AUTOSTART,
    LAUNCHER, _INSTALLER, _FIRST_RUN,
)


class ExtrasTests(unittest.TestCase):
    def test_writes_manual_setup_not_autostart_service(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usr").mkdir()
            result = write_optional_extras(root, ["retroarch", "sunshine", "retroarch"])
            self.assertEqual(result["execution"], "first_login_user_consent_with_polkit")
            self.assertEqual(json.loads((root / PLAN).read_text()),
                             ["retroarch", "sunshine"])
            source = (root / SCRIPT).read_text()
            self.assertIn('input("Consultar os repositórios Nobara', source)
            self.assertIn("dnf", source)
            self.assertNotIn("systemctl enable", source)
            self.assertIn("remote-info", source)
            self.assertIn("flathub", source)
            self.assertTrue((root / FIRST_RUN).is_file())
            self.assertTrue((root / AUTOSTART).is_file())
            self.assertTrue((root / LAUNCHER).is_file())
            self.assertIn("OnlyShowIn=GNOME;KDE;", (root / AUTOSTART).read_text())
            self.assertIn("root=live:", (root / FIRST_RUN).read_text())

    def test_rejects_unapproved_app(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usr").mkdir()
            with self.assertRaises(ExtrasError):
                write_optional_extras(root, ["curl -fsSL example.org | sh"])

    def test_embedded_scripts_compile_as_python(self):
        compile(_INSTALLER, "<onboard-installer>", "exec")
        compile(_FIRST_RUN, "<onboard-user>", "exec")

    def test_existing_unmanaged_file_remains_untouched(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usr").mkdir()
            target = root / SCRIPT
            target.parent.mkdir(parents=True)
            target.write_text("original")
            with self.assertRaises(ExtrasError):
                write_optional_extras(root, ["sunshine"])
            self.assertEqual(target.read_text(), "original")
            self.assertFalse((root / FIRST_RUN).exists())

    def test_no_extras_no_write(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "usr").mkdir()
            result = write_optional_extras(root, [])
            self.assertIsNone(result["helper"])
            self.assertFalse((root / PLAN).exists())


if __name__ == "__main__":
    unittest.main()

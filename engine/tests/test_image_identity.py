import tempfile
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from jolven_iso.image_identity import (
    IdentityError, check_selected_edition, inspect_nobara_root,
    parse_official_filename, parse_os_release,
)


class IdentityTests(unittest.TestCase):
    def test_five_published_editions(self):
        editions = {
            "official": "Official", "gnome": "GNOME", "kde": "KDE",
            "steam-htpc": "Steam-HTPC",
            "steam-handheld": "Steam-Handheld",
        }
        for key, label in editions.items():
            name = f"Nobara-44-{label}-2026-08-28.iso"
            self.assertEqual(
                check_selected_edition(name, key)["edition_matches_filename"],
                True,
            )
            self.assertEqual(parse_official_filename(name)["edition"], label)

    def test_refuses_inconsistent_published_filename(self):
        with self.assertRaises(IdentityError):
            check_selected_edition("Nobara-44-KDE-2026-08-28.iso", "gnome")

    def test_renamed_file_does_not_claim_authentication(self):
        result = check_selected_edition("local.iso", "gnome")
        self.assertFalse(result["publisher_authenticated"])
        self.assertFalse(result["filename_matches_official_pattern"])

    def test_accepts_nobara_root_and_rejects_fedora(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "etc").mkdir()
            release = root / "etc/os-release"
            release.write_text('NAME="Nobara Linux"\nID=nobara\nVERSION_ID=44\n')
            self.assertEqual(inspect_nobara_root(root)["version_id"], "44")
            release.write_text("ID=fedora\nVERSION_ID=44\n")
            with self.assertRaises(IdentityError):
                inspect_nobara_root(root)

    def test_rejects_too_old_and_malformed_release(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "etc").mkdir()
            release = root / "etc/os-release"
            release.write_text("ID=nobara\nVERSION_ID=40\n")
            with self.assertRaises(IdentityError):
                inspect_nobara_root(root)
            release.write_text("ID=nobara\nVERSION_ID=not-a-number\n")
            with self.assertRaises(IdentityError):
                inspect_nobara_root(root)

    def test_symlink_escape_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "root"
            (root / "etc").mkdir(parents=True)
            (root / "etc/os-release").symlink_to("/etc/os-release")
            with self.assertRaises(IdentityError):
                inspect_nobara_root(root)

    def test_parse_release_is_data_not_shell(self):
        data = parse_os_release(
            'ID=nobara\nVERSION_ID="44"\nENV=$(touch /tmp/unwanted)\n'
        )
        self.assertEqual(data["ID"], "nobara")
        self.assertEqual(data["VERSION_ID"], "44")
        self.assertEqual(data["ENV"], "$(touch /tmp/unwanted)")


if __name__ == "__main__":
    unittest.main()

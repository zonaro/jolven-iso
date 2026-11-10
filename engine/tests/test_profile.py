import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from jolven_iso.profile import (
    ProfileError, SCHEMA_DIR, OVERRIDE, render_override, apply_appearance,
)


class ProfileTests(unittest.TestCase):
    def test_schema_defaults_do_not_embed_secrets(self):
        content = render_override(
            {"theme": "Jolven", "accent_hex": "#a78bfa"}
        )
        self.assertIn("theme-slug='jolven'", content)
        self.assertIn("theme-accent-custom='#A78BFA'", content)
        self.assertNotIn("password", content)

    def test_custom_maps_to_supported_jolven_slug(self):
        self.assertIn("theme-slug='jolven'", render_override({
            "theme": "Custom", "accent_hex": "#ffffff",
        }))

    def test_unknown_keys_and_bad_colors_fail(self):
        with self.assertRaises(ProfileError):
            render_override({
                "theme": "Jolven", "accent_hex": "#123456", "api_key": "secret",
            })
        with self.assertRaises(ProfileError):
            render_override({"theme": "Jolven", "accent_hex": "#bad'xx"})

    def test_defaults_compiled_without_changing_user_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            schema_dir = root / SCHEMA_DIR
            schema_dir.mkdir(parents=True)
            (schema_dir / "io.github.zonaro.Jolven.gschema.xml").write_text("<schemalist/>")
            with patch("jolven_iso.profile.subprocess.run") as run:
                run.return_value.returncode = 0
                location = apply_appearance(root, {
                    "theme": "Adwaita", "accent_hex": "#a78bfa",
                })
                self.assertEqual(location, "/" + str(SCHEMA_DIR / OVERRIDE))
                self.assertIn("theme-slug='adwaita'", (schema_dir / OVERRIDE).read_text())
                run.assert_called_once()


if __name__ == "__main__":
    unittest.main()

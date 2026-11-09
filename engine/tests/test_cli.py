import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from jolven_iso.cli import (
    PreflightError, check_iso, plan_project, reject_secret_keys,
    validate_project, verify_iso,
)


class CliTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.iso = Path(self.temp.name) / "Nobara-44-GNOME.iso"
        data = bytearray(16 * 2048 + 2048)
        data[16 * 2048 + 1:16 * 2048 + 6] = b"CD001"
        self.iso.write_bytes(data)
        self.hash = hashlib.sha256(data).hexdigest()
        self.project = {
            "schema_version": 1, "distribution": "nobara",
            "edition": "gnome", "source_iso": str(self.iso),
            "source_sha256": self.hash, "expected_sha256": self.hash,
            "jolven_session": True, "extras": ["sunshine"],
            "appearance": {"theme": "Jolven", "accent_hex": "#A78BFA"},
        }

    def test_valid_iso_and_hash(self):
        self.assertTrue(check_iso(self.iso)["iso9660"])
        self.assertTrue(verify_iso(self.iso, self.hash)["matches_supplied_sha256"])

    def test_reject_bad_iso(self):
        self.iso.write_bytes(b"not an ISO")
        with self.assertRaises(PreflightError):
            check_iso(self.iso)

    def test_reject_bad_hash(self):
        with self.assertRaises(PreflightError):
            verify_iso(self.iso, "0" * 64)

    def test_reject_secrets(self):
        with self.assertRaises(PreflightError):
            reject_secret_keys({"api_key": "should-never-be-in-iso"})
        with self.assertRaises(PreflightError):
            validate_project({**self.project, "password": "secret"})

    def test_plan_is_non_destructive(self):
        project_file = Path(self.temp.name) / "project.json"
        project_file.write_text(json.dumps(self.project), encoding="utf-8")
        result = plan_project(project_file)
        self.assertFalse(result["compose_available"])
        self.assertEqual(result["requested_extras"], ["sunshine"])


if __name__ == "__main__":
    unittest.main()

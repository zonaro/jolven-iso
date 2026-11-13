"""Distribution profiles are catalog metadata, not a compose whitelist."""
import unittest

from jolven_iso.distributions import PROFILES, list_profiles, profile


class DistributionProfilesTest(unittest.TestCase):
    def test_requested_distros_are_present(self):
        self.assertEqual(
            set(PROFILES), {"nobara", "fedora", "ubuntu", "cachyos", "biglinux"}
        )

    def test_only_nobara_has_existing_experimental_compose_path(self):
        for item in list_profiles():
            self.assertTrue(item["inspection_available"])
            self.assertFalse(item["boot_tested"])
            self.assertFalse(item["install_tested"])
            if item["id"] == "nobara":
                self.assertEqual(item["compose_status"], "experimental_unverified")
            else:
                self.assertEqual(item["compose_status"], "not_implemented")

    def test_unknown_distribution_rejected(self):
        with self.assertRaises(ValueError):
            profile("made-up")


if __name__ == "__main__":
    unittest.main()

"""Synthetic smoke test for the experimental remaster pipeline.

Does NOT establish bootability or Nobara edition compatibility. Needs root,
xorriso, squashfs-tools, e2fsprogs and glib-compile-schemas.
"""
import hashlib
import io
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from jolven_iso.remaster import remaster_iso, prerequisites, RemasterError


def run(*args):
    subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


@unittest.skipUnless(prerequisites()["ready_for_experimental_compose"],
                     "Linux root and ISO tools not available")
class RemasterSmokeTest(unittest.TestCase):
    def test_compose_synthetic_live_iso(self):
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            live_root = work / "live"
            (live_root / "usr/bin").mkdir(parents=True)
            (live_root / "usr/libexec").mkdir(parents=True)
            (live_root / "usr/lib64").mkdir(parents=True)
            (live_root / "usr/lib64/libgtk-4.so.1").write_bytes(b"stub")
            (live_root / "usr/lib64/libadwaita-1.so.0").write_bytes(b"stub")
            (live_root / "etc").mkdir(parents=True)
            (live_root / "etc/os-release").write_text('ID=nobara\nVERSION_ID=44\n')
            (live_root / "usr/share/glib-2.0/schemas").mkdir(parents=True)
            for name in ("gamescope", "python3"):
                (live_root / "usr/bin" / name).write_text("#!/bin/sh\nexit 0\n")
            schema = (
                '<?xml version="1.0" encoding="UTF-8"?>\n'
                '<schemalist><schema id="io.github.zonaro.Jolven" '
                'path="/io/github/zonaro/Jolven/">'
                '<key name="theme-slug" type="s"><default>"jolven"</default></key>'
                '<key name="theme-accent-custom" type="s">'
                '<default>""</default></key>'
                '</schema></schemalist>'
            )
            (live_root / "usr/share/glib-2.0/schemas"
             / "io.github.zonaro.Jolven.gschema.xml").write_text(schema)
            iso_root = work / "iso_root" / "LiveOS"
            iso_root.mkdir(parents=True)
            run("mksquashfs", str(live_root), str(iso_root / "squashfs.img"),
                "-noappend", "-comp", "gzip", "-processors", "2")
            source = work / "source.iso"
            # Synthetic El Torito catalog verifies boot metadata replay.
            # These dummy bytes are NOT executable bootloader code.
            (work / "iso_root" / "dummy-boot.img").write_bytes(bytes(2048))
            run("xorriso", "-as", "mkisofs", "-o", str(source),
                "-b", "dummy-boot.img", "-no-emul-boot",
                str(work / "iso_root"))

            archive_path = work / "jolven.tar.gz"
            entries = {
                "usr/bin/jolven": b"#!/bin/sh\n",
                "usr/bin/jolven-session": b"#!/bin/sh\n",
                "usr/libexec/jolven-game-mode-setup": b"#!/bin/sh\n",
            }
            with tarfile.open(archive_path, "w:gz") as archive:
                for name, data in entries.items():
                    item = tarfile.TarInfo(name)
                    item.size = len(data)
                    item.mode = 0o755
                    archive.addfile(item, io.BytesIO(data))
            digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
            output = work / "custom.iso"
            report = remaster_iso(
                source, output,
                jolven_archive=archive_path,
                jolven_sha256=digest,
                appearance={"theme": "Jolven", "accent_hex": "#A78BFA"},
                extras=["retroarch"],
                experimental=True,
            )
            self.assertEqual(report["status"], "experimental_unverified_iso")
            self.assertEqual(report["source_root_identity"]["distribution"], "nobara")
            self.assertEqual(report["structural_audit"]["optical_boot_images"], 1)
            self.assertFalse(report["structural_audit"]["boot_verified"])
            self.assertTrue(output.exists())
            saved = work / "saved-squash.img"
            run("xorriso", "-osirrox", "on", "-indev", str(output),
                "-extract", "/LiveOS/squashfs.img", str(saved))
            unpacked = work / "unpacked"
            run("unsquashfs", "-d", str(unpacked), str(saved))
            self.assertTrue((unpacked / "usr/bin/jolven").is_file())
            self.assertTrue((unpacked / "usr/share/wayland-sessions"
                             / "io.github.zonaro.Jolven.GameMode.desktop").is_file())
            self.assertTrue((unpacked / "usr/share/glib-2.0/schemas"
                             / "99_jolven_iso.gschema.override").is_file())
            self.assertTrue((unpacked / "usr/share/jolven-iso"
                             / "optional-packages.json").is_file())
            self.assertTrue((unpacked / "etc/xdg/autostart"
                             / "jolven-iso-setup.desktop").is_file())
            self.assertTrue((unpacked / "usr/libexec"
                             / "jolven-iso-first-run").is_file())
            mismatched = work / "Nobara-45-GNOME-2026-08-28.iso"
            source.rename(mismatched)
            blocked = work / "should-not-exist.iso"
            with self.assertRaisesRegex(RemasterError, "VERSION_ID differ"):
                remaster_iso(
                    mismatched, blocked,
                    jolven_archive=archive_path,
                    jolven_sha256=digest,
                    appearance={"theme": "Jolven", "accent_hex": "#A78BFA"},
                    experimental=True,
                )
            self.assertFalse(blocked.exists())


if __name__ == "__main__":
    unittest.main()

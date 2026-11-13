import 'package:flutter_test/flutter_test.dart';
import 'package:jolven_iso/services/official_iso_catalog.dart';
import 'package:jolven_iso/services/iso_downloader.dart';

void main() {
  final hash = ''.padRight(64, 'a');
  final shortHash = ''.padRight(32, 'b');

  test('Ubuntu lists only Desktop amd64 and validates named SHA256', () {
    final sums = '$hash *ubuntu-26.04.1-desktop-amd64.iso\n'
        '$hash *ubuntu-26.04.1-live-server-amd64.iso\n';
    final images = OfficialIsoCatalog.ubuntu('26.04', sums);
    expect(images, hasLength(1));
    expect(images.single.name, 'ubuntu-26.04.1-desktop-amd64.iso');
    expect(OfficialIsoCatalog.trustedDownload(images.single), isTrue);
    expect(OfficialIsoCatalog.parseChecksum(
        sums, images.single.name, 'sha256'), hash);
  });

  test('CachyOS latest Desktop ISO requires official host and SHA256', () {
    final source = OfficialIsoCatalog.cachyos('260809',
        '<a href="cachyos-desktop-linux-260809.iso">ISO</a>'
        '<a href="cachyos-desktop-linux-260809.iso.sha256">SHA</a>');
    expect(source, hasLength(1));
    expect(OfficialIsoCatalog.trustedDownload(source.single), isTrue);
    expect(OfficialIsoCatalog.parseChecksum(
      '$hash  cachyos-desktop-linux-260809.iso',
      source.single.name, 'sha256'), hash);
    expect(OfficialIsoCatalog.cachyos('260809',
      '<a href="evil.iso">Wrong image</a>'), isEmpty);
  });

  test('BigLinux selects only latest dated ISOs and records MD5 limitation', () {
    final images = OfficialIsoCatalog.biglinux('''
<a href="biglinux_2026-08-19_k612.iso">old</a>
<a href="biglinux_2026-10-03_k612.iso">older kernel</a>
<a href="biglinux_2026-10-03_k618.iso">default</a>
<a href="biglinux_2026-10-03_k72.iso">new kernel</a>
<a href="xivastudio_2026-10-16_k618.iso">not BigLinux</a>
''');
    expect(images, hasLength(3));
    expect(images.every((iso) => iso.algorithm == 'md5'), isTrue);
    expect(images.every(OfficialIsoCatalog.trustedDownload), isTrue);
    expect(OfficialIsoCatalog.parseChecksum(
      '$shortHash *biglinux_2026-10-03_k618.iso',
      'biglinux_2026-10-03_k618.iso', 'md5'), shortHash);
  });

  test('Fedora reads x86_64 ISO from signed-manifest style', () {
    const filename = 'Fedora-Workstation-Live-45-1.4.x86_64.iso';
    final manifests = '-----BEGIN PGP SIGNED MESSAGE-----\n'
        'Hash: SHA256\n\nSHA256 ($filename) = $hash\n';
    final images = OfficialIsoCatalog.fedora(45, '1.4', manifests);
    expect(images, hasLength(1));
    expect(images.single.name, filename);
    expect(OfficialIsoCatalog.trustedDownload(images.single), isTrue);
    expect(OfficialIsoCatalog.parseChecksum(
      manifests, filename, 'sha256'), hash);
  });

  test('unknown hosts and checksum tampering are rejected', () {
    final iso = OfficialIsoCatalog.ubuntu('26.04',
      '$hash  ubuntu-26.04.1-desktop-amd64.iso').single;
    final bad = OfficialIso(
      distribution: 'ubuntu', name: iso.name,
      url: Uri.parse('https://example.com/ubuntu.iso'),
      checksumUrl: iso.checksumUrl,
      algorithm: 'sha256', label: 'bad');
    expect(OfficialIsoCatalog.trustedDownload(bad), isFalse);
    expect(() => OfficialIsoCatalog.parseChecksum(
      '$hash  another.iso', iso.name, 'sha256'), throwsFormatException);
    expect(IsoDownloader.safeRedirect(
        Uri.parse('http://localhost/image.iso')), isFalse);
    expect(IsoDownloader.safeRedirect(
        Uri.parse('https://127.0.0.1/image.iso')), isFalse);
    expect(IsoDownloader.safeRedirect(
        Uri.parse('https://mirror.example.org/image.iso')), isTrue);
  });
}

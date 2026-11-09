import 'package:flutter_test/flutter_test.dart';
import 'package:jolven_iso/models/iso_project.dart';
import 'package:jolven_iso/services/nobara_catalog.dart';

void main() {
  const iso = 'Nobara-44-GNOME-2026-08-28.iso';
  const root = 'https://nobara-images.nobaraproject.org';
  final sample = '''
<article class="card download-row">
<a href="$root/$iso.sha256sum">Checksum</a>
<button class="button button--primary download-btn"
 data-iso="$iso"
 data-url="$root/$iso">Download</button>
</article>''';

  test('lê somente a ISO anunciada pelo site oficial', () {
    final images = NobaraCatalog.parseDownloadPage(sample);
    expect(images.length, 1);
    expect(images.single.edition, NobaraEdition.gnome);
    expect(images.single.url.host, 'nobara-images.nobaraproject.org');
  });

  test('recusa URLs fora do domínio oficial e nome inconsistente', () {
    expect(
      NobaraCatalog.parseDownloadPage(
        sample.replaceAll(root, 'https://invalid.example')),
      isEmpty,
    );
    expect(
      NobaraCatalog.parseDownloadPage(
        sample.replaceFirst('data-iso="$iso"', 'data-iso="fake.iso"')),
      isEmpty,
    );
  });

  test('confere arquivo associado à linha de checksum', () {
    final hash = ''.padRight(64, 'a');
    expect(NobaraCatalog.parseChecksum('$hash  $iso\n', iso), hash);
    expect(NobaraCatalog.parseChecksum('$hash\n', iso), hash);
    expect(() => NobaraCatalog.parseChecksum('$hash  outro.iso', iso),
        throwsFormatException);
  });
}

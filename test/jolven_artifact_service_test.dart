import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jolven_iso/services/jolven_artifact_service.dart';

void main() {
  final name = 'jolven-linux-x86_64-${''.padRight(40, 'a')}.tar.gz';
  const tag = 'v0.2.0-preview';
  final base = 'https://github.com/zonaro/jolven-iso/releases/download/$tag';

  test('aceita somente pacote e checksum da mesma release', () {
    final json = jsonEncode({
      'tag_name': tag,
      'assets': [
        {'name': name, 'browser_download_url': '$base/$name'},
        {'name': '$name.sha256',
          'browser_download_url': '$base/$name.sha256'},
      ],
    });
    final release = JolvenArtifactService.parseRelease(json);
    expect(release.name, name);
    expect(release.version, tag);
  });

  test('rejeita arquivo fora do GitHub e sem checksum pareado', () {
    expect(
      () => JolvenArtifactService.parseRelease(jsonEncode({
        'tag_name': tag,
        'assets': [
          {'name': name, 'browser_download_url': 'https://evil.example/$name'},
        ],
      })),
      throwsFormatException,
    );
    expect(
      () => JolvenArtifactService.parseRelease(jsonEncode({
        'tag_name': tag,
        'assets': [
          {'name': name, 'browser_download_url': '$base/$name'},
        ],
      })),
      throwsFormatException,
    );
  });

  test('localiza artefato em lista de releases incluindo preview', () {
    final list = jsonEncode([
      {'tag_name': 'v0.1.0', 'assets': []},
      {
        'tag_name': tag,
        'assets': [
          {'name': name, 'browser_download_url': '$base/$name'},
          {'name': '$name.sha256',
            'browser_download_url': '$base/$name.sha256'},
        ],
      },
    ]);
    final artifact = JolvenArtifactService.parseReleases(list);
    expect(artifact.version, tag);
    expect(
      () => JolvenArtifactService.parseReleases('[]'),
      throwsFormatException,
    );
  });

  test('checksum exige nome do tarball ou digest isolado', () {
    final digest = ''.padRight(64, 'b');
    expect(JolvenArtifactService.parseChecksum('$digest  $name', name), digest);
    expect(JolvenArtifactService.parseChecksum(digest, name), digest);
    expect(
      () => JolvenArtifactService.parseChecksum('$digest  wrong.tar.gz', name),
      throwsFormatException,
    );
  });
}

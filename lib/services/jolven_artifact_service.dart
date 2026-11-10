import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Release-managed Jolven usr/ tarball; never run scripts from this download.
class JolvenReleaseAsset {
  const JolvenReleaseAsset({
    required this.name,
    required this.archive,
    required this.checksum,
    required this.version,
  });

  final String name;
  final Uri archive;
  final Uri checksum;
  final String version;
}

class JolvenArtifactService {
  static final Uri api = Uri.parse(
    'https://api.github.com/repos/zonaro/jolven-iso/releases?per_page=10',
  );
  static const maxMetadataBytes = 1024 * 1024;
  static const maxChecksumBytes = 4096;
  static const maxArchiveBytes = 1024 * 1024 * 1024;

  static final _artifactName =
      RegExp(r'^jolven-linux-x86_64-[a-f0-9]{40}\.tar\.gz$');

  static bool trustedAsset(Uri uri, String name) =>
      uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      uri.userInfo.isEmpty && uri.query.isEmpty && uri.fragment.isEmpty &&
      uri.pathSegments.length == 6 &&
      uri.pathSegments[0] == 'zonaro' &&
      uri.pathSegments[1] == 'jolven-iso' &&
      uri.pathSegments[2] == 'releases' &&
      uri.pathSegments[3] == 'download' &&
      uri.pathSegments.last == name;

  static JolvenReleaseAsset parseRelease(String content) {
    final data = jsonDecode(content);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Resposta de release inválida.');
    }
    final tag = data['tag_name'];
    final assets = data['assets'];
    if (tag is! String || tag.isEmpty || assets is! List) {
      throw const FormatException('Release sem versão ou arquivos.');
    }
    final candidates = <String, Uri>{};
    for (final item in assets) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final name = item['name'];
      final raw = item['browser_download_url'];
      if (name is! String || raw is! String) {
        continue;
      }
      final url = Uri.tryParse(raw);
      if (url == null || !trustedAsset(url, name)) {
        continue;
      }
      if (url.pathSegments[4] != tag) {
        continue;
      }
      candidates[name] = url;
    }
    for (final entry in candidates.entries) {
      if (!_artifactName.hasMatch(entry.key)) {
        continue;
      }
      final check = candidates['${entry.key}.sha256'];
      if (check != null) {
        return JolvenReleaseAsset(
          name: entry.key,
          archive: entry.value,
          checksum: check,
          version: tag,
        );
      }
    }
    throw const FormatException(
      'Release ainda não possui tarball Jolven x86_64 e checksum correspondentes.',
    );
  }

  static String parseChecksum(String content, String name) {
    for (final line in content.trim().split(RegExp(r'\r?\n'))) {
      final match =
          RegExp(r'^([a-f0-9A-F]{64})(?:\s+\*?(.+))?$').firstMatch(line.trim());
      if (match == null) {
        continue;
      }
      final actualName = match.group(2);
      if (actualName != null && actualName != name) {
        continue;
      }
      return match.group(1)!.toLowerCase();
    }
    throw const FormatException('Checksum Jolven inválido ou com nome divergente.');
  }

  Future<String> _text(Uri uri, {required int limit}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'Jolven-ISO-Builder');
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok ||
          response.redirects.any((x) => x.location.scheme != 'https')) {
        throw const HttpException('Não foi possível consultar release via HTTPS.');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Resposta maior do que o limite seguro.');
        }
        bytes.addAll(chunk);
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }

  static JolvenReleaseAsset parseReleases(String content) {
    final releases = jsonDecode(content);
    if (releases is! List) {
      throw const FormatException('Lista de releases inválida.');
    }
    for (final release in releases) {
      if (release is! Map<String, dynamic>) {
        continue;
      }
      try {
        return parseRelease(jsonEncode(release));
      } on FormatException {
        // Older releases may predate the pinned Jolven artifact.
      }
    }
    throw const FormatException(
      'Nenhuma release com pacote Jolven verificável foi publicada ainda.',
    );
  }

  Future<JolvenReleaseAsset> latest() async {
    try {
      return parseReleases(await _text(api, limit: maxMetadataBytes));
    } on HttpException {
      throw const FormatException(
        'Não foi possível consultar as releases do Builder.',
      );
    }
  }

  Future<String> expectedSha256(JolvenReleaseAsset release) =>
      _text(release.checksum, limit: maxChecksumBytes).then(
        (value) => parseChecksum(value, release.name),
      );

  Future<String> download({
    required JolvenReleaseAsset release,
    required File destination,
    required String expectedSha256,
    required void Function(int, int?) onProgress,
  }) async {
    if (!trustedAsset(release.archive, release.name) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256)) {
      throw const FormatException('Origem/assinatura do pacote inválida.');
    }
    if (await destination.exists()) {
      throw const FileSystemException('Destino já existe.');
    }
    final temp = File('${destination.path}.part');
    if (await temp.exists()) {
      throw const FileSystemException(
        'Download parcial existente; selecione outro destino.',
      );
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(release.archive);
      request.headers.set(HttpHeaders.userAgentHeader, 'Jolven-ISO-Builder');
      request.followRedirects = true;
      request.maxRedirects = 5;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok ||
          response.redirects.any((x) => x.location.scheme != 'https')) {
        throw const FormatException('Redirect/HTTP inválido no pacote Jolven.');
      }
      var count = 0;
      final stream = temp.openWrite(mode: FileMode.write);
      try {
        await for (final chunk in response) {
          count += chunk.length;
          if (count > maxArchiveBytes) {
            throw const FormatException('Pacote excede o limite permitido.');
          }
          stream.add(chunk);
          onProgress(count, response.contentLength > 0
              ? response.contentLength : null);
        }
      } finally {
        await stream.flush();
        await stream.close();
      }
      final actual = (await sha256.bind(temp.openRead()).first).toString();
      if (actual != expectedSha256) {
        throw const FormatException('Checksum Jolven divergente; rejeitado.');
      }
      if (await destination.exists()) {
        throw const FileSystemException('Destino criado durante download.');
      }
      await temp.rename(destination.path);
      return actual;
    } finally {
      client.close(force: true);
      if (await temp.exists()) {
        await temp.delete();
      }
    }
  }
}

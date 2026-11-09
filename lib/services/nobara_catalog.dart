import 'dart:io';

import '../models/iso_project.dart';

/// HTTPS trust from Nobara's website; not a cryptographic release signature.
class NobaraIso {
  const NobaraIso({required this.edition, required this.name,
    required this.url, required this.checksumUrl});
  final NobaraEdition edition;
  final String name;
  final Uri url;
  final Uri checksumUrl;
}

class NobaraCatalog {
  static final Uri page = Uri.parse('https://nobaraproject.org/download.html');
  static const maxHtmlBytes = 2 * 1024 * 1024;
  static const maxChecksumBytes = 4096;
  static final _isoName = RegExp(
    r'^Nobara-[0-9]+-(Official|GNOME|KDE|Steam-HTPC|Steam-Handheld)-'
    r'[0-9]{4}-[0-9]{2}-[0-9]{2}\.iso$',
  );

  static bool trustedDownloadUri(Uri uri) =>
      uri.scheme == 'https' &&
      uri.host == 'nobara-images.nobaraproject.org' &&
      !uri.hasPort && uri.userInfo.isEmpty &&
      uri.query.isEmpty && uri.fragment.isEmpty;

  static NobaraEdition? _editionOf(String filename) {
    final match = _isoName.firstMatch(filename);
    if (match == null) return null;
    switch (match.group(1)) {
      case 'Official': return NobaraEdition.official;
      case 'GNOME': return NobaraEdition.gnome;
      case 'KDE': return NobaraEdition.kde;
      case 'Steam-HTPC': return NobaraEdition.steamHtpc;
      case 'Steam-Handheld': return NobaraEdition.steamHandheld;
    }
    return null;
  }

  /// Fail closed if the upstream markup or URLs change unexpectedly.
  static List<NobaraIso> parseDownloadPage(String html) {
    final matches = RegExp(
      r'data-iso="([^"]+)"\s+data-url="([^"]+)"',
      multiLine: true,
    ).allMatches(html);
    final records = <NobaraEdition, NobaraIso>{};
    for (final match in matches) {
      final name = match.group(1)!;
      final edition = _editionOf(name);
      final url = Uri.tryParse(match.group(2)!);
      if (edition == null || url == null || !trustedDownloadUri(url)) continue;
      if (url.pathSegments.last != name) continue;
      final sectionStart = html.lastIndexOf('<article', match.start);
      if (sectionStart < 0) continue;
      final segment = html.substring(sectionStart, match.start);
      final checksumMatches =
          RegExp(r'href="([^"]+\.iso\.sha256sum)"').allMatches(segment);
      if (checksumMatches.isEmpty) continue;
      final checksumUrl = Uri.tryParse(checksumMatches.last.group(1)!);
      if (checksumUrl == null ||
          !trustedDownloadUri(checksumUrl) ||
          checksumUrl.pathSegments.last != '$name.sha256sum') continue;
      records[edition] = NobaraIso(
        edition: edition, name: name, url: url, checksumUrl: checksumUrl);
    }
    return [
      for (final edition in NobaraEdition.values)
        if (records.containsKey(edition)) records[edition]!,
    ];
  }

  static String parseChecksum(String content, String filename) {
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      final match = RegExp(r'^([a-fA-F0-9]{64})(?:\s+\*?(.+))?$')
          .firstMatch(line);
      if (match == null) continue;
      final namedFile = match.group(2)?.trim();
      if (namedFile != null && namedFile != filename) continue;
      return match.group(1)!.toLowerCase();
    }
    throw const FormatException('Checksum oficial inválido ou incompatível.');
  }

  static Future<String> _fetchText(
    Uri uri, {required int limit, required bool Function(Uri) trust}
  ) async {
    if (!trust(uri)) {
      throw const FormatException('Endereço não pertence à origem oficial.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    client.autoUncompress = true;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: uri);
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > limit) {
          throw const FormatException('Resposta oficial excedeu o limite.');
        }
        bytes.addAll(chunk);
      }
      return String.fromCharCodes(bytes);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<NobaraIso>> load() async {
    final html = await _fetchText(
      page, limit: maxHtmlBytes, trust: (uri) => uri == page);
    final catalog = parseDownloadPage(html);
    if (catalog.isEmpty) {
      throw const FormatException(
        'O formato da página oficial mudou. Não é seguro inferir downloads.');
    }
    return catalog;
  }

  Future<String> expectedHash(NobaraIso iso) async {
    final content = await _fetchText(
      iso.checksumUrl, limit: maxChecksumBytes, trust: trustedDownloadUri);
    return parseChecksum(content, iso.name);
  }
}

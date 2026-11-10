import 'dart:io';
import 'package:crypto/crypto.dart';
import 'nobara_catalog.dart';
import 'iso_signature.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Download cancelado; arquivo parcial preservado.';
}

class IsoDownloader {
  HttpClient? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  /// Uses a .part file, resumes only with a valid HTTP Content-Range, and
  /// refuses to expose the final ISO until its checksum matches upstream.
  Future<String> download(
    NobaraIso iso, File destination, {
    required String expectedSha256,
    required void Function(int bytes, int? total) onProgress,
  }) async {
    if (!NobaraCatalog.trustedDownloadUri(iso.url) ||
        iso.url.pathSegments.last != iso.name) {
      throw const FormatException('ISO de origem não confiável.');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256)) {
      throw const FormatException('Checksum SHA-256 oficial inválido.');
    }
    if (await destination.exists()) {
      throw const FileSystemException('Destino já existe. Escolha outro nome.');
    }
    _cancelled = false;
    final partial = File('${destination.path}.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    _client = client;
    try {
      var offset = await partial.exists() ? await partial.length() : 0;
      final request = await client.getUrl(iso.url);
      request.followRedirects = false;
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close();
      if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
          offset > 0) {
        // May already be complete. Checksum below is the authority.
      } else {
        if (response.statusCode == HttpStatus.partialContent) {
          final contentRange =
              response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
          if (!contentRange.startsWith('bytes $offset-')) {
            throw const FormatException('Resposta HTTP Range incompatível.');
          }
        } else if (response.statusCode == HttpStatus.ok) {
          offset = 0; // Server ignored Range, restart rather than append.
        } else {
          throw HttpException('Download HTTP ${response.statusCode}', uri: iso.url);
        }
        final total = response.contentLength < 0
            ? null
            : offset + response.contentLength;
        final writer = partial.openWrite(
          mode: offset == 0 ? FileMode.write : FileMode.append,
        );
        try {
          await for (final chunk in response) {
            if (_cancelled) throw const DownloadCancelled();
            writer.add(chunk);
            offset += chunk.length;
            onProgress(offset, total);
          }
        } finally {
          await writer.flush();
          await writer.close();
        }
      }
      if (_cancelled) throw const DownloadCancelled();
      final hash = (await sha256.bind(partial.openRead()).first).toString();
      if (hash != expectedSha256) {
        await partial.delete();
        throw const FormatException(
          'SHA-256 divergente. Download descartado por segurança.');
      }
      if (!await IsoSignature.isIso9660(partial)) {
        await partial.delete();
        throw const FormatException('Download não contém uma imagem ISO-9660 válida.');
      }
      if (await destination.exists()) {
        throw const FileSystemException('Destino já existe. Escolha outro nome.');
      }
      await partial.rename(destination.path);
      return hash;
    } finally {
      _client = null;
      client.close(force: true);
    }
  }
}

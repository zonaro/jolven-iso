// ignore_for_file: prefer_interpolation_to_compose_strings, prefer_adjacent_string_concatenation, curly_braces_in_flow_control_structures

import 'dart:io';
import 'package:crypto/crypto.dart';
import 'nobara_catalog.dart';
import 'official_iso_catalog.dart';
import 'iso_signature.dart';

class DownloadCancelled implements Exception {
  const DownloadCancelled();
  @override
  String toString() => 'Download cancelado; arquivo parcial preservado.';
}

class IsoDownloadResult {
  const IsoDownloadResult(this.sha256, this.verifiedAlgorithm);
  final String sha256;
  final String verifiedAlgorithm;
}

/// Shared streaming downloader for Nobara and other official distro catalogs.
/// No completed ISO is published until its upstream checksum is matched.
class IsoDownloader {
  HttpClient? _client;
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<String> download(
    NobaraIso iso, File destination, {
    required String expectedSha256,
    required void Function(int bytes, int? total) onProgress,
  }) async {
    if (!NobaraCatalog.trustedDownloadUri(iso.url) ||
        iso.url.pathSegments.last != iso.name) {
      throw const FormatException('ISO de origem não confiável.');
    }
    final value = await _download(iso.url, destination,
      expected: expectedSha256, kind: 'sha256',
      onProgress: onProgress);
    return value.sha256;
  }

  Future<IsoDownloadResult> downloadOfficial(
    OfficialIso iso, File destination, {
    required String expectedDigest,
    required void Function(int bytes, int? total) onProgress,
  }) async {
    if (!OfficialIsoCatalog.trustedDownload(iso)) {
      throw const FormatException('Origem de ISO fora do catálogo oficial.');
    }
    return _download(iso.url, destination, expected: expectedDigest,
      kind: iso.algorithm, onProgress: onProgress);
  }

  static bool safeRedirect(Uri uri) {
    if (uri.scheme != 'https' || uri.userInfo.isNotEmpty ||
        uri.hasPort || uri.host.isEmpty || !uri.host.contains('.') ||
        uri.host == 'localhost' || uri.host.endsWith('.localhost') ||
        uri.host.endsWith('.local') || uri.host.endsWith('.internal') ||
        uri.host.contains(':') ||
        RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(uri.host)) {
      return false;
    }
    return true;
  }

  Future<HttpClientResponse> _open(
      HttpClient client, Uri original, int offset) async {
    var url = original;
    for (var hop = 0; hop <= 6; hop++) {
      if (_cancelled) throw const DownloadCancelled();
      if (hop > 0 && !safeRedirect(url)) {
        throw const FormatException('Redirecionamento HTTPS inseguro.');
      }
      final req = await client.getUrl(url);
      req.followRedirects = false;
      if (offset > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      final response = await req.close();
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw const FormatException('Redirecionamento sem destino.');
        }
        url = url.resolve(location);
        await response.drain<void>();
        continue;
      }
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent &&
          !(response.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
            offset > 0)) {
        throw HttpException('Download HTTP ' + response.statusCode.toString(), uri: url);
      }
      return response;
    }
    throw const FormatException('Muitos redirecionamentos na ISO.');
  }

  Future<IsoDownloadResult> _download(Uri source, File destination, {
    required String expected,
    required String kind,
    required void Function(int bytes, int? total) onProgress,
  }) async {
    final size = kind == 'md5' ? 32 : kind == 'sha256' ? 64 : 0;
    if (size == 0 || !RegExp('^[a-fA-F0-9]{$size}' + r'$').hasMatch(expected)) {
      throw const FormatException('Checksum oficial inválido.');
    }
    if (await destination.exists()) {
      throw const FileSystemException('Destino já existe; escolha outro nome.');
    }
    _cancelled = false;
    final partial = File(destination.path + '.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    _client = client;
    try {
      var offset = await partial.exists() ? await partial.length() : 0;
      final response = await _open(client, source, offset);
      if (response.statusCode != HttpStatus.requestedRangeNotSatisfiable) {
        if (response.statusCode == HttpStatus.partialContent) {
          final range = response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
          final parsed = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
          if (parsed == null || int.parse(parsed.group(1)!) != offset ||
              int.parse(parsed.group(2)!) < offset ||
              int.parse(parsed.group(3)!) <= int.parse(parsed.group(2)!)) {
            throw const FormatException('Resposta HTTP Range incompatível.');
          }
        } else {
          offset = 0; // Server ignored Range: restart, never append.
        }
        final total = response.contentLength < 0
            ? null : offset + response.contentLength;
        final writer = partial.openWrite(
          mode: offset == 0 ? FileMode.write : FileMode.append);
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
      final digest = (await (kind == 'md5' ? md5 : sha256)
          .bind(partial.openRead()).first).toString();
      if (digest != expected.toLowerCase()) {
        await partial.delete();
        throw const FormatException('Checksum divergente. ISO parcial descartada.');
      }
      if (!await IsoSignature.isIso9660(partial)) {
        await partial.delete();
        throw const FormatException('Arquivo não é uma ISO-9660 válida.');
      }
      final sha = kind == 'sha256' ? digest :
          (await sha256.bind(partial.openRead()).first).toString();
      if (_cancelled) throw const DownloadCancelled();
      if (await destination.exists()) {
        throw const FileSystemException('Destino criado por outro processo.');
      }
      await partial.rename(destination.path);
      return IsoDownloadResult(sha, kind);
    } catch (error) {
      if (_cancelled) throw const DownloadCancelled();
      rethrow;
    } finally {
      _client = null;
      client.close(force: true);
    }
  }
}

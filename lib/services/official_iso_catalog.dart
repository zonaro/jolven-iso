import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class OfficialIso {
  const OfficialIso({required this.distribution, required this.name,
    required this.url, required this.checksumUrl, required this.algorithm,
    required this.label});
  final String distribution, name, algorithm, label;
  final Uri url, checksumUrl;
}

/// ISO metadata comes from HTTPS directories controlled by each distro.
class OfficialIsoCatalog {
  static bool trustedUri(Uri url, String host) =>
      url.scheme == 'https' && url.host == host && !url.hasPort &&
      url.userInfo.isEmpty && url.query.isEmpty && url.fragment.isEmpty;

  static bool trustedDownload(OfficialIso iso) {
    const hosts = {
      'ubuntu': ['releases.ubuntu.com', 'releases.ubuntu.com', 'sha256'],
      'cachyos': ['build.cachyos.org', 'build.cachyos.org', 'sha256'],
      'biglinux': ['iso.biglinux.com.br', 'iso.biglinux.com.br', 'md5'],
      'fedora': ['download.fedoraproject.org', 'dl.fedoraproject.org', 'sha256'],
    };
    final rule = hosts[iso.distribution];
    if (rule == null || !iso.name.endsWith('.iso') || iso.name.contains('..') ||
        iso.url.pathSegments.last != iso.name ||
        !trustedUri(iso.url, rule[0]) || !trustedUri(iso.checksumUrl, rule[1]) ||
        iso.algorithm != rule[2]) return false;
    switch (iso.distribution) {
      case 'ubuntu':
        return iso.checksumUrl.pathSegments.last == 'SHA256SUMS' &&
            iso.url.pathSegments.length == iso.checksumUrl.pathSegments.length &&
            iso.url.pathSegments.first == iso.checksumUrl.pathSegments.first;
      case 'cachyos':
        return iso.checksumUrl.path == iso.url.path + '.sha256';
      case 'biglinux':
        return iso.checksumUrl.path == iso.url.path + '.md5';
      case 'fedora':
        return iso.checksumUrl.path.endsWith('-CHECKSUM') &&
            iso.url.pathSegments.length == iso.checksumUrl.pathSegments.length &&
            iso.url.pathSegments.take(8).join('/') ==
                iso.checksumUrl.pathSegments.take(8).join('/');
    }
    return false;
  }

  Future<String> _get(Uri url, String host, int limit) async {
    if (!trustedUri(url, host)) {
      throw const FormatException('Endereço do catálogo não confiável.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await client.getUrl(url);
      req.followRedirects = false;
      final response = await req.close();
      if (response.statusCode != 200) {
        throw HttpException('Catálogo HTTP ' + response.statusCode.toString(), uri: url);
      }
      final data = BytesBuilder(copy: false);
      await for (final part in response) {
        if (data.length + part.length > limit) {
          throw const FormatException('Catálogo oficial excedeu o limite.');
        }
        data.add(part);
      }
      return utf8.decode(data.takeBytes());
    } finally {
      client.close(force: true);
    }
  }

  static List<String> hrefs(String html, RegExp pattern) {
    final names = <String>{};
    for (final match in RegExp(r'''href\s*=\s*["']([^"']+)["']''',
        caseSensitive: false).allMatches(html)) {
      final value = match.group(1)!;
      if (pattern.hasMatch(value)) names.add(value);
    }
    return names.toList()..sort();
  }

  static String parseChecksum(String text, String filename, String algorithm) {
    if (algorithm != 'sha256' && algorithm != 'md5') {
      throw const FormatException('Checksum desconhecido.');
    }
    final size = algorithm == 'sha256' ? 64 : 32;
    final check = RegExp('^[a-fA-F0-9]{$size}' + r'$');
    for (final row in const LineSplitter().convert(text)) {
      final sum = RegExp(r'^([a-fA-F0-9]+)\s+\*?(\S+)$')
          .firstMatch(row.trim());
      if (sum != null && sum.group(2) == filename &&
          check.hasMatch(sum.group(1)!)) return sum.group(1)!.toLowerCase();
      final rpm = RegExp(r'^SHA256 \(([^)]+\.iso)\) = ([a-fA-F0-9]{64})$')
          .firstMatch(row.trim());
      if (algorithm == 'sha256' && rpm != null &&
          rpm.group(1) == filename) return rpm.group(2)!.toLowerCase();
    }
    throw FormatException('Checksum oficial não encontrado para $filename.');
  }

  static List<OfficialIso> ubuntu(String release, String text) {
    final names = <String>{};
    for (final line in const LineSplitter().convert(text)) {
      final match = RegExp(
          r'^[a-fA-F0-9]{64}\s+\*?(ubuntu-\d{2}\.\d{2}(?:\.\d+)?-desktop-amd64\.iso)$')
          .firstMatch(line.trim());
      if (match != null) names.add(match.group(1)!);
    }
    return [for (final name in names)
      OfficialIso(distribution: 'ubuntu', name: name,
        url: Uri.parse('https://releases.ubuntu.com/$release/$name'),
        checksumUrl: Uri.parse('https://releases.ubuntu.com/$release/SHA256SUMS'),
        algorithm: 'sha256', label: 'Ubuntu ' + name.split('-')[1] + ' · Desktop amd64')];
  }

  static List<OfficialIso> cachyos(String version, String html) {
    final name = 'cachyos-desktop-linux-$version.iso';
    if (!hrefs(html, RegExp('^' + RegExp.escape(name) + r'$')).contains(name)) {
      return [];
    }
    return [OfficialIso(distribution: 'cachyos', name: name,
      url: Uri.parse('https://build.cachyos.org/ISO/desktop/$version/$name'),
      checksumUrl: Uri.parse('https://build.cachyos.org/ISO/desktop/$version/$name.sha256'),
      algorithm: 'sha256', label: 'CachyOS Desktop $version · x86_64')];
  }

  static List<OfficialIso> biglinux(String html) {
    final files = hrefs(html, RegExp(r'^biglinux_\d{4}-\d{2}-\d{2}_k\d+\.iso$'));
    if (files.isEmpty) return [];
    final latest = files.last.substring(9, 19);
    return [for (final name in files)
      if (name.substring(9, 19) == latest)
        OfficialIso(distribution: 'biglinux', name: name,
          url: Uri.parse('https://iso.biglinux.com.br/$name'),
          checksumUrl: Uri.parse('https://iso.biglinux.com.br/$name.md5'),
          algorithm: 'md5', label: 'BigLinux ' + name.substring(9))];
  }

  static List<OfficialIso> fedora(int release, String build, String checksum) {
    final names = <String>{};
    for (final line in const LineSplitter().convert(checksum)) {
      final match = RegExp(
          r'^SHA256 \((Fedora-Workstation-[A-Za-z0-9._-]+\.iso)\) = [a-fA-F0-9]{64}$')
          .firstMatch(line.trim());
      if (match != null && match.group(1)!.contains('x86_64')) {
        names.add(match.group(1)!);
      }
    }
    return [for (final name in names)
      OfficialIso(distribution: 'fedora', name: name,
        url: Uri.parse('https://download.fedoraproject.org/pub/fedora/linux/releases/'
            '$release/Workstation/x86_64/iso/$name'),
        checksumUrl: Uri.parse('https://dl.fedoraproject.org/pub/fedora/linux/releases/'
            '$release/Workstation/x86_64/iso/Fedora-Workstation-$release-$build-x86_64-CHECKSUM'),
        algorithm: 'sha256', label: 'Fedora Workstation $release · x86_64')];
  }

  Future<List<OfficialIso>> load(String distribution) async {
    const maxPage = 2 * 1024 * 1024;
    const maxSums = 128 * 1024;
    switch (distribution) {
      case 'ubuntu':
        final index = await _get(Uri.parse('https://releases.ubuntu.com/'),
            'releases.ubuntu.com', maxPage);
        final dirs = hrefs(index, RegExp(r'^\d{2}\.\d{2}/$'));
        if (dirs.isEmpty) throw const FormatException('Catálogo Ubuntu vazio.');
        final selected = <String>{dirs.last};
        for (final dir in dirs.reversed) {
          if (dir.endsWith('.04/')) { selected.add(dir); break; }
        }
        final found = <OfficialIso>[];
        for (final dir in selected) {
          final version = dir.substring(0, dir.length - 1);
          final sums = await _get(
            Uri.parse('https://releases.ubuntu.com/$version/SHA256SUMS'),
            'releases.ubuntu.com', maxSums);
          found.addAll(ubuntu(version, sums));
        }
        return found;
      case 'cachyos':
        final index = await _get(
            Uri.parse('https://build.cachyos.org/ISO/desktop/'),
            'build.cachyos.org', maxPage);
        final dirs = hrefs(index, RegExp(r'^\d{6}/$'));
        if (dirs.isEmpty) throw const FormatException('Catálogo CachyOS vazio.');
        final version = dirs.last.replaceAll('/', '');
        return cachyos(version, await _get(Uri.parse(
            'https://build.cachyos.org/ISO/desktop/$version/'),
            'build.cachyos.org', maxPage));
      case 'biglinux':
        return biglinux(await _get(
            Uri.parse('https://iso.biglinux.com.br/'),
            'iso.biglinux.com.br', maxPage));
      case 'fedora':
        final page = await _get(
            Uri.parse('https://fedoraproject.org/workstation/download/'),
            'fedoraproject.org', maxPage);
        final match = RegExp(
            r'Fedora-Workstation-(\d+)-([0-9.]+)-x86_64-CHECKSUM')
            .firstMatch(page);
        if (match == null) throw const FormatException('Catálogo Fedora mudou.');
        final version = int.parse(match.group(1)!);
        final build = match.group(2)!;
        final sums = await _get(Uri.parse(
          'https://dl.fedoraproject.org/pub/fedora/linux/releases/'
          '$version/Workstation/x86_64/iso/Fedora-Workstation-$version-$build-x86_64-CHECKSUM'),
          'dl.fedoraproject.org', maxSums);
        return fedora(version, build, sums);
      default:
        throw const FormatException('Distribuição desconhecida.');
    }
  }

  Future<String> expectedHash(OfficialIso iso) async {
    if (!trustedDownload(iso)) {
      throw const FormatException('Origem da ISO não confiável.');
    }
    final checksum = await _get(iso.checksumUrl, iso.checksumUrl.host,
        128 * 1024);
    return parseChecksum(checksum, iso.name, iso.algorithm);
  }
}

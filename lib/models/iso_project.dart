enum NobaraEdition {
  official('official', 'Official (KDE)'),
  gnome('gnome', 'GNOME'),
  kde('kde', 'KDE'),
  steamHtpc('steam-htpc', 'Steam-HTPC'),
  steamHandheld('steam-handheld', 'Steam-Handheld');

  const NobaraEdition(this.id, this.label);
  final String id;
  final String label;
}

class IsoProject {
  const IsoProject({
    required this.edition,
    required this.sourceIso,
    required this.sourceSha256,
    required this.expectedSha256,
    required this.extras,
    required this.theme,
    required this.accentHex,
  });

  final NobaraEdition edition;
  final String sourceIso;
  final String sourceSha256;
  final String expectedSha256;
  final List<String> extras;
  final String theme;
  final String accentHex;

  static const knownExtras = <String>{
    'sunshine',
    'retroarch',
    'uzdoom',
    'eden',
    'cemu',
    'openrgb',
  };

  /// Published filenames encode an edition; avoid a contradictory selection.
  /// Local renamed files still require a staged root identity check.
  static bool filenameMatchesEdition(String filepath, NobaraEdition edition) {
    final name = filepath.replaceAll('\\', '/').split('/').last;
    final match = RegExp(
      r'^Nobara-[0-9]+-(Official|GNOME|KDE|Steam-HTPC|Steam-Handheld)-'
      r'[0-9]{4}-[0-9]{2}-[0-9]{2}\.iso$',
    ).firstMatch(name);
    if (match == null) return true;
    const labels = {
      NobaraEdition.official: 'Official',
      NobaraEdition.gnome: 'GNOME',
      NobaraEdition.kde: 'KDE',
      NobaraEdition.steamHtpc: 'Steam-HTPC',
      NobaraEdition.steamHandheld: 'Steam-Handheld',
    };
    return match.group(1) == labels[edition];
  }

  static final sha256Pattern = RegExp(r'^[a-fA-F0-9]{64}$');
  static final colorPattern = RegExp(r'^#[a-fA-F0-9]{6}$');

  bool get hashMatches =>
      sha256Pattern.hasMatch(expectedSha256) &&
      sourceSha256.toLowerCase() == expectedSha256.toLowerCase();

  Map<String, Object> toJson() => <String, Object>{
        'schema_version': 1,
        'distribution': 'nobara',
        'edition': edition.id,
        'source_iso': sourceIso,
        'source_sha256': sourceSha256.toLowerCase(),
        'expected_sha256': expectedSha256.toLowerCase(),
        'jolven_session': true,
        'extras': extras.toSet().toList()..sort(),
        'appearance': <String, String>{
          'theme': theme,
          'accent_hex': accentHex,
        },
      };

  factory IsoProject.fromJson(Map<String, dynamic> data) {
    if (data['schema_version'] != 1 || data['distribution'] != 'nobara') {
      throw const FormatException('Esquema ou distribuição não suportados.');
    }
    final editionName = data['edition'];
    final edition = NobaraEdition.values
        .where((item) => item.id == editionName)
        .firstOrNull;
    if (edition == null) {
      throw const FormatException('Edição Nobara desconhecida.');
    }
    if (data['jolven_session'] != true) {
      throw const FormatException('Jolven Session é obrigatória.');
    }
    final extras = (data['extras'] as List<dynamic>).cast<String>();
    final appearance = data['appearance'] as Map<String, dynamic>;
    final project = IsoProject(
      edition: edition,
      sourceIso: data['source_iso'] as String,
      sourceSha256: data['source_sha256'] as String,
      expectedSha256: data['expected_sha256'] as String,
      extras: extras,
      theme: appearance['theme'] as String,
      accentHex: appearance['accent_hex'] as String,
    );
    if (project.sourceIso.isEmpty ||
        !filenameMatchesEdition(project.sourceIso, project.edition) ||
        !project.hashMatches ||
        !colorPattern.hasMatch(project.accentHex) ||
        extras.any((item) => !knownExtras.contains(item))) {
      throw const FormatException('Projeto inválido ou hash não conferido.');
    }
    return project;
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:jolven_iso/models/iso_project.dart';

void main() {
  final hash = 'a' * 64;
  test('preserva as cinco edições sem inventar outra', () {
    expect(NobaraEdition.values.length, 5);
    expect(NobaraEdition.steamHandheld.id, 'steam-handheld');
  });

  test('exporta e importa projeto versionado, sem segredos', () {
    final project = IsoProject(
      edition: NobaraEdition.gnome,
      sourceIso: '/tmp/nobara.iso',
      sourceSha256: hash,
      expectedSha256: hash,
      extras: const ['sunshine', 'retroarch'],
      theme: 'Jolven',
      accentHex: '#A78BFA',
    );
    final data = project.toJson();
    expect(data['jolven_session'], true);
    expect(data.containsKey('api_key'), false);
    final roundTrip = IsoProject.fromJson(data);
    expect(roundTrip.edition, NobaraEdition.gnome);
    expect(roundTrip.hashMatches, true);
  });

  test('não aceita checksum divergente', () {
    final project = IsoProject(
      edition: NobaraEdition.kde,
      sourceIso: '/tmp/nobara.iso',
      sourceSha256: hash,
      expectedSha256: 'b' * 64,
      extras: const [],
      theme: 'Jolven',
      accentHex: '#A78BFA',
    );
    expect(project.hashMatches, false);
    expect(() => IsoProject.fromJson(project.toJson()), throwsFormatException);
  });
}

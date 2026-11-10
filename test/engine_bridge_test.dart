import 'package:flutter_test/flutter_test.dart';
import 'package:jolven_iso/services/engine_bridge.dart';

void main() {
  test('apresenta diagnóstico JSON de sucesso', () {
    const result = EngineResult(0, '{"mount_backend":"libguestfs-fuse"}', '');
    expect(result.ok, isTrue);
    expect(result.json?['mount_backend'], 'libguestfs-fuse');
  });

  test('mantém stderr legível quando o backend não existe', () {
    const result = EngineResult(2, '', 'Python não encontrado');
    expect(result.ok, isFalse);
    expect(result.json, isNull);
    expect(result.message, contains('Python'));
  });

  test('rejeita JSON inválido sem travar a interface', () {
    const result = EngineResult(0, 'log sem JSON', '');
    expect(result.json, isNull);
  });
}

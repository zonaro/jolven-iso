import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jolven_iso/services/iso_signature.dart';

void main() {
  test('detecta descritor ISO-9660 sem confundir hash com validade', () async {
    final dir = await Directory.systemTemp.createTemp('jolven-iso-signature-');
    try {
      final file = File('${dir.path}/synthetic.iso');
      final data = List<int>.filled(32774, 0);
      data.setRange(32769, 32774, 'CD001'.codeUnits);
      await file.writeAsBytes(data);
      expect(await IsoSignature.isIso9660(file), isTrue);
      await file.writeAsBytes([1, 2, 3, 4]);
      expect(await IsoSignature.isIso9660(file), isFalse);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}

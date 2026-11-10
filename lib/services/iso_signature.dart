import 'dart:io';

/// Basic ISO-9660 primary volume descriptor check. This only checks format,
/// not authenticity, edition, bootability, installed rootfs or signature.
class IsoSignature {
  static Future<bool> isIso9660(File file) async {
    if (!await file.exists() || await file.length() < 32774) {
      return false;
    }
    final reader = await file.open(mode: FileMode.read);
    try {
      await reader.setPosition(16 * 2048 + 1);
      return String.fromCharCodes(await reader.read(5)) == 'CD001';
    } finally {
      await reader.close();
    }
  }
}

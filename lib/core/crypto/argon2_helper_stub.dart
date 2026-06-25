import 'dart:typed_data';

Future<Uint8List> deriveArgon2Key(String password, Uint8List salt) async {
  throw UnsupportedError("Argon2 key derivation is not supported on this platform.");
}

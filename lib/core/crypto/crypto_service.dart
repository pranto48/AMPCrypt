import 'dart:typed_data';

abstract class CryptoService {
  /// Generates a cryptographically secure random byte array of the specified length.
  Uint8List generateSecureRandom(int length);

  /// Derives a 256-bit key from the password and salt using Argon2id.
  Future<Uint8List> deriveKey(String password, Uint8List salt);

  /// Splits a master secret into SLIP-39 mnemonic shares.
  ///
  /// [authLevel] controls the Group 1 configuration (1–4):
  ///   1FA → Group 1 = [1, 1]  (Password only)
  ///   2FA → Group 1 = [2, 2]  (Password + Fingerprint)
  ///   3FA → Group 1 = [3, 3]  (Password + Fingerprint + Face)
  ///   4FA → Group 1 = [4, 4]  (All four factors)
  /// Group 2 (Backup): always 2-of-3 threshold.
  List<String> splitSecret(Uint8List secret, {required String passphrase, int authLevel = 4});

  /// Recovers the master secret from SLIP-39 mnemonic shares.
  Uint8List recoverSecret(List<String> mnemonics, {required String passphrase});

  /// Encrypts data using AES-GCM-256 with the derived key.
  /// Returns a concatenated byte array containing: nonce (12 bytes) + tag/mac (16 bytes) + ciphertext.
  Future<Uint8List> encryptData(Uint8List data, Uint8List key);

  /// Decrypts data using AES-GCM-256 with the derived key.
  /// Expects the concatenated byte array format: nonce + tag/mac + ciphertext.
  Future<Uint8List> decryptData(Uint8List encryptedData, Uint8List key);
}

import 'dart:typed_data';

abstract class CryptoService {
  /// Generates a cryptographically secure random byte array of the specified length.
  Uint8List generateSecureRandom(int length);

  /// Derives a 256-bit key from the password and salt using Argon2id.
  Future<Uint8List> deriveKey(String password, Uint8List salt);

  /// Splits a master secret into SLIP-39 mnemonic shares.
  /// 
  /// Group 1 (Operational): 4-of-4 threshold (Password-bound, Face, Fingerprint, Voice).
  /// Group 2 (Backup): 2-of-3 threshold (Backup Recovery mnemonics).
  List<String> splitSecret(Uint8List secret, {required String passphrase});

  /// Recovers the master secret from SLIP-39 mnemonic shares.
  Uint8List recoverSecret(List<String> mnemonics, {required String passphrase});

  /// Encrypts data using AES-GCM-256 with the derived key.
  /// Returns a concatenated byte array containing: nonce (12 bytes) + tag/mac (16 bytes) + ciphertext.
  Future<Uint8List> encryptData(Uint8List data, Uint8List key);

  /// Decrypts data using AES-GCM-256 with the derived key.
  /// Expects the concatenated byte array format: nonce + tag/mac + ciphertext.
  Future<Uint8List> decryptData(Uint8List encryptedData, Uint8List key);
}

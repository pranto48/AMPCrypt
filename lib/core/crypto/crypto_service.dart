/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

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

  /// Securely overwrites the key buffer in RAM with zeros.
  void zeroizeKey(Uint8List key);

  /// Chunked streaming encryption: streams ciphertext in 64KB blocks with minimal RAM.
  /// Each file starts with an encrypted Self-Healing Header (path, size, timestamp).
  Stream<List<int>> encryptStream(
    Stream<List<int>> inputStream,
    Uint8List key, {
    String? originalPath,
    int? expectedSize,
  });

  /// Chunked streaming decryption: decrypts block-by-block with minimal RAM.
  /// Automatically handles both chunked AMPC files and legacy single-box files.
  Stream<List<int>> decryptStream(
    Stream<List<int>> inputStream,
    Uint8List key,
  );

  /// Extracts the Self-Healing File Header metadata without loading the entire file.
  Future<Map<String, dynamic>?> extractFileHeader(
    Uint8List headerPrefixBytes,
    Uint8List key,
  );
}

/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:slip39/slip39.dart';
import 'crypto_service.dart';

class MockCryptoService implements CryptoService {
  final _random = Random.secure();
  final _aesAlgorithm = AesGcm.with256bits();
  final _sha256 = Sha256();

  @override
  Uint8List generateSecureRandom(int length) {
    return Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
  }

  @override
  Future<Uint8List> deriveKey(String password, Uint8List salt) async {
    // Pure Dart SHA-256 key derivation for tests/mock environments
    final input = [...utf8.encode(password), ...salt];
    final hashResult = await _sha256.hash(input);
    return Uint8List.fromList(hashResult.bytes);
  }

  @override
  List<String> splitSecret(Uint8List secret, {required String passphrase, int authLevel = 4}) {
    final level = authLevel.clamp(1, 4);
    final groups = [
      [level, level], // Group 1 — dynamic
      [2, 3],         // Group 2 — backup
    ];

    final slip = Slip39.from(
      groups,
      masterSecret: secret,
      passphrase: passphrase,
      threshold: 1,
    );

    return slip.fromPath('r').mnemonics;
  }

  @override
  Uint8List recoverSecret(List<String> mnemonics, {required String passphrase}) {
    final recovered = Slip39.recoverSecret(mnemonics, passphrase: passphrase);
    return Uint8List.fromList(recovered);
  }

  @override
  Future<Uint8List> encryptData(Uint8List data, Uint8List key) async {
    final secretKey = SecretKey(key);
    final nonce = _aesAlgorithm.newNonce();
    
    final secretBox = await _aesAlgorithm.encrypt(
      data,
      secretKey: secretKey,
      nonce: nonce,
    );

    final macBytes = secretBox.mac.bytes;
    final cipherText = secretBox.cipherText;

    final result = BytesBuilder();
    result.add(nonce);
    result.add(macBytes);
    result.add(cipherText);

    return result.takeBytes();
  }

  @override
  Future<Uint8List> decryptData(Uint8List encryptedData, Uint8List key) async {
    if (encryptedData.length < 28) {
      throw ArgumentError("Encrypted data is too short");
    }

    final secretKey = SecretKey(key);
    final nonce = encryptedData.sublist(0, 12);
    final macBytes = encryptedData.sublist(12, 28);
    final cipherText = encryptedData.sublist(28);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decrypted = await _aesAlgorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decrypted);
  }

  @override
  void zeroizeKey(Uint8List key) {
    key.fillRange(0, key.length, 0);
  }

  @override
  Stream<List<int>> encryptStream(
    Stream<List<int>> inputStream,
    Uint8List key, {
    String? originalPath,
    int? expectedSize,
  }) async* {
    final bytesBuilder = BytesBuilder();
    await for (final chunk in inputStream) {
      bytesBuilder.add(chunk);
    }
    final plain = bytesBuilder.takeBytes();
    final enc = await encryptData(plain, key);
    yield enc;
  }

  @override
  Stream<List<int>> decryptStream(
    Stream<List<int>> inputStream,
    Uint8List key,
  ) async* {
    final bytesBuilder = BytesBuilder();
    await for (final chunk in inputStream) {
      bytesBuilder.add(chunk);
    }
    final enc = bytesBuilder.takeBytes();
    final dec = await decryptData(enc, key);
    yield dec;
  }

  @override
  Future<Map<String, dynamic>?> extractFileHeader(
    Uint8List headerPrefixBytes,
    Uint8List key,
  ) async {
    return null;
  }
}

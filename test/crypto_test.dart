/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampcrypt/core/crypto/crypto_service.dart';
import 'package:ampcrypt/core/crypto/crypto_service_impl.dart';
import 'package:ampcrypt/core/crypto/mock_crypto_service.dart';

void main() {
  late CryptoService cryptoService;

  setUp(() {
    cryptoService = MockCryptoService();
  });

  test('MockCryptoService - Master Key generation', () {
    final key = cryptoService.generateSecureRandom(32);
    expect(key.length, equals(32));
    expect(key, isNot(equals(Uint8List(32)))); // Not all zeros
  });

  test('MockCryptoService - SLIP-39 split and recovery', () {
    final secret = cryptoService.generateSecureRandom(32);
    final passphrase = "test-passphrase";

    // Split the secret
    final mnemonics = cryptoService.splitSecret(secret, passphrase: passphrase);
    expect(mnemonics.length, equals(7)); // 4 from Group 1 + 3 from Group 2 = 7 mnemonics

    final group1Mnemonics = mnemonics.sublist(0, 4);
    final group2Mnemonics = mnemonics.sublist(4);

    // 1. Recover using Group 1 (operational group) - requires 4-of-4
    final recovered1 = cryptoService.recoverSecret(group1Mnemonics, passphrase: passphrase);
    expect(recovered1, equals(secret));

    // 2. Recover using Group 2 (backup group) - requires 2-of-3
    final recovered2 = cryptoService.recoverSecret(
      [group2Mnemonics[0], group2Mnemonics[1]], 
      passphrase: passphrase,
    );
    expect(recovered2, equals(secret));
  });

  test('MockCryptoService - key derivation and AES-GCM encryption/decryption', () async {
    final password = "super-secret-password";
    final salt = cryptoService.generateSecureRandom(16);

    // Derive key
    final derivedKey = await cryptoService.deriveKey(password, salt);
    expect(derivedKey.length, equals(32)); // 256-bit key

    // Data to encrypt
    final originalData = Uint8List.fromList("Secret operational share data".codeUnits);

    // Encrypt
    final encryptedData = await cryptoService.encryptData(originalData, derivedKey);
    expect(encryptedData.length, equals(originalData.length + 28)); // nonce (12) + tag (16) + cipher

    // Decrypt
    final decryptedData = await cryptoService.decryptData(encryptedData, derivedKey);
    expect(decryptedData, equals(originalData));
  });

  test('CryptoServiceImpl - Streaming encryption and decryption with self-healing header', () async {
    final realCrypto = CryptoServiceImpl();
    final key = realCrypto.generateSecureRandom(32);
    final originalText = "Zero-Trust Military Grade Vault Payload 2026";
    final originalBytes = Uint8List.fromList(originalText.codeUnits);

    final encryptedStream = realCrypto.encryptStream(
      Stream.value(originalBytes),
      key,
      originalPath: '/Documents/classified.pdf',
    );

    final encryptedChunks = await encryptedStream.toList();
    final allEncryptedBytes = <int>[];
    for (final chunk in encryptedChunks) {
      allEncryptedBytes.addAll(chunk);
    }

    // Verify magic header AMPC\x01
    expect(allEncryptedBytes.sublist(0, 5), equals([0x41, 0x4D, 0x50, 0x43, 0x01]));

    // Decrypt stream
    final decryptedStream = realCrypto.decryptStream(
      Stream.value(Uint8List.fromList(allEncryptedBytes)),
      key,
    );

    final decryptedChunks = await decryptedStream.toList();
    final allDecryptedBytes = <int>[];
    for (final chunk in decryptedChunks) {
      allDecryptedBytes.addAll(chunk);
    }

    expect(String.fromCharCodes(allDecryptedBytes), equals(originalText));
  });

  test('CryptoServiceImpl - Extract self-healing file header', () async {
    final realCrypto = CryptoServiceImpl();
    final key = realCrypto.generateSecureRandom(32);
    final originalBytes = Uint8List.fromList("Payload data".codeUnits);

    final encryptedStream = realCrypto.encryptStream(
      Stream.value(originalBytes),
      key,
      originalPath: '/Photos/secret_family.jpg',
    );

    final encryptedBytes = await encryptedStream.fold<List<int>>([], (prev, elem) => prev..addAll(elem));

    final header = await realCrypto.extractFileHeader(Uint8List.fromList(encryptedBytes), key);
    expect(header, isNotNull);
    expect(header!['path'], equals('/Photos/secret_family.jpg'));
    expect(header['timestamp'], isNotNull);
  });
}

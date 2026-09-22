/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * This program is free software under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampcrypt/core/security/memory_shield.dart';
import 'package:ampcrypt/core/crypto/post_quantum_envelope.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MemoryShield Tests', () {
    test('Should securely wipe Uint8List buffers', () {
      final buffer = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      MemoryShield.wipeBuffer(buffer);
      expect(buffer, equals(Uint8List(8)));
    });

    test('Should handle Win32 VirtualLock allocation and deallocation gracefully', () {
      final shield = MemoryShield();
      if (Platform.isWindows && shield.isAvailable) {
        final ptr = shield.allocateLockedMemory(64);
        expect(ptr, isNotNull);
        shield.freeLockedMemory(ptr, 64);
      }
    });
  });

  group('PostQuantumEnvelope Tests', () {
    late PostQuantumEnvelope pq;

    setUp(() {
      pq = PostQuantumEnvelope();
    });

    test('Should generate valid ML-KEM-768 keypair dimensions', () {
      final keyPair = pq.generateKeyPair();
      final pk = keyPair['publicKey']!;
      final sk = keyPair['secretKey']!;

      expect(pk.length, equals(1184));
      expect(sk.length, equals(2400));
    });

    test('Should wrap and unwrap master key using hybrid envelope', () {
      final keyPair = pq.generateKeyPair();
      final pk = keyPair['publicKey']!;
      final sk = keyPair['secretKey']!;

      final classicalKey = Uint8List.fromList(List.generate(32, (i) => i + 10));
      final masterKey = Uint8List.fromList(List.generate(32, (i) => i ^ 0xAA));

      // Wrap
      final envelope = pq.wrapMasterKey(
        masterKey: masterKey,
        classicalKey: classicalKey,
        pqPublicKey: pk,
      );

      expect(envelope['magic'], equals(PostQuantumEnvelope.magicHeader));
      expect(envelope['pq_ciphertext'], isNotEmpty);
      expect(envelope['wrapped_master_key'], isNotEmpty);

      // Unwrap
      final unwrappedKey = pq.unwrapMasterKey(
        envelope: envelope,
        classicalKey: classicalKey,
        pqSecretKey: sk,
      );

      expect(unwrappedKey, equals(masterKey));
    });

    test('Should reject tampered Post-Quantum envelope', () {
      final keyPair = pq.generateKeyPair();
      final pk = keyPair['publicKey']!;
      final sk = keyPair['secretKey']!;

      final classicalKey = Uint8List.fromList(List.generate(32, (i) => i + 10));
      final masterKey = Uint8List.fromList(List.generate(32, (i) => i ^ 0x55));

      final envelope = pq.wrapMasterKey(
        masterKey: masterKey,
        classicalKey: classicalKey,
        pqPublicKey: pk,
      );

      // Tamper with wrong classical key
      final wrongClassicalKey = Uint8List.fromList(List.generate(32, (i) => i + 99));
      expect(
        () => pq.unwrapMasterKey(
          envelope: envelope,
          classicalKey: wrongClassicalKey,
          pqSecretKey: sk,
        ),
        throwsA(anything),
      );
    });
  });
}

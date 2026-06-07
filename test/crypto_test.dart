import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ampcrypt/core/crypto/crypto_service.dart';
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
}

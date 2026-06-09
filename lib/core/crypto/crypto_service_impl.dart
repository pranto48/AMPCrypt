import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:slip39/slip39.dart';
import 'package:argon2/argon2.dart';
import 'crypto_service.dart';

class CryptoServiceImpl implements CryptoService {
  final _random = Random.secure();
  final _aesAlgorithm = AesGcm.with256bits();

  @override
  Uint8List generateSecureRandom(int length) {
    return Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
  }

  @override
  Future<Uint8List> deriveKey(String password, Uint8List salt) async {
    // We use recommended parameters for Argon2id key derivation:
    // Memory: 32MB (32768 KB = 2^15), Iterations: 3, Parallelism (lanes): 2
    final parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      version: Argon2Parameters.ARGON2_VERSION_13,
      iterations: 3,
      memoryPowerOf2: 15,
      lanes: 2,
    );
    final generator = Argon2BytesGenerator();
    generator.init(parameters);

    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    final hash = Uint8List(32);
    generator.generateBytes(passwordBytes, hash, 0, hash.length);
    return hash;
  }

  @override
  List<String> splitSecret(Uint8List secret, {required String passphrase, int authLevel = 4}) {
    // SLIP-39 group structure:
    // Group 1: Operational Factors -> threshold = authLevel, size = authLevel
    //   1FA: [1,1] Password only
    //   2FA: [2,2] Password + Fingerprint
    //   3FA: [3,3] Password + Fingerprint + Face
    //   4FA: [4,4] Password + Fingerprint + Face + Voice
    // Group 2: Backup Recovery -> threshold 2, size 3 (always)
    final level = authLevel.clamp(1, 4);
    final groups = [
      [level, level], // Group 1 — operational
      [2, 3],         // Group 2 — backup recovery
    ];

    final slip = Slip39.from(
      groups,
      masterSecret: secret,
      passphrase: passphrase,
      threshold: 1, // Either group alone is sufficient to recover the secret
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

    // Concatenate: nonce (12 bytes) + tag/mac (16 bytes) + ciphertext
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
}

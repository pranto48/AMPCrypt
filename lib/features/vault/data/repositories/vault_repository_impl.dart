import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/crypto/crypto_service.dart';
import '../../domain/repositories/vault_repository.dart';

class VaultRepositoryImpl implements VaultRepository {
  final CryptoService _cryptoService;
  final SharedPreferences _prefs;

  // In-memory cache for the unlocked master key
  Uint8List? _cachedMasterKey;

  VaultRepositoryImpl({
    required CryptoService cryptoService,
    required SharedPreferences prefs,
  })  : _cryptoService = cryptoService,
        _prefs = prefs;

  @override
  bool get isVaultCreated => _prefs.getBool('vault_created') ?? false;

  @override
  bool get isUnlocked => _cachedMasterKey != null;

  @override
  String? get masterKeyHex {
    if (_cachedMasterKey == null) return null;
    return _cachedMasterKey!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  Future<List<String>> createVault(String password) async {
    // 1. Generate Master Key (256-bit)
    final masterKey = _cryptoService.generateSecureRandom(32);

    // 2. Generate Salt (16 bytes)
    final salt = _cryptoService.generateSecureRandom(16);

    // 3. Split Master Key via SLIP-39
    // Returns 7 mnemonics:
    // 0-3: Group 1 (Operational: Password-bound, Face, Fingerprint, Voice)
    // 4-6: Group 2 (Backup Recovery: 3 shares, threshold 2)
    final passphrase = "ampcrypt-secure-passphrase";
    final mnemonics = _cryptoService.splitSecret(masterKey, passphrase: passphrase);

    final passwordShare = mnemonics[0];
    final faceShare = mnemonics[1];
    final fingerprintShare = mnemonics[2];
    final voiceShare = mnemonics[3];
    final recoveryMnemonics = mnemonics.sublist(4);

    // 4. Derive key from password
    final derivedKey = await _cryptoService.deriveKey(password, salt);

    // 5. Encrypt Password-Bound Share
    final encryptedPasswordShare = await _cryptoService.encryptData(
      Uint8List.fromList(utf8.encode(passwordShare)),
      derivedKey,
    );

    // 6. Save encrypted shares, salt, and details in SharedPreferences
    await _prefs.setString('password_salt', base64Encode(salt));
    await _prefs.setString('encrypted_password_share', base64Encode(encryptedPasswordShare));
    await _prefs.setString('mock_face_share', base64Encode(utf8.encode(faceShare)));
    await _prefs.setString('mock_fingerprint_share', base64Encode(utf8.encode(fingerprintShare)));
    await _prefs.setString('mock_voice_share', base64Encode(utf8.encode(voiceShare)));
    await _prefs.setBool('vault_created', true);
    await _prefs.setBool('is_device_trusted', true);
    await _prefs.setString('device_fingerprint', _generateMockDeviceFingerprint());

    // Cache the master key since it's just created (unlocked state)
    _cachedMasterKey = masterKey;

    // Return the recovery mnemonics to display to the user
    return recoveryMnemonics;
  }

  @override
  Future<bool> unlockVault(String password) async {
    try {
      final saltBase64 = _prefs.getString('password_salt');
      final encryptedShareBase64 = _prefs.getString('encrypted_password_share');
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      // 1. Derive key from password
      final derivedKey = await _cryptoService.deriveKey(password, salt);

      // 2. Decrypt Password-Bound Share
      final decryptedBytes = await _cryptoService.decryptData(encryptedPasswordShare, derivedKey);
      final passwordShare = utf8.decode(decryptedBytes);

      // 3. Load other operational shares
      final faceShareBase64 = _prefs.getString('mock_face_share');
      final fingerprintShareBase64 = _prefs.getString('mock_fingerprint_share');
      final voiceShareBase64 = _prefs.getString('mock_voice_share');

      if (faceShareBase64 == null || fingerprintShareBase64 == null || voiceShareBase64 == null) {
        return false;
      }

      final faceShare = utf8.decode(base64Decode(faceShareBase64));
      final fingerprintShare = utf8.decode(base64Decode(fingerprintShareBase64));
      final voiceShare = utf8.decode(base64Decode(voiceShareBase64));

      // 4. Reconstruct Master Key using SLIP-39 Group 1 shares (4-of-4)
      final passphrase = "ampcrypt-secure-passphrase";
      final recoveredMasterKey = _cryptoService.recoverSecret(
        [passwordShare, faceShare, fingerprintShare, voiceShare],
        passphrase: passphrase,
      );

      _cachedMasterKey = recoveredMasterKey;
      return true;
    } catch (e) {
      // Failed decryption or recovery
      return false;
    }
  }

  @override
  Future<bool> recoverVault(List<String> recoveryPhrases) async {
    try {
      if (recoveryPhrases.length < 2) return false;
      final passphrase = "ampcrypt-secure-passphrase";

      // Reconstruct Master Key using SLIP-39 Group 2 recovery (2-of-3)
      final recoveredMasterKey = _cryptoService.recoverSecret(
        recoveryPhrases,
        passphrase: passphrase,
      );

      _cachedMasterKey = recoveredMasterKey;
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  void lockVault() {
    _cachedMasterKey = null;
  }

  @override
  Future<Map<String, dynamic>> getDeviceStatus() async {
    final isTrusted = _prefs.getBool('is_device_trusted') ?? false;
    final fingerprint = _prefs.getString('device_fingerprint') ?? 'Unknown';
    return {
      'is_trusted': isTrusted,
      'device_fingerprint': fingerprint,
      'device_name': 'Local Web Browser Client',
      'last_verified': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<void> trustCurrentDevice() async {
    await _prefs.setBool('is_device_trusted', true);
  }

  String _generateMockDeviceFingerprint() {
    final random = Random();
    final chars = '0123456789ABCDEF';
    return List.generate(16, (i) {
      if (i == 4 || i == 8 || i == 12) return '-';
      return chars[random.nextInt(16)];
    }).join();
  }
}

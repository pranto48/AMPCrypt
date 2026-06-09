import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../../../../core/crypto/crypto_service.dart';
import '../../../../core/storage/webdav_server.dart';
import '../../domain/repositories/vault_repository.dart';

/// Factor names in Group 1, indexed by position.
/// For an authLevel of N, only the first N factors are used.
const _kFactorKeys = [
  'encrypted_password_share',  // Factor 0 — always present
  'mock_fingerprint_share',    // Factor 1 — 2FA+
  'mock_face_share',           // Factor 2 — 3FA+
  'mock_voice_share',          // Factor 3 — 4FA
];

class VaultRepositoryImpl implements VaultRepository {
  final CryptoService _cryptoService;
  final SharedPreferences _prefs;
  final WebDavServer _webDavServer;

  // In-memory cache for the unlocked master key
  Uint8List? _cachedMasterKey;

  VaultRepositoryImpl({
    required CryptoService cryptoService,
    required SharedPreferences prefs,
  })  : _cryptoService = cryptoService,
        _prefs = prefs,
        _webDavServer = WebDavServer(cryptoService);

  @override
  int? get webDavPort => _webDavServer.isRunning ? _webDavServer.port : null;

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
  int get configuredAuthLevel => _prefs.getInt('auth_level') ?? 4;

  // ─── CREATE VAULT ────────────────────────────────────────────────────────────

  @override
  Future<List<String>> createVault(String password, {int authLevel = 4}) async {
    final level = authLevel.clamp(1, 4);

    // 1. Generate Master Key (256-bit) and Salt (16 bytes)
    final masterKey = _cryptoService.generateSecureRandom(32);
    final salt = _cryptoService.generateSecureRandom(16);

    // 2. Split Master Key via SLIP-39 using the selected auth level.
    //    Returns: level Group-1 shares + 3 Group-2 backup shares = level+3 mnemonics.
    //    Ordering: [0..level-1] = Group 1 operational, [level..level+2] = Group 2 backup.
    final passphrase = "ampcrypt-secure-passphrase";
    final mnemonics = _cryptoService.splitSecret(
      masterKey,
      passphrase: passphrase,
      authLevel: level,
    );

    // Group 1 shares: indices 0 … level-1
    final operationalShares = mnemonics.sublist(0, level);
    // Group 2 recovery shares: indices level … level+2
    final recoveryMnemonics = mnemonics.sublist(level, level + 3);

    // 3. Derive key from password using Argon2id
    final derivedKey = await _cryptoService.deriveKey(password, salt);

    // 4. Encrypt the password-bound share (Factor 0) with the derived key
    final encryptedPasswordShare = await _cryptoService.encryptData(
      Uint8List.fromList(utf8.encode(operationalShares[0])),
      derivedKey,
    );

    // 5. Persist salt + encrypted password share
    await _prefs.setString('password_salt', base64Encode(salt));
    await _prefs.setString('encrypted_password_share', base64Encode(encryptedPasswordShare));

    // 6. Persist the remaining operational shares (Factors 1-3) as mock biometric shares.
    //    We store only the shares that exist for this auth level.
    for (int i = 1; i < level; i++) {
      await _prefs.setString(
        _kFactorKeys[i],
        base64Encode(utf8.encode(operationalShares[i])),
      );
    }
    // Clear any old shares from a previous higher auth level
    for (int i = level; i < 4; i++) {
      await _prefs.remove(_kFactorKeys[i]);
    }

    // 7. Persist metadata
    await _prefs.setInt('auth_level', level);
    await _prefs.setBool('vault_created', true);
    await _prefs.setBool('is_device_trusted', true);
    await _prefs.setString('device_fingerprint', _generateMockDeviceFingerprint());

    // 8. Cache master key (vault is now unlocked)
    _cachedMasterKey = masterKey;

    // Start WebDAV server and mount drive
    await _startServerAndMount(masterKey);

    return recoveryMnemonics;
  }

  // ─── UNLOCK VAULT ────────────────────────────────────────────────────────────

  @override
  Future<bool> unlockVault(String password) async {
    try {
      final level = configuredAuthLevel;
      final saltBase64 = _prefs.getString('password_salt');
      final encryptedShareBase64 = _prefs.getString('encrypted_password_share');
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      // 1. Derive key from password and decrypt the password share (Factor 0)
      final derivedKey = await _cryptoService.deriveKey(password, salt);
      final decryptedBytes = await _cryptoService.decryptData(encryptedPasswordShare, derivedKey);
      final passwordShare = utf8.decode(decryptedBytes);

      // 2. Collect all Group-1 shares needed to reconstruct the master key
      final List<String> sharesToReconstruct = [passwordShare];

      for (int i = 1; i < level; i++) {
        final shareBase64 = _prefs.getString(_kFactorKeys[i]);
        if (shareBase64 == null) return false; // Missing required share
        sharesToReconstruct.add(utf8.decode(base64Decode(shareBase64)));
      }

      // 3. Reconstruct master key — all Group-1 shares (threshold = level = all required)
      final passphrase = "ampcrypt-secure-passphrase";
      final recoveredMasterKey = _cryptoService.recoverSecret(
        sharesToReconstruct,
        passphrase: passphrase,
      );

      _cachedMasterKey = recoveredMasterKey;
      await _startServerAndMount(recoveredMasterKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── RECOVERY ────────────────────────────────────────────────────────────────

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
      await _startServerAndMount(recoveredMasterKey);
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── LOCK ────────────────────────────────────────────────────────────────────

  @override
  void lockVault() {
    _cachedMasterKey = null;
    _stopServerAndUnmount();
  }

  // ─── MOUNT HELPERS ───────────────────────────────────────────────────────────

  String _getHomeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '';
    }
    return Platform.environment['HOME'] ?? '';
  }

  Future<void> _startServerAndMount(Uint8List masterKey) async {
    final vaultPath = getVaultPath();
    final driveLetter = getDriveLetter();

    // Start WebDAV server
    await _webDavServer.start(masterKey, vaultPath);

    // Mount to driveLetter on Windows
    if (Platform.isWindows && _webDavServer.isRunning) {
      final port = _webDavServer.port;
      // First try to safely unmount any existing drive to prevent conflicts
      await Process.run('cmd.exe', ['/c', 'net use $driveLetter /delete /y']);
      // Mount the network drive
      await Process.run('cmd.exe', ['/c', 'net use $driveLetter http://localhost:$port /persistent:no']);
    }
  }

  Future<void> _stopServerAndUnmount() async {
    if (Platform.isWindows) {
      final driveLetter = getDriveLetter();
      await Process.run('cmd.exe', ['/c', 'net use $driveLetter /delete /y']);
    }
    await _webDavServer.stop();
  }

  // ─── DEVICE STATUS ───────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> getDeviceStatus() async {
    final isTrusted = _prefs.getBool('is_device_trusted') ?? false;
    final fingerprint = _prefs.getString('device_fingerprint') ?? 'Unknown';
    return {
      'is_trusted': isTrusted,
      'device_fingerprint': fingerprint,
      'device_name': 'Local Windows Client',
      'last_verified': DateTime.now().toIso8601String(),
    };
  }

  @override
  Future<void> trustCurrentDevice() async {
    await _prefs.setBool('is_device_trusted', true);
  }

  @override
  String getVaultPath() {
    final configuredPath = _prefs.getString('vault_path');
    if (configuredPath != null && configuredPath.isNotEmpty) {
      return configuredPath;
    }
    final home = _getHomeDir();
    return p.join(home, '.ampcrypt_vault');
  }

  @override
  String getDriveLetter() {
    return _prefs.getString('drive_letter') ?? 'Z:';
  }

  @override
  Future<void> updateVaultSettings(String path, String driveLetter) async {
    final isCurrentlyUnlocked = isUnlocked;
    final masterKey = _cachedMasterKey;
    
    if (isCurrentlyUnlocked && masterKey != null) {
      await _stopServerAndUnmount();
    }
    
    await _prefs.setString('vault_path', path);
    await _prefs.setString('drive_letter', driveLetter);
    
    if (isCurrentlyUnlocked && masterKey != null) {
      await _startServerAndMount(masterKey);
    }
  }

  @override
  double get monitorSensitivity => _prefs.getDouble('monitor_sensitivity') ?? 0.65;

  @override
  Future<void> setMonitorSensitivity(double value) async {
    await _prefs.setDouble('monitor_sensitivity', value);
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────────

  String _generateMockDeviceFingerprint() {
    final random = Random();
    final chars = '0123456789ABCDEF';
    return List.generate(16, (i) {
      if (i == 4 || i == 8 || i == 12) return '-';
      return chars[random.nextInt(16)];
    }).join();
  }
}

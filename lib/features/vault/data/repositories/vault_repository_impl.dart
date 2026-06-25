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
  bool get isVaultCreated {
    final localCreated = _prefs.getBool('vault_created') ?? false;
    if (localCreated) return true;
    final config = _loadVaultConfig();
    return config != null && (config['vault_created'] == true);
  }

  @override
  bool get isUnlocked => _cachedMasterKey != null;

  @override
  String? get masterKeyHex {
    if (_cachedMasterKey == null) return null;
    return _cachedMasterKey!.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  int get configuredAuthLevel {
    final config = _loadVaultConfig();
    if (config != null && config.containsKey('auth_level')) {
      return config['auth_level'] as int;
    }
    return _prefs.getInt('auth_level') ?? 4;
  }

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

    final vaultPath = getVaultPath();

    // Build portable config
    final Map<String, dynamic> configMap = {
      'vault_created': true,
      'auth_level': level,
      'password_salt': base64Encode(salt),
      'encrypted_password_share': base64Encode(encryptedPasswordShare),
    };
    for (int i = 1; i < level; i++) {
      configMap[_kFactorKeys[i]] = base64Encode(utf8.encode(operationalShares[i]));
    }
    
    // Ensure vault directory exists
    Directory(vaultPath).createSync(recursive: true);
    await _saveVaultConfig(configMap);

    // 5. Persist locally for caching/compatibility
    await _prefs.setString('password_salt', base64Encode(salt));
    await _prefs.setString('encrypted_password_share', base64Encode(encryptedPasswordShare));

    // 6. Persist mock shares locally
    for (int i = 1; i < level; i++) {
      await _prefs.setString(
        _kFactorKeys[i],
        base64Encode(utf8.encode(operationalShares[i])),
      );
    }
    for (int i = level; i < 4; i++) {
      await _prefs.remove(_kFactorKeys[i]);
    }

    // 7. Persist metadata
    await _prefs.setInt('auth_level', level);
    await _prefs.setBool('vault_created', true);
    await _prefs.setBool('is_device_trusted', true);
    await _prefs.setString('device_fingerprint', _generateMockDeviceFingerprint());

    // 8. Cache master key
    _cachedMasterKey = masterKey;

    await _startServerAndMount(masterKey);

    return recoveryMnemonics;
  }

  // ─── UNLOCK VAULT ────────────────────────────────────────────────────────────

  @override
  Future<bool> unlockVault(String password) async {
    try {
      final config = _loadVaultConfig();
      final String? saltBase64 = config != null ? config['password_salt'] : _prefs.getString('password_salt');
      final String? encryptedShareBase64 = config != null ? config['encrypted_password_share'] : _prefs.getString('encrypted_password_share');
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      // 1. Derive key from password and decrypt the password share (Factor 0)
      final derivedKey = await _cryptoService.deriveKey(password, salt);
      final decryptedBytes = await _cryptoService.decryptData(encryptedPasswordShare, derivedKey);
      final passwordShare = utf8.decode(decryptedBytes);

      // 2. Collect all Group-1 shares needed to reconstruct the master key
      final List<String> sharesToReconstruct = [passwordShare];

      final actualLevel = config != null && config.containsKey('auth_level') 
          ? (config['auth_level'] as int) 
          : configuredAuthLevel;

      for (int i = 1; i < actualLevel; i++) {
        final shareBase64 = config != null 
            ? config[_kFactorKeys[i]] 
            : _prefs.getString(_kFactorKeys[i]);
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
    if (_cachedMasterKey != null) {
      _cachedMasterKey!.fillRange(0, _cachedMasterKey!.length, 0);
      _cachedMasterKey = null;
    }
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
      // Mount the network drive (using UNC format with DavWWWRoot to ensure Windows Explorer queries quota sizes correctly)
      await Process.run('cmd.exe', ['/c', 'net use $driveLetter \\\\localhost@$port\\DavWWWRoot /persistent:no']);

      // Rename and set drive icon in Windows Explorer
      try {
        final letterOnly = driveLetter.replaceAll(':', '');
        // Rename using PowerShell (via COM object Namespace)
        await Process.run('powershell.exe', [
          '-Command',
          '(New-Object -ComObject Shell.Application).NameSpace(\'$driveLetter\').Self.Name = \'AMPCrypt\''
        ]);

        // Set drive icon in Registry (HKCU so it is writeable without admin privileges)
        // Note: Using Set-Item on the key path correctly overwrites the unnamed default value of the DefaultIcon key.
        final exePath = Platform.resolvedExecutable;
        await Process.run('powershell.exe', [
          '-Command',
          'New-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultIcon" -Force; Set-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultIcon" -Value "$exePath"'
        ]);
      } catch (_) {}
    }
  }

  Future<void> _stopServerAndUnmount() async {
    if (Platform.isWindows) {
      final driveLetter = getDriveLetter();
      await Process.run('cmd.exe', ['/c', 'net use $driveLetter /delete /y']);

      try {
        final letterOnly = driveLetter.replaceAll(':', '');
        // Clean up registry key on unmount
        await Process.run('powershell.exe', [
          '-Command',
          'Remove-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly" -Recurse -ErrorAction SilentlyContinue'
        ]);
      } catch (_) {}
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

  @override
  int get autoLockMinutes => _prefs.getInt('auto_lock_minutes') ?? 0;

  @override
  Future<void> setAutoLockMinutes(int minutes) async {
    await _prefs.setInt('auto_lock_minutes', minutes);
  }

  @override
  DateTime? get lastActivityTime => _webDavServer.lastActivityTime;

  @override
  Future<void> clearVaultData() async {
    try {
      final vaultPath = getVaultPath();
      final configFile = File(p.join(vaultPath, 'vault.json'));
      if (configFile.existsSync()) {
        configFile.deleteSync();
      }
      final dataDir = Directory(p.join(vaultPath, 'data'));
      if (dataDir.existsSync()) {
        dataDir.deleteSync(recursive: true);
      }
      final indexFile = File(p.join(vaultPath, 'metadata.json.enc'));
      if (indexFile.existsSync()) {
        indexFile.deleteSync();
      }
    } catch (_) {}
  }

  // ─── HELPERS ─────────────────────────────────────────────────────────────────

  Future<void> _saveVaultConfig(Map<String, dynamic> config) async {
    final vaultPath = getVaultPath();
    final configFile = File(p.join(vaultPath, 'vault.json'));
    await configFile.writeAsString(json.encode(config), flush: true);
  }

  Map<String, dynamic>? _loadVaultConfig() {
    try {
      final vaultPath = getVaultPath();
      final configFile = File(p.join(vaultPath, 'vault.json'));
      if (configFile.existsSync()) {
        return json.decode(configFile.readAsStringSync()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  @override
  bool get isQuestionsRecoveryEnabled {
    final config = _loadVaultConfig();
    return config != null && config['questions_recovery_enabled'] == true;
  }

  @override
  String? getQuestionsRecoveryEmail() {
    final config = _loadVaultConfig();
    return config?['questions_recovery_email'] as String?;
  }

  @override
  List<String>? getQuestionsRecoveryQuestions() {
    final config = _loadVaultConfig();
    final list = config?['questions_recovery_questions'];
    if (list != null) {
      return List<String>.from(list);
    }
    return null;
  }

  @override
  Future<void> enableQuestionsRecovery(String email, List<String> questions, List<String> answers) async {
    final masterKey = _cachedMasterKey;
    if (masterKey == null) throw Exception("Vault must be unlocked to configure recovery options.");

    // Derive combined answers key
    final combinedAnswers = answers.map((a) => a.trim().toLowerCase()).join('_');
    final salt = _cryptoService.generateSecureRandom(16);
    final derivedKey = await _cryptoService.deriveKey(combinedAnswers, salt);

    // Encrypt cached master key
    final encryptedMasterKey = await _cryptoService.encryptData(masterKey, derivedKey);

    // Load, update and save config
    final config = _loadVaultConfig() ?? <String, dynamic>{};
    config['questions_recovery_enabled'] = true;
    config['questions_recovery_email'] = email;
    config['questions_recovery_questions'] = questions;
    config['questions_recovery_salt'] = base64Encode(salt);
    config['questions_recovery_encrypted_master_key'] = base64Encode(encryptedMasterKey);

    await _saveVaultConfig(config);
  }

  @override
  Future<void> disableQuestionsRecovery() async {
    final config = _loadVaultConfig();
    if (config != null) {
      config.remove('questions_recovery_enabled');
      config.remove('questions_recovery_email');
      config.remove('questions_recovery_questions');
      config.remove('questions_recovery_salt');
      config.remove('questions_recovery_encrypted_master_key');
      await _saveVaultConfig(config);
    }
  }

  @override
  Future<bool> sendRecoveryEmail(String email, String code) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('https://api.resend.com/emails'));
      
      request.headers.set('Authorization', 'Bearer re_JRnu4jFo_JRjAbMeMnqraKM3yKAJPFNdf');
      request.headers.set('Content-Type', 'application/json');
      
      final body = {
        'from': 'AMPCrypt <onboarding@resend.dev>',
        'to': [email],
        'subject': 'AMPCrypt Recovery Verification Code',
        'html': '<p>Your AMPCrypt security recovery code is: <strong>$code</strong></p><p>Please enter this code in the application along with your security question answers to recover your vault.</p>'
      };
      
      request.write(json.encode(body));
      final response = await request.close();
      
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> recoverWithQuestionsAndEmail(List<String> answers) async {
    try {
      final config = _loadVaultConfig();
      if (config == null || config['questions_recovery_enabled'] != true) return null;

      final saltBase64 = config['questions_recovery_salt'] as String?;
      final encryptedMasterKeyBase64 = config['questions_recovery_encrypted_master_key'] as String?;
      if (saltBase64 == null || encryptedMasterKeyBase64 == null) return null;

      final salt = base64Decode(saltBase64);
      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);

      final combinedAnswers = answers.map((a) => a.trim().toLowerCase()).join('_');
      final derivedKey = await _cryptoService.deriveKey(combinedAnswers, salt);

      final decryptedBytes = await _cryptoService.decryptData(encryptedMasterKey, derivedKey);
      return decryptedBytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> unlockWithMasterKey(Uint8List masterKey) async {
    _cachedMasterKey = masterKey;
    await _startServerAndMount(masterKey);
    return true;
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

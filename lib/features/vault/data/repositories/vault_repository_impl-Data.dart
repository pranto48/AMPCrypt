/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import '../../../../core/crypto/crypto_service.dart';
import '../../../../core/storage/webdav_server.dart';
import '../../../../core/storage/vault_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ftpconnect/ftpconnect.dart';
import '../../domain/repositories/vault_repository.dart';
import '../../../../core/portable_state_sync.dart';
import '../../../../core/storage/cloud_filter_service.dart';
import '../../../../core/security/canary_guard_service.dart';
import '../../../../core/platform/windows_shell_service.dart';

/// Factor names in Group 1, indexed by position.
/// For an authLevel of N, only the first N factors are used.
const _kFactorKeys = [
  'encrypted_password_share', // Factor 0 — always present
  'mock_fingerprint_share', // Factor 1 — 2FA+
  'mock_face_share', // Factor 2 — 3FA+
  'mock_voice_share', // Factor 3 — 4FA
];

class VaultRepositoryImpl implements VaultRepository {
  final CryptoService _cryptoService;
  final SharedPreferences _prefs;
  final WebDavServer _webDavServer;
  Process? _rcloneProcess;

  // In-memory cache for the unlocked master key
  Uint8List? _cachedMasterKey;

  VaultRepositoryImpl({
    required CryptoService cryptoService,
    required this._prefs,
  }) : _cryptoService = cryptoService,
       _webDavServer = WebDavServer(cryptoService) {
    _initVaultFromHistory();
  }

  void _initVaultFromHistory() async {
    try {
      final currentPath = _prefs.getString('vault_path');
      if (currentPath == null || currentPath.isEmpty) {
        final list = getRememberedVaults();
        if (list.isNotEmpty) {
          await selectVault(list.first);
        }
      }
    } catch (_) {}
  }

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
    return _cachedMasterKey!
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
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
  Future<List<String>> createVault(
    String password, {
    int authLevel = 4,
    List<String>? questions,
    List<String>? answers,
  }) async {
    final level = authLevel.clamp(1, 4);

    // 1. Generate Master Key (256-bit) and Salt (16 bytes)
    final masterKey = _cryptoService.generateSecureRandom(32);
    final salt = _cryptoService.generateSecureRandom(16);

    // 2. Split Master Key via SLIP-39 using the selected auth level.
    final passphrase = "ampcrypt-secure-passphrase";
    final mnemonics = _cryptoService.splitSecret(
      masterKey,
      passphrase: passphrase,
      authLevel: level,
    );

    final operationalShares = mnemonics.sublist(0, level);
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
      configMap[_kFactorKeys[i]] = base64Encode(
        utf8.encode(operationalShares[i]),
      );
    }

    // If security questions recovery is provided, encrypt masterKey with 3 security answers
    if (questions != null &&
        answers != null &&
        questions.length >= 3 &&
        answers.length >= 3) {
      final combinedAnswers = answers
          .map((a) => a.trim().toLowerCase())
          .join('_');
      final qSalt = _cryptoService.generateSecureRandom(16);
      final derivedQKey = await _cryptoService.deriveKey(
        combinedAnswers,
        qSalt,
      );
      final encryptedMasterKey = await _cryptoService.encryptData(
        masterKey,
        derivedQKey,
      );

      configMap['questions_recovery_enabled'] = true;
      configMap['questions_recovery_email'] = 'vault_recovery@ampcrypt.local';
      configMap['questions_recovery_questions'] = questions;
      configMap['questions_recovery_salt'] = base64Encode(qSalt);
      configMap['questions_recovery_encrypted_master_key'] = base64Encode(
        encryptedMasterKey,
      );
    }

    // Ensure vault directory exists
    Directory(vaultPath).createSync(recursive: true);
    await _saveVaultConfig(configMap);

    // 5. Persist locally for caching/compatibility
    await _prefs.setString('password_salt', base64Encode(salt));
    await _prefs.setString(
      'encrypted_password_share',
      base64Encode(encryptedPasswordShare),
    );

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
    if (configMap.containsKey('questions_recovery_enabled')) {
      await _prefs.setBool('questions_recovery_enabled', true);
      await _prefs.setString(
        'questions_recovery_email',
        'vault_recovery@ampcrypt.local',
      );
      await _prefs.setStringList('questions_recovery_questions', questions!);
      await _prefs.setString(
        'questions_recovery_salt',
        configMap['questions_recovery_salt'],
      );
      await _prefs.setString(
        'questions_recovery_encrypted_master_key',
        configMap['questions_recovery_encrypted_master_key'],
      );
    }

    await _prefs.setInt('auth_level', level);
    await _prefs.setBool('vault_created', true);
    await _prefs.setBool('is_device_trusted', true);
    await _prefs.setString(
      'device_fingerprint',
      _generateMockDeviceFingerprint(),
    );

    // 8. Cache master key
    _cachedMasterKey = masterKey;

    // 9. Windows-specific: Extract pre-formatted VHDX container template
    if (Platform.isWindows) {
      final vhdxPath = p.join(vaultPath, 'vault.vhdx');
      final vhdxEncPath = p.join(vaultPath, 'vault.vhdx.enc');
      final tempZipPath = p.join(vaultPath, 'vault_template.zip');

      // Extract compressed pre-formatted VHDX from assets to local vault folder
      try {
        final byteData = await rootBundle.load('assets/vault_template.zip');
        final buffer = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        await File(tempZipPath).writeAsBytes(buffer, flush: true);

        // Decompress using native PowerShell Expand-Archive (runs under standard privileges)
        await Process.run('powershell.exe', [
          '-Command',
          "Expand-Archive -Path '$tempZipPath' -DestinationPath '$vaultPath' -Force",
        ]);

        // Cleanup temporary zip file
        try {
          await File(tempZipPath).delete();
        } catch (_) {}

        // Rename template to standard vault name
        final templateFile = File(p.join(vaultPath, 'vault_template.vhdx'));
        if (templateFile.existsSync()) {
          await templateFile.rename(vhdxPath);
        }
      } catch (_) {}

      // Encrypt container using the master key
      final vhdxFile = File(vhdxPath);
      final vhdxEncFile = File(vhdxEncPath);
      if (vhdxFile.existsSync()) {
        await _encryptFile(vhdxFile, vhdxEncFile, masterKey);
        vhdxFile.deleteSync();
      }
    }

    // Save to remembered vaults
    await addRememberedVault(
      VaultProfile(
        name: p.basename(vaultPath),
        path: vaultPath,
        storageType: 'local',
        driveLetter: getDriveLetter(),
      ),
    );

    await _startServerAndMount(masterKey);

    return recoveryMnemonics;
  }

  @override
  bool isVaultPathValid(String? path) {
    if (path == null || path.isEmpty) return false;
    final dir = Directory(path);
    if (!dir.existsSync()) return false;
    final masterkey = File(p.join(path, 'masterkey.ampcrypt'));
    final vault = File(p.join(path, 'vault.ampcrypt'));
    return masterkey.existsSync() || vault.existsSync();
  }

  @override
  Future<bool> relocateVaultFolder(String newPath) async {
    if (!isVaultPathValid(newPath)) return false;
    await _prefs.setString('vault_path', newPath);
    final profiles = getRememberedVaults();
    if (profiles.isNotEmpty) {
      final old = profiles.first;
      String name = p.basename(newPath).replaceAll('.ampcrypt_vault_', '');
      if (name.isEmpty || name == '.' || name == '/') name = 'Data';
      profiles[0] = VaultProfile(
        name: name,
        path: newPath,
        storageType: old.storageType,
        driveLetter: old.driveLetter,
      );
      await saveRememberedVaults(profiles);
    }
    return true;
  }

  @override
  Future<void> addRememberedVault(VaultProfile profile) async {
    final profiles = getRememberedVaults();
    profiles.removeWhere((p) => p.path == profile.path);
    profiles.insert(0, profile);
    await saveRememberedVaults(profiles);
  }

  // ─── UNLOCK VAULT ────────────────────────────────────────────────────────────

  @override
  Future<bool> unlockVault(String password) async {
    final vPath = getVaultPath();
    if (!Directory(vPath).existsSync()) {
      throw Exception(
        'Vault directory not found at "$vPath". Please relocate vault folder.',
      );
    }
    try {
      final config = _loadVaultConfig();
      final String? saltBase64 = config != null
          ? config['password_salt']
          : _prefs.getString('password_salt');
      final String? encryptedShareBase64 = config != null
          ? config['encrypted_password_share']
          : _prefs.getString('encrypted_password_share');
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      // 1. Derive key from password and decrypt the password share (Factor 0)
      final derivedKey = await _cryptoService.deriveKey(password, salt);
      final decryptedBytes = await _cryptoService.decryptData(
        encryptedPasswordShare,
        derivedKey,
      );
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

      // Arm Canary Honey-pot Threat Guard
      try {
        CanaryGuardService().armTrap(
          vaultPath: vPath,
          onBreach: (reason, canaryPath) {
            lockVault();
          },
        );
      } catch (_) {}

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

      final vPath = getVaultPath();
      try {
        CanaryGuardService().armTrap(
          vaultPath: vPath,
          onBreach: (reason, canaryPath) {
            lockVault();
          },
        );
      } catch (_) {}

      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── LOCK ────────────────────────────────────────────────────────────────────

  @override
  void lockVault() {
    CanaryGuardService().disarmTrap();
    Uint8List? keyToUse;
    if (_cachedMasterKey != null) {
      keyToUse = Uint8List.fromList(_cachedMasterKey!);
      _cachedMasterKey!.fillRange(0, _cachedMasterKey!.length, 0);
      _cachedMasterKey = null;
    }
    _stopServerAndUnmount(keyToUse);
  }

  @override
  Future<bool> verifyVaultPassword(String password) async {
    try {
      final config = _loadVaultConfig();
      final String? saltBase64 = config != null
          ? config['password_salt']
          : _prefs.getString('password_salt');
      final String? encryptedShareBase64 = config != null
          ? config['encrypted_password_share']
          : _prefs.getString('encrypted_password_share');
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      final derivedKey = await _cryptoService.deriveKey(password, salt);
      final decryptedBytes = await _cryptoService.decryptData(
        encryptedPasswordShare,
        derivedKey,
      );
      _cryptoService.zeroizeKey(derivedKey);
      final passwordShare = utf8.decode(decryptedBytes);
      return passwordShare.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  List<VaultProfile> getRememberedVaults() {
    try {
      final jsonString = _prefs.getString('remembered_vaults');
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> list = json.decode(jsonString);
        return list
            .map((e) => VaultProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    final currentPath = _prefs.getString('vault_path');
    final isCreated = _prefs.getBool('vault_created') ?? false;
    if (isCreated && currentPath != null && currentPath.isNotEmpty) {
      String name = p.basename(currentPath).replaceAll('.ampcrypt_vault_', '');
      if (name.isEmpty || name == '.' || name == '/') name = 'Data';
      final driveLetter = _prefs.getString('drive_letter') ?? 'G:';
      return [
        VaultProfile(
          name: name,
          path: currentPath,
          storageType: 'local',
          driveLetter: driveLetter,
        ),
      ];
    }
    return [];
  }

  @override
  Future<void> saveRememberedVaults(List<VaultProfile> profiles) async {
    final listMap = profiles.map((p) => p.toJson()).toList();
    await _prefs.setString('remembered_vaults', json.encode(listMap));
  }

  @override
  Future<void> removeVaultFromApp(String targetPath) async {
    lockVault();
    final target = targetPath.isNotEmpty ? targetPath : getVaultPath();
    final profiles = getRememberedVaults();

    profiles.removeWhere((p) => p.path == target || p.path == targetPath);
    await saveRememberedVaults(profiles);

    if (profiles.isNotEmpty) {
      final next = profiles.first;
      await _prefs.setString('vault_path', next.path);
      await _prefs.setString('drive_letter', next.driveLetter);
      await _prefs.setBool('vault_created', true);
    } else {
      await _prefs.remove('vault_path');
      await _prefs.setBool('vault_created', false);
    }
  }

  @override
  Future<bool> forceDeleteVaultDataWithPassword(
    String password,
    String targetPath,
  ) async {
    final isVerified = await verifyVaultPassword(password);
    if (!isVerified) return false;

    lockVault();

    final target = targetPath.isNotEmpty ? targetPath : getVaultPath();

    try {
      final dir = Directory(target);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } catch (_) {
      await clearVaultData();
    }

    await removeVaultFromApp(target);
    return true;
  }

  @override
  Future<bool> deleteVaultDataWithPassword(String password) async {
    return forceDeleteVaultDataWithPassword(password, getVaultPath());
  }

  // ─── MOUNT HELPERS ───────────────────────────────────────────────────────────

  String _getHomeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'] ?? '';
    }
    return Platform.environment['HOME'] ?? '';
  }

  static const _winFspChannel = MethodChannel('ampcrypt/winfsp');
  static const _helloChannel = MethodChannel('ampcrypt/windows_hello');



  Future<void> _startServerAndMount(Uint8List masterKey) async {
    final vaultPath = getVaultPath();
    final driveLetter = getDriveLetter();



    // Start WebDAV server with abstract storage
    VaultStorage storage;
    if (storageType == 'ftp') {
      storage = FtpVaultStorage(
        host: _prefs.getString('ftp_host') ?? '',
        port: _prefs.getInt('ftp_port') ?? 21,
        username: _prefs.getString('ftp_username') ?? '',
        password: _prefs.getString('ftp_password') ?? '',
        remotePath: _prefs.getString('ftp_remote_path') ?? '',
      );
    } else {
      storage = LocalVaultStorage(vaultPath);
    }

    await _webDavServer.start(masterKey, storage);
    // Mount to driveLetter on Windows
    if (Platform.isWindows && _webDavServer.isRunning) {
      final port = _webDavServer.port;

      // 1. Ensure CFAPI sync root is unregistered from physical vault path so Windows physical disk I/O works 100% without timeouts
      try {
        await CloudFilterService.unregisterSyncRoot(vaultPath);
      } catch (_) {}

      // 2. Drive Letter Mount: Always mount through the WebDAV Encryption Server (rclone / native WebDAV redirector)
      final cleanLetter = driveLetter.replaceAll(':', '').trim();

      // Clear any previous stale mappings
      try {
        await Process.run('net.exe', ['use', '$cleanLetter:', '/delete', '/y']);
        await Process.run('subst.exe', ['$cleanLetter:', '/d']);
      } catch (_) {}

      final fspInstalled = await isWinFspInstalled();
      final rclonePath = await _ensureRclone();

      if (fspInstalled && rclonePath != null) {
        try {
          if (_rcloneProcess != null) {
            _rcloneProcess!.kill();
            _rcloneProcess = null;
          }
          final supportDir = await getApplicationSupportDirectory();
          final cachePath = storageType == 'ftp'
              ? p.join(supportDir.path, '.amp_cache_ftp')
              : p.join(vaultPath, '.amp_cache');

          _rcloneProcess = await Process.start(rclonePath, [
            'mount',
            ':webdav:',
            driveLetter,
            '--webdav-url',
            'http://127.0.0.1:$port',
            '--webdav-vendor',
            'other',
            '--dir-cache-time',
            '1s',
            '--vfs-cache-mode',
            'full',
            '--cache-dir',
            cachePath,
            '--no-checksum',
            '--no-modtime',
            '--volname',
            'AMPCrypt Vault',
          ], runInShell: false);
          
          for (int i = 0; i < 20; i++) {
            await Future.delayed(const Duration(milliseconds: 150));
            if (Directory('$cleanLetter:\\').existsSync()) {
              break;
            }
          }
        } catch (_) {}
      } else if (cleanLetter.isNotEmpty) {
        try {
          await Process.run('net.exe', ['use', '$cleanLetter:', 'http://127.0.0.1:$port/DavWWWRoot']);
        } catch (_) {}
      }

      // Also notify WinFSP about vault root path for accurate disk stats
      // (rclone path — try to derive drive root from vaultPath)
      try {
        final driveLetter2 = driveLetter.replaceAll(':', '');
        // No-op for rclone mode; vault path disk root is set via getDiskSpace C++ handler
      } catch (_) {}

      // HKLM / HKCU Local Drive Icon Injection (Fixing the Square Icon)
      try {
        final letterOnly = driveLetter.replaceAll(':', '');
        final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';

        final iconFile = File(p.join(vaultPath, 'vault_drive.ico'));
        String securityIcon = iconFile.path;
        try {
          final byteData = await rootBundle.load('assets/vault_drive.ico');
          await iconFile.writeAsBytes(
            byteData.buffer.asUint8List(
              byteData.offsetInBytes,
              byteData.lengthInBytes,
            ),
            flush: true,
          );
        } catch (_) {
          if (!await iconFile.exists()) {
            securityIcon = '$systemRoot\\System32\\imageres.dll,104';
          }
        }

        // 1. HKCU DriveIcons (no admin needed)
        try {
          await Process.run('powershell.exe', [
            '-Command',
            'New-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultIcon" -Force; Set-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultIcon" -Value "$securityIcon"; New-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultLabel" -Force; Set-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultLabel" -Value "AMPCrypt Vault"',
          ]);
        } catch (_) {}

        // 2. HKLM DriveIcons (in case of admin/elevation permissions)
        try {
          await Process.run('reg.exe', [
            'add',
            'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultIcon',
            '/ve',
            '/d',
            securityIcon,
            '/f',
          ]);
          await Process.run('reg.exe', [
            'add',
            'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultLabel',
            '/ve',
            '/d',
            'AMPCrypt Vault',
            '/f',
          ]);
        } catch (_) {}

        // Secret Vault registry icon injection (Explorer.exe Drives)
        try {
          await Process.run('reg.exe', [
            'add',
            'HKCU\\Software\\Classes\\Applications\\Explorer.exe\\Drives\\$letterOnly\\DefaultIcon',
            '/ve',
            '/d',
            securityIcon,
            '/f',
          ]);
          await Process.run('reg.exe', [
            'add',
            'HKCU\\Software\\Classes\\Applications\\Explorer.exe\\Drives\\$letterOnly\\DefaultLabel',
            '/ve',
            '/d',
            'AMPCrypt Vault',
            '/f',
          ]);
        } catch (_) {}
      } catch (_) {}

      // Notify Windows shell to refresh icon cache immediately — called twice
      // (once now, and once after 1 s) to ensure Explorer picks up the new icon.
      try {
        await _winFspChannel.invokeMethod<void>('refreshShell');
      } catch (_) {}
      Future.delayed(const Duration(milliseconds: 1000), () async {
        try {
          await _winFspChannel.invokeMethod<void>('refreshShell');
        } catch (_) {}
      });
    }
  }

  Future<void> _stopServerAndUnmount([Uint8List? masterKey]) async {
    final keyToUse = masterKey ?? _cachedMasterKey;
    if (Platform.isWindows) {
      final preferredLetter = getDriveLetter().replaceAll(':', '');
      final activeLetter =
          _prefs.getString('drive_letter')?.replaceAll(':', '') ??
          preferredLetter;



      // Rclone WebDAV Mount Cleanup (FTP Fallback)
      try {
        await CloudFilterService.setVaultState(isUnlocked: false);
      } catch (_) {}

      if (_rcloneProcess != null) {
        _rcloneProcess!.kill();
        _rcloneProcess = null;
      }
      try {
        await Process.run('taskkill.exe', ['/f', '/im', 'rclone.exe']);
      } catch (_) {}

      try {
        for (var letter in [preferredLetter, activeLetter]) {
          try {
            await Process.run('net.exe', ['use', '$letter:', '/delete', '/y']);
          } catch (_) {}
          try {
            await Process.run('subst.exe', ['$letter:', '/d']);
          } catch (_) {}
          try {
            await Process.run('powershell.exe', [
              '-Command',
              'Remove-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letter" -Recurse -ErrorAction SilentlyContinue',
            ]);
          } catch (_) {}
          try {
            await Process.run('reg.exe', [
              'delete',
              'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letter',
              '/f',
            ]);
          } catch (_) {}
          try {
            await Process.run('reg.exe', [
              'delete',
              'HKCU\\Software\\Classes\\Applications\\Explorer.exe\\Drives\\$letter',
              '/f',
            ]);
          } catch (_) {}
        }

        // Cache Cleanup
        try {
          final tfsDavDir = Directory(
            r'C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp\TfsStore\Tfs_DAV',
          );
          if (await tfsDavDir.exists()) {
            await tfsDavDir.delete(recursive: true);
          }
        } catch (_) {}
        try {
          await Process.run('cmd.exe', [
            '/c',
            r'del /f /s /q "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp\TfsStore\Tfs_DAV\*"',
          ]);
        } catch (_) {}

        try {
          await _winFspChannel.invokeMethod<void>('refreshShell');
        } catch (_) {}
      } catch (_) {}
    }

    await _webDavServer.stop();

    // Silently delete .amp_cache directory in background after unmount
    Future.delayed(const Duration(milliseconds: 1000), () async {
      try {
        final vaultPath = getVaultPath();
        final localCache = Directory(p.join(vaultPath, '.amp_cache'));
        if (await localCache.exists()) {
          await localCache.delete(recursive: true);
        }
      } catch (_) {}
      try {
        final supportDir = await getApplicationSupportDirectory();
        final ftpCache = Directory(p.join(supportDir.path, '.amp_cache_ftp'));
        if (await ftpCache.exists()) {
          await ftpCache.delete(recursive: true);
        }
      } catch (_) {}
    });
  }

  @override
  Future<bool> isWinFspInstalled() async {
    if (!Platform.isWindows) return true;
    try {
      final result = await Process.run('reg.exe', [
        'query',
        r'HKLM\SOFTWARE\WOW6432Node\WinFsp',
      ]);
      if (result.exitCode == 0) return true;
    } catch (_) {}
    try {
      final result = await Process.run('reg.exe', [
        'query',
        r'HKLM\SOFTWARE\WinFsp',
      ]);
      if (result.exitCode == 0) return true;
    } catch (_) {}
    if (Directory(r'C:\Program Files (x86)\WinFsp').existsSync() ||
        Directory(r'C:\Program Files\WinFsp').existsSync() ||
        File(r'C:\Windows\System32\drivers\winfsp-x64.sys').existsSync()) {
      return true;
    }
    return false;
  }

  @override
  Future<bool> installWinFsp() async {
    if (!Platform.isWindows) return true;
    if (await isWinFspInstalled()) return true;

    try {
      Directory supportDir;
      try {
        supportDir = await getApplicationSupportDirectory();
      } catch (_) {
        supportDir = Directory.systemTemp;
      }
      final msiPath = p.join(supportDir.path, 'winfsp-2.0.23075.msi');
      final msiFile = File(msiPath);

      if (!await msiFile.exists()) {
        // 1. Check bundled Flutter asset first
        try {
          final byteData = await rootBundle.load('assets/winfsp.msi');
          await msiFile.writeAsBytes(byteData.buffer.asUint8List());
        } catch (_) {
          // 2. Download official WinFsp installer from GitHub release
          final client = HttpClient();
          final request = await client.getUrl(Uri.parse(
              'https://github.com/winfsp/winfsp/releases/download/v2.0/winfsp-2.0.23075.msi'));
          final response = await request.close();
          if (response.statusCode == 200) {
            final bytes = await response.fold<List<int>>(
                <int>[], (previous, element) => previous..addAll(element));
            await msiFile.writeAsBytes(bytes);
          }
        }
      }

      if (await msiFile.exists()) {
        // Run silent unattended MSI installer with elevation
        try {
          await Process.run('powershell.exe', [
            '-Command',
            'Start-Process msiexec.exe -ArgumentList \'/i\', \'\"$msiPath\"\', \'/qn\', \'/norestart\' -Verb RunAs -Wait',
          ]);
        } catch (_) {
          await Process.run('msiexec.exe', [
            '/i',
            msiPath,
            '/qn',
            '/norestart',
          ]);
        }

        // Poll registry up to 10 seconds for installation completion
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (await isWinFspInstalled()) {
            return true;
          }
        }
      }
    } catch (_) {}

    return await isWinFspInstalled();
  }

  Future<String?> _ensureRclone() async {
    try {
      // 1. Check same directory as current executable
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final localExe = File(p.join(exeDir, 'rclone.exe'));
      if (await localExe.exists()) return localExe.path;

      // 2. Check installer's Program Files directory (bundled rclone)
      final programFiles =
          Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
      final bundledRclone = File(p.join(programFiles, 'ampcrypt', 'rclone.exe'));
      if (await bundledRclone.exists()) {
        return bundledRclone.path;
      }

      // 3. Check AppData support directory
      final supportDir = await getApplicationSupportDirectory();
      final rcloneExe = File(p.join(supportDir.path, 'rclone.exe'));
      if (await rcloneExe.exists()) {
        return rcloneExe.path;
      }

      // 4. Check local assets/rclone.exe
      final assetRclone = File(p.join(Directory.current.path, 'assets', 'rclone.exe'));
      if (await assetRclone.exists()) {
        return assetRclone.path;
      }
    } catch (_) {}

    return null;
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
    final remembered = getRememberedVaults();
    if (remembered.isNotEmpty && remembered.first.path.isNotEmpty) {
      return remembered.first.path;
    }
    final home = _getHomeDir();
    return p.join(home, 'AMPCrypt_Vault');
  }

  @override
  String? getFtpHost() {
    return _prefs.getString('ftp_host');
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

    await _prefs.setString('vault_storage_type', 'local');
    await _prefs.setString('vault_path', path);
    await _prefs.setString('drive_letter', driveLetter);

    // Save to remembered vaults
    await addRememberedVault(
      VaultProfile(
        name: p.basename(path),
        path: path,
        storageType: 'local',
        driveLetter: driveLetter,
      ),
    );

    if (isCurrentlyUnlocked && masterKey != null) {
      await _startServerAndMount(masterKey);
    }
  }

  @override
  String get storageType => _prefs.getString('vault_storage_type') ?? 'local';

  @override
  Future<bool> testFtpConnection(
    String host,
    int port,
    String user,
    String pass,
    String path,
  ) async {
    final client = FTPConnect(
      host,
      port: port,
      user: user,
      pass: pass,
      timeout: 10,
    );
    try {
      await client.connect();
      if (path.isNotEmpty && path != '/') {
        final dirs = path.split('/').where((d) => d.isNotEmpty).toList();
        for (final dir in dirs) {
          bool dirExists = false;
          try {
            dirExists = await client.changeDirectory(dir);
          } catch (_) {}
          if (!dirExists) {
            await client.makeDirectory(dir);
            await client.changeDirectory(dir);
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  @override
  Future<List<String>> listFtpDirectories(
    String host,
    int port,
    String user,
    String pass,
    String currentPath,
  ) async {
    final client = FTPConnect(
      host,
      port: port,
      user: user,
      pass: pass,
      timeout: 10,
    );
    try {
      await client.connect();
      if (currentPath.isNotEmpty && currentPath != '/') {
        final dirs = currentPath.split('/').where((d) => d.isNotEmpty).toList();
        for (final dir in dirs) {
          try {
            await client.changeDirectory(dir);
          } catch (_) {
            break;
          }
        }
      }
      final entries = await client.listDirectoryContent();
      return entries
          .where((entry) => entry.type == FTPEntryType.dir)
          .map((entry) => entry.name)
          .where((name) => name.isNotEmpty && name != '.' && name != '..')
          .cast<String>()
          .toList();
    } catch (e) {
      throw Exception("Failed to list FTP directories: $e");
    } finally {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  @override
  Future<bool> createFtpDirectory(
    String host,
    int port,
    String user,
    String pass,
    String parentPath,
    String folderName,
  ) async {
    final client = FTPConnect(
      host,
      port: port,
      user: user,
      pass: pass,
      timeout: 10,
    );
    try {
      await client.connect();
      if (parentPath.isNotEmpty && parentPath != '/') {
        final dirs = parentPath.split('/').where((d) => d.isNotEmpty).toList();
        for (final dir in dirs) {
          try {
            await client.changeDirectory(dir);
          } catch (_) {}
        }
      }
      return await client.makeDirectory(folderName);
    } catch (_) {
      return false;
    } finally {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  @override
  Future<void> saveFtpVaultSettings({
    required String host,
    required int port,
    required String user,
    required String pass,
    required String path,
    required String driveLetter,
  }) async {
    final isCurrentlyUnlocked = isUnlocked;
    final masterKey = _cachedMasterKey;

    if (isCurrentlyUnlocked && masterKey != null) {
      await _stopServerAndUnmount();
    }

    await _prefs.setString('vault_storage_type', 'ftp');
    await _prefs.setString('ftp_host', host);
    await _prefs.setInt('ftp_port', port);
    await _prefs.setString('ftp_username', user);
    await _prefs.setString('ftp_password', pass);
    await _prefs.setString('ftp_remote_path', path);
    await _prefs.setString('drive_letter', driveLetter);

    // Save to remembered vaults
    await addRememberedVault(
      VaultProfile(
        name: 'FTP: $host$path',
        path: path,
        storageType: 'ftp',
        driveLetter: driveLetter,
        ftpHost: host,
        ftpPort: port,
        ftpUsername: user,
        ftpPassword: pass,
        ftpRemotePath: path,
      ),
    );

    if (isCurrentlyUnlocked && masterKey != null) {
      await _startServerAndMount(masterKey);
    }
  }

  @override
  Future<List<String>> createFtpVault(
    String password, {
    required String host,
    required int port,
    required String user,
    required String pass,
    required String path,
    required String driveLetter,
    int authLevel = 4,
  }) async {
    final level = authLevel.clamp(1, 4);

    // 1. Generate Master Key (256-bit) and Salt (16 bytes)
    final masterKey = _cryptoService.generateSecureRandom(32);
    final salt = _cryptoService.generateSecureRandom(16);

    // 2. Split Master Key via SLIP-39
    final passphrase = "ampcrypt-secure-passphrase";
    final mnemonics = _cryptoService.splitSecret(
      masterKey,
      passphrase: passphrase,
      authLevel: level,
    );

    final operationalShares = mnemonics.sublist(0, level);
    final recoveryMnemonics = mnemonics.sublist(level, level + 3);

    // 3. Derive key from password using Argon2id
    final derivedKey = await _cryptoService.deriveKey(password, salt);

    // 4. Encrypt the password-bound share
    final encryptedPasswordShare = await _cryptoService.encryptData(
      Uint8List.fromList(utf8.encode(operationalShares[0])),
      derivedKey,
    );

    // Build configs
    final Map<String, dynamic> metadataMap = {
      'vault_created': true,
      'auth_level': level,
      'password_salt': base64Encode(salt),
    };
    final Map<String, dynamic> masterkeyMap = {
      'encrypted_password_share': base64Encode(encryptedPasswordShare),
    };
    for (int i = 1; i < level; i++) {
      masterkeyMap[_kFactorKeys[i]] = base64Encode(
        utf8.encode(operationalShares[i]),
      );
    }

    // 5. Upload configs to FTP server
    final storage = FtpVaultStorage(
      host: host,
      port: port,
      username: user,
      password: pass,
      remotePath: path,
    );
    await storage.initialize();
    final metadataBytes = Uint8List.fromList(
      utf8.encode(json.encode(metadataMap)),
    );
    final masterkeyBytes = Uint8List.fromList(
      utf8.encode(json.encode(masterkeyMap)),
    );
    await storage.writeFile('vault.ampcrypt', metadataBytes);
    await storage.writeFile('masterkey.ampcrypt', masterkeyBytes);

    // 6. Persist settings and credentials locally
    await _prefs.setString('vault_storage_type', 'ftp');
    await _prefs.setString('ftp_host', host);
    await _prefs.setInt('ftp_port', port);
    await _prefs.setString('ftp_username', user);
    await _prefs.setString('ftp_password', pass);
    await _prefs.setString('ftp_remote_path', path);
    await _prefs.setString('drive_letter', driveLetter);

    await _prefs.setString('password_salt', base64Encode(salt));
    await _prefs.setString(
      'encrypted_password_share',
      base64Encode(encryptedPasswordShare),
    );
    for (int i = 1; i < level; i++) {
      await _prefs.setString(
        _kFactorKeys[i],
        base64Encode(utf8.encode(operationalShares[i])),
      );
    }
    for (int i = level; i < 4; i++) {
      await _prefs.remove(_kFactorKeys[i]);
    }

    await _prefs.setInt('auth_level', level);
    await _prefs.setBool('vault_created', true);
    await _prefs.setBool('is_device_trusted', true);
    await _prefs.setString(
      'device_fingerprint',
      _generateMockDeviceFingerprint(),
    );

    // 7. Cache master key and mount
    _cachedMasterKey = masterKey;

    // Save to remembered vaults
    await addRememberedVault(
      VaultProfile(
        name: 'FTP: $host$path',
        path: path,
        storageType: 'ftp',
        driveLetter: driveLetter,
        ftpHost: host,
        ftpPort: port,
        ftpUsername: user,
        ftpPassword: pass,
        ftpRemotePath: path,
      ),
    );

    await _startServerAndMount(masterKey);

    return recoveryMnemonics;
  }

  @override
  Future<bool> openFtpVault(
    String password, {
    required String host,
    required int port,
    required String user,
    required String pass,
    required String path,
    required String driveLetter,
  }) async {
    try {
      final storage = FtpVaultStorage(
        host: host,
        port: port,
        username: user,
        password: pass,
        remotePath: path,
      );

      final exists = await storage.fileExists('vault.ampcrypt');
      if (!exists) return false;

      final metadataBytes = await storage.readFile('vault.ampcrypt');
      final metadataMap =
          json.decode(utf8.decode(metadataBytes)) as Map<String, dynamic>;

      Map<String, dynamic> masterkeyMap = {};
      if (await storage.fileExists('masterkey.ampcrypt')) {
        final masterkeyBytes = await storage.readFile('masterkey.ampcrypt');
        masterkeyMap =
            json.decode(utf8.decode(masterkeyBytes)) as Map<String, dynamic>;
      }

      final configMap = {...metadataMap, ...masterkeyMap};

      final String? saltBase64 = configMap['password_salt'];
      final String? encryptedShareBase64 =
          configMap['encrypted_password_share'];
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      // 1. Verify password
      final derivedKey = await _cryptoService.deriveKey(password, salt);
      final decryptedBytes = await _cryptoService.decryptData(
        encryptedPasswordShare,
        derivedKey,
      );
      final passwordShare = utf8.decode(decryptedBytes);

      // 2. Reconstruct master key
      final List<String> sharesToReconstruct = [passwordShare];
      final actualLevel = configMap['auth_level'] as int;
      for (int i = 1; i < actualLevel; i++) {
        final shareBase64 = configMap[_kFactorKeys[i]];
        if (shareBase64 == null) return false;
        sharesToReconstruct.add(utf8.decode(base64Decode(shareBase64)));
      }

      final passphrase = "ampcrypt-secure-passphrase";
      final recoveredMasterKey = _cryptoService.recoverSecret(
        sharesToReconstruct,
        passphrase: passphrase,
      );

      // 3. Persist settings and credentials locally on success
      await _prefs.setString('vault_storage_type', 'ftp');
      await _prefs.setString('ftp_host', host);
      await _prefs.setInt('ftp_port', port);
      await _prefs.setString('ftp_username', user);
      await _prefs.setString('ftp_password', pass);
      await _prefs.setString('ftp_remote_path', path);
      await _prefs.setString('drive_letter', driveLetter);

      await _prefs.setString('password_salt', saltBase64);
      await _prefs.setString('encrypted_password_share', encryptedShareBase64);
      for (int i = 1; i < actualLevel; i++) {
        await _prefs.setString(_kFactorKeys[i], configMap[_kFactorKeys[i]]);
      }
      for (int i = actualLevel; i < 4; i++) {
        await _prefs.remove(_kFactorKeys[i]);
      }

      await _prefs.setInt('auth_level', actualLevel);
      await _prefs.setBool('vault_created', true);
      await _prefs.setBool('is_device_trusted', true);
      await _prefs.setString(
        'device_fingerprint',
        _generateMockDeviceFingerprint(),
      );

      // 4. Cache master key and mount
      _cachedMasterKey = recoveredMasterKey;

      // Save to remembered vaults
      await addRememberedVault(
        VaultProfile(
          name: 'FTP: $host$path',
          path: path,
          storageType: 'ftp',
          driveLetter: driveLetter,
          ftpHost: host,
          ftpPort: port,
          ftpUsername: user,
          ftpPassword: pass,
          ftpRemotePath: path,
        ),
      );

      await _startServerAndMount(recoveredMasterKey);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  double get monitorSensitivity =>
      _prefs.getDouble('monitor_sensitivity') ?? 0.65;

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
      final metadataFile = File(p.join(vaultPath, 'vault.ampcrypt'));
      if (metadataFile.existsSync()) {
        metadataFile.deleteSync();
      }
      final masterkeyFile = File(p.join(vaultPath, 'masterkey.ampcrypt'));
      if (masterkeyFile.existsSync()) {
        masterkeyFile.deleteSync();
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
    final metadataFile = File(p.join(vaultPath, 'vault.ampcrypt'));
    final masterkeyFile = File(p.join(vaultPath, 'masterkey.ampcrypt'));

    final Map<String, dynamic> metadata = {};
    final Map<String, dynamic> masterkey = {};

    final masterkeyKeys = ['encrypted_password_share', ..._kFactorKeys];

    config.forEach((key, value) {
      if (masterkeyKeys.contains(key)) {
        masterkey[key] = value;
      } else {
        metadata[key] = value;
      }
    });

    await metadataFile.writeAsString(json.encode(metadata), flush: true);
    await masterkeyFile.writeAsString(json.encode(masterkey), flush: true);

    // Auto-generate backup .bkup files matching Cryptomator format
    try {
      final hash = DateTime.now().millisecondsSinceEpoch
          .toRadixString(16)
          .toUpperCase()
          .padLeft(8, '0')
          .substring(0, 8);
      final masterkeyBkup = File(
        p.join(vaultPath, 'masterkey.ampcrypt.$hash.bkup'),
      );
      final vaultBkup = File(p.join(vaultPath, 'vault.ampcrypt.$hash.bkup'));
      await masterkeyBkup.writeAsString(json.encode(masterkey), flush: true);
      await vaultBkup.writeAsString(json.encode(metadata), flush: true);

      // Create encrypted data directory 'd'
      Directory(p.join(vaultPath, 'd')).createSync(recursive: true);

      // Create IMPORTANT.rtf instruction file
      final importantFile = File(p.join(vaultPath, 'IMPORTANT.rtf'));
      if (!importantFile.existsSync()) {
        await importantFile.writeAsString(
          r'{\rtf1\ansi\deff0 {\fonttbl{\f0 Arial;}}\f0\fs20 THIS FOLDER CONTAINS AN AMPCRYPT ENCRYPTED VAULT.\par DO NOT MODIFY OR DELETE ANY FILES OR THE "d" DIRECTORY.}',
          flush: true,
        );
      }
    } catch (_) {}

    await PortableStateSync.syncToPortable();
  }

  Map<String, dynamic>? _loadVaultConfig() {
    try {
      final vaultPath = getVaultPath();
      final metadataFile = File(p.join(vaultPath, 'vault.ampcrypt'));
      final masterkeyFile = File(p.join(vaultPath, 'masterkey.ampcrypt'));

      Map<String, dynamic>? metadata;
      Map<String, dynamic>? masterkey;

      if (metadataFile.existsSync()) {
        metadata =
            json.decode(metadataFile.readAsStringSync())
                as Map<String, dynamic>;
      }
      if (masterkeyFile.existsSync()) {
        masterkey =
            json.decode(masterkeyFile.readAsStringSync())
                as Map<String, dynamic>;
      }

      if (metadata != null || masterkey != null) {
        final Map<String, dynamic> merged = {};
        if (metadata != null) merged.addAll(metadata);
        if (masterkey != null) merged.addAll(masterkey);
        return merged;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _encryptFile(
    File inputFile,
    File outputFile,
    Uint8List key,
  ) async {
    final bytes = await inputFile.readAsBytes();
    final encrypted = await _cryptoService.encryptData(bytes, key);
    await outputFile.writeAsBytes(encrypted, flush: true);
  }

  Future<void> _decryptFile(
    File inputFile,
    File outputFile,
    Uint8List key,
  ) async {
    final bytes = await inputFile.readAsBytes();
    final decrypted = await _cryptoService.decryptData(bytes, key);
    await outputFile.writeAsBytes(decrypted, flush: true);
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
  Future<void> enableQuestionsRecovery(
    String email,
    List<String> questions,
    List<String> answers,
  ) async {
    final masterKey = _cachedMasterKey;
    if (masterKey == null)
      throw Exception("Vault must be unlocked to configure recovery options.");

    // Derive combined answers key
    final combinedAnswers = answers
        .map((a) => a.trim().toLowerCase())
        .join('_');
    final salt = _cryptoService.generateSecureRandom(16);
    final derivedKey = await _cryptoService.deriveKey(combinedAnswers, salt);

    // Encrypt cached master key
    final encryptedMasterKey = await _cryptoService.encryptData(
      masterKey,
      derivedKey,
    );

    // Load, update and save config
    final config = _loadVaultConfig() ?? <String, dynamic>{};
    config['questions_recovery_enabled'] = true;
    config['questions_recovery_email'] = email;
    config['questions_recovery_questions'] = questions;
    config['questions_recovery_salt'] = base64Encode(salt);
    config['questions_recovery_encrypted_master_key'] = base64Encode(
      encryptedMasterKey,
    );

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
  Future<String?> sendRecoveryEmail(String email, String code) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('https://ampcrypt.itsupport.com.bd/api/send-email'),
      );

      request.headers.set('Content-Type', 'application/json');

      final body = {
        'to': [email],
        'subject': 'AMPCrypt Recovery Verification Code',
        'html':
            '<p>Your AMPCrypt security recovery code is: <strong>$code</strong></p><p>Please enter this code in the application along with your security question answers to recover your vault.</p>',
      };

      request.write(json.encode(body));
      final response = await request.close();

      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200 || response.statusCode == 201) {
        return null; // Success
      } else {
        try {
          final errJson = json.decode(responseBody);
          return errJson['message'] ??
              'SMTP server returned status ${response.statusCode}';
        } catch (_) {
          return 'SMTP server returned status ${response.statusCode}';
        }
      }
    } catch (e) {
      return e.toString();
    }
  }

  @override
  Future<Uint8List?> recoverWithQuestionsAndEmail(List<String> answers) async {
    try {
      final config = _loadVaultConfig();
      if (config == null || config['questions_recovery_enabled'] != true)
        return null;

      final saltBase64 = config['questions_recovery_salt'] as String?;
      final encryptedMasterKeyBase64 =
          config['questions_recovery_encrypted_master_key'] as String?;
      if (saltBase64 == null || encryptedMasterKeyBase64 == null) return null;

      final salt = base64Decode(saltBase64);
      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);

      final combinedAnswers = answers
          .map((a) => a.trim().toLowerCase())
          .join('_');
      final derivedKey = await _cryptoService.deriveKey(combinedAnswers, salt);

      final decryptedBytes = await _cryptoService.decryptData(
        encryptedMasterKey,
        derivedKey,
      );
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

  @override
  Future<void> resetMasterPasswordWithKey(
    Uint8List masterKey,
    String newPassword,
  ) async {
    final level = configuredAuthLevel;

    // 1. Generate fresh Salt (16 bytes)
    final salt = _cryptoService.generateSecureRandom(16);

    // 2. Re-split Master Key via SLIP-39 using configured auth level
    const passphrase = "ampcrypt-secure-passphrase";
    final mnemonics = _cryptoService.splitSecret(
      masterKey,
      passphrase: passphrase,
      authLevel: level,
    );

    final operationalShares = mnemonics.sublist(0, level);

    // 3. Derive key from new password using Argon2id
    final derivedKey = await _cryptoService.deriveKey(newPassword, salt);

    // 4. Encrypt the password-bound share (Factor 0) with new derived key
    final encryptedPasswordShare = await _cryptoService.encryptData(
      Uint8List.fromList(utf8.encode(operationalShares[0])),
      derivedKey,
    );

    // 5. Update vault config on disk
    final config = _loadVaultConfig() ?? <String, dynamic>{};
    config['password_salt'] = base64Encode(salt);
    config['encrypted_password_share'] = base64Encode(encryptedPasswordShare);

    await _saveVaultConfig(config);

    // 6. Update local SharedPreferences
    await _prefs.setString('password_salt', base64Encode(salt));
    await _prefs.setString(
      'encrypted_password_share',
      base64Encode(encryptedPasswordShare),
    );

    _cachedMasterKey = masterKey;
  }

  String _generateMockDeviceFingerprint() {
    final random = Random();
    final chars = '0123456789ABCDEF';
    return List.generate(16, (i) {
      if (i == 4 || i == 8 || i == 12) return '-';
      return chars[random.nextInt(16)];
    }).join();
  }

  @override
  Future<bool> isTpmSupported() async {
    if (!Platform.isWindows) return false;
    try {
      final supported = await _helloChannel.invokeMethod<bool>(
        'isTpmSupported',
      );
      return supported ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isTpmUnlockEnabled {
    final enabled = _prefs.getBool('is_tpm_enabled') ?? false;
    final cipher = _prefs.getString('tpm_encrypted_master_key');
    return enabled && cipher != null;
  }

  @override
  Future<bool> enableTpmUnlock() async {
    if (!Platform.isWindows || _cachedMasterKey == null) return false;
    try {
      final String? cipher = await _helloChannel.invokeMethod<String>(
        'encryptKek',
        _cachedMasterKey,
      );
      if (cipher != null) {
        await _prefs.setBool('is_tpm_enabled', true);
        await _prefs.setString('tpm_encrypted_master_key', cipher);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> disableTpmUnlock() async {
    await _prefs.remove('is_tpm_enabled');
    await _prefs.remove('tpm_encrypted_master_key');
  }

  @override
  Future<Uint8List?> unlockWithTpm() async {
    if (!Platform.isWindows) return null;
    final cipher = _prefs.getString('tpm_encrypted_master_key');
    if (cipher == null) return null;
    try {
      final rawKek = await _helloChannel.invokeMethod<dynamic>(
        'decryptKek',
        cipher,
      );
      if (rawKek is Uint8List) {
        return rawKek;
      } else if (rawKek is List) {
        return Uint8List.fromList(List<int>.from(rawKek));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<File> _getHistoryFile() async {
    final supportDir = await getApplicationSupportDirectory();
    return File(p.join(supportDir.path, 'vaults.json'));
  }

  Future<void> _saveRememberedVaults(List<VaultProfile> profiles) async {
    try {
      final file = await _getHistoryFile();
      final data = {
        'last_active_path': getVaultPath(),
        'vaults': profiles.map((p) => p.toJson()).toList(),
      };
      await file.writeAsString(json.encode(data), flush: true);
    } catch (_) {}
    await PortableStateSync.syncToPortable();
  }

  @override
  Future<void> removeRememberedVault(String path) async {
    await removeVaultFromApp(path);
  }

  @override
  Future<void> exportVaultsHistory(String destinationFilePath) async {
    try {
      final file = await _getHistoryFile();
      if (await file.exists()) {
        final destFile = File(destinationFilePath);
        await destFile.create(recursive: true);
        await file.copy(destFile.path);
      } else {
        final destFile = File(destinationFilePath);
        await destFile.create(recursive: true);
        final emptyData = {'last_active_path': '', 'vaults': []};
        await destFile.writeAsString(json.encode(emptyData), flush: true);
      }
    } catch (_) {}
  }

  @override
  Future<void> importVaultsHistory(String sourceFilePath) async {
    try {
      final srcFile = File(sourceFilePath);
      if (await srcFile.exists()) {
        final content = await srcFile.readAsString();
        final data = json.decode(content);
        if (data is Map && data.containsKey('vaults')) {
          final list = data['vaults'] as List;
          final profiles = list
              .map(
                (item) => VaultProfile.fromJson(item as Map<String, dynamic>),
              )
              .toList();
          await _saveRememberedVaults(profiles);
          if (profiles.isNotEmpty) {
            await selectVault(profiles.first);
          }
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> selectVault(VaultProfile profile) async {
    final isCurrentlyUnlocked = isUnlocked;
    final masterKey = _cachedMasterKey;

    if (isCurrentlyUnlocked && masterKey != null) {
      await _stopServerAndUnmount();
    }

    // Clear old prefs
    await _prefs.remove('vault_storage_type');
    await _prefs.remove('vault_path');
    await _prefs.remove('drive_letter');
    await _prefs.remove('ftp_host');
    await _prefs.remove('ftp_port');
    await _prefs.remove('ftp_username');
    await _prefs.remove('ftp_password');
    await _prefs.remove('ftp_remote_path');
    await _prefs.remove('password_salt');
    await _prefs.remove('encrypted_password_share');
    await _prefs.remove('auth_level');
    await _prefs.remove('vault_created');
    for (final key in _kFactorKeys) {
      await _prefs.remove(key);
    }

    // Save new configuration
    await _prefs.setString('vault_storage_type', profile.storageType);
    await _prefs.setString('drive_letter', profile.driveLetter);

    if (profile.storageType == 'ftp') {
      await _prefs.setString('ftp_host', profile.ftpHost ?? '');
      await _prefs.setInt('ftp_port', profile.ftpPort ?? 21);
      await _prefs.setString('ftp_username', profile.ftpUsername ?? '');
      await _prefs.setString('ftp_password', profile.ftpPassword ?? '');
      await _prefs.setString('ftp_remote_path', profile.path);
    } else {
      await _prefs.setString('vault_path', profile.path);
    }

    // Attempt to load configurations from vault.json (local) or FTP to see if created
    if (profile.storageType == 'local') {
      final config = _loadVaultConfig();
      if (config != null) {
        await _prefs.setBool('vault_created', config['vault_created'] == true);
        if (config.containsKey('auth_level')) {
          await _prefs.setInt('auth_level', config['auth_level'] as int);
        }
        if (config.containsKey('password_salt')) {
          await _prefs.setString(
            'password_salt',
            config['password_salt'] as String,
          );
        }
        if (config.containsKey('encrypted_password_share')) {
          await _prefs.setString(
            'encrypted_password_share',
            config['encrypted_password_share'] as String,
          );
        }
        for (final key in _kFactorKeys) {
          if (config.containsKey(key)) {
            await _prefs.setString(key, config[key] as String);
          }
        }
      }
    } else {
      // FTP - try to load vault.json
      try {
        final storage = FtpVaultStorage(
          host: profile.ftpHost ?? '',
          port: profile.ftpPort ?? 21,
          username: profile.ftpUsername ?? '',
          password: profile.ftpPassword ?? '',
          remotePath: profile.path,
        );
        final exists = await storage.fileExists('vault.ampcrypt');
        if (exists) {
          final metadataBytes = await storage.readFile('vault.ampcrypt');
          final metadataMap =
              json.decode(utf8.decode(metadataBytes)) as Map<String, dynamic>;
          Map<String, dynamic> masterkeyMap = {};
          if (await storage.fileExists('masterkey.ampcrypt')) {
            final masterkeyBytes = await storage.readFile('masterkey.ampcrypt');
            masterkeyMap =
                json.decode(utf8.decode(masterkeyBytes))
                    as Map<String, dynamic>;
          }
          final configMap = {...metadataMap, ...masterkeyMap};
          await _prefs.setBool(
            'vault_created',
            configMap['vault_created'] == true,
          );
          if (configMap.containsKey('auth_level')) {
            await _prefs.setInt('auth_level', configMap['auth_level'] as int);
          }
          if (configMap.containsKey('password_salt')) {
            await _prefs.setString(
              'password_salt',
              configMap['password_salt'] as String,
            );
          }
          if (configMap.containsKey('encrypted_password_share')) {
            await _prefs.setString(
              'encrypted_password_share',
              configMap['encrypted_password_share'] as String,
            );
          }
          for (final key in _kFactorKeys) {
            if (configMap.containsKey(key)) {
              await _prefs.setString(key, configMap[key] as String);
            }
          }
        }
      } catch (_) {}
    }

    // Save last active vault state
    await _prefs.setBool('vault_created', isVaultCreated);

    if (isCurrentlyUnlocked && masterKey != null) {
      await _startServerAndMount(masterKey);
    }
  }

  @override
  Future<bool> verifyAndAddExistingVault({
    required String name,
    required String path,
    required String password,
    required String driveLetter,
  }) async {
    try {
      final metadataFile = File(p.join(path, 'vault.ampcrypt'));
      final masterkeyFile = File(p.join(path, 'masterkey.ampcrypt'));
      if (!await metadataFile.exists()) return false;

      final metadataMap =
          json.decode(await metadataFile.readAsString())
              as Map<String, dynamic>;
      Map<String, dynamic> masterkeyMap = {};
      if (await masterkeyFile.exists()) {
        masterkeyMap =
            json.decode(await masterkeyFile.readAsString())
                as Map<String, dynamic>;
      }

      final config = {...metadataMap, ...masterkeyMap};
      final String? saltBase64 = config['password_salt'];
      final String? encryptedShareBase64 = config['encrypted_password_share'];
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      // 1. Derive key from password and decrypt the password share
      final derivedKey = await _cryptoService.deriveKey(password, salt);
      final decryptedBytes = await _cryptoService.decryptData(
        encryptedPasswordShare,
        derivedKey,
      );
      final passwordShare = utf8.decode(decryptedBytes);

      // 2. Collect other shares from config
      final List<String> sharesToReconstruct = [passwordShare];
      final actualLevel = config['auth_level'] as int? ?? 1;

      for (int i = 1; i < actualLevel; i++) {
        final shareBase64 = config[_kFactorKeys[i]];
        if (shareBase64 == null) return false;
        sharesToReconstruct.add(utf8.decode(base64Decode(shareBase64)));
      }

      // 3. Reconstruct master key
      final passphrase = "ampcrypt-secure-passphrase";
      final recoveredMasterKey = _cryptoService.recoverSecret(
        sharesToReconstruct,
        passphrase: passphrase,
      );

      // 4. Read and decrypt metadata.json.enc to verify the Master Key
      final indexFile = File(p.join(path, 'metadata.json.enc'));
      if (await indexFile.exists()) {
        final encryptedMetadata = await indexFile.readAsBytes();
        final decryptedMetadataBytes = await _cryptoService.decryptData(
          encryptedMetadata,
          recoveredMasterKey,
        );
        final jsonString = utf8.decode(decryptedMetadataBytes);
        json.decode(jsonString);
      }

      // If we got here, verification succeeded! Add to remembered vaults
      final profile = VaultProfile(
        name: name.isNotEmpty ? name : p.basename(path),
        path: path,
        storageType: 'local',
        driveLetter: driveLetter,
      );
      await addRememberedVault(profile);
      await selectVault(profile);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  List<Map<String, dynamic>> listVaultDirectory(String virtualPath) => [];

  @override
  Future<Uint8List?> getVaultFileBytes(String virtualPath) async => null;

  @override
  Future<bool> importFileToVault(String localSourcePath, String targetVirtualDir) async => false;

  @override
  Future<bool> exportFileFromVault(String virtualPath, String localDestPath) async => false;

  @override
  Future<bool> createVaultDirectory(String virtualDirPath) async => false;

  @override
  Future<bool> deleteVaultPath(String virtualPath) async => false;

  @override
  Future<int> scavengeVaultFiles() async => 0;
}

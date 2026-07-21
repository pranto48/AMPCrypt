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
  Process? _rcloneProcess;

  // In-memory cache for the unlocked master key
  Uint8List? _cachedMasterKey;

  VaultRepositoryImpl({
    required CryptoService cryptoService,
    required this._prefs,
  })  : _cryptoService = cryptoService,
        _webDavServer = WebDavServer(cryptoService) {
    _initVaultFromHistory();
  }

  void _initVaultFromHistory() async {
    try {
      final currentPath = _prefs.getString('vault_path');
      if (currentPath == null || currentPath.isEmpty) {
        final list = await getRememberedVaults();
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

    // 9. Windows-specific: Extract pre-formatted VHDX container template
    if (Platform.isWindows) {
      final vhdxPath = p.join(vaultPath, 'vault.vhdx');
      final vhdxEncPath = p.join(vaultPath, 'vault.vhdx.enc');
      final tempZipPath = p.join(vaultPath, 'vault_template.zip');

      // Extract compressed pre-formatted VHDX from assets to local vault folder
      try {
        final byteData = await rootBundle.load('assets/vault_template.zip');
        final buffer = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        await File(tempZipPath).writeAsBytes(buffer, flush: true);

        // Decompress using native PowerShell Expand-Archive (runs under standard privileges)
        await Process.run('powershell.exe', [
          '-Command',
          "Expand-Archive -Path '$tempZipPath' -DestinationPath '$vaultPath' -Force"
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
    await addRememberedVault(VaultProfile(
      name: p.basename(vaultPath),
      path: vaultPath,
      storageType: 'local',
      driveLetter: getDriveLetter(),
    ));

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

  static const _winFspChannel = MethodChannel('ampcrypt/winfsp');
  static const _helloChannel = MethodChannel('ampcrypt/windows_hello');

  Future<String?> _mountVhdxDiskpart(String vhdxPath, String preferredLetter) async {
    final letterOnly = preferredLetter.replaceAll(':', '');
    String targetLetter = letterOnly;
    try {
      final drivesResult = await Process.run('powershell.exe', [
        '-Command',
        '[System.IO.DriveInfo]::GetDrives() | Select-Object -ExpandProperty Name'
      ]);
      final activeDrives = drivesResult.stdout.toString().split('\r\n')
          .map((d) => d.replaceAll(':\\', '').trim().toUpperCase())
          .where((d) => d.isNotEmpty)
          .toList();
      
      if (activeDrives.contains(letterOnly.toUpperCase())) {
        final candidates = ['Z','Y','X','W','V','U','T','S','R','Q','P','O','N','M','L','K','J','I','H','G'];
        for (var c in candidates) {
          if (!activeDrives.contains(c)) {
            targetLetter = c;
            break;
          }
        }
      }
    } catch (_) {}

    final supportDir = await getApplicationSupportDirectory();
    final mountScriptPath = p.join(supportDir.path, 'mount_script.txt');
    final scriptContent = [
      'select vdisk file="$vhdxPath"',
      'attach vdisk',
      'online disk',
      'attributes disk clear readonly',
      'select partition 1',
      'assign letter=$targetLetter',
    ].join('\r\n');
    
    await File(mountScriptPath).writeAsString(scriptContent);
    try {
      final res = await Process.run('diskpart.exe', ['/s', mountScriptPath]);
      if (res.exitCode != 0) return null;
    } catch (_) {
      return null; // Requires elevation; fall back to WebDAV
    }
    
    bool success = false;
    for (int i = 0; i < 5; i++) {
      await Future.delayed(const Duration(milliseconds: 1000));
      try {
        final checkResult = await Process.run('powershell.exe', [
          '-Command',
          '[System.IO.DriveInfo]::GetDrives() | Where-Object { \$_.Name -eq "' + targetLetter + ':\\" } | Select-Object -ExpandProperty Name'
        ]);
        if (checkResult.stdout.toString().trim().isNotEmpty) {
          success = true;
          break;
        }
      } catch (_) {}
    }

    if (success) {
      return '$targetLetter:';
    }
    return null;
  }

  Future<void> _dismountVhdxDiskpart(String vhdxPath) async {
    final supportDir = await getApplicationSupportDirectory();
    final unmountScriptPath = p.join(supportDir.path, 'unmount_script.txt');
    final scriptContent = [
      'select vdisk file="$vhdxPath"',
      'offline disk',
      'detach vdisk',
    ].join('\r\n');
    await File(unmountScriptPath).writeAsString(scriptContent);
    try {
      await Process.run('diskpart.exe', ['/s', unmountScriptPath]);
    } catch (_) {}
  }

  Future<void> _startServerAndMount(Uint8List masterKey) async {
    final vaultPath = getVaultPath();
    final driveLetter = getDriveLetter();

    if (Platform.isWindows && storageType == 'local') {
      try {
        final vhdxPath = p.join(vaultPath, 'vault.vhdx');
        final vhdxEncPath = p.join(vaultPath, 'vault.vhdx.enc');

        final vhdxFile = File(vhdxPath);
        final vhdxEncFile = File(vhdxEncPath);

        // ── LEGACY VAULT MIGRATION ──────────────────────────────────────────
        if (!vhdxEncFile.existsSync()) {
          final tempZipPath = p.join(vaultPath, 'vault_template.zip');
          try {
            final byteData = await rootBundle.load('assets/vault_template.zip');
            final buffer = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
            await File(tempZipPath).writeAsBytes(buffer, flush: true);

            await Process.run('powershell.exe', [
              '-Command',
              "Expand-Archive -Path '$tempZipPath' -DestinationPath '$vaultPath' -Force"
            ]);
            try { await File(tempZipPath).delete(); } catch (_) {}

            final templateFile = File(p.join(vaultPath, 'vault_template.vhdx'));
            if (templateFile.existsSync()) {
              await templateFile.rename(vhdxPath);
            }
          } catch (_) {}

          if (vhdxFile.existsSync()) {
            final tempLetter = await _mountVhdxDiskpart(vhdxPath, 'Y');
            if (tempLetter != null) {
              final legacyDataDir = Directory(p.join(vaultPath, 'data'));
              if (legacyDataDir.existsSync()) {
                try {
                  await Process.run('powershell.exe', [
                    '-Command',
                    "Copy-Item -Path '${legacyDataDir.path}\\*' -Destination '${tempLetter}\\' -Recurse -Force -ErrorAction SilentlyContinue"
                  ]);
                } catch (_) {}
              }
              await _dismountVhdxDiskpart(vhdxPath);
              await Future.delayed(const Duration(milliseconds: 1500));
            } else {
              await _dismountVhdxDiskpart(vhdxPath);
              await Future.delayed(const Duration(milliseconds: 1500));
            }

            if (vhdxFile.existsSync()) {
              await _encryptFile(vhdxFile, vhdxEncFile, masterKey);
              try { vhdxFile.deleteSync(); } catch (_) {}
            }
          }
        }

        // ── NORMAL UNLOCK: DECRYPT ──────────────────────────────────────────
        if (vhdxEncFile.existsSync() && !vhdxFile.existsSync()) {
          await _decryptFile(vhdxEncFile, vhdxFile, masterKey);
        }

        // ── MOUNT VHDX VIA DISKPART ─────────────────────────────────────────
        if (vhdxFile.existsSync()) {
          final activeDriveLetter = await _mountVhdxDiskpart(vhdxPath, driveLetter);
          if (activeDriveLetter != null) {
            await _prefs.setString('drive_letter', activeDriveLetter);

            // ── INJECT TRANSPARENT CUSTOM ICON ──────────────────────────────────
            final activeLetter = activeDriveLetter.replaceAll(':', '');
            try {
              final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
              final supportDir = await getApplicationSupportDirectory();
              final iconFile = File(p.join(supportDir.path, 'vault_drive.ico'));
              String securityIcon = iconFile.path;
              if (!await iconFile.exists()) {
                try {
                  final byteData = await rootBundle.load('assets/vault_drive.ico');
                  await iconFile.writeAsBytes(
                    byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
                    flush: true,
                  );
                } catch (_) {
                  securityIcon = '$systemRoot\\System32\\imageres.dll,104';
                }
              }

              // HKLM and HKCU registry overrides
              try {
                await Process.run('powershell.exe', [
                  '-Command',
                  'New-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$activeLetter\\DefaultIcon" -Force; Set-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$activeLetter\\DefaultIcon" -Value "$securityIcon"; New-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$activeLetter\\DefaultLabel" -Force; Set-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$activeLetter\\DefaultLabel" -Value "AMPCrypt Vault"'
                ]);
              } catch (_) {}

              try {
                await Process.run('reg.exe', [
                  'add',
                  'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$activeLetter\\DefaultIcon',
                  '/ve', '/d', securityIcon, '/f'
                ]);
                await Process.run('reg.exe', [
                  'add',
                  'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$activeLetter\\DefaultLabel',
                  '/ve', '/d', 'AMPCrypt Vault', '/f'
                ]);
              } catch (_) {}

              try {
                await Process.run('reg.exe', [
                  'add',
                  'HKCU\\Software\\Classes\\Applications\\Explorer.exe\\Drives\\$activeLetter\\DefaultIcon',
                  '/ve', '/d', securityIcon, '/f'
                ]);
                await Process.run('reg.exe', [
                  'add',
                  'HKCU\\Software\\Classes\\Applications\\Explorer.exe\\Drives\\$activeLetter\\DefaultLabel',
                  '/ve', '/d', 'AMPCrypt Vault', '/f'
                ]);
              } catch (_) {}
            } catch (_) {}

            // Notify Windows shell immediately, then again after 1s
            try {
              await _winFspChannel.invokeMethod<void>('refreshShell');
            } catch (_) {}
            Future.delayed(const Duration(milliseconds: 1000), () async {
              try {
                await _winFspChannel.invokeMethod<void>('refreshShell');
              } catch (_) {}
            });
            
            await PortableStateSync.syncToPortable();
            return;
          }
        }
      } catch (_) {
        // VHDX / diskpart failed due to elevation; fall back to WebDAV/WinFSP zero-elevation storage
      }
    }

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
      
      // Check WinFSP dependency first
      final fspInstalled = await isWinFspInstalled();
      if (!fspInstalled) {
        throw Exception("WINFSP_MISSING");
      }
      
      // Ensure rclone is available
      final rclonePath = await _ensureRclone();
      
      // Safely kill any existing rclone process
      try {
        if (_rcloneProcess != null) {
          _rcloneProcess!.kill();
          _rcloneProcess = null;
        }
      } catch (_) {}

      // Launch silent rclone.exe mount process
      final supportDir = await getApplicationSupportDirectory();
      final cachePath = storageType == 'ftp'
          ? p.join(supportDir.path, '.amp_cache_ftp')
          : p.join(vaultPath, '.amp_cache');

      _rcloneProcess = await Process.start(
        rclonePath,
        [
          'mount',
          ':webdav:',
          driveLetter,
          '--webdav-url',
          'http://127.0.0.1:$port',
          '--vfs-cache-mode',
          'writes',
          '--cache-dir',
          cachePath,
          '--network-mode=false',
          '--no-checksum',
          '--no-modtime',
          '--volname',
          'AMPCrypt',
        ],
        runInShell: false,
      );

      // Wait a moment for rclone to initialize mount
      await Future.delayed(const Duration(milliseconds: 1500));

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
        
        final supportDir = await getApplicationSupportDirectory();
        final iconFile = File(p.join(supportDir.path, 'vault_drive.ico'));
        String securityIcon = iconFile.path;
        if (!await iconFile.exists()) {
          try {
            final byteData = await rootBundle.load('assets/vault_drive.ico');
            await iconFile.writeAsBytes(
              byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
              flush: true,
            );
          } catch (_) {
            securityIcon = '$systemRoot\\System32\\imageres.dll,104';
          }
        }

        // 1. HKCU DriveIcons (no admin needed)
        try {
          await Process.run('powershell.exe', [
            '-Command',
            'New-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultIcon" -Force; Set-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultIcon" -Value "$securityIcon"; New-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultLabel" -Force; Set-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultLabel" -Value "AMPCrypt Vault"'
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
            '/f'
          ]);
          await Process.run('reg.exe', [
            'add',
            'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letterOnly\\DefaultLabel',
            '/ve',
            '/d',
            'AMPCrypt Vault',
            '/f'
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
            '/f'
          ]);
          await Process.run('reg.exe', [
            'add',
            'HKCU\\Software\\Classes\\Applications\\Explorer.exe\\Drives\\$letterOnly\\DefaultLabel',
            '/ve',
            '/d',
            'AMPCrypt Vault',
            '/f'
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

  Future<void> _stopServerAndUnmount() async {
    if (Platform.isWindows) {
      final preferredLetter = getDriveLetter().replaceAll(':', '');
      final activeLetter = _prefs.getString('drive_letter')?.replaceAll(':', '') ?? preferredLetter;

      if (storageType == 'local') {
        final vaultPath = getVaultPath();
        final vhdxPath = p.join(vaultPath, 'vault.vhdx');
        final vhdxEncPath = p.join(vaultPath, 'vault.vhdx.enc');

        await _dismountVhdxDiskpart(vhdxPath);
        await Future.delayed(const Duration(milliseconds: 1500));

        final masterKey = _cachedMasterKey;
        if (masterKey != null) {
          final vhdxFile = File(vhdxPath);
          final vhdxEncFile = File(vhdxEncPath);
          if (vhdxFile.existsSync()) {
            try {
              await _encryptFile(vhdxFile, vhdxEncFile, masterKey);
              vhdxFile.deleteSync();
            } catch (_) {}
          }
        }

        // Clean up registry keys for both preferred and active letters
        for (var letter in [preferredLetter, activeLetter]) {
          try {
            await Process.run('powershell.exe', [
              '-Command',
              'Remove-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letter" -Recurse -ErrorAction SilentlyContinue'
            ]);
          } catch (_) {}
          try {
            await Process.run('reg.exe', [
              'delete',
              'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letter',
              '/f'
            ]);
          } catch (_) {}
          try {
            await Process.run('reg.exe', [
              'delete',
              'HKCU\\Software\\Classes\\Applications\\Explorer.exe\\Drives\\$letter',
              '/f'
            ]);
          } catch (_) {}
        }

        try {
          await _winFspChannel.invokeMethod<void>('refreshShell');
        } catch (_) {}
        
        await PortableStateSync.syncToPortable();
        return;
      }

      // Rclone WebDAV Mount Cleanup (FTP Fallback)
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
            await Process.run('powershell.exe', [
              '-Command',
              'Remove-Item -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letter" -Recurse -ErrorAction SilentlyContinue'
            ]);
          } catch (_) {}
          try {
            await Process.run('reg.exe', [
              'delete',
              'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Explorer\\DriveIcons\\$letter',
              '/f'
            ]);
          } catch (_) {}
          try {
            await Process.run('reg.exe', [
              'delete',
              'HKCU\\Software\\Classes\\Applications\\Explorer.exe\\Drives\\$letter',
              '/f'
            ]);
          } catch (_) {}
        }

        // Cache Cleanup
        try {
          final tfsDavDir = Directory(r'C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp\TfsStore\Tfs_DAV');
          if (await tfsDavDir.exists()) {
            await tfsDavDir.delete(recursive: true);
          }
        } catch (_) {}
        try {
          await Process.run('cmd.exe', [
            '/c',
            r'del /f /s /q "C:\Windows\ServiceProfiles\LocalService\AppData\Local\Temp\TfsStore\Tfs_DAV\*"'
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
      final result = await Process.run('reg.exe', ['query', r'HKLM\SOFTWARE\WOW6432Node\WinFsp']);
      if (result.exitCode == 0) return true;
    } catch (_) {}
    try {
      final result = await Process.run('reg.exe', ['query', r'HKLM\SOFTWARE\WinFsp']);
      if (result.exitCode == 0) return true;
    } catch (_) {}
    return false;
  }

  Future<String> _ensureRclone() async {
    // 1. Check installer's Program Files directory first (bundled rclone)
    final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final bundledRclone = File(p.join(programFiles, 'ampcrypt', 'rclone.exe'));
    if (await bundledRclone.exists()) {
      return bundledRclone.path;
    }

    // 2. Check AppData support directory (previously downloaded)
    final supportDir = await getApplicationSupportDirectory();
    final rcloneExe = File(p.join(supportDir.path, 'rclone.exe'));
    if (await rcloneExe.exists()) {
      return rcloneExe.path;
    }

    // 3. Last resort: download from internet silently
    final psCommand = '''
      Set-Location -Path '${supportDir.path}';
      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
      Invoke-WebRequest -Uri 'https://downloads.rclone.org/v1.66.0/rclone-v1.66.0-windows-amd64.zip' -OutFile 'rclone.zip';
      Expand-Archive -Path 'rclone.zip' -DestinationPath 'rclone-temp' -Force;
      Copy-Item 'rclone-temp\\rclone-v1.66.0-windows-amd64\\rclone.exe' -Destination 'rclone.exe' -Force;
      Remove-Item -Recurse -Force 'rclone-temp', 'rclone.zip'
    ''';
    
    await Process.run('powershell.exe', ['-Command', psCommand]);
    return rcloneExe.path;
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
    // Default to D:\Data on Windows; fall back to home dir on other platforms
    if (Platform.isWindows) {
      return r'D:\Data';
    }
    final home = _getHomeDir();
    return p.join(home, '.ampcrypt_vault');
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
    await addRememberedVault(VaultProfile(
      name: p.basename(path),
      path: path,
      storageType: 'local',
      driveLetter: driveLetter,
    ));
    
    if (isCurrentlyUnlocked && masterKey != null) {
      await _startServerAndMount(masterKey);
    }
  }

  @override
  String get storageType => _prefs.getString('vault_storage_type') ?? 'local';

  @override
  Future<bool> testFtpConnection(String host, int port, String user, String pass, String path) async {
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
  Future<List<String>> listFtpDirectories(String host, int port, String user, String pass, String currentPath) async {
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
  Future<bool> createFtpDirectory(String host, int port, String user, String pass, String parentPath, String folderName) async {
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
    await addRememberedVault(VaultProfile(
      name: 'FTP: $host$path',
      path: path,
      storageType: 'ftp',
      driveLetter: driveLetter,
      ftpHost: host,
      ftpPort: port,
      ftpUsername: user,
      ftpPassword: pass,
      ftpRemotePath: path,
    ));
    
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
      masterkeyMap[_kFactorKeys[i]] = base64Encode(utf8.encode(operationalShares[i]));
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
    final metadataBytes = Uint8List.fromList(utf8.encode(json.encode(metadataMap)));
    final masterkeyBytes = Uint8List.fromList(utf8.encode(json.encode(masterkeyMap)));
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
    await _prefs.setString('encrypted_password_share', base64Encode(encryptedPasswordShare));
    for (int i = 1; i < level; i++) {
      await _prefs.setString(_kFactorKeys[i], base64Encode(utf8.encode(operationalShares[i])));
    }
    for (int i = level; i < 4; i++) {
      await _prefs.remove(_kFactorKeys[i]);
    }

    await _prefs.setInt('auth_level', level);
    await _prefs.setBool('vault_created', true);
    await _prefs.setBool('is_device_trusted', true);
    await _prefs.setString('device_fingerprint', _generateMockDeviceFingerprint());

    // 7. Cache master key and mount
    _cachedMasterKey = masterKey;

    // Save to remembered vaults
    await addRememberedVault(VaultProfile(
      name: 'FTP: $host$path',
      path: path,
      storageType: 'ftp',
      driveLetter: driveLetter,
      ftpHost: host,
      ftpPort: port,
      ftpUsername: user,
      ftpPassword: pass,
      ftpRemotePath: path,
    ));

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
      final metadataMap = json.decode(utf8.decode(metadataBytes)) as Map<String, dynamic>;

      Map<String, dynamic> masterkeyMap = {};
      if (await storage.fileExists('masterkey.ampcrypt')) {
        final masterkeyBytes = await storage.readFile('masterkey.ampcrypt');
        masterkeyMap = json.decode(utf8.decode(masterkeyBytes)) as Map<String, dynamic>;
      }

      final configMap = {...metadataMap, ...masterkeyMap};

      final String? saltBase64 = configMap['password_salt'];
      final String? encryptedShareBase64 = configMap['encrypted_password_share'];
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      // 1. Verify password
      final derivedKey = await _cryptoService.deriveKey(password, salt);
      final decryptedBytes = await _cryptoService.decryptData(encryptedPasswordShare, derivedKey);
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
      await _prefs.setString('device_fingerprint', _generateMockDeviceFingerprint());

      // 4. Cache master key and mount
      _cachedMasterKey = recoveredMasterKey;

      // Save to remembered vaults
      await addRememberedVault(VaultProfile(
        name: 'FTP: $host$path',
        path: path,
        storageType: 'ftp',
        driveLetter: driveLetter,
        ftpHost: host,
        ftpPort: port,
        ftpUsername: user,
        ftpPassword: pass,
        ftpRemotePath: path,
      ));

      await _startServerAndMount(recoveredMasterKey);
      return true;
    } catch (_) {
      return false;
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

    final masterkeyKeys = [
      'encrypted_password_share',
      ..._kFactorKeys,
    ];

    config.forEach((key, value) {
      if (masterkeyKeys.contains(key)) {
        masterkey[key] = value;
      } else {
        metadata[key] = value;
      }
    });

    await metadataFile.writeAsString(json.encode(metadata), flush: true);
    await masterkeyFile.writeAsString(json.encode(masterkey), flush: true);
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
        metadata = json.decode(metadataFile.readAsStringSync()) as Map<String, dynamic>;
      }
      if (masterkeyFile.existsSync()) {
        masterkey = json.decode(masterkeyFile.readAsStringSync()) as Map<String, dynamic>;
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

  Future<void> _encryptFile(File inputFile, File outputFile, Uint8List key) async {
    final bytes = await inputFile.readAsBytes();
    final encrypted = await _cryptoService.encryptData(bytes, key);
    await outputFile.writeAsBytes(encrypted, flush: true);
  }

  Future<void> _decryptFile(File inputFile, File outputFile, Uint8List key) async {
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
  Future<String?> sendRecoveryEmail(String email, String code) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('https://api.resend.com/emails'));
      
      request.headers.set('Authorization', 'Bearer re_6uqukUSr_JhcPeNW5AhY2264TZASygaS9');
      request.headers.set('Content-Type', 'application/json');
      
      final body = {
        'from': 'AMPCrypt <noreply@itsupport.bd>',
        'to': [email],
        'subject': 'AMPCrypt Recovery Verification Code',
        'html': '<p>Your AMPCrypt security recovery code is: <strong>$code</strong></p><p>Please enter this code in the application along with your security question answers to recover your vault.</p>'
      };
      
      request.write(json.encode(body));
      final response = await request.close();
      
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200 || response.statusCode == 201) {
        return null; // Success
      } else {
        try {
          final errJson = json.decode(responseBody);
          return errJson['message'] ?? 'SMTP server returned status ${response.statusCode}';
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

  @override
  Future<bool> isTpmSupported() async {
    if (!Platform.isWindows) return false;
    try {
      final supported = await _helloChannel.invokeMethod<bool>('isTpmSupported');
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
      final String? cipher = await _helloChannel.invokeMethod<String>('encryptKek', _cachedMasterKey);
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
      final rawKek = await _helloChannel.invokeMethod<dynamic>('decryptKek', cipher);
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
  Future<List<VaultProfile>> getRememberedVaults() async {
    try {
      final file = await _getHistoryFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final data = json.decode(content);
      if (data is Map && data.containsKey('vaults')) {
        final list = data['vaults'] as List;
        return list.map((item) => VaultProfile.fromJson(item as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return [];
  }

  @override
  Future<void> addRememberedVault(VaultProfile profile) async {
    final list = await getRememberedVaults();
    final index = list.indexWhere((p) => p.path == profile.path);
    if (index != -1) {
      list[index] = profile;
    } else {
      list.add(profile);
    }
    await _saveRememberedVaults(list);
  }

  @override
  Future<void> removeRememberedVault(String path) async {
    final list = await getRememberedVaults();
    list.removeWhere((p) => p.path == path);
    await _saveRememberedVaults(list);
    
    // If the removed vault was the active one, clear active settings or switch
    if (getVaultPath() == path || (storageType == 'ftp' && _prefs.getString('ftp_remote_path') == path)) {
      if (list.isNotEmpty) {
        await selectVault(list.first);
      } else {
        // Clear all vault settings
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
      }
    }
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
        final emptyData = {
          'last_active_path': '',
          'vaults': [],
        };
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
          final profiles = list.map((item) => VaultProfile.fromJson(item as Map<String, dynamic>)).toList();
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
          await _prefs.setString('password_salt', config['password_salt'] as String);
        }
        if (config.containsKey('encrypted_password_share')) {
          await _prefs.setString('encrypted_password_share', config['encrypted_password_share'] as String);
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
          final metadataMap = json.decode(utf8.decode(metadataBytes)) as Map<String, dynamic>;
          Map<String, dynamic> masterkeyMap = {};
          if (await storage.fileExists('masterkey.ampcrypt')) {
            final masterkeyBytes = await storage.readFile('masterkey.ampcrypt');
            masterkeyMap = json.decode(utf8.decode(masterkeyBytes)) as Map<String, dynamic>;
          }
          final configMap = {...metadataMap, ...masterkeyMap};
          await _prefs.setBool('vault_created', configMap['vault_created'] == true);
          if (configMap.containsKey('auth_level')) {
            await _prefs.setInt('auth_level', configMap['auth_level'] as int);
          }
          if (configMap.containsKey('password_salt')) {
            await _prefs.setString('password_salt', configMap['password_salt'] as String);
          }
          if (configMap.containsKey('encrypted_password_share')) {
            await _prefs.setString('encrypted_password_share', configMap['encrypted_password_share'] as String);
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

      final metadataMap = json.decode(await metadataFile.readAsString()) as Map<String, dynamic>;
      Map<String, dynamic> masterkeyMap = {};
      if (await masterkeyFile.exists()) {
        masterkeyMap = json.decode(await masterkeyFile.readAsString()) as Map<String, dynamic>;
      }

      final config = {...metadataMap, ...masterkeyMap};
      final String? saltBase64 = config['password_salt'];
      final String? encryptedShareBase64 = config['encrypted_password_share'];
      if (saltBase64 == null || encryptedShareBase64 == null) return false;

      final salt = base64Decode(saltBase64);
      final encryptedPasswordShare = base64Decode(encryptedShareBase64);

      // 1. Derive key from password and decrypt the password share
      final derivedKey = await _cryptoService.deriveKey(password, salt);
      final decryptedBytes = await _cryptoService.decryptData(encryptedPasswordShare, derivedKey);
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
        final decryptedMetadataBytes = await _cryptoService.decryptData(encryptedMetadata, recoveredMasterKey);
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
}

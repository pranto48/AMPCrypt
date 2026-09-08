/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * This program is free software under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

typedef SecurityBreachCallback = void Function(String breachReason, String canaryPath);

class CanaryGuardService {
  static final CanaryGuardService _instance = CanaryGuardService._internal();
  factory CanaryGuardService() => _instance;
  CanaryGuardService._internal();

  final List<String> _canaryFilenames = [
    '.canary_vault_header.dat',
    '.sec_honey_token.bin',
    'system_integrity_canary.sys',
  ];

  final Map<String, String> _knownCanaryHashes = {};
  StreamSubscription<FileSystemEvent>? _watcherSubscription;
  Timer? _pollingTimer;
  bool _isArmed = false;
  SecurityBreachCallback? _onBreachDetected;

  bool get isArmed => _isArmed;

  /// Arms the canary honey-pot trap inside the given [vaultPath].
  Future<void> armTrap({
    required String vaultPath,
    required SecurityBreachCallback onBreach,
  }) async {
    _onBreachDetected = onBreach;
    _knownCanaryHashes.clear();

    final dataDir = Directory(p.join(vaultPath, 'data'));
    if (!dataDir.existsSync()) {
      try {
        dataDir.createSync(recursive: true);
      } catch (_) {}
    }

    // Plant or verify each canary file
    for (final filename in _canaryFilenames) {
      final canaryFile = File(p.join(dataDir.path, filename));
      if (!canaryFile.existsSync()) {
        final randomPayload = _generateCanaryPayload(filename);
        await canaryFile.writeAsBytes(randomPayload, flush: true);
      }
      final hash = await _computeFileSha256(canaryFile);
      _knownCanaryHashes[canaryFile.path] = hash;
    }

    // Setup active file system watcher
    try {
      _watcherSubscription = dataDir.watch(events: FileSystemEvent.all).listen((event) {
        if (_knownCanaryHashes.containsKey(event.path)) {
          _verifyCanaryIntegrity(event.path, 'Real-time watcher detected modification event: ${event.type}');
        }
      });
    } catch (_) {}

    // Setup periodic polling watchdog (checks every 3 seconds)
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _performPeriodicCanaryAudit();
    });

    _isArmed = true;
  }

  /// Disarms and cleans up canary monitors upon vault lock.
  void disarmTrap() {
    _watcherSubscription?.cancel();
    _watcherSubscription = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _knownCanaryHashes.clear();
    _isArmed = false;
    _onBreachDetected = null;
  }

  Future<void> _performPeriodicCanaryAudit() async {
    if (!_isArmed) return;
    for (final entry in _knownCanaryHashes.entries) {
      final file = File(entry.key);
      if (!file.existsSync()) {
        _triggerBreachAlert('Canary honey-pot file was unexpectedly deleted or renamed.', entry.key);
        return;
      }
      final currentHash = await _computeFileSha256(file);
      if (currentHash != entry.value) {
        _triggerBreachAlert('Ransomware unauthorized encryption/modification detected on canary file.', entry.key);
        return;
      }
    }
  }

  Future<void> _verifyCanaryIntegrity(String canaryPath, String reason) async {
    if (!_isArmed) return;
    final file = File(canaryPath);
    if (!file.existsSync()) {
      _triggerBreachAlert('Canary honey-pot deleted by external process.', canaryPath);
      return;
    }
    final currentHash = await _computeFileSha256(file);
    final expectedHash = _knownCanaryHashes[canaryPath];
    if (currentHash != expectedHash) {
      _triggerBreachAlert('Ransomware payload detected modifying canary trap ($reason).', canaryPath);
    }
  }

  void _triggerBreachAlert(String reason, String canaryPath) {
    if (!_isArmed) return;
    _isArmed = false;
    _onBreachDetected?.call(reason, canaryPath);
  }

  Uint8List _generateCanaryPayload(String seed) {
    final bytes = utf8.encode('AMPCrypt-ZeroTrust-Canary-HoneyPot::$seed::${DateTime.now().toIso8601String()}');
    return Uint8List.fromList(sha256.convert(bytes).bytes);
  }

  Future<String> _computeFileSha256(File file) async {
    try {
      final bytes = await file.readAsBytes();
      return sha256.convert(bytes).toString();
    } catch (_) {
      return '';
    }
  }
}

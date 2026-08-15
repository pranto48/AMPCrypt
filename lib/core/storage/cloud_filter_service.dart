/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'package:flutter/services.dart';

class CloudFilterService {
  static const MethodChannel _channel =
      MethodChannel('com.itsupport.ampcrypt/cfapi');

  /// Registers a local directory as a native Windows Cloud Filter Sync Root.
  /// This places AMPCrypt at the top of the File Explorer Navigation Pane
  /// with custom display name and drive icon.
  static Future<bool> registerSyncRoot({
    required String path,
    required String name,
    String? iconPath,
  }) async {
    if (!Platform.isWindows) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'registerSyncRoot',
        {
          'path': path,
          'name': name,
          'icon': iconPath ?? '',
        },
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Unregisters the Windows Cloud Filter Sync Root and removes it from Explorer Pane.
  static Future<bool> unregisterSyncRoot(String path) async {
    if (!Platform.isWindows) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'unregisterSyncRoot',
        {'path': path},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Projects a 0-byte dehydrated placeholder file into the sync root directory.
  static Future<bool> createPlaceholder({
    required String syncRootPath,
    required String relativePath,
    required int fileSize,
    String? fileIdentity,
  }) async {
    if (!Platform.isWindows) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'createPlaceholder',
        {
          'syncRootPath': syncRootPath,
          'relativePath': relativePath,
          'fileSize': fileSize,
          'fileIdentity': fileIdentity ?? relativePath,
        },
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sets the Vault state (Locked or Unlocked) and updates the in-RAM master key buffer.
  static Future<bool> setVaultState({
    required bool isUnlocked,
    Uint8List? masterKey,
  }) async {
    if (!Platform.isWindows) return false;
    try {
      final bool? result = await _channel.invokeMethod<bool>(
        'setVaultState',
        {
          'isUnlocked': isUnlocked,
          'masterKey': masterKey,
        },
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}

/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PortableStateSync {
  static bool _isPortable = false;
  static bool get isPortable => _isPortable;

  static Future<void> init() async {
    if (!Platform.isWindows) return;
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);
      final exeLower = exeDir.toLowerCase();
      
      // Packaged MSIX apps or apps installed in Program Files/WindowsApps are NEVER portable
      final isPackagedOrInstalled = exeLower.contains('windowsapps') ||
          exeLower.contains('program files') ||
          Platform.environment.containsKey('PACKAGE_NAME');
      
      if (isPackagedOrInstalled) {
        _isPortable = false;
        return;
      }

      // Standalone/USB portable mode uses 'portable_data' (never Flutter's engine 'data' directory)
      final portableDataDir = Directory(p.join(exeDir, 'portable_data'));
      final portableFlag = File(p.join(exeDir, 'portable.flag'));

      if (portableDataDir.existsSync() || portableFlag.existsSync()) {
        _isPortable = true;
      }

      if (_isPortable) {
        if (!portableDataDir.existsSync()) {
          portableDataDir.createSync(recursive: true);
        }

        // Sync from portable folder to AppData (restore state)
        final supportDir = await getApplicationSupportDirectory();
        await _copyDirectory(portableDataDir, supportDir);
      }
    } catch (_) {}
  }

  static Future<void> syncToPortable() async {
    if (!_isPortable) return;
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);
      final portableDataDir = Directory(p.join(exeDir, 'portable_data'));
      final supportDir = await getApplicationSupportDirectory();
      
      if (!portableDataDir.existsSync()) {
        portableDataDir.createSync(recursive: true);
      }
      await _copyDirectory(supportDir, portableDataDir);
    } catch (_) {}
  }

  static Future<void> _copyDirectory(Directory source, Directory destination) async {
    if (!source.existsSync()) return;
    await for (var entity in source.list(recursive: true)) {
      if (entity is File) {
        // Skip temp script/mount files and lock files
        final name = p.basename(entity.path);
        if (name.endsWith('.ps1') || name.endsWith('.txt') || name.endsWith('.ico') || name.startsWith('.')) {
          continue;
        }
        final relativePath = p.relative(entity.path, from: source.path);
        final targetPath = p.join(destination.path, relativePath);
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        await entity.copy(targetFile.path);
      }
    }
  }
}

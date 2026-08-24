/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * This program is free software under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'package:path/path.dart' as p;

class WindowsShellService {
  static final WindowsShellService _instance = WindowsShellService._internal();
  factory WindowsShellService() => _instance;
  WindowsShellService._internal();

  /// Registers Windows Explorer Context Menu entries for files and folders.
  Future<bool> registerExplorerContextMenu() async {
    if (!Platform.isWindows) return false;
    try {
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);
      final iconPath = p.join(exeDir, 'data', 'flutter_assets', 'assets', 'app_icon.ico');
      final appIcon = File(iconPath).existsSync() ? iconPath : exePath;

      // 1. File Context Menu: Encrypt with AMPCrypt
      final fileReg = '''
Windows Registry Editor Version 5.00

[HKEY_CURRENT_USER\\Software\\Classes\\*\\shell\\AMPCrypt]
@="Encrypt with AMPCrypt"
"Icon"="\\"${appIcon.replaceAll('\\', '\\\\')}\\""

[HKEY_CURRENT_USER\\Software\\Classes\\*\\shell\\AMPCrypt\\command]
@="\\"${exePath.replaceAll('\\', '\\\\')}\\" --encrypt \\"%1\\""

[HKEY_CURRENT_USER\\Software\\Classes\\*\\shell\\AMPCryptShred]
@="Secure Shred with AMPCrypt"
"Icon"="\\"${appIcon.replaceAll('\\', '\\\\')}\\""

[HKEY_CURRENT_USER\\Software\\Classes\\*\\shell\\AMPCryptShred\\command]
@="\\"${exePath.replaceAll('\\', '\\\\')}\\" --shred \\"%1\\""

[HKEY_CURRENT_USER\\Software\\Classes\\Directory\\shell\\AMPCrypt]
@="Create AMPCrypt Vault Here"
"Icon"="\\"${appIcon.replaceAll('\\', '\\\\')}\\""

[HKEY_CURRENT_USER\\Software\\Classes\\Directory\\shell\\AMPCrypt\\command]
@="\\"${exePath.replaceAll('\\', '\\\\')}\\" --vault-path \\"%1\\""
''';

      final tempReg = File(p.join(Directory.systemTemp.path, 'ampcrypt_shell.reg'));
      await tempReg.writeAsString(fileReg);
      await Process.run('reg.exe', ['import', tempReg.path]);
      try {
        await tempReg.delete();
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Unregisters Windows Explorer Context Menu entries.
  Future<bool> unregisterExplorerContextMenu() async {
    if (!Platform.isWindows) return false;
    try {
      await Process.run('reg.exe', [
        'delete',
        r'HKCU\Software\Classes\*\shell\AMPCrypt',
        '/f',
      ]);
      await Process.run('reg.exe', [
        'delete',
        r'HKCU\Software\Classes\*\shell\AMPCryptShred',
        '/f',
      ]);
      await Process.run('reg.exe', [
        'delete',
        r'HKCU\Software\Classes\Directory\shell\AMPCrypt',
        '/f',
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Toggles Run on Windows Startup.
  Future<bool> setStartWithWindows(bool enable) async {
    if (!Platform.isWindows) return false;
    try {
      if (enable) {
        final exePath = Platform.resolvedExecutable;
        await Process.run('reg.exe', [
          'add',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'AMPCrypt',
          '/t',
          'REG_SZ',
          '/d',
          '"$exePath" --minimized',
          '/f',
        ]);
      } else {
        await Process.run('reg.exe', [
          'delete',
          r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run',
          '/v',
          'AMPCrypt',
          '/f',
        ]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

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
      final isProgramFiles = exeDir.toLowerCase().contains('program files');
      final portableDataDir = Directory(p.join(exeDir, 'data'));
      
      if (portableDataDir.existsSync()) {
        _isPortable = true;
      } else if (!isProgramFiles) {
        // Test if writable
        final testFile = File(p.join(exeDir, '.write_test'));
        await testFile.writeAsString('test', flush: true);
        await testFile.delete();
        _isPortable = true;
      }

      if (_isPortable) {
        // Ensure local data directory exists next to exe
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
      final portableDataDir = Directory(p.join(exeDir, 'data'));
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

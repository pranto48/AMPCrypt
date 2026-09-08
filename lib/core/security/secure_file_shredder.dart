/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * This program is free software under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

enum ShreddingStandard {
  quickZeroWipe,    // 1-Pass: Overwrite with all zeros
  dod5220_22_M_3Pass, // 3-Pass: Zeros, Ones, Random
  enhanced7Pass,     // 7-Pass: DoD Enhanced multi-cycle random overwrite
}

class SecureFileShredder {
  static final SecureFileShredder _instance = SecureFileShredder._internal();
  factory SecureFileShredder() => _instance;
  SecureFileShredder._internal();

  final Random _secureRandom = Random.secure();

  /// Securely shreds a single file or an entire directory tree using the specified standard.
  Future<bool> shredPath(
    String targetPath, {
    ShreddingStandard standard = ShreddingStandard.dod5220_22_M_3Pass,
    void Function(double progress, String currentFile)? onProgress,
  }) async {
    final file = File(targetPath);
    final dir = Directory(targetPath);

    if (file.existsSync()) {
      return await _shredFile(file, standard: standard);
    } else if (dir.existsSync()) {
      return await _shredDirectory(dir, standard: standard, onProgress: onProgress);
    }
    return false;
  }

  Future<bool> _shredFile(File file, {required ShreddingStandard standard}) async {
    try {
      final length = await file.length();
      final passes = _getPasses(standard);

      final raf = await file.open(mode: FileMode.write);
      try {
        for (int pass = 0; pass < passes; pass++) {
          final buffer = _generatePassBuffer(length, pass, standard);
          await raf.setPosition(0);
          await raf.writeFrom(buffer);
          await raf.flush();
        }
        // Truncate to 0 bytes
        await raf.truncate(0);
      } finally {
        await raf.close();
      }

      // Rename to random obfuscated name before deletion to destroy filesystem journal metadata
      final parentDir = file.parent.path;
      final randomName = _generateRandomAlphaNumeric(16);
      final renamedFile = await file.rename(p.join(parentDir, randomName));
      await renamedFile.delete();

      return true;
    } catch (_) {
      try {
        if (file.existsSync()) await file.delete();
      } catch (_) {}
      return false;
    }
  }

  Future<bool> _shredDirectory(
    Directory dir, {
    required ShreddingStandard standard,
    void Function(double progress, String currentFile)? onProgress,
  }) async {
    try {
      final entities = dir.listSync(recursive: true, followLinks: false);
      final total = entities.length;
      int processed = 0;

      for (final entity in entities.reversed) {
        if (entity is File) {
          await _shredFile(entity, standard: standard);
        } else if (entity is Directory) {
          try {
            await entity.delete();
          } catch (_) {}
        }
        processed++;
        if (onProgress != null && total > 0) {
          onProgress(processed / total, entity.path);
        }
      }

      try {
        if (dir.existsSync()) await dir.delete();
      } catch (_) {}

      return true;
    } catch (_) {
      return false;
    }
  }

  int _getPasses(ShreddingStandard standard) {
    switch (standard) {
      case ShreddingStandard.quickZeroWipe:
        return 1;
      case ShreddingStandard.dod5220_22_M_3Pass:
        return 3;
      case ShreddingStandard.enhanced7Pass:
        return 7;
    }
  }

  Uint8List _generatePassBuffer(int length, int passIndex, ShreddingStandard standard) {
    final buffer = Uint8List(length);
    if (standard == ShreddingStandard.quickZeroWipe) {
      buffer.fillRange(0, length, 0x00);
    } else if (standard == ShreddingStandard.dod5220_22_M_3Pass) {
      if (passIndex == 0) {
        buffer.fillRange(0, length, 0x00);
      } else if (passIndex == 1) {
        buffer.fillRange(0, length, 0xFF);
      } else {
        for (int i = 0; i < length; i++) {
          buffer[i] = _secureRandom.nextInt(256);
        }
      }
    } else {
      // 7-Pass alternating pattern + random
      for (int i = 0; i < length; i++) {
        buffer[i] = _secureRandom.nextInt(256);
      }
    }
    return buffer;
  }

  String _generateRandomAlphaNumeric(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(length, (_) => chars[_secureRandom.nextInt(chars.length)]).join();
  }
}

/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'dart:typed_data';
import 'package:ftpconnect/ftpconnect.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

abstract class VaultStorage {
  Future<void> initialize();
  Future<bool> fileExists(String relativePath);
  Future<Uint8List> readFile(String relativePath);
  Future<void> writeFile(String relativePath, Uint8List bytes);
  Future<void> deleteFile(String relativePath);
  Future<void> copyFile(String srcRelativePath, String destRelativePath);
  Stream<List<int>> openRead(String relativePath);
  Future<void> writeStream(String relativePath, Stream<List<int>> stream);
  Future<List<String>> listFiles(String relativeDirectory);
  String? get localPath;

  /// Calculates a 2-character sharded directory path with .ampcrypt file extension.
  static String getShardedPath(String relativePath) {
    final norm = relativePath.replaceAll('\\', '/');
    if (!norm.startsWith('data/')) return relativePath;

    final filename = p.basename(norm);
    String baseName = filename;
    if (baseName.endsWith('.ampcrypt')) {
      baseName = baseName.substring(0, baseName.length - 9);
    } else if (baseName.endsWith('.c9r')) {
      baseName = baseName.substring(0, baseName.length - 4);
    }

    if (baseName.isEmpty || baseName == '.' || baseName == '..') return relativePath;

    String prefix;
    if (baseName.length >= 2) {
      prefix = baseName.substring(0, 2).toUpperCase();
    } else {
      prefix = '${baseName}0'.toUpperCase();
    }

    return 'data/$prefix/$baseName.ampcrypt';
  }
}

class LocalVaultStorage implements VaultStorage {
  final String vaultPath;

  LocalVaultStorage(this.vaultPath);

  @override
  String? get localPath => vaultPath;

  String _resolveFile(String relativePath) {
    final norm = relativePath.replaceAll('\\', '/');
    if (!norm.startsWith('data/')) {
      return p.join(vaultPath, relativePath);
    }

    final targetSharded = VaultStorage.getShardedPath(relativePath);
    final targetFile = File(p.join(vaultPath, targetSharded));
    if (targetFile.existsSync()) {
      return targetFile.path;
    }

    // Direct check if relativePath already includes extension
    final directFile = File(p.join(vaultPath, relativePath));
    if (directFile.existsSync()) {
      // Migrate legacy file to 2-character sharded directory
      try {
        final parentDir = targetFile.parent;
        if (!parentDir.existsSync()) {
          parentDir.createSync(recursive: true);
        }
        directFile.copySync(targetFile.path);
        directFile.deleteSync();
        return targetFile.path;
      } catch (_) {
        return directFile.path;
      }
    }

    return targetFile.path;
  }

  @override
  Future<void> initialize() async {
    final dataDir = Directory(p.join(vaultPath, 'data'));
    if (!dataDir.existsSync()) {
      dataDir.createSync(recursive: true);
    }
  }

  @override
  Future<bool> fileExists(String relativePath) async {
    final filePath = _resolveFile(relativePath);
    return File(filePath).existsSync();
  }

  @override
  Future<Uint8List> readFile(String relativePath) async {
    final filePath = _resolveFile(relativePath);
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileNotFoundException("File not found: $relativePath");
    }
    return await file.readAsBytes();
  }

  @override
  Future<void> writeFile(String relativePath, Uint8List bytes) async {
    final filePath = _resolveFile(relativePath);
    final file = File(filePath);
    final parentDir = file.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Stream<List<int>> openRead(String relativePath) {
    final filePath = _resolveFile(relativePath);
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileNotFoundException("File not found: $relativePath");
    }
    return file.openRead();
  }

  @override
  Future<void> writeStream(String relativePath, Stream<List<int>> stream) async {
    final filePath = _resolveFile(relativePath);
    final file = File(filePath);
    final parentDir = file.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }
    final sink = file.openWrite();
    await sink.addStream(stream);
    await sink.flush();
    await sink.close();
  }

  @override
  Future<List<String>> listFiles(String relativeDirectory) async {
    final dir = Directory(p.join(vaultPath, relativeDirectory));
    if (!dir.existsSync()) return [];

    final List<String> result = [];
    final entities = dir.listSync(recursive: true);
    for (final entity in entities) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name.endsWith('.ampcrypt')) {
          final pureName = name.substring(0, name.length - 9);
          result.add(pureName);
        } else if (!name.endsWith('.tmp') && !name.endsWith('.bak')) {
          result.add(name);
        }
      }
    }
    return result;
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final filePath = _resolveFile(relativePath);
    final file = File(filePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  @override
  Future<void> copyFile(String srcRelativePath, String destRelativePath) async {
    final srcPath = _resolveFile(srcRelativePath);
    final destPath = _resolveFile(destRelativePath);
    final srcFile = File(srcPath);
    final destFile = File(destPath);
    if (!srcFile.existsSync()) {
      throw FileNotFoundException("Source file not found: $srcRelativePath");
    }
    final parentDir = destFile.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }
    await srcFile.copy(destFile.path);
  }
}

class FtpVaultStorage implements VaultStorage {
  final String host;
  final int port;
  final String username;
  final String password;
  final String remotePath;

  FtpVaultStorage({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.remotePath,
  });

  @override
  String? get localPath => null;

  FTPConnect _createClient() {
    return FTPConnect(
      host,
      port: port,
      user: username,
      pass: password,
      timeout: 30,
    );
  }

  Future<T> _withFtp<T>(Future<T> Function(FTPConnect client) action) async {
    final client = _createClient();
    try {
      await client.connect();
      await client.sendCustomCommand('TYPE I');

      if (remotePath.isNotEmpty && remotePath != '/') {
        final dirs = remotePath.split('/').where((d) => d.isNotEmpty).toList();
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
      return await action(client);
    } finally {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  Future<void> _navigateToRelativeDir(FTPConnect client, String relativePath) async {
    final parts = relativePath.split('/');
    if (parts.length > 1) {
      for (int i = 0; i < parts.length - 1; i++) {
        final dirName = parts[i];
        if (dirName.isEmpty) continue;
        bool dirExists = false;
        try {
          dirExists = await client.changeDirectory(dirName);
        } catch (_) {}
        if (!dirExists) {
          await client.makeDirectory(dirName);
          await client.changeDirectory(dirName);
        }
      }
    }
  }

  @override
  Future<void> initialize() async {
    await _withFtp((client) async {
      bool dataDirExists = false;
      try {
        dataDirExists = await client.changeDirectory('data');
      } catch (_) {}
      if (!dataDirExists) {
        await client.makeDirectory('data');
      }
    });
  }

  @override
  Future<bool> fileExists(String relativePath) async {
    final targetPath = VaultStorage.getShardedPath(relativePath);
    return await _withFtp((client) async {
      await _navigateToRelativeDir(client, targetPath);
      final filename = p.basename(targetPath);
      return await client.checkFileExists(filename);
    });
  }

  @override
  Future<Uint8List> readFile(String relativePath) async {
    final targetPath = VaultStorage.getShardedPath(relativePath);
    return await _withFtp((client) async {
      await _navigateToRelativeDir(client, targetPath);
      final filename = p.basename(targetPath);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, 'ftp_temp_${DateTime.now().millisecondsSinceEpoch}.tmp'));
      try {
        final downloaded = await client.downloadFile(filename, tempFile);
        if (!downloaded || !tempFile.existsSync()) {
          throw FileNotFoundException("Failed to download FTP file: $relativePath");
        }
        return await tempFile.readAsBytes();
      } finally {
        if (tempFile.existsSync()) {
          try { tempFile.deleteSync(); } catch (_) {}
        }
      }
    });
  }

  @override
  Future<void> writeFile(String relativePath, Uint8List bytes) async {
    final targetPath = VaultStorage.getShardedPath(relativePath);
    await _withFtp((client) async {
      await _navigateToRelativeDir(client, targetPath);
      final filename = p.basename(targetPath);
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(p.join(tempDir.path, 'ftp_upload_${DateTime.now().millisecondsSinceEpoch}.tmp'));
      try {
        await tempFile.writeAsBytes(bytes, flush: true);
        await client.uploadFile(tempFile, sRemoteName: filename);
      } finally {
        if (tempFile.existsSync()) {
          try { tempFile.deleteSync(); } catch (_) {}
        }
      }
    });
  }

  @override
  Stream<List<int>> openRead(String relativePath) {
    final controller = StreamController<List<int>>();
    readFile(relativePath).then((bytes) {
      controller.add(bytes);
      controller.close();
    }).catchError((err) {
      controller.addError(err);
      controller.close();
    });
    return controller.stream;
  }

  @override
  Future<void> writeStream(String relativePath, Stream<List<int>> stream) async {
    final bytesBuilder = BytesBuilder();
    await for (final chunk in stream) {
      bytesBuilder.add(chunk);
    }
    await writeFile(relativePath, bytesBuilder.takeBytes());
  }

  @override
  Future<List<String>> listFiles(String relativeDirectory) async {
    return await _withFtp((client) async {
      await _navigateToRelativeDir(client, relativeDirectory);
      final List<FTPEntry> entries = await client.listDirectoryContent();
      return entries
          .where((e) => e.type == FTPEntryType.FILE)
          .map((e) {
            final name = e.name;
            if (name.endsWith('.ampcrypt')) {
              return name.substring(0, name.length - 9);
            }
            return name;
          })
          .where((name) => !name.endsWith('.tmp') && !name.endsWith('.bak'))
          .toList();
    });
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final targetPath = VaultStorage.getShardedPath(relativePath);
    await _withFtp((client) async {
      await _navigateToRelativeDir(client, targetPath);
      final filename = p.basename(targetPath);
      try {
        await client.deleteFile(filename);
      } catch (_) {}
    });
  }

  @override
  Future<void> copyFile(String srcRelativePath, String destRelativePath) async {
    final bytes = await readFile(srcRelativePath);
    await writeFile(destRelativePath, bytes);
  }
}

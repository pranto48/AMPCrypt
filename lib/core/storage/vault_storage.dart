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
  String? get localPath;
}

class LocalVaultStorage implements VaultStorage {
  final String vaultPath;

  LocalVaultStorage(this.vaultPath);

  @override
  String? get localPath => vaultPath;

  @override
  Future<void> initialize() async {
    final dataDir = Directory(p.join(vaultPath, 'data'));
    if (!dataDir.existsSync()) {
      dataDir.createSync(recursive: true);
    }
  }

  @override
  Future<bool> fileExists(String relativePath) async {
    final file = File(p.join(vaultPath, relativePath));
    return file.existsSync();
  }

  @override
  Future<Uint8List> readFile(String relativePath) async {
    final file = File(p.join(vaultPath, relativePath));
    if (!file.existsSync()) {
      throw FileNotFoundException("File not found: $relativePath");
    }
    return await file.readAsBytes();
  }

  @override
  Future<void> writeFile(String relativePath, Uint8List bytes) async {
    final file = File(p.join(vaultPath, relativePath));
    final parentDir = file.parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    final file = File(p.join(vaultPath, relativePath));
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  @override
  Future<void> copyFile(String srcRelativePath, String destRelativePath) async {
    final srcFile = File(p.join(vaultPath, srcRelativePath));
    final destFile = File(p.join(vaultPath, destRelativePath));
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
      // Ensure binary mode for file transfers
      await client.sendCustomCommand('TYPE I');

      // Navigate to or create remote root path
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
    return await _withFtp((client) async {
      await _navigateToRelativeDir(client, relativePath);
      final filename = relativePath.split('/').last;
      return await client.existFile(filename);
    });
  }

  @override
  Future<Uint8List> readFile(String relativePath) async {
    final tempDir = await getTemporaryDirectory();
    final localFile = File(p.join(tempDir.path, 'ampcrypt_download_${DateTime.now().microsecondsSinceEpoch}.tmp'));

    try {
      final success = await _withFtp((client) async {
        await _navigateToRelativeDir(client, relativePath);
        final filename = relativePath.split('/').last;
        return await client.downloadFileWithRetry(filename, localFile, pRetryCount: 1);
      });

      if (!success) {
        throw Exception("Failed to download file from FTP: $relativePath");
      }
      return await localFile.readAsBytes();
    } finally {
      if (localFile.existsSync()) {
        localFile.deleteSync();
      }
    }
  }

  @override
  Future<void> writeFile(String relativePath, Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final filename = relativePath.split('/').last;
    final localFile = File(p.join(tempDir.path, 'ampcrypt_upload_${DateTime.now().microsecondsSinceEpoch}_$filename'));

    try {
      await localFile.writeAsBytes(bytes, flush: true);

      final success = await _withFtp((client) async {
        await _navigateToRelativeDir(client, relativePath);
        return await client.uploadFileWithRetry(localFile, pRetryCount: 1);
      });

      if (!success) {
        throw Exception("Failed to upload file to FTP: $relativePath");
      }
    } finally {
      if (localFile.existsSync()) {
        localFile.deleteSync();
      }
    }
  }

  @override
  Future<void> deleteFile(String relativePath) async {
    await _withFtp((client) async {
      await _navigateToRelativeDir(client, relativePath);
      final filename = relativePath.split('/').last;
      try {
        await client.deleteFile(filename);
      } catch (_) {}
    });
  }

  @override
  Future<void> copyFile(String srcRelativePath, String destRelativePath) async {
    final tempDir = await getTemporaryDirectory();
    final localFile = File(p.join(tempDir.path, 'ampcrypt_copy_${DateTime.now().microsecondsSinceEpoch}.tmp'));

    try {
      final downloadSuccess = await _withFtp((client) async {
        await _navigateToRelativeDir(client, srcRelativePath);
        final srcFilename = srcRelativePath.split('/').last;
        return await client.downloadFileWithRetry(srcFilename, localFile, pRetryCount: 1);
      });

      if (!downloadSuccess) {
        throw Exception("Failed to download source file for copy: $srcRelativePath");
      }

      final uploadSuccess = await _withFtp((client) async {
        await _navigateToRelativeDir(client, destRelativePath);
        return await client.uploadFileWithRetry(localFile, pRetryCount: 1);
      });

      if (!uploadSuccess) {
        throw Exception("Failed to upload copy to destination: $destRelativePath");
      }
    } finally {
      if (localFile.existsSync()) {
        localFile.deleteSync();
      }
    }
  }
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}

/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:flutter/services.dart';
import '../crypto/crypto_service.dart';
import 'vault_storage.dart';

class WebDavServer {
  final CryptoService _cryptoService;
  static const _winFspChannel = MethodChannel('ampcrypt/winfsp');
  
  HttpServer? _server;
  Uint8List? _masterKey;
  VaultStorage? _storage;
  Map<String, dynamic> _index = {'version': 1, 'files': {}, 'directories': []};
  
  bool get isRunning => _server != null;
  int get port => _server?.port ?? 0;
  
  DateTime? lastActivityTime;
  int _cachedTotalSize = 100 * 1024 * 1024 * 1024; // 100 GB fallback
  int _cachedFreeSize = 50 * 1024 * 1024 * 1024;  // 50 GB fallback
  DateTime? _lastQuotaUpdate;
  
  WebDavServer(this._cryptoService);
  
  /// Starts the WebDAV server on loopback IPv4 with a dynamic port.
  Future<void> start(Uint8List masterKey, VaultStorage storage) async {
    if (isRunning) return;
    
    _masterKey = Uint8List.fromList(masterKey);
    _storage = storage;
    
    // Immediately calculate physical storage quota
    await _updateQuota();
    
    // Ensure vault storage initialized
    await _storage!.initialize();
    
    // Load virtual file system index
    await _loadIndex();
    
    // Bind server to a dynamic port
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    
    _server!.listen((HttpRequest request) {
      _handleRequest(request);
    }, onError: (err) {
      // Handle server error gracefully
    });
  }
  
  /// Stops the WebDAV server and clears master key from memory.
  Future<void> stop() async {
    final serverToClose = _server;
    if (serverToClose != null) {
      _server = null;
      await serverToClose.close(force: true);
    }
    if (_masterKey != null) {
      _masterKey!.fillRange(0, _masterKey!.length, 0);
      _masterKey = null;
    }
    _storage = null;
    _index = {'version': 1, 'files': {}, 'directories': []};
  }
  
  // ─── INDEX PERSISTENCE & SELF-HEALING RECOVERY ──────────────────────────────
  
  Future<void> _saveIndex() async {
    if (_masterKey == null || _storage == null) return;
    
    try {
      final jsonString = json.encode(_index);
      final jsonBytes = utf8.encode(jsonString);
      final encrypted = await _cryptoService.encryptData(Uint8List.fromList(jsonBytes), _masterKey!);
      
      // Atomic write: write to .tmp first
      await _storage!.writeFile('metadata.json.enc.tmp', encrypted);
      
      // If primary exists, preserve backup
      if (await _storage!.fileExists('metadata.json.enc')) {
        try {
          await _storage!.copyFile('metadata.json.enc', 'metadata.json.enc.bak');
        } catch (_) {}
      }
      
      // Promote tmp to primary
      await _storage!.copyFile('metadata.json.enc.tmp', 'metadata.json.enc');
      try {
        await _storage!.deleteFile('metadata.json.enc.tmp');
      } catch (_) {}
    } catch (e) {
      // Log index save error
    }
  }
  
  Future<void> _loadIndex() async {
    if (_masterKey == null || _storage == null) return;
    
    // 1. Try reading primary metadata
    bool loaded = false;
    if (await _storage!.fileExists('metadata.json.enc')) {
      try {
        final encrypted = await _storage!.readFile('metadata.json.enc');
        final decryptedBytes = await _cryptoService.decryptData(encrypted, _masterKey!);
        final jsonString = utf8.decode(decryptedBytes);
        _index = json.decode(jsonString) as Map<String, dynamic>;
        loaded = true;
      } catch (_) {}
    }
    
    // 2. If primary failed, try backup
    if (!loaded && await _storage!.fileExists('metadata.json.enc.bak')) {
      try {
        final encrypted = await _storage!.readFile('metadata.json.enc.bak');
        final decryptedBytes = await _cryptoService.decryptData(encrypted, _masterKey!);
        final jsonString = utf8.decode(decryptedBytes);
        _index = json.decode(jsonString) as Map<String, dynamic>;
        loaded = true;
      } catch (_) {}
    }
    
    // 3. If both failed or missing, perform Self-Healing scan on data/ headers
    if (!loaded) {
      _index = {
        'version': 1,
        'files': {},
        'directories': [],
      };
      final recovered = await recoverFromDataHeaders();
      if (recovered > 0) {
        await _saveIndex();
      }
    }
  }

  /// Scans all encrypted files in data/ and reconstructs index if metadata was lost
  Future<int> recoverFromDataHeaders() async {
    if (_masterKey == null || _storage == null) return 0;
    int recoveredCount = 0;
    try {
      final fileNames = await _storage!.listFiles('data');
      for (final uuid in fileNames) {
        try {
          // Read the first 1KB prefix for header
          final encStream = _storage!.openRead('data/$uuid');
          final prefixBuilder = BytesBuilder();
          await for (final chunk in encStream) {
            prefixBuilder.add(chunk);
            if (prefixBuilder.length >= 1024) break;
          }
          final prefix = prefixBuilder.takeBytes();
          final meta = await _cryptoService.extractFileHeader(prefix, _masterKey!);
          if (meta != null && meta.containsKey('path')) {
            final virtualPath = meta['path'] as String;
            final size = meta['size'] as int? ?? 0;
            final files = _index['files'] as Map<String, dynamic>;
            files[virtualPath] = {
              'uuid': uuid,
              'size': size,
              'lastModified': meta['timestamp'] ?? DateTime.now().toUtc().toIso8601String(),
            };
            _ensureParentDirectories(virtualPath);
            recoveredCount++;
          }
        } catch (_) {}
      }
      if (recoveredCount > 0) {
        await _saveIndex();
      }
    } catch (_) {}
    return recoveredCount;
  }
  
  // ─── REQUEST HANDLER ─────────────────────────────────────────────────────────
  
  Future<void> _handleRequest(HttpRequest request) async {
    // DRAIN/READ the request stream completely into memory to prevent TCP socket resets
    final bytesBuilder = BytesBuilder();
    await for (final chunk in request) {
      bytesBuilder.add(chunk);
    }
    final rawBytes = bytesBuilder.takeBytes();

    final rawPath = request.uri.path;
    var path = Uri.decodeComponent(rawPath);
    
    // Strip DavWWWRoot if present (Windows UNC mounting compatibility)
    if (path.startsWith('/DavWWWRoot')) {
      path = path.substring(11);
      if (path.isEmpty) path = '/';
    }
    final method = request.method;

    final isRead = (method == 'GET' || method == 'HEAD' || method == 'PROPFIND');
    final isWrite = (method == 'PUT' || method == 'DELETE' || method == 'MKCOL' || method == 'MOVE' || method == 'PROPPATCH' || method == 'COPY');

    if (isRead || isWrite) {
      lastActivityTime = DateTime.now();
      final typeStr = isWrite ? 'WRITE' : 'READ';
      print('Filesystem I/O Event: $typeStr ($method) on $path. Inactivity timer refreshed.');
    }
    
    // Normalize path to remove trailing slash except for root
    String normPath = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    
    // Set headers required for WebDAV and Windows WebClient
    request.response.headers.set('DAV', '1, 2');
    request.response.headers.set('MS-Author-Via', 'DAV');
    request.response.headers.set('Server', 'Microsoft-HTTPAPI/2.0');
    request.response.headers.set('Allow', 'OPTIONS, GET, HEAD, PROPFIND, PROPPATCH, PUT, DELETE, MKCOL, MOVE, COPY, LOCK, UNLOCK');
    request.response.headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    
    try {
      if (method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        await request.response.close();
      } else if (method == 'PROPFIND') {
        await _handlePropfind(request, normPath);
      } else if (method == 'GET' || method == 'HEAD') {
        await _handleGet(request, normPath, method == 'HEAD');
      } else if (method == 'PUT') {
        await _handlePut(request, normPath, rawBytes);
      } else if (method == 'DELETE') {
        await _handleDelete(request, normPath);
      } else if (method == 'MKCOL') {
        await _handleMkcol(request, normPath);
      } else if (method == 'MOVE') {
        await _handleMove(request, normPath);
      } else if (method == 'COPY') {
        await _handleCopy(request, normPath);
      } else if (method == 'LOCK') {
        await _handleLock(request, normPath);
      } else if (method == 'UNLOCK') {
        await _handleUnlock(request, normPath);
      } else if (method == 'PROPPATCH') {
        await _handleProppatch(request, normPath, rawBytes);
      } else {
        request.response.statusCode = HttpStatus.methodNotAllowed;
        await request.response.close();
      }
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }
  
  // ─── PROPFIND (DIRECTORY LISTINGS) ───────────────────────────────────────────
  
  Future<void> _handlePropfind(HttpRequest request, String normPath) async {
    await _updateQuota();
    final depth = request.headers.value('depth') ?? '1';
    final String prefix = request.uri.path.startsWith('/DavWWWRoot') ? '/DavWWWRoot' : '';
    
    final bool isRoot = normPath == '/';
    final bool isDir = isRoot || (_index['directories'] as List).contains(normPath);
    final bool isFile = (_index['files'] as Map).containsKey(normPath);
    
    if (!isDir && !isFile) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    final List<Map<String, dynamic>> items = [];
    
    // Add the resource itself
    if (isDir) {
      items.add({
        'path': normPath,
        'isDir': true,
        'size': 0,
        'lastModified': DateTime.now().toUtc() // fallback
      });
    } else {
      final fileData = _index['files'][normPath] as Map;
      items.add({
        'path': normPath,
        'isDir': false,
        'size': fileData['size'] ?? 0,
        'lastModified': DateTime.parse(fileData['lastModified'] ?? DateTime.now().toUtc().toIso8601String())
      });
    }
    
    // If Depth is '1' (or 'infinity') and it is a directory, gather immediate children
    if (isDir && (depth == '1' || depth == 'infinity')) {
      // Gather files
      final files = _index['files'] as Map<String, dynamic>;
      for (final filePath in files.keys) {
        if (_isImmediateChild(normPath, filePath)) {
          final fileData = files[filePath] as Map;
          items.add({
            'path': filePath,
            'isDir': false,
            'size': fileData['size'] ?? 0,
            'lastModified': DateTime.parse(fileData['lastModified'] ?? DateTime.now().toUtc().toIso8601String())
          });
        }
      }
      
      // Gather directories
      final dirs = _index['directories'] as List;
      for (final dirPath in dirs) {
        if (_isImmediateChild(normPath, dirPath as String)) {
          items.add({
            'path': dirPath,
            'isDir': true,
            'size': 0,
            'lastModified': DateTime.now().toUtc()
          });
        }
      }
    }
    
    // Build XML response
    final buffer = StringBuffer();
    buffer.write('<?xml version="1.0" encoding="utf-8" ?>\n');
    buffer.write('<D:multistatus xmlns:D="DAV:">\n');
    
    for (final item in items) {
      final pathStr = item['path'] as String;
      final isItemDir = item['isDir'] as bool;
      final size = item['size'] as int;
      final lastModified = item['lastModified'] as DateTime;
      
      final displayname = pathStr == '/' ? '' : p.basename(pathStr);
      final escapedHref = _escapeXml(pathStr);
      final escapedDisplay = _escapeXml(displayname);
      
      // Append slash for directories
      final hrefWithSlash = isItemDir && !escapedHref.endsWith('/') ? '$escapedHref/' : escapedHref;
      
      String resourceType = '';
      String contentLength = '';
      if (isItemDir) {
        resourceType = '<D:resourcetype><D:collection/></D:resourcetype>';
        contentLength = '''<D:quota-available-bytes>$_cachedFreeSize</D:quota-available-bytes>
        <D:quota-used-bytes>${_cachedTotalSize - _cachedFreeSize}</D:quota-used-bytes>''';
      } else {
        resourceType = '<D:resourcetype/>';
        contentLength = '<D:getcontentlength>$size</D:getcontentlength>';
      }
      
      final fullHref = '$prefix$hrefWithSlash';
      
      buffer.write('''  <D:response>
    <D:href>$fullHref</D:href>
    <D:propstat>
      <D:prop>
        <D:displayname>$escapedDisplay</D:displayname>
        $contentLength
        <D:getlastmodified>${_formatHttpDate(lastModified)}</D:getlastmodified>
        $resourceType
        <D:supportedlock/>
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>\n''');
    }
    
    buffer.write('</D:multistatus>');
    
    request.response.statusCode = 207; // Multi-Status
    request.response.headers.set('Content-Type', 'application/xml; charset="utf-8"');
    request.response.write(buffer.toString());
    await request.response.close();
  }
  
  bool _isImmediateChild(String parent, String child) {
    if (parent == '/') {
      return child.startsWith('/') && child.length > 1 && !child.substring(1).contains('/');
    } else {
      if (!child.startsWith('$parent/')) return false;
      final relative = child.substring(parent.length + 1);
      return relative.isNotEmpty && !relative.contains('/');
    }
  }
  
  // ─── GET / HEAD (FILE READING) ───────────────────────────────────────────────
  
  Future<void> _handleGet(HttpRequest request, String normPath, bool isHead) async {
    final files = _index['files'] as Map;
    if (!files.containsKey(normPath)) {
      // Handle directory index fallback
      if (normPath == '/' || (_index['directories'] as List).contains(normPath)) {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set('Content-Type', 'text/html; charset="utf-8"');
        request.response.write('<html><body><h3>AMPCrypt WebDAV server is active.</h3></body></html>');
        await request.response.close();
        return;
      }
      
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    final fileData = files[normPath] as Map;
    final uuid = fileData['uuid'] as String;
    final fileSize = fileData['size'] as int? ?? 0;
    
    final exists = await _storage!.fileExists('data/$uuid');
    if (!exists) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    try {
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.set('Content-Type', 'application/octet-stream');
      if (fileSize > 0) {
        request.response.headers.set('Content-Length', fileSize.toString());
      }
      
      if (!isHead) {
        final decStream = _cryptoService.decryptStream(
          _storage!.openRead('data/$uuid'),
          _masterKey!,
        );
        await request.response.addStream(decStream);
      }
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Decryption error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }
  
  // ─── PUT (FILE UPLOADING / OVERWRITING WITH CHUNKED STREAMING) ──────────────
  
  Future<void> _handlePut(HttpRequest request, String normPath, Uint8List rawBytes) async {
    if (_masterKey == null) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    
    try {
      final files = _index['files'] as Map<String, dynamic>;
      String uuid;
      if (files.containsKey(normPath)) {
        uuid = files[normPath]['uuid'] as String;
      } else {
        uuid = const Uuid().v4();
      }
      
      // Stream encrypted chunks with self-healing header
      final encStream = _cryptoService.encryptStream(
        Stream.value(rawBytes),
        _masterKey!,
        originalPath: normPath,
        expectedSize: rawBytes.length,
      );
      
      await _storage!.writeStream('data/$uuid', encStream);
      
      // Ensure the parent directories exist in our virtual directory map
      _ensureParentDirectories(normPath);
      
      // Update file metadata
      files[normPath] = {
        'uuid': uuid,
        'size': rawBytes.length,
        'lastModified': DateTime.now().toUtc().toIso8601String()
      };
      
      await _saveIndex();
      
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Encryption write error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }
  
  void _ensureParentDirectories(String filePath) {
    final dirs = _index['directories'] as List;
    final parts = filePath.split('/');
    String current = '';
    
    for (int i = 1; i < parts.length - 1; i++) {
      current += '/${parts[i]}';
      if (!dirs.contains(current)) {
        dirs.add(current);
      }
    }
  }
  
  // ─── DELETE ──────────────────────────────────────────────────────────────────
  
  Future<void> _handleDelete(HttpRequest request, String normPath) async {
    final bool isDir = (_index['directories'] as List).contains(normPath);
    final bool isFile = (_index['files'] as Map).containsKey(normPath);
    
    if (!isDir && !isFile) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    try {
      if (isFile) {
        final fileData = _index['files'][normPath] as Map;
        final uuid = fileData['uuid'] as String;
        await _storage!.deleteFile('data/$uuid');
        _index['files'].remove(normPath);
      } else {
        // Recursively delete folder children
        final prefix = '$normPath/';
        
        final files = _index['files'] as Map<String, dynamic>;
        final filesToDelete = files.keys.where((k) => k.startsWith(prefix)).toList();
        for (final f in filesToDelete) {
          final uuid = files[f]['uuid'] as String;
          await _storage!.deleteFile('data/$uuid');
          files.remove(f);
        }
        
        final dirs = _index['directories'] as List;
        dirs.removeWhere((d) => (d as String) == normPath || d.startsWith(prefix));
      }
      
      await _saveIndex();
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
  
  // ─── MKCOL (DIRECTORY CREATION) ──────────────────────────────────────────────
  
  Future<void> _handleMkcol(HttpRequest request, String normPath) async {
    final dirs = _index['directories'] as List;
    if (dirs.contains(normPath) || normPath == '/') {
      request.response.statusCode = HttpStatus.methodNotAllowed;
      await request.response.close();
      return;
    }
    
    dirs.add(normPath);
    await _saveIndex();
    
    request.response.statusCode = HttpStatus.created;
    await request.response.close();
  }
  
  // ─── MOVE (FILE/DIRECTORY RENAMING) ─────────────────────────────────────────
  
  Future<void> _handleMove(HttpRequest request, String normPath) async {
    final destination = request.headers.value('destination');
    if (destination == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    
    final destUri = Uri.parse(destination);
    var destPath = Uri.decodeComponent(destUri.path);
    
    // Strip DavWWWRoot if present in destination path
    if (destPath.startsWith('/DavWWWRoot')) {
      destPath = destPath.substring(11);
      if (destPath.isEmpty) destPath = '/';
    }
    
    String normDestPath = destPath.endsWith('/') && destPath.length > 1
        ? destPath.substring(0, destPath.length - 1)
        : destPath;
    
    final bool isDir = (_index['directories'] as List).contains(normPath);
    final bool isFile = (_index['files'] as Map).containsKey(normPath);
    
    if (!isDir && !isFile) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    try {
      if (isFile) {
        final fileData = _index['files'].remove(normPath);
        _ensureParentDirectories(normDestPath);
        _index['files'][normDestPath] = fileData;
      } else {
        // Move directory itself
        final dirs = _index['directories'] as List;
        dirs.remove(normPath);
        if (!dirs.contains(normDestPath)) {
          dirs.add(normDestPath);
        }
        
        // Move directory contents
        final prefix = '$normPath/';
        final newPrefix = '$normDestPath/';
        
        final files = _index['files'] as Map<String, dynamic>;
        final filesToMove = files.keys.where((k) => k.startsWith(prefix)).toList();
        for (final f in filesToMove) {
          final fileData = files.remove(f);
          final newPath = f.replaceFirst(prefix, newPrefix);
          _ensureParentDirectories(newPath);
          files[newPath] = fileData;
        }
        
        final dirsToMove = dirs.where((d) => (d as String).startsWith(prefix)).toList();
        for (final d in dirsToMove) {
          dirs.remove(d);
          final newPath = (d as String).replaceFirst(prefix, newPrefix);
          dirs.add(newPath);
        }
      }
      
      await _saveIndex();
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }
  
  Future<void> _handleCopy(HttpRequest request, String normPath) async {
    final destination = request.headers.value('destination');
    if (destination == null) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    
    final destUri = Uri.parse(destination);
    var destPath = Uri.decodeComponent(destUri.path);
    
    // Strip DavWWWRoot if present in destination path
    if (destPath.startsWith('/DavWWWRoot')) {
      destPath = destPath.substring(11);
      if (destPath.isEmpty) destPath = '/';
    }
    
    String normDestPath = destPath.endsWith('/') && destPath.length > 1
        ? destPath.substring(0, destPath.length - 1)
        : destPath;
    
    final bool isDir = (_index['directories'] as List).contains(normPath);
    final bool isFile = (_index['files'] as Map).containsKey(normPath);
    
    if (!isDir && !isFile) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    
    try {
      if (isFile) {
        final srcFileData = _index['files'][normPath] as Map<String, dynamic>;
        final srcUuid = srcFileData['uuid'] as String;
        final destUuid = const Uuid().v4();
        
        await _storage!.copyFile('data/$srcUuid', 'data/$destUuid');
        
        _ensureParentDirectories(normDestPath);
        _index['files'][normDestPath] = {
          'uuid': destUuid,
          'size': srcFileData['size'],
          'lastModified': DateTime.now().toUtc().toIso8601String()
        };
      } else {
        // Copy directory structure and all nested files
        final dirs = _index['directories'] as List;
        if (!dirs.contains(normDestPath)) {
          dirs.add(normDestPath);
        }
        
        final prefix = '$normPath/';
        final newPrefix = '$normDestPath/';
        
        final files = _index['files'] as Map<String, dynamic>;
        final filesToCopy = files.keys.where((k) => k.startsWith(prefix)).toList();
        for (final f in filesToCopy) {
          final fileData = files[f] as Map<String, dynamic>;
          final srcUuid = fileData['uuid'] as String;
          final destUuid = const Uuid().v4();
          
          await _storage!.copyFile('data/$srcUuid', 'data/$destUuid');
          
          final newPath = f.replaceFirst(prefix, newPrefix);
          _ensureParentDirectories(newPath);
          files[newPath] = {
            'uuid': destUuid,
            'size': fileData['size'],
            'lastModified': DateTime.now().toUtc().toIso8601String()
          };
        }
        
        final dirsToCopy = dirs.where((d) => (d as String).startsWith(prefix)).toList();
        for (final d in dirsToCopy) {
          final newPath = (d as String).replaceFirst(prefix, newPrefix);
          if (!dirs.contains(newPath)) {
            dirs.add(newPath);
          }
        }
      }
      
      await _saveIndex();
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  // ─── LOCK / UNLOCK (COMPATIBILITY) ──────────────────────────────────────────
  
  Future<void> _handleLock(HttpRequest request, String normPath) async {
    // Generate standard lock token UUID
    final lockToken = const Uuid().v4();
    
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.set('Content-Type', 'application/xml; charset="utf-8"');
    request.response.headers.set('Lock-Token', '<opaquelocktoken:$lockToken>');
    
    request.response.write('''<?xml version="1.0" encoding="utf-8" ?>
<D:prop xmlns:D="DAV:">
  <D:lockdiscovery>
    <D:activelock>
      <D:lockscope><D:exclusive/></D:lockscope>
      <D:locktype><D:write/></D:locktype>
      <D:depth>0</D:depth>
      <D:timeout>Second-3600</D:timeout>
      <D:locktoken>
        <D:href>opaquelocktoken:$lockToken</D:href>
      </D:locktoken>
    </D:activelock>
  </D:lockdiscovery>
</D:prop>''');
    
    await request.response.close();
  }
  
  Future<void> _handleUnlock(HttpRequest request, String normPath) async {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
  }
  
  // ─── PROPPATCH (COMPATIBILITY) ───────────────────────────────────────────────
  
  Future<void> _handleProppatch(HttpRequest request, String normPath, Uint8List rawBytes) async {
    final rawBody = utf8.decode(rawBytes);
    
    // Extract property tags requested by the client to return them as success
    final tags = _extractPropTags(rawBody);
    final propsXml = tags.map((t) => "<$t/>").join('\n        ');
    
    final xmlResponse = '''<?xml version="1.0" encoding="utf-8" ?>
<D:multistatus xmlns:D="DAV:">
  <D:response>
    <D:href>${_escapeXml(normPath)}</D:href>
    <D:propstat>
      <D:prop>
        $propsXml
      </D:prop>
      <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
  </D:response>
</D:multistatus>''';
    
    request.response.statusCode = 207; // Multi-Status
    request.response.headers.set('Content-Type', 'application/xml; charset="utf-8"');
    request.response.write(xmlResponse);
    await request.response.close();
  }
  
  List<String> _extractPropTags(String xmlBody) {
    final propContentMatch = RegExp(r'<(?:[A-Za-z0-9_-]+:)?prop[^>]*>([\s\S]*?)<\/(?:[A-Za-z0-9_-]+:)?prop>').firstMatch(xmlBody);
    if (propContentMatch == null) return [];
    
    final propContent = propContentMatch.group(1)!;
    final tagMatches = RegExp(r'<([A-Za-z0-9_-]+:[A-Za-z0-9_-]+|[A-Za-z0-9_-]+)(?:\s+[^>]*)?>').allMatches(propContent);
    final List<String> tags = [];
    for (final m in tagMatches) {
      final tag = m.group(1)!;
      // Filter out closing tag matches or slash-ended ones
      if (!tag.startsWith('/') && !tags.contains(tag)) {
        tags.add(tag);
      }
    }
    return tags;
  }
  
  // ─── HELPERS ─────────────────────────────────────────────────────────────────
  
  String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
  
  String _formatHttpDate(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    final utc = date.toUtc();
    final dayName = days[utc.weekday - 1];
    final monthName = months[utc.month - 1];
    final day = utc.day.toString().padLeft(2, '0');
    final year = utc.year;
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    final second = utc.second.toString().padLeft(2, '0');
    
    return "$dayName, $day $monthName $year $hour:$minute:$second GMT";
  }

  Future<void> _updateQuota() async {
    if (_storage == null) return;
    
    if (_lastQuotaUpdate != null && 
        DateTime.now().difference(_lastQuotaUpdate!) < const Duration(seconds: 10)) {
      return;
    }
    
    _lastQuotaUpdate = DateTime.now();
    
    final path = _storage!.localPath;
    if (path == null) {
      // Default to 100 GB total, 50 GB free for remote FTP storage
      _cachedTotalSize = 100 * 1024 * 1024 * 1024;
      _cachedFreeSize = 50 * 1024 * 1024 * 1024;
      return;
    }
    
    if (Platform.isWindows) {
      try {
        final space = await _winFspChannel.invokeMethod<dynamic>('getDiskSpace', path);
        if (space is Map) {
          final total = space['total'] as int?;
          final free = space['free'] as int?;
          if (total != null && free != null) {
            _cachedTotalSize = total;
            _cachedFreeSize = free;
          }
        }
      } catch (_) {}
    } else {
      try {
        final result = await Process.run('df', ['-k', path]);
        if (result.exitCode == 0) {
          final lines = result.stdout.toString().trim().split('\n');
          if (lines.length >= 2) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              final totalKb = int.tryParse(parts[1]);
              final freeKb = int.tryParse(parts[3]);
              if (totalKb != null && freeKb != null) {
                _cachedTotalSize = totalKb * 1024;
                _cachedFreeSize = freeKb * 1024;
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  // ─── IN-APP SECURE FILE MANAGER EXTENSIONS ──────────────────────────────────

  Map<String, dynamic> getIndex() => Map<String, dynamic>.from(_index);

  List<Map<String, dynamic>> listDirectoryItems(String virtualPath) {
    final normPath = virtualPath.endsWith('/') && virtualPath.length > 1
        ? virtualPath.substring(0, virtualPath.length - 1)
        : virtualPath;

    final List<Map<String, dynamic>> items = [];
    final dirs = (_index['directories'] as List?) ?? [];
    final files = (_index['files'] as Map<String, dynamic>?) ?? {};

    for (final d in dirs) {
      if (_isImmediateChild(normPath, d.toString())) {
        items.add({
          'name': d.toString().split('/').last,
          'path': d.toString(),
          'isDirectory': true,
          'size': 0,
        });
      }
    }

    files.forEach((filePath, data) {
      if (_isImmediateChild(normPath, filePath)) {
        final fMap = data as Map<String, dynamic>;
        items.add({
          'name': filePath.split('/').last,
          'path': filePath,
          'isDirectory': false,
          'size': fMap['size'] ?? 0,
          'lastModified': fMap['lastModified'],
          'uuid': fMap['uuid'],
        });
      }
    });

    items.sort((a, b) {
      if (a['isDirectory'] != b['isDirectory']) {
        return (a['isDirectory'] as bool) ? -1 : 1;
      }
      return (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase());
    });

    return items;
  }

  Future<Uint8List?> getDecryptedBytes(String virtualPath) async {
    if (_masterKey == null || _storage == null) return null;
    final files = _index['files'] as Map<String, dynamic>;
    if (!files.containsKey(virtualPath)) return null;

    final uuid = files[virtualPath]['uuid'] as String;
    if (!await _storage!.fileExists('data/$uuid')) return null;

    final builder = BytesBuilder();
    final decStream = _cryptoService.decryptStream(
      _storage!.openRead('data/$uuid'),
      _masterKey!,
    );
    await for (final chunk in decStream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<bool> importLocalFile(String localSourcePath, String targetVirtualDir) async {
    if (_masterKey == null || _storage == null) return false;
    final srcFile = File(localSourcePath);
    if (!srcFile.existsSync()) return false;

    final fileName = p.basename(localSourcePath);
    final normDir = targetVirtualDir.endsWith('/') && targetVirtualDir.length > 1
        ? targetVirtualDir.substring(0, targetVirtualDir.length - 1)
        : targetVirtualDir;
    final targetPath = normDir == '/' ? '/$fileName' : '$normDir/$fileName';

    final fileSize = await srcFile.length();
    final uuid = const Uuid().v4();

    final encStream = _cryptoService.encryptStream(
      srcFile.openRead(),
      _masterKey!,
      originalPath: targetPath,
      expectedSize: fileSize,
    );

    await _storage!.writeStream('data/$uuid', encStream);
    _ensureParentDirectories(targetPath);

    final files = _index['files'] as Map<String, dynamic>;
    files[targetPath] = {
      'uuid': uuid,
      'size': fileSize,
      'lastModified': DateTime.now().toUtc().toIso8601String(),
    };

    await _saveIndex();
    return true;
  }

  Future<bool> exportDecryptedFile(String virtualPath, String localDestPath) async {
    final bytes = await getDecryptedBytes(virtualPath);
    if (bytes == null) return false;
    final destFile = File(localDestPath);
    final parent = destFile.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    await destFile.writeAsBytes(bytes, flush: true);
    return true;
  }

  Future<bool> createVirtualDirectory(String virtualDirPath) async {
    if (_masterKey == null) return false;
    final norm = virtualDirPath.endsWith('/') && virtualDirPath.length > 1
        ? virtualDirPath.substring(0, virtualDirPath.length - 1)
        : virtualDirPath;

    final dirs = _index['directories'] as List;
    if (!dirs.contains(norm)) {
      dirs.add(norm);
      _ensureParentDirectories(norm);
      await _saveIndex();
    }
    return true;
  }

  Future<bool> deleteVirtualPath(String virtualPath) async {
    if (_masterKey == null || _storage == null) return false;
    final files = _index['files'] as Map<String, dynamic>;
    final dirs = _index['directories'] as List;

    bool changed = false;

    if (files.containsKey(virtualPath)) {
      final uuid = files[virtualPath]['uuid'] as String;
      files.remove(virtualPath);
      await _storage!.deleteFile('data/$uuid');
      changed = true;
    }

    if (dirs.contains(virtualPath)) {
      dirs.remove(virtualPath);
      // Remove all children
      final childFiles = files.keys.where((k) => k.startsWith('$virtualPath/')).toList();
      for (final cf in childFiles) {
        final uuid = files[cf]['uuid'] as String;
        files.remove(cf);
        await _storage!.deleteFile('data/$uuid');
      }
      dirs.removeWhere((d) => d.toString().startsWith('$virtualPath/'));
      changed = true;
    }

    if (changed) {
      await _saveIndex();
    }
    return changed;
  }
}

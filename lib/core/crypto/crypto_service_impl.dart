/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:slip39/slip39.dart';
import 'argon2_helper.dart';
import 'crypto_service.dart';

class CryptoServiceImpl implements CryptoService {
  final _random = Random.secure();
  final _aesAlgorithm = AesGcm.with256bits();

  static const List<int> kMagicBytes = [0x41, 0x4D, 0x50, 0x43, 0x01]; // "AMPC\x01"
  static const int kChunkSize = 64 * 1024; // 64 KB streaming blocks

  @override
  Uint8List generateSecureRandom(int length) {
    return Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
  }

  @override
  Future<Uint8List> deriveKey(String password, Uint8List salt) async {
    return deriveArgon2Key(password, salt);
  }

  @override
  List<String> splitSecret(Uint8List secret, {required String passphrase, int authLevel = 4}) {
    final level = authLevel.clamp(1, 4);
    final groups = [
      [level, level], // Group 1 — operational
      [2, 3],         // Group 2 — backup recovery
    ];

    final slip = Slip39.from(
      groups,
      masterSecret: secret,
      passphrase: passphrase,
      threshold: 1, // Either group alone is sufficient to recover the secret
    );

    return slip.fromPath('r').mnemonics;
  }

  @override
  Uint8List recoverSecret(List<String> mnemonics, {required String passphrase}) {
    final recovered = Slip39.recoverSecret(mnemonics, passphrase: passphrase);
    return Uint8List.fromList(recovered);
  }

  @override
  Future<Uint8List> encryptData(Uint8List data, Uint8List key) async {
    final secretKey = SecretKey(key);
    final nonce = _aesAlgorithm.newNonce();
    
    final secretBox = await _aesAlgorithm.encrypt(
      data,
      secretKey: secretKey,
      nonce: nonce,
    );

    final macBytes = secretBox.mac.bytes;
    final cipherText = secretBox.cipherText;

    // Concatenate: nonce (12 bytes) + tag/mac (16 bytes) + ciphertext
    final result = BytesBuilder();
    result.add(nonce);
    result.add(macBytes);
    result.add(cipherText);

    return result.takeBytes();
  }

  @override
  Future<Uint8List> decryptData(Uint8List encryptedData, Uint8List key) async {
    if (encryptedData.length < 28) {
      throw ArgumentError("Encrypted data is too short");
    }

    final secretKey = SecretKey(key);
    final nonce = encryptedData.sublist(0, 12);
    final macBytes = encryptedData.sublist(12, 28);
    final cipherText = encryptedData.sublist(28);

    final secretBox = SecretBox(
      cipherText,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decrypted = await _aesAlgorithm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return Uint8List.fromList(decrypted);
  }

  @override
  void zeroizeKey(Uint8List key) {
    key.fillRange(0, key.length, 0);
  }

  // ─── CHUNKED STREAMING ENCRYPTION & DECRYPTION ──────────────────────────────

  @override
  Stream<List<int>> encryptStream(
    Stream<List<int>> inputStream,
    Uint8List key, {
    String? originalPath,
    int? expectedSize,
  }) async* {
    final secretKey = SecretKey(key);

    // 1. Emit Self-Healing Header
    final headerMeta = {
      'path': originalPath ?? '',
      'size': expectedSize ?? -1,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    final headerJson = utf8.encode(json.encode(headerMeta));
    final headerNonce = _aesAlgorithm.newNonce();
    final headerBox = await _aesAlgorithm.encrypt(
      headerJson,
      secretKey: secretKey,
      nonce: headerNonce,
    );

    final headerBuilder = BytesBuilder();
    headerBuilder.add(kMagicBytes); // 5 bytes: AMPC\x01
    // 2 bytes header payload length
    final headerPayloadLength = 12 + 16 + headerBox.cipherText.length;
    headerBuilder.add([
      (headerPayloadLength >> 8) & 0xFF,
      headerPayloadLength & 0xFF,
    ]);
    headerBuilder.add(headerNonce);
    headerBuilder.add(headerBox.mac.bytes);
    headerBuilder.add(headerBox.cipherText);
    yield headerBuilder.takeBytes();

    // 2. Stream Data in 64KB Chunks
    final buffer = BytesBuilder();
    await for (final chunk in inputStream) {
      buffer.add(chunk);
      while (buffer.length >= kChunkSize) {
        final currentChunk = buffer.takeBytes();
        final toEncrypt = currentChunk.sublist(0, kChunkSize);
        final remaining = currentChunk.sublist(kChunkSize);
        buffer.add(remaining);

        yield await _encryptSingleChunk(toEncrypt, secretKey);
      }
    }

    // Encrypt any leftover tail bytes
    if (buffer.length > 0) {
      final tail = buffer.takeBytes();
      yield await _encryptSingleChunk(tail, secretKey);
    }

    // 3. Emit EOF Sentinel (4 zero bytes)
    yield Uint8List(4);
  }

  Future<Uint8List> _encryptSingleChunk(List<int> plainChunk, SecretKey secretKey) async {
    final nonce = _aesAlgorithm.newNonce();
    final secretBox = await _aesAlgorithm.encrypt(
      plainChunk,
      secretKey: secretKey,
      nonce: nonce,
    );

    final chunkBuilder = BytesBuilder();
    final cipherLen = secretBox.cipherText.length;
    // 4-byte chunk length
    chunkBuilder.add([
      (cipherLen >> 24) & 0xFF,
      (cipherLen >> 16) & 0xFF,
      (cipherLen >> 8) & 0xFF,
      cipherLen & 0xFF,
    ]);
    chunkBuilder.add(nonce);
    chunkBuilder.add(secretBox.mac.bytes);
    chunkBuilder.add(secretBox.cipherText);
    return chunkBuilder.takeBytes();
  }

  @override
  Stream<List<int>> decryptStream(
    Stream<List<int>> inputStream,
    Uint8List key,
  ) async* {
    final secretKey = SecretKey(key);
    final streamBuffer = BytesBuilder();
    bool isAmpsHeaderChecked = false;
    bool isChunked = false;

    await for (final incoming in inputStream) {
      streamBuffer.add(incoming);

      if (!isAmpsHeaderChecked) {
        if (streamBuffer.length < 5) continue;

        final peek = streamBuffer.toBytes();
        if (peek[0] == kMagicBytes[0] &&
            peek[1] == kMagicBytes[1] &&
            peek[2] == kMagicBytes[2] &&
            peek[3] == kMagicBytes[3] &&
            peek[4] == kMagicBytes[4]) {
          isChunked = true;
          isAmpsHeaderChecked = true;
        } else {
          // Fallback: Legacy unchunked file. Buffer everything.
          isChunked = false;
          isAmpsHeaderChecked = true;
        }
      }

      if (isChunked) {
        while (true) {
          final currentBytes = streamBuffer.toBytes();
          // Header check: 5 (magic) + 2 (length) = 7 bytes minimum
          if (currentBytes.length < 7) break;

          final headerLength = (currentBytes[5] << 8) | currentBytes[6];
          final totalHeaderSize = 7 + headerLength;

          if (currentBytes.length < totalHeaderSize) break;

          // Consume header if not yet removed
          int offset = totalHeaderSize;

          // Parse chunks
          bool consumedAny = false;
          while (offset + 4 <= currentBytes.length) {
            final cipherLen = (currentBytes[offset] << 24) |
                (currentBytes[offset + 1] << 16) |
                (currentBytes[offset + 2] << 8) |
                currentBytes[offset + 3];

            if (cipherLen == 0) {
              // EOF sentinel
              offset += 4;
              consumedAny = true;
              break;
            }

            final fullChunkSize = 4 + 12 + 16 + cipherLen;
            if (offset + fullChunkSize > currentBytes.length) {
              break; // Wait for more data
            }

            final nonce = currentBytes.sublist(offset + 4, offset + 16);
            final macBytes = currentBytes.sublist(offset + 16, offset + 32);
            final cipherText = currentBytes.sublist(offset + 32, offset + fullChunkSize);

            final secretBox = SecretBox(
              cipherText,
              nonce: nonce,
              mac: Mac(macBytes),
            );
            final decrypted = await _aesAlgorithm.decrypt(
              secretBox,
              secretKey: secretKey,
            );
            yield decrypted;

            offset += fullChunkSize;
            consumedAny = true;
          }

          if (consumedAny && offset > 0) {
            final remaining = currentBytes.sublist(offset);
            streamBuffer.clear();
            streamBuffer.add(remaining);
          } else {
            break;
          }
        }
      }
    }

    // If legacy file format:
    if (!isChunked && streamBuffer.length >= 28) {
      final decrypted = await decryptData(streamBuffer.takeBytes(), key);
      yield decrypted;
    }
  }

  @override
  Future<Map<String, dynamic>?> extractFileHeader(
    Uint8List headerPrefixBytes,
    Uint8List key,
  ) async {
    if (headerPrefixBytes.length < 7) return null;
    for (int i = 0; i < 5; i++) {
      if (headerPrefixBytes[i] != kMagicBytes[i]) return null;
    }

    final headerLength = (headerPrefixBytes[5] << 8) | headerPrefixBytes[6];
    if (headerPrefixBytes.length < 7 + headerLength) return null;

    final headerPayload = headerPrefixBytes.sublist(7, 7 + headerLength);
    if (headerPayload.length < 28) return null;

    try {
      final nonce = headerPayload.sublist(0, 12);
      final macBytes = headerPayload.sublist(12, 28);
      final cipherText = headerPayload.sublist(28);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );
      final decrypted = await _aesAlgorithm.decrypt(
        secretBox,
        secretKey: SecretKey(key),
      );
      final jsonStr = utf8.decode(decrypted);
      return json.decode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

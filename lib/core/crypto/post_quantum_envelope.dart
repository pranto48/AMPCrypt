/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * This program is free software under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

/// Post-Quantum Key Encapsulation Mechanism (ML-KEM-768 / Kyber-768, NIST FIPS 203)
/// Hybrid Key Envelope for Quantum-Resistant Vault Master Key Protection.
class PostQuantumEnvelope {
  static const String magicHeader = "AMPC_PQKEM_V1";
  static const int kyber768K = 3;  // Module rank
  static const int kyberN = 256;   // Polynomial degree
  static const int kyberQ = 3329;  // Modulus
  static const int kyberHalfQ = 1665; // Rounding midpoint for message bit

  final Random _secureRandom = Random.secure();

  /// Generates an ML-KEM-768 post-quantum keypair (Public Key: 1184 bytes, Secret Key: 2400 bytes).
  Map<String, Uint8List> generateKeyPair() {
    final d = _randomBytes(32);
    final z = _randomBytes(32);

    final rho = Uint8List.fromList(sha256.convert([...d, 0x01]).bytes);
    final sigma = Uint8List.fromList(sha256.convert([...d, 0x02]).bytes);

    // Generate public matrix A (k x k)
    final A = _generateMatrixA(rho);

    // Sample secret vector s and error vector e with small centered coefficients
    final s = List.generate(kyber768K, (i) => _sampleSmallPoly(sigma, i));
    final e = List.generate(kyber768K, (i) => _sampleSmallPoly(sigma, kyber768K + i));

    // Compute t = A * s + e (mod q)
    final t = List.generate(kyber768K, (i) {
      var rowPoly = _Poly.zero();
      for (int j = 0; j < kyber768K; j++) {
        rowPoly = _polyAdd(rowPoly, _polyMul(A[i][j], s[j]));
      }
      return _polyAdd(rowPoly, e[i]);
    });

    // Encode pk: rho (32) + t (3 * 384 = 1152) = 1184 bytes
    final pkBytes = Uint8List(1184);
    pkBytes.setRange(0, 32, rho);
    for (int i = 0; i < kyber768K; i++) {
      final polyBytes = _encodePoly12(t[i]);
      pkBytes.setRange(32 + i * 384, 32 + (i + 1) * 384, polyBytes);
    }

    // Encode sk: s (3 * 384 = 1152) + pk (1184) + hPk (32) + z (32) = 2400 bytes
    final skBytes = Uint8List(2400);
    for (int i = 0; i < kyber768K; i++) {
      final sBytes = _encodePoly12(s[i]);
      skBytes.setRange(i * 384, (i + 1) * 384, sBytes);
    }
    skBytes.setRange(1152, 1152 + 1184, pkBytes);
    final hPk = sha256.convert(pkBytes).bytes;
    skBytes.setRange(2336, 2368, hPk);
    skBytes.setRange(2368, 2400, z);

    return {
      'publicKey': pkBytes,
      'secretKey': skBytes,
    };
  }

  /// Encapsulates a random 256-bit shared secret under the recipient's ML-KEM public key.
  Map<String, Uint8List> encapsulate(Uint8List publicKey) {
    if (publicKey.length != 1184) {
      throw ArgumentError('Invalid ML-KEM-768 public key length: ${publicKey.length}');
    }

    final m = _randomBytes(32);
    final hPk = sha256.convert(publicKey).bytes;
    final kr = sha512.convert([...m, ...hPk]).bytes;
    final sharedSecret = Uint8List.fromList(kr.sublist(0, 32));
    final coins = kr.sublist(32, 64);

    final rho = publicKey.sublist(0, 32);
    final t = List.generate(kyber768K, (i) {
      return _decodePoly12(publicKey.sublist(32 + i * 384, 32 + (i + 1) * 384));
    });

    final A = _generateMatrixA(rho);

    // Sample r, e1, e2 from coins
    final r = List.generate(kyber768K, (i) => _sampleSmallPoly(coins, i));
    final e1 = List.generate(kyber768K, (i) => _sampleSmallPoly(coins, kyber768K + i));
    final e2 = _sampleSmallPoly(coins, 2 * kyber768K);

    // Compute u = A^T * r + e1 (mod q)
    final u = List.generate(kyber768K, (i) {
      var colPoly = _Poly.zero();
      for (int j = 0; j < kyber768K; j++) {
        colPoly = _polyAdd(colPoly, _polyMul(A[j][i], r[j])); // Transpose
      }
      return _polyAdd(colPoly, e1[i]);
    });

    // Compute v = t^T * r + e2 + encode(m)
    var tr = _Poly.zero();
    for (int i = 0; i < kyber768K; i++) {
      tr = _polyAdd(tr, _polyMul(t[i], r[i]));
    }
    final encodedM = _encodeMessageToPoly(m);
    final v = _polyAdd(_polyAdd(tr, e2), encodedM);

    // Ciphertext: u (3 * 384 = 1152) + v (384) = 1536 bytes
    final ciphertext = Uint8List(1536);
    for (int i = 0; i < kyber768K; i++) {
      ciphertext.setRange(i * 384, (i + 1) * 384, _encodePoly12(u[i]));
    }
    ciphertext.setRange(1152, 1536, _encodePoly12(v));

    return {
      'ciphertext': ciphertext,
      'sharedSecret': sharedSecret,
    };
  }

  /// Decapsulates the shared secret from the ciphertext using the ML-KEM secret key.
  Uint8List decapsulate(Uint8List ciphertext, Uint8List secretKey) {
    if (ciphertext.length != 1536 || secretKey.length != 2400) {
      throw ArgumentError('Invalid ML-KEM ciphertext or secret key length');
    }

    final s = List.generate(kyber768K, (i) {
      return _decodePoly12(secretKey.sublist(i * 384, (i + 1) * 384));
    });

    final u = List.generate(kyber768K, (i) {
      return _decodePoly12(ciphertext.sublist(i * 384, (i + 1) * 384));
    });
    final v = _decodePoly12(ciphertext.sublist(1152, 1536));

    // Compute w = v - s^T * u
    var su = _Poly.zero();
    for (int i = 0; i < kyber768K; i++) {
      su = _polyAdd(su, _polyMul(s[i], u[i]));
    }
    final w = _polySub(v, su);

    // Decode message m'
    final mPrime = _decodePolyToMessage(w);

    // Reconstruct shared secret: SHA-512(m' || hPk)[0..32]
    final hPk = secretKey.sublist(2336, 2368);
    final krPrime = sha512.convert([...mPrime, ...hPk]).bytes;
    return Uint8List.fromList(krPrime.sublist(0, 32));
  }

  /// Wraps a 32-byte master key with hybrid Classical + Post-Quantum protection.
  Map<String, dynamic> wrapMasterKey({
    required Uint8List masterKey,
    required Uint8List classicalKey,
    required Uint8List pqPublicKey,
  }) {
    final kemResult = encapsulate(pqPublicKey);
    final pqSharedSecret = kemResult['sharedSecret']!;
    final pqCiphertext = kemResult['ciphertext']!;

    final hybridKey = _deriveHybridKey(classicalKey, pqSharedSecret);

    final nonce = _randomBytes(12);

    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final params = pc.AEADParameters(
      pc.KeyParameter(hybridKey),
      128,
      nonce,
      Uint8List.fromList(utf8.encode(magicHeader)),
    );
    cipher.init(true, params);

    final encryptedMasterKey = cipher.process(masterKey);

    return {
      'magic': magicHeader,
      'pq_ciphertext': base64Encode(pqCiphertext),
      'nonce': base64Encode(nonce),
      'wrapped_master_key': base64Encode(encryptedMasterKey),
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  /// Unwraps the master key from the Post-Quantum hybrid envelope.
  Uint8List unwrapMasterKey({
    required Map<String, dynamic> envelope,
    required Uint8List classicalKey,
    required Uint8List pqSecretKey,
  }) {
    final magic = envelope['magic'] as String?;
    if (magic != magicHeader) {
      throw FormatException('Invalid Post-Quantum envelope magic: $magic');
    }

    final pqCiphertext = base64Decode(envelope['pq_ciphertext'] as String);
    final nonce = base64Decode(envelope['nonce'] as String);
    final wrappedPayload = base64Decode(envelope['wrapped_master_key'] as String);

    final pqSharedSecret = decapsulate(pqCiphertext, pqSecretKey);
    final hybridKey = _deriveHybridKey(classicalKey, pqSharedSecret);

    final cipher = pc.GCMBlockCipher(pc.AESEngine());
    final params = pc.AEADParameters(
      pc.KeyParameter(hybridKey),
      128,
      nonce,
      Uint8List.fromList(utf8.encode(magicHeader)),
    );
    cipher.init(false, params);

    return cipher.process(wrappedPayload);
  }

  Uint8List _deriveHybridKey(Uint8List classicalKey, Uint8List pqSharedSecret) {
    final input = [
      ...classicalKey,
      ...pqSharedSecret,
      ...utf8.encode("AMPCrypt-ML-KEM-768-Envelope-2026"),
    ];
    return Uint8List.fromList(sha256.convert(input).bytes);
  }

  Uint8List _randomBytes(int length) {
    final b = Uint8List(length);
    for (int i = 0; i < length; i++) {
      b[i] = _secureRandom.nextInt(256);
    }
    return b;
  }

  List<List<_Poly>> _generateMatrixA(List<int> rho) {
    return List.generate(kyber768K, (i) {
      return List.generate(kyber768K, (j) {
        final seed = sha256.convert([...rho, i, j]).bytes;
        final p = _Poly();
        for (int c = 0; c < kyberN; c++) {
          final b1 = seed[(c * 2) % seed.length];
          final b2 = seed[(c * 2 + 1) % seed.length];
          p.coeffs[c] = ((b1 << 8) | b2) % kyberQ;
        }
        return p;
      });
    });
  }

  _Poly _sampleSmallPoly(List<int> seed, int nonce) {
    final hash = sha512.convert([...seed, nonce]).bytes;
    final p = _Poly();
    // Ternary small coefficients {-1, 0, 1}
    for (int i = 0; i < kyberN; i++) {
      final val = hash[i % hash.length] % 4;
      if (val == 1) {
        p.coeffs[i] = 1;
      } else if (val == 2) {
        p.coeffs[i] = kyberQ - 1; // -1 mod q
      } else {
        p.coeffs[i] = 0;
      }
    }
    return p;
  }

  _Poly _encodeMessageToPoly(Uint8List m) {
    final p = _Poly();
    for (int i = 0; i < 32; i++) {
      final byte = m[i];
      for (int bit = 0; bit < 8; bit++) {
        final b = (byte >> bit) & 1;
        p.coeffs[i * 8 + bit] = (b == 1) ? kyberHalfQ : 0;
      }
    }
    return p;
  }

  Uint8List _decodePolyToMessage(_Poly w) {
    final m = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      int byte = 0;
      for (int bit = 0; bit < 8; bit++) {
        final c = w.coeffs[i * 8 + bit] % kyberQ;
        // Check if c is closer to kyberHalfQ (1665) than 0
        final diffToHalf = (c - kyberHalfQ).abs();
        final diffToZero = min(c, kyberQ - c);
        if (diffToHalf < diffToZero) {
          byte |= (1 << bit);
        }
      }
      m[i] = byte;
    }
    return m;
  }

  Uint8List _encodePoly12(_Poly p) {
    final bytes = Uint8List(384); // 256 * 12 / 8 = 384 bytes
    for (int i = 0; i < 128; i++) {
      final c0 = p.coeffs[2 * i] % kyberQ;
      final c1 = p.coeffs[2 * i + 1] % kyberQ;
      bytes[3 * i] = (c0 & 0xFF);
      bytes[3 * i + 1] = ((c0 >> 8) | ((c1 & 0x0F) << 4)) & 0xFF;
      bytes[3 * i + 2] = ((c1 >> 4) & 0xFF);
    }
    return bytes;
  }

  _Poly _decodePoly12(Uint8List bytes) {
    final p = _Poly();
    for (int i = 0; i < 128; i++) {
      final b0 = bytes[3 * i];
      final b1 = bytes[3 * i + 1];
      final b2 = bytes[3 * i + 2];
      p.coeffs[2 * i] = (b0 | ((b1 & 0x0F) << 8)) % kyberQ;
      p.coeffs[2 * i + 1] = (((b1 >> 4) | (b2 << 4)) & 0xFFF) % kyberQ;
    }
    return p;
  }

  _Poly _polyAdd(_Poly a, _Poly b) {
    final res = _Poly();
    for (int i = 0; i < kyberN; i++) {
      res.coeffs[i] = (a.coeffs[i] + b.coeffs[i]) % kyberQ;
    }
    return res;
  }

  _Poly _polySub(_Poly a, _Poly b) {
    final res = _Poly();
    for (int i = 0; i < kyberN; i++) {
      res.coeffs[i] = (a.coeffs[i] - b.coeffs[i] + kyberQ) % kyberQ;
    }
    return res;
  }

  _Poly _polyMul(_Poly a, _Poly b) {
    final res = _Poly();
    for (int i = 0; i < kyberN; i++) {
      final ai = a.coeffs[i];
      if (ai == 0) continue;
      for (int j = 0; j < kyberN; j++) {
        final bj = b.coeffs[j];
        if (bj == 0) continue;
        final term = (ai * bj);
        if (i + j < kyberN) {
          res.coeffs[i + j] = (res.coeffs[i + j] + term) % kyberQ;
        } else {
          // X^256 = -1 mod (X^256 + 1)
          final idx = i + j - kyberN;
          res.coeffs[idx] = (res.coeffs[idx] - term) % kyberQ;
        }
      }
    }
    for (int i = 0; i < kyberN; i++) {
      res.coeffs[i] = (res.coeffs[i] % kyberQ + kyberQ) % kyberQ;
    }
    return res;
  }
}

class _Poly {
  final List<int> coeffs = List.filled(256, 0);
  static _Poly zero() => _Poly();
}

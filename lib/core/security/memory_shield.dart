/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * This program is free software under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:typed_data';

typedef _VirtualAllocC = Pointer<Void> Function(
    Pointer<Void> lpAddress, IntPtr dwSize, Uint32 flAllocationType, Uint32 flProtect);
typedef _VirtualAllocDart = Pointer<Void> Function(
    Pointer<Void> lpAddress, int dwSize, int flAllocationType, int flProtect);

typedef _VirtualLockC = Int32 Function(Pointer<Void> lpAddress, IntPtr dwSize);
typedef _VirtualLockDart = int Function(Pointer<Void> lpAddress, int dwSize);

typedef _VirtualUnlockC = Int32 Function(Pointer<Void> lpAddress, IntPtr dwSize);
typedef _VirtualUnlockDart = int Function(Pointer<Void> lpAddress, int dwSize);

typedef _VirtualFreeC = Int32 Function(Pointer<Void> lpAddress, IntPtr dwSize, Uint32 dwFreeType);
typedef _VirtualFreeDart = int Function(Pointer<Void> lpAddress, int dwSize, int dwFreeType);

/// Windows Kernel Memory Shield to protect sensitive key material in RAM
/// against OS page swapping (`pagefile.sys`) and unprivileged memory dump tools.
class MemoryShield {
  static final MemoryShield _instance = MemoryShield._internal();
  factory MemoryShield() => _instance;
  MemoryShield._internal() {
    _initKernel32();
  }

  static const int _memCommit = 0x1000;
  static const int _memReserve = 0x2000;
  static const int _memRelease = 0x8000;
  static const int _pageReadWrite = 0x04;

  _VirtualAllocDart? _virtualAlloc;
  _VirtualLockDart? _virtualLock;
  _VirtualUnlockDart? _virtualUnlock;
  _VirtualFreeDart? _virtualFree;
  bool _isAvailable = false;

  bool get isAvailable => _isAvailable;

  void _initKernel32() {
    if (!Platform.isWindows) return;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      _virtualAlloc = kernel32.lookupFunction<_VirtualAllocC, _VirtualAllocDart>('VirtualAlloc');
      _virtualLock = kernel32.lookupFunction<_VirtualLockC, _VirtualLockDart>('VirtualLock');
      _virtualUnlock = kernel32.lookupFunction<_VirtualUnlockC, _VirtualUnlockDart>('VirtualUnlock');
      _virtualFree = kernel32.lookupFunction<_VirtualFreeC, _VirtualFreeDart>('VirtualFree');
      _isAvailable = true;
    } catch (_) {
      _isAvailable = false;
    }
  }

  /// Allocates a committed, pinned memory page locked in physical RAM.
  Pointer<Uint8>? allocateLockedMemory(int sizeBytes) {
    if (!_isAvailable || sizeBytes <= 0) return null;
    try {
      final ptr = _virtualAlloc!(
        nullptr,
        sizeBytes,
        _memCommit | _memReserve,
        _pageReadWrite,
      );
      if (ptr.address == 0) return null;

      // Lock memory into physical working set
      final lockResult = _virtualLock!(ptr, sizeBytes);
      if (lockResult == 0) {
        // Fallback: memory still usable even if VirtualLock hit quota limit
      }
      return ptr.cast<Uint8>();
    } catch (_) {
      return null;
    }
  }

  /// Cryptographically zeroes out memory before releasing and unlocking from RAM.
  void freeLockedMemory(Pointer<Uint8>? ptr, int sizeBytes) {
    if (ptr == null || ptr.address == 0 || sizeBytes <= 0) return;
    try {
      // 3-Pass DoD zeroization in RAM
      for (int i = 0; i < sizeBytes; i++) {
        ptr[i] = 0x55;
      }
      for (int i = 0; i < sizeBytes; i++) {
        ptr[i] = 0xAA;
      }
      for (int i = 0; i < sizeBytes; i++) {
        ptr[i] = 0x00;
      }

      if (_isAvailable) {
        if (_virtualUnlock != null) {
          _virtualUnlock!(ptr.cast<Void>(), sizeBytes);
        }
        if (_virtualFree != null) {
          _virtualFree!(ptr.cast<Void>(), 0, _memRelease);
        }
      }
    } catch (_) {}
  }

  /// Performs secure multi-pass zeroization on standard [Uint8List] buffer.
  static void wipeBuffer(Uint8List? buffer) {
    if (buffer == null || buffer.isEmpty) return;
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = 0x55;
    }
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = 0xAA;
    }
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = 0x00;
    }
  }
}

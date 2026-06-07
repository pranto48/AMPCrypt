import 'dart:typed_data';

abstract class VaultRepository {
  /// Check if the vault has already been set up/created on this device.
  bool get isVaultCreated;

  /// Check if the vault is currently unlocked.
  bool get isUnlocked;

  /// Retrieves the decrypted Master Key in hex representation, or null if locked.
  String? get masterKeyHex;

  /// Creates a new vault.
  /// 
  /// Derives password share using Argon2id, splits secret via SLIP-39,
  /// saves encrypted password share and mock biometric shares,
  /// and returns the 3 Backup Recovery phrases.
  Future<List<String>> createVault(String password);

  /// Unlocks the vault using the user's password and mock biometric shares.
  Future<bool> unlockVault(String password);

  /// Recovers the vault using any 2 of the 3 backup recovery phrases.
  Future<bool> recoverVault(List<String> recoveryPhrases);

  /// Locks the vault, clearing the master key from memory.
  void lockVault();

  /// Gets simulated device status information for display.
  Future<Map<String, dynamic>> getDeviceStatus();

  /// Registers/Trusts the current device (mock).
  Future<void> trustCurrentDevice();
}

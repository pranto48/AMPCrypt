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
  /// [authLevel] (1–4) controls how many SLIP-39 Group 1 shares are generated.
  /// 1FA = Password only, 2FA = +Fingerprint, 3FA = +Face, 4FA = +Voice.
  Future<List<String>> createVault(String password, {int authLevel = 4});

  /// Returns the auth level (1–4) that was configured when the vault was created.
  int get configuredAuthLevel;

  /// Unlocks the vault using the user's password.
  /// The repository reads the stored auth level and reconstructs only the required shares.
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

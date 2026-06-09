
abstract class VaultRepository {
  /// Check if the vault has already been set up/created on this device.
  bool get isVaultCreated;

  /// Check if the vault is currently unlocked.
  bool get isUnlocked;

  /// Retrieves the decrypted Master Key in hex representation, or null if locked.
  String? get masterKeyHex;

  /// Exposes the active WebDAV virtual drive mount port, or null if locked/inactive.
  int? get webDavPort;

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

  /// Gets the vault folder path.
  String getVaultPath();

  /// Gets the virtual drive mount letter.
  String getDriveLetter();

  /// Updates the vault storage path and drive letter.
  Future<void> updateVaultSettings(String path, String driveLetter);

  /// Gets the Ransomware Monitor sensitivity threshold.
  double get monitorSensitivity;

  /// Sets the Ransomware Monitor sensitivity threshold.
  Future<void> setMonitorSensitivity(double value);
}

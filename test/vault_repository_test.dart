import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ampcrypt/core/crypto/crypto_service.dart';
import 'package:ampcrypt/core/crypto/mock_crypto_service.dart';
import 'package:ampcrypt/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:ampcrypt/features/vault/domain/repositories/vault_repository.dart';

void main() {
  late CryptoService cryptoService;
  late VaultRepository vaultRepository;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tempDir = Directory.systemTemp.createTempSync('ampcrypt_test_');
    await prefs.setString('vault_path', tempDir.path);
    cryptoService = MockCryptoService();
    vaultRepository = VaultRepositoryImpl(
      cryptoService: cryptoService,
      prefs: prefs,
    );
  });

  test('VaultRepository - Initial state', () {
    expect(vaultRepository.isVaultCreated, isFalse);
    expect(vaultRepository.isUnlocked, isFalse);
    expect(vaultRepository.masterKeyHex, isNull);
  });

  test('VaultRepository - Create vault flow', () async {
    final password = "test-vault-password";
    final recoveryMnemonics = await vaultRepository.createVault(password);

    expect(vaultRepository.isVaultCreated, isTrue);
    expect(vaultRepository.isUnlocked, isTrue);
    expect(vaultRepository.masterKeyHex, isNotNull);
    expect(recoveryMnemonics.length, equals(3)); // 3 Backup Recovery Mnemonics
  });

  test('VaultRepository - Lock and Unlock flow', () async {
    final password = "test-vault-password";
    await vaultRepository.createVault(password);

    // Save the original master key
    final originalMasterKeyHex = vaultRepository.masterKeyHex;

    // Lock vault
    vaultRepository.lockVault();
    expect(vaultRepository.isUnlocked, isFalse);
    expect(vaultRepository.masterKeyHex, isNull);

    // Unlock vault with correct password
    final success = await vaultRepository.unlockVault(password);
    expect(success, isTrue);
    expect(vaultRepository.isUnlocked, isTrue);
    expect(vaultRepository.masterKeyHex, equals(originalMasterKeyHex));

    // Lock and attempt unlock with wrong password
    vaultRepository.lockVault();
    final fail = await vaultRepository.unlockVault("wrong-password");
    expect(fail, isFalse);
    expect(vaultRepository.isUnlocked, isFalse);
  });

  test('VaultRepository - Recovery flow', () async {
    final password = "test-vault-password";
    final recoveryMnemonics = await vaultRepository.createVault(password);
    final originalMasterKeyHex = vaultRepository.masterKeyHex;

    // Lock vault
    vaultRepository.lockVault();

    // Recover using any 2 of the 3 recovery phrases
    final recoveryPhrases = [recoveryMnemonics[0], recoveryMnemonics[1]];
    final success = await vaultRepository.recoverVault(recoveryPhrases);

    expect(success, isTrue);
    expect(vaultRepository.isUnlocked, isTrue);
    expect(vaultRepository.masterKeyHex, equals(originalMasterKeyHex));

    // Lock and attempt recovery with invalid/insufficient phrases
    vaultRepository.lockVault();
    final fail = await vaultRepository.recoverVault([recoveryMnemonics[0]]);
    expect(fail, isFalse);
    expect(vaultRepository.isUnlocked, isFalse);
  });
}

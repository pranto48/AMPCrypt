/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ampcrypt/core/crypto/mock_crypto_service.dart';
import 'package:ampcrypt/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:ampcrypt/features/vault/domain/repositories/vault_repository.dart';
import 'package:ampcrypt/features/vault/presentation/bloc/vault_bloc.dart';
import 'package:ampcrypt/features/vault/presentation/bloc/vault_event.dart';
import 'package:ampcrypt/features/vault/presentation/bloc/vault_state.dart';

@Timeout(Duration(seconds: 120))

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VaultRepository vaultRepository;
  late VaultBloc vaultBloc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tempDir = Directory.systemTemp.createTempSync('ampcrypt_bloc_test_');
    await prefs.setString('vault_path', tempDir.path);
    final cryptoService = MockCryptoService();
    vaultRepository = VaultRepositoryImpl(
      cryptoService: cryptoService,
      prefs: prefs,
    );
    vaultBloc = VaultBloc(vaultRepository: vaultRepository);
  });

  tearDown(() {
    vaultBloc.close();
  });

  test('VaultBloc - Initial state is VaultInitialState', () {
    expect(vaultBloc.state, equals(VaultInitialState()));
  });

  test('VaultBloc - CheckVaultStatusEvent triggers VaultUninitializedState', () async {
    final expectation = expectLater(
      vaultBloc.stream,
      emitsInOrder([
        VaultUninitializedState(),
      ]),
    );
    vaultBloc.add(CheckVaultStatusEvent());
    await expectation;
  });

  test('VaultBloc - CreateVaultEvent triggers Loading then UnlockedState', () async {
    final expectation = expectLater(
      vaultBloc.stream,
      emitsInOrder([
        isA<VaultLoadingState>(),
        isA<VaultUnlockedState>(),
      ]),
    );
    vaultBloc.add(CreateVaultEvent("password123"));
    await expectation;
    expect(vaultRepository.isVaultCreated, isTrue);
    expect(vaultRepository.isUnlocked, isTrue);
  });

  test('VaultBloc - Unlock flow triggers Loading then UnlockedState/FailureState', () async {
    // 1. Setup the vault
    await vaultRepository.createVault("password123");
    vaultRepository.lockVault();

    // 2. Unlock with correct password
    final expectation1 = expectLater(
      vaultBloc.stream,
      emitsInOrder([
        isA<VaultLoadingState>(),
        isA<VaultUnlockedState>(),
      ]),
    );
    vaultBloc.add(UnlockVaultEvent("password123"));
    await expectation1;

    // Lock again
    vaultRepository.lockVault();

    // 3. Unlock with incorrect password
    final expectation2 = expectLater(
      vaultBloc.stream,
      emitsInOrder([
        isA<VaultLoadingState>(),
        isA<VaultFailureState>(),
      ]),
    );
    vaultBloc.add(UnlockVaultEvent("wrong_pass"));
    await expectation2;
  });
}

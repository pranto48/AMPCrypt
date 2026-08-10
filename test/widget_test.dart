/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ampcrypt/core/crypto/mock_crypto_service.dart';
import 'package:ampcrypt/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:ampcrypt/features/ransomware_monitor/data/datasources/directory_watcher_service.dart';
import 'package:ampcrypt/main.dart';

void main() {
  testWidgets('AMPCrypt smoke test - shows setup screen when uninitialized', (WidgetTester tester) async {
    // Configure desktop viewport size for test
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 1. Setup mock SharedPreferences
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tempDir = Directory.systemTemp.createTempSync('ampcrypt_widget_test_');
    await prefs.setString('vault_path', tempDir.path);
    final cryptoService = MockCryptoService();
    final vaultRepository = VaultRepositoryImpl(
      cryptoService: cryptoService,
      prefs: prefs,
    );
    final watcherService = DirectoryWatcherService();

    // 2. Build the app and trigger a frame
    await tester.pumpWidget(MyApp(
      vaultRepository: vaultRepository,
      watcherService: watcherService,
      prefs: prefs,
    ));
    await tester.pumpAndSettle();



    // 3. Verify that it displays the setup screen elements
    expect(find.text('Initialize Vault'), findsOneWidget);
    expect(find.text('GENERATE VAULT'), findsOneWidget);
    expect(find.text('VAULT PASSPHRASE'), findsOneWidget);
  });
}

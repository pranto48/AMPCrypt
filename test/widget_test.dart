import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ampcrypt/core/crypto/mock_crypto_service.dart';
import 'package:ampcrypt/features/vault/data/repositories/vault_repository_impl.dart';
import 'package:ampcrypt/main.dart';

void main() {
  testWidgets('AMPCrypt smoke test - shows setup screen when uninitialized', (WidgetTester tester) async {
    // 1. Setup mock SharedPreferences
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cryptoService = MockCryptoService();
    final vaultRepository = VaultRepositoryImpl(
      cryptoService: cryptoService,
      prefs: prefs,
    );

    // 2. Build the app and trigger a frame
    await tester.pumpWidget(MyApp(vaultRepository: vaultRepository));
    await tester.pumpAndSettle();

    // 3. Verify that it displays the setup screen elements
    expect(find.text('Initialize AMPCrypt Vault'), findsOneWidget);
    expect(find.text('GENERATE VAULT'), findsOneWidget);
    expect(find.text('VAULT PASSPHRASE'), findsOneWidget);
  });
}

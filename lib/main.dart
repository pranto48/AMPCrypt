import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/crypto/crypto_service_impl.dart';
import 'features/vault/data/repositories/vault_repository_impl.dart';
import 'features/vault/presentation/bloc/vault_bloc.dart';
import 'features/vault/presentation/pages/vault_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  
  // Initialize Core Services & Repositories
  final cryptoService = CryptoServiceImpl();
  final vaultRepository = VaultRepositoryImpl(
    cryptoService: cryptoService,
    prefs: prefs,
  );

  runApp(MyApp(vaultRepository: vaultRepository));
}

class MyApp extends StatelessWidget {
  final VaultRepositoryImpl vaultRepository;
  
  const MyApp({super.key, required this.vaultRepository});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AMPCrypt Zero-Trust Vault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF8B5CF6),
        scaffoldBackgroundColor: const Color(0xFF070B19),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF0F172A),
          error: Color(0xFFEF4444),
        ),
        textTheme: GoogleFonts.outfitTextTheme(
          ThemeData.dark().textTheme,
        ),
        useMaterial3: true,
      ),
      home: BlocProvider(
        create: (context) => VaultBloc(vaultRepository: vaultRepository),
        child: const VaultPage(),
      ),
    );
  }
}

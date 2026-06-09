import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'core/crypto/crypto_service_impl.dart';
import 'features/vault/data/repositories/vault_repository_impl.dart';
import 'features/vault/presentation/bloc/vault_bloc.dart';
import 'features/vault/presentation/pages/vault_page.dart';
import 'features/ransomware_monitor/data/datasources/directory_watcher_service.dart';
import 'features/ransomware_monitor/presentation/bloc/monitor_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Desktop Window Manager & Auto-Start
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(960, 640),
      minimumSize: Size(960, 640),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setPreventClose(true);
    });

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
      );
    } catch (_) {}
  }
  
  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  
  // Initialize Core Services & Repositories
  final cryptoService = CryptoServiceImpl();
  final vaultRepository = VaultRepositoryImpl(
    cryptoService: cryptoService,
    prefs: prefs,
  );

  final watcherService = DirectoryWatcherService();

  runApp(MyApp(
    vaultRepository: vaultRepository,
    watcherService: watcherService,
  ));
}

class MyApp extends StatelessWidget {
  final VaultRepositoryImpl vaultRepository;
  final DirectoryWatcherService watcherService;
  
  const MyApp({
    super.key,
    required this.vaultRepository,
    required this.watcherService,
  });

  @override
  Widget build(BuildContext context) {

    return MultiBlocProvider(
      providers: [
        BlocProvider<VaultBloc>(
          create: (context) => VaultBloc(vaultRepository: vaultRepository),
        ),
      ],
      child: BlocProvider<MonitorBloc>(
        create: (context) => MonitorBloc(
          watcherService: watcherService,
          vaultBloc: context.read<VaultBloc>(),
          vaultRepository: vaultRepository,
        ),
        child: MaterialApp(
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
          home: const VaultPage(),
        ),
      ),
    );
  }
}

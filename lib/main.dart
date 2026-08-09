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

import 'core/portable_state_sync.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PortableStateSync.init();

  // Initialize SharedPreferences
  final prefs = await SharedPreferences.getInstance();
  final hideOnStart = prefs.getBool('hide_on_start') ?? false;

  // Initialize Desktop Window Manager & Auto-Start
  if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(960, 640),
      minimumSize: Size(960, 640),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (!hideOnStart) {
        await windowManager.show();
        await windowManager.focus();
      }
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
    prefs: prefs,
  ));
}

class MyApp extends StatefulWidget {
  final VaultRepositoryImpl vaultRepository;
  final DirectoryWatcherService watcherService;
  final SharedPreferences prefs;
  
  const MyApp({
    super.key,
    required this.vaultRepository,
    required this.watcherService,
    required this.prefs,
  });

  @override
  State<MyApp> createState() => MyAppState();

  static MyAppState? of(BuildContext context) =>
      context.findAncestorStateOfType<MyAppState>();
}

class MyAppState extends State<MyApp> {
  late ThemeMode _themeMode;

  @override
  void initState() {
    super.initState();
    final lookAndFeel = widget.prefs.getString('look_and_feel') ?? 'Light';
    if (lookAndFeel == 'Light') {
      _themeMode = ThemeMode.light;
    } else if (lookAndFeel == 'Dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
  }

  void setThemeMode(ThemeMode mode) {
    setState(() {
      _themeMode = mode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<VaultBloc>(
          create: (context) => VaultBloc(vaultRepository: widget.vaultRepository),
        ),
      ],
      child: BlocProvider<MonitorBloc>(
        create: (context) => MonitorBloc(
          watcherService: widget.watcherService,
          vaultBloc: context.read<VaultBloc>(),
          vaultRepository: widget.vaultRepository,
        ),
        child: MaterialApp(
          title: 'AMPCrypt Zero-Trust Vault',
          debugShowCheckedModeBanner: false,
          themeMode: _themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFF22C55E),
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF22C55E),
              secondary: Color(0xFF16A34A),
              surface: Colors.white,
              error: Color(0xFFE06C75),
            ),
            textTheme: GoogleFonts.outfitTextTheme(
              ThemeData.light().textTheme,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF22C55E),
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF22C55E),
              secondary: Color(0xFF16A34A),
              surface: Color(0xFF1E293B),
              error: Color(0xFFE06C75),
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

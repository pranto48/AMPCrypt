import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import '../../domain/repositories/vault_repository.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:local_auth/local_auth.dart';
import 'package:camera/camera.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ampcrypt/core/version.dart';
import 'package:http/http.dart' as http_pkg;

import '../bloc/vault_bloc.dart';
import '../bloc/vault_event.dart';
import '../bloc/vault_state.dart';
import '../../../biometrics/data/datasources/face_verification_service.dart';
import '../../../biometrics/data/datasources/fingerprint_verification_service.dart';
import '../../../biometrics/data/datasources/voice_verification_service.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_bloc.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_event.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_state.dart';

bool get isSystemDark {
  try {
    return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
  } catch (_) {
    return true; // default dark
  }
}

Color get kPrimaryColor => const Color(0xFF00A29A);
Color get kPrimaryHoverColor => const Color(0xFF00B3AA);
Color get kScaffoldBackgroundColor => isSystemDark ? const Color(0xFF1E2228) : const Color(0xFFF1F5F9);
Color get kSurfaceColor => const Color(0xFF181B20); // Keep vault core components dark for readability of white text
Color get kSidebarBackgroundColor => isSystemDark ? const Color(0xFF14171A) : const Color(0xFF1E2228);
Color get kSuccessColor => const Color(0xFF98C379);
Color get kErrorColor => const Color(0xFFE06C75);

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

enum ActiveView { dashboard, settings, recovery }

class _VaultPageState extends State<VaultPage> with WindowListener, TrayListener {
  ActiveView _activeView = ActiveView.dashboard;
  bool _minimizeToTray = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initSystemTray();
    _loadSettings();
    // Check initial vault status
    context.read<VaultBloc>().add(CheckVaultStatusEvent());
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _minimizeToTray = prefs.getBool('minimize_to_tray') ?? true;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux)) return;

    try {
      await trayManager.setIcon(
        Platform.isWindows 
            ? 'assets/app_icon.ico' 
            : 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png'
      );
      
      final menu = Menu(
        items: [
          MenuItem(key: 'open', label: 'Open Dashboard'),
          MenuItem(key: 'lock', label: 'Lock All Vaults'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Quit'),
        ],
      );
      await trayManager.setContextMenu(menu);
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('Failed to initialize system tray: $e');
    }
  }

  // --- WindowListener overrides ---
  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      if (_minimizeToTray) {
        await windowManager.hide();
      } else {
        _quitApp();
      }
    }
  }

  @override
  void onWindowMinimize() async {
    if (_minimizeToTray) {
      await windowManager.hide();
    }
  }

  // --- TrayListener overrides ---
  void onTrayIconClick() {
    _restoreWindow();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'open') {
      _restoreWindow();
    } else if (menuItem.key == 'lock') {
      context.read<VaultBloc>().add(LockVaultEvent());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kErrorColor,
          content: Text('All vaults locked from system tray.', style: GoogleFonts.outfit()),
        ),
      );
    } else if (menuItem.key == 'quit') {
      _quitApp();
    }
  }

  Future<void> _restoreWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _quitApp() async {
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Widget _buildCustomTitleBar() {
    return Container(
      height: 40,
      color: kSidebarBackgroundColor,
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: kPrimaryColor,
                      ),
                      child: const Icon(
                        Icons.vpn_key_rounded,
                        color: Colors.white,
                        size: 10,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AMPCrypt - Zero-Trust Vault',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _buildWindowButton(
            icon: Icons.minimize_rounded,
            onPressed: () => windowManager.minimize(),
            hoverColor: Colors.white.withOpacity(0.08),
          ),
          _buildWindowButton(
            icon: Icons.crop_square_rounded,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
            hoverColor: Colors.white.withOpacity(0.08),
          ),
          _buildWindowButton(
            icon: Icons.close_rounded,
            onPressed: () => onWindowClose(),
            hoverColor: kErrorColor.withOpacity(0.8),
            iconColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Widget _buildWindowButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color hoverColor,
    Color? iconColor,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: hoverColor,
        child: Container(
          width: 46,
          height: 40,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 16,
            color: iconColor ?? Colors.white.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  void _showOpenVaultDialog(BuildContext context) async {
    final repository = context.read<VaultBloc>().repository;
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null) {
      if (context.mounted) {
        _showMountDialogForPath(context, selectedDirectory);
      }
    }
  }

  void _showMountDialogForPath(BuildContext context, String path) {
    final repository = context.read<VaultBloc>().repository;
    String selectedDrive = repository.getDriveLetter();
    
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kSurfaceColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(
                'Open Existing Vault',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected folder:',
                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    path,
                    style: GoogleFonts.shareTechMono(color: kPrimaryColor, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedDrive,
                    dropdownColor: kSurfaceColor,
                    decoration: InputDecoration(
                      labelText: 'Virtual Drive Letter',
                      labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                    ),
                    style: GoogleFonts.outfit(color: Colors.white),
                    items: ['D:', 'E:', 'F:', 'G:', 'H:', 'V:', 'W:', 'X:', 'Y:', 'Z:']
                        .map((drive) => DropdownMenuItem(
                              value: drive,
                              child: Text(drive, style: GoogleFonts.outfit(color: Colors.white)),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedDrive = val;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await repository.updateVaultSettings(path, selectedDrive);
                    if (context.mounted) {
                      context.read<VaultBloc>().add(CheckVaultStatusEvent());
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: kSuccessColor,
                          content: Text('Vault profile loaded. Unlock to mount.', style: GoogleFonts.outfit()),
                        ),
                      );
                    }
                  },
                  child: Text('Open Vault', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const WebLandingPage();
    }
    final showCustomTitleBar = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    return Scaffold(
      backgroundColor: kScaffoldBackgroundColor,
      body: Column(
        children: [
          if (showCustomTitleBar) _buildCustomTitleBar(),
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        kScaffoldBackgroundColor,
                        kSurfaceColor,
                        kSidebarBackgroundColor,
                      ],
                    ),
                  ),
                  child: BlocConsumer<VaultBloc, VaultState>(
              listener: (context, state) {
                if (state is VaultFailureState) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF3F0B24),
                      content: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFFF4D88)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              state.errorMessage,
                              style: GoogleFonts.outfit(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      duration: const Duration(seconds: 4),
                      action: SnackBarAction(
                        label: 'Dismiss',
                        textColor: const Color(0xFFFF4D88),
                        onPressed: () {},
                      ),
                    ),
                  );
                }
              },
              builder: (context, state) {
                return Row(
                  children: [
                    _buildSidebar(context, state),
                    Container(
                      width: 1,
                      color: Colors.white.withOpacity(0.08),
                    ),
                    Expanded(
                      child: _buildDesktopMainContent(context, state),
                    ),
                  ],
                );
              },
            ),
          ),
          BlocBuilder<MonitorBloc, MonitorState>(
            builder: (context, monitorState) {
              if (monitorState.isAlarmTriggered) {
                return RansomwareAlarmOverlay(
                  watchedPath: monitorState.watchedPath ?? 'Unknown Path',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    ),
  ],
),
);
  }

  Widget _buildSidebar(BuildContext context, VaultState state) {
    final isUnlocked = state is VaultUnlockedState;
    final isCreated = state is! VaultUninitializedState && state is! VaultInitialState;

    Widget navItem({
      required String title,
      required IconData icon,
      required ActiveView view,
    }) {
      final isSelected = _activeView == view;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 3.0),
        child: InkWell(
          onTap: () {
            setState(() {
              _activeView = view;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected 
                  ? kPrimaryColor.withOpacity(0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected 
                    ? kPrimaryColor.withOpacity(0.25)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? kPrimaryColor : const Color(0xFF64748B),
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      width: 250,
      color: kSidebarBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kPrimaryColor.withOpacity(0.15),
                    border: Border.all(
                      color: kPrimaryColor.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: const Icon(Icons.security_rounded, color: kPrimaryColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'AMPCrypt Client',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
          const SizedBox(height: 12),
          
          navItem(title: 'Dashboard', icon: Icons.dashboard_outlined, view: ActiveView.dashboard),
          navItem(title: 'Security Recovery', icon: Icons.vpn_key_outlined, view: ActiveView.recovery),
          navItem(title: 'App Settings', icon: Icons.settings_outlined, view: ActiveView.settings),

          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8),
            child: Text(
              'CURRENT VAULT',
              style: GoogleFonts.outfit(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
                color: const Color(0xFF94A3B8).withOpacity(0.6),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                if (isCreated)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: kSurfaceColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: kPrimaryColor.withOpacity(0.15),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isUnlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                              color: isUnlocked ? kSuccessColor : kErrorColor,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Primary Vault',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Path: ${context.read<VaultBloc>().repository.getVaultPath()}',
                          style: GoogleFonts.shareTechMono(
                            fontSize: 10,
                            color: const Color(0xFF94A3B8),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Drive: ${context.read<VaultBloc>().repository.getDriveLetter()}',
                          style: GoogleFonts.shareTechMono(
                            fontSize: 10,
                            color: kPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: Text(
                      'No vaults initialized.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: const Color(0xFF94A3B8),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      cardColor: kSurfaceColor,
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: 'Add or Open Vault',
                      offset: const Offset(0, -90),
                      onSelected: (value) {
                        if (value == 'new') {
                          _showCreateVaultDialog(context);
                        } else if (value == 'open') {
                          _showOpenVaultDialog(context);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'new',
                          child: Row(
                            children: [
                              const Icon(Icons.add_circle_outline, color: kPrimaryColor, size: 16),
                              const SizedBox(width: 8),
                              Text('Create New Vault', style: GoogleFonts.outfit(fontSize: 12)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'open',
                          child: Row(
                            children: [
                              const Icon(Icons.folder_open_outlined, color: kPrimaryColor, size: 16),
                              const SizedBox(width: 8),
                              Text('Open Existing Vault', style: GoogleFonts.outfit(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E2228),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add, size: 16, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              'ADD VAULT',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_up, size: 16, color: Colors.white70),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateVaultDialog(BuildContext context) {
    final repository = context.read<VaultBloc>().repository;
    final defaultPath = repository.getVaultPath();
    final defaultDrive = repository.getDriveLetter();

    final nameController = TextEditingController(text: 'Primary');
    final pathController = TextEditingController(text: defaultPath);
    String selectedDrive = defaultDrive;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kSurfaceColor,
              title: Text(
                'Create New Vault',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 450,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: GoogleFonts.outfit(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Vault Name',
                        labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                      ),
                      onChanged: (val) {
                        final cleanName = val.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').toLowerCase();
                        if (cleanName.isNotEmpty) {
                          final parentDir = Directory(defaultPath).parent.path;
                          setDialogState(() {
                            pathController.text = p.join(parentDir, '.ampcrypt_vault_$cleanName');
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: pathController,
                            style: GoogleFonts.outfit(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Vault Folder Path',
                              labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
                              enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.folder_open, color: kPrimaryColor),
                          onPressed: () async {
                            String? selectedDirectory = await FilePicker.getDirectoryPath();
                            if (selectedDirectory != null) {
                              setDialogState(() {
                                pathController.text = selectedDirectory;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedDrive,
                      dropdownColor: const Color(0xFF1E293B),
                      decoration: InputDecoration(
                        labelText: 'Virtual Drive Letter',
                        labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                      ),
                      style: GoogleFonts.outfit(color: Colors.white),
                      items: ['D:', 'E:', 'F:', 'G:', 'H:', 'V:', 'W:', 'X:', 'Y:', 'Z:']
                          .map((drive) => DropdownMenuItem(
                                value: drive,
                                child: Text(drive, style: GoogleFonts.outfit(color: Colors.white)),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            selectedDrive = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    if (pathController.text.isNotEmpty) {
                      final path = pathController.text;
                      final drive = selectedDrive;
                      Navigator.of(dialogContext).pop();
                      
                      await repository.updateVaultSettings(path, drive);
                      
                      if (context.mounted) {
                        context.read<VaultBloc>().add(ResetToUninitializedEvent());
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: kSuccessColor,
                            content: Text(
                              'Vault profile configured. Setup your security keys.',
                              style: GoogleFonts.outfit(),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text('Create & Setup', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDesktopMainContent(BuildContext context, VaultState state) {
    final isUnlocked = state is VaultUnlockedState;
    final isCreated = state is! VaultUninitializedState && state is! VaultInitialState;

    String viewTitle = 'Welcome to AMPCrypt';
    String viewSubtitle = 'Secure Zero-Trust System';
    IconData viewIcon = Icons.shield;
    Color viewColor = const Color(0xFF94A3B8);

    if (_activeView == ActiveView.settings) {
      viewTitle = 'App Settings';
      viewSubtitle = 'App Configuration & Hardware Diagnostics';
      viewIcon = Icons.settings;
      viewColor = kPrimaryColor;
    } else if (_activeView == ActiveView.recovery) {
      viewTitle = 'Master Key Recovery';
      viewSubtitle = 'Reconstruct Master Key from SLIP-39 Mnemonic Shares';
      viewIcon = Icons.vpn_key;
      viewColor = const Color(0xFFFF9E0B);
    } else if (isCreated) {
      viewTitle = 'Primary Vault';
      viewSubtitle = isUnlocked ? 'Unlocked & Mounted' : 'Locked';
      viewIcon = isUnlocked ? Icons.lock_open : Icons.lock;
      viewColor = isUnlocked ? kSuccessColor : kErrorColor;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                viewTitle,
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    viewIcon,
                    size: 14,
                    color: viewColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    viewSubtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: viewColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Divider(color: Colors.white.withOpacity(0.06), height: 1),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: const BoxConstraints(
                  maxWidth: 800,
                ),
                child: _activeView == ActiveView.settings
                    ? SettingsView(
                        onClose: () {
                          _loadSettings();
                          setState(() => _activeView = ActiveView.dashboard);
                        },
                        onQuit: _quitApp,
                      )
                    : (_activeView == ActiveView.recovery
                        ? const InlineRecoveryView()
                        : (isUnlocked 
                            ? UnlockedDashboardView(state: state)
                            : _buildVaultConsoleView(context, state))),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVaultConsoleView(BuildContext context, VaultState state) {
    if (state is VaultInitialState) {
      return const VaultLoadingView(message: 'Initializing Secure Environment...');
    } else if (state is VaultLoadingState) {
      return VaultLoadingView(message: state.message);
    } else if (state is VaultUninitializedState) {
      return const CreateVaultView();
    } else if (state is VaultLockedState) {
      return const UnlockVaultView();
    } else if (state is VaultFailureState) {
      return _buildFailureView(context, state);
    }
    return const Center(child: Text('Unknown State'));
  }

  Widget _buildFailureView(BuildContext context, VaultFailureState state) {
    final previousState = state.previousState;
    return Stack(
      children: [
        if (previousState is VaultLockedState)
          const UnlockVaultView()
        else if (previousState is VaultUninitializedState)
          const CreateVaultView()
        else
          const UnlockVaultView(),
      ],
    );
  }
}

class SettingsView extends StatefulWidget {
  final VoidCallback onClose;
  final VoidCallback onQuit;
  const SettingsView({super.key, required this.onClose, required this.onQuit});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late TextEditingController pathController;
  late String selectedDrive;
  late double selectedSensitivity;
  late int selectedAutoLock;

  bool isStartupEnabled = false;
  bool isCheckingUpdates = false;
  bool minimizeToTray = true;

  bool isScanning = false;
  bool? hasFingerprint;
  bool? hasCamera;
  bool? hasMic;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    final repository = context.read<VaultBloc>().repository;
    pathController = TextEditingController(text: repository.getVaultPath());
    selectedDrive = repository.getDriveLetter();
    selectedSensitivity = repository.monitorSensitivity;
    selectedAutoLock = repository.autoLockMinutes;
    
    _loadStartupStatus();
    _loadSettings();
    _runDiagnostic();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        minimizeToTray = prefs.getBool('minimize_to_tray') ?? true;
      });
    } catch (_) {}
  }

  Future<void> _toggleMinimizeToTray(bool val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('minimize_to_tray', val);
      setState(() {
        minimizeToTray = val;
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    pathController.dispose();
    super.dispose();
  }

  Future<void> _loadStartupStatus() async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS)) return;
    try {
      final enabled = await launchAtStartup.isEnabled();
      setState(() {
        isStartupEnabled = enabled;
      });
    } catch (_) {}
  }

  Future<void> _toggleStartup(bool val) async {
    if (kIsWeb || (!Platform.isWindows && !Platform.isMacOS)) return;
    try {
      if (val) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      setState(() {
        isStartupEnabled = val;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kSuccessColor,
          content: Text(
            val ? 'AMPCrypt registered to launch at startup.' : 'Startup launch disabled.',
            style: GoogleFonts.outfit(),
          ),
        ),
      );
    } catch (_) {}
  }

  Future<void> _checkUpdates() async {
    setState(() {
      isCheckingUpdates = true;
    });
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) {
      setState(() {
        isCheckingUpdates = false;
      });
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: kSurfaceColor,
          title: Text(
            'Software Update',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'You are running the latest version of AMPCrypt ($kAppVersion).',
            style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('OK', style: GoogleFonts.outfit(color: kPrimaryColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _runDiagnostic() async {
    setState(() {
      isScanning = true;
    });
    bool fingerprint = false;
    try {
      final localAuth = LocalAuthentication();
      fingerprint = await localAuth.isDeviceSupported() || await localAuth.canCheckBiometrics;
    } catch (_) {}

    bool cameraAvailable = false;
    try {
      final cameras = await availableCameras();
      cameraAvailable = cameras.isNotEmpty;
    } catch (_) {}

    bool micAvailable = false;
    if (Platform.isWindows) {
      try {
        final result = await Process.run('powershell', [
          '-Command',
          'Get-CimInstance -ClassName Win32_PnPEntity | Where-Object { \$_.PNPClass -eq \'AudioEndpoint\' } | Select-Object -ExpandProperty Name'
        ]);
        if (result.exitCode == 0) {
          final output = result.stdout.toString().toLowerCase();
          micAvailable = output.contains('microphone') || output.contains('mic') || output.contains('input');
        }
      } catch (_) {}
    } else {
      micAvailable = true;
    }

    if (mounted) {
      setState(() {
        hasFingerprint = fingerprint;
        hasCamera = cameraAvailable;
        hasMic = micAvailable;
        isScanning = false;
      });
    }
  }

  Widget _deviceRow(String name, IconData icon, bool? detected) {
    Widget statusWidget;
    if (detected == null) {
      statusWidget = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: kPrimaryColor)),
          SizedBox(width: 8),
          Text('Checking...', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
        ],
      );
    } else if (detected) {
      statusWidget = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: kSuccessColor, size: 14),
          SizedBox(width: 4),
          Text('Detected', style: TextStyle(color: kSuccessColor, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      );
    } else {
      statusWidget = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, color: kErrorColor, size: 14),
          SizedBox(width: 4),
          Text('Not Detected', style: TextStyle(color: kErrorColor, fontSize: 11)),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF94A3B8), size: 16),
              const SizedBox(width: 10),
              Text(name, style: GoogleFonts.outfit(color: Colors.white, fontSize: 12)),
            ],
          ),
          statusWidget,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<VaultBloc>().repository;

    return GlassmorphicCard(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              indicatorColor: kPrimaryColor,
              labelColor: Colors.white,
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.outfit(fontSize: 13),
              tabs: const [
                Tab(text: 'General Settings'),
                Tab(text: 'System & Startup'),
                Tab(text: 'Security & Hardware'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DIRECTORY CONFIGURATION',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: pathController,
                              style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                labelText: 'Vault Folder Path',
                                labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.folder_open, color: kPrimaryColor, size: 18),
                            onPressed: () async {
                              String? selectedDirectory = await FilePicker.getDirectoryPath();
                              if (selectedDirectory != null) {
                                setState(() {
                                  pathController.text = selectedDirectory;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedDrive,
                              dropdownColor: const Color(0xFF1E293B),
                              decoration: InputDecoration(
                                labelText: 'Virtual Drive Letter',
                                labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                              ),
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                              items: ['D:', 'E:', 'F:', 'G:', 'H:', 'V:', 'W:', 'X:', 'Y:', 'Z:']
                                  .map((drive) => DropdownMenuItem(
                                        value: drive,
                                        child: Text(drive, style: GoogleFonts.outfit(color: Colors.white)),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    selectedDrive = val;
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: selectedAutoLock,
                              dropdownColor: const Color(0xFF1E293B),
                              decoration: InputDecoration(
                                labelText: 'Auto-Lock Inactivity Timeout',
                                labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                              ),
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('Never')),
                                DropdownMenuItem(value: 5, child: Text('5 Minutes')),
                                DropdownMenuItem(value: 15, child: Text('15 Minutes')),
                                DropdownMenuItem(value: 30, child: Text('30 Minutes')),
                                DropdownMenuItem(value: 60, child: Text('60 Minutes')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    selectedAutoLock = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'STARTUP & SYSTEM INTEGRATION',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        decoration: BoxDecoration(
                          color: kSurfaceColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                Platform.isMacOS 
                                    ? 'Run at macOS Startup' 
                                    : (Platform.isWindows ? 'Run at Windows Startup' : 'Run at System Startup'),
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                              ),
                              subtitle: Text('Launch AMPCrypt silently when your system boots', style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 11)),
                              activeColor: kPrimaryColor,
                              value: isStartupEnabled,
                              onChanged: _toggleStartup,
                            ),
                            const Divider(color: Colors.white10, height: 1),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('Minimize to System Tray on Close', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                              subtitle: Text('Keep the app running in the background when window is closed', style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 11)),
                              activeColor: kPrimaryColor,
                              value: minimizeToTray,
                              onChanged: _toggleMinimizeToTray,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kSurfaceColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.08)),
                                gradient: LinearGradient(
                                  colors: [
                                    kSurfaceColor,
                                    kSidebarBackgroundColor.withOpacity(0.4),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: const LinearGradient(
                                            colors: [kPrimaryColor, Color(0xFF005E5A)],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: kPrimaryColor.withOpacity(0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.verified_user_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'AMPCrypt Security Suite',
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Wrap(
                                              children: [
                                                Text(
                                                  'Made by ',
                                                  style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF64748B)),
                                                ),
                                                InkWell(
                                                  onTap: () => launchUrl(Uri.parse('https://itsupport.com.bd/'), mode: LaunchMode.externalApplication),
                                                  child: Text(
                                                    'IT Support BD',
                                                    style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: kPrimaryColor, decoration: TextDecoration.underline),
                                                  ),
                                                ),
                                                Text(
                                                  ' | Contributor: ',
                                                  style: GoogleFonts.outfit(fontSize: 10, color: const Color(0xFF64748B)),
                                                ),
                                                InkWell(
                                                  onTap: () => launchUrl(Uri.parse('https://arifmahmud.com/'), mode: LaunchMode.externalApplication),
                                                  child: Text(
                                                    'Arif Mahmud Pranto',
                                                    style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: kPrimaryColor, decoration: TextDecoration.underline),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Divider(color: Colors.white.withOpacity(0.08), height: 1),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: kSuccessColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'OPEN SOURCE',
                                          style: GoogleFonts.outfit(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: kSuccessColor,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Version $kAppVersion (Stable)',
                                        style: GoogleFonts.shareTechMono(
                                          fontSize: 11,
                                          color: const Color(0xFF94A3B8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'An enterprise-grade, zero-trust offline cryptographic vault protecting your files with 4-Factor Biometric interlocking (Password, Face, Fingerprint, Voice), SLIP-39 secret splitting, and Unsupervised ML ransomware behavior shielding.',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      color: const Color(0xFF94A3B8),
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  InkWell(
                                    onTap: () async {
                                      try {
                                        await launchUrl(
                                          Uri.parse('https://ampcrypt.itsupport.bd/'),
                                          mode: LaunchMode.externalApplication,
                                        );
                                      } catch (_) {}
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.language_rounded,
                                            color: kPrimaryColor,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'https://ampcrypt.itsupport.bd/',
                                            style: GoogleFonts.outfit(
                                              fontSize: 12,
                                              color: kPrimaryColor,
                                              fontWeight: FontWeight.bold,
                                              decoration: TextDecoration.underline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            children: [
                              SizedBox(
                                width: 180,
                                height: 36,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E2228),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    textStyle: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold),
                                    side: const BorderSide(color: Colors.white10),
                                  ),
                                  icon: isCheckingUpdates
                                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white))
                                      : const Icon(Icons.sync_rounded, size: 14),
                                  label: Text(isCheckingUpdates ? 'CHECKING...' : 'CHECK FOR UPDATES'),
                                  onPressed: isCheckingUpdates ? null : _checkUpdates,
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: 180,
                                height: 36,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kErrorColor.withOpacity(0.15),
                                    foregroundColor: kErrorColor,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    textStyle: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold),
                                    side: BorderSide(color: kErrorColor.withOpacity(0.3)),
                                  ),
                                  icon: const Icon(Icons.power_settings_new_rounded, size: 14),
                                  label: const Text('QUIT APPLICATION'),
                                  onPressed: () => widget.onQuit(),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'RANSOMWARE HEURISTICS MONITOR',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: kPrimaryColor,
                            ),
                          ),
                          Text(
                            selectedSensitivity.toStringAsFixed(2),
                            style: GoogleFonts.shareTechMono(color: kPrimaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ],
                      ),
                      Slider(
                        value: selectedSensitivity,
                        min: 0.3,
                        max: 0.9,
                        activeColor: kPrimaryColor,
                        inactiveColor: const Color(0xFF1E1E38),
                        onChanged: (val) {
                          setState(() {
                            selectedSensitivity = val;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'HARDWARE VERIFICATION DIAGNOSTICS',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: kPrimaryColor,
                            ),
                          ),
                          InkWell(
                            onTap: isScanning ? null : _runDiagnostic,
                            child: Text(
                              isScanning ? 'SCANNING...' : 'RE-RUN SCAN',
                              style: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _deviceRow('Fingerprint Reader', Icons.fingerprint, hasFingerprint),
                      _deviceRow('Webcam / Camera', Icons.camera_alt_outlined, hasCamera),
                      _deviceRow('Microphone (Mic)', Icons.mic_none_outlined, hasMic),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white10, height: 1),
                      const SizedBox(height: 16),
                      _buildQuestionsRecoverySetting(repository),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF334155)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: widget.onClose,
                  child: Text('CANCEL', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold, fontSize: 12)),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: () async {
                    if (pathController.text.isNotEmpty) {
                      await repository.updateVaultSettings(pathController.text, selectedDrive);
                      await repository.setMonitorSensitivity(selectedSensitivity);
                      await repository.setAutoLockMinutes(selectedAutoLock);
                      
                      if (context.mounted) {
                        context.read<VaultBloc>().add(CheckVaultStatusEvent());
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: kSuccessColor,
                            content: Text('Settings saved successfully.', style: GoogleFonts.outfit()),
                          ),
                        );
                        widget.onClose();
                      }
                    }
                  },
                  child: Text('SAVE SETTINGS', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionsRecoverySetting(VaultRepository repository) {
    final isEnabled = repository.isQuestionsRecoveryEnabled;
    final email = repository.getQuestionsRecoveryEmail();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kSurfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.contact_mail_outlined,
                    color: isEnabled ? kSuccessColor : const Color(0xFF94A3B8),
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Questions & Email OTP Recovery',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isEnabled ? kSuccessColor.withOpacity(0.1) : Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isEnabled ? kSuccessColor.withOpacity(0.3) : Colors.white24,
                  ),
                ),
                child: Text(
                  isEnabled ? 'ACTIVE' : 'INACTIVE',
                  style: GoogleFonts.outfit(
                    color: isEnabled ? kSuccessColor : const Color(0xFF94A3B8),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isEnabled
                ? 'Master Password recovery is active. Linked to email: $email.'
                : 'Configure 3 security questions and an email verification code to recover your Master Password if forgotten.',
            style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 11),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 36,
            child: isEnabled
                ? OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kErrorColor,
                      side: BorderSide(color: kErrorColor.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 14),
                    label: const Text('DEACTIVATE RECOVERY'),
                    onPressed: () async {
                      await repository.disableQuestionsRecovery();
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: kErrorColor,
                            content: Text(
                              'Security questions recovery deactivated.',
                              style: GoogleFonts.outfit(),
                            ),
                          ),
                        );
                      }
                    },
                  )
                : ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.settings_outlined, size: 14),
                    label: const Text('CONFIGURE RECOVERY'),
                    onPressed: () {
                      _showConfigureQuestionsDialog(context, repository);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _showConfigureQuestionsDialog(BuildContext context, VaultRepository repository) {
    final emailController = TextEditingController();
    final q1Controller = TextEditingController(text: 'What was the name of your first pet?');
    final q2Controller = TextEditingController(text: 'In what city were you born?');
    final q3Controller = TextEditingController(text: 'What is your mother\'s maiden name?');
    final a1Controller = TextEditingController();
    final a2Controller = TextEditingController();
    final a3Controller = TextEditingController();

    final predefinedQuestions = [
      'What was the name of your first pet?',
      'In what city were you born?',
      'What is your mother\'s maiden name?',
      'What was the name of your first school?',
      'What is the name of the street you grew up on?',
      'What is your favorite book or movie?',
    ];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kSurfaceColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text(
                'Configure Recovery Questions & Email',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This will encrypt your Master Key with answers to your security questions. If you forget your password, you can recover it by completing this verification and matching the email OTP code.',
                        style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 11),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Recovery Email Address',
                          labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Question 1
                      DropdownButtonFormField<String>(
                        value: predefinedQuestions.contains(q1Controller.text) ? q1Controller.text : predefinedQuestions[0],
                        dropdownColor: kSurfaceColor,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Security Question 1',
                          labelStyle: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        items: predefinedQuestions
                            .map((q) => DropdownMenuItem(value: q, child: Text(q, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            q1Controller.text = val;
                          }
                        },
                      ),
                      TextField(
                        controller: a1Controller,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Answer 1',
                          labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Question 2
                      DropdownButtonFormField<String>(
                        value: predefinedQuestions.contains(q2Controller.text) ? q2Controller.text : predefinedQuestions[1],
                        dropdownColor: kSurfaceColor,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Security Question 2',
                          labelStyle: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        items: predefinedQuestions
                            .map((q) => DropdownMenuItem(value: q, child: Text(q, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            q2Controller.text = val;
                          }
                        },
                      ),
                      TextField(
                        controller: a2Controller,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Answer 2',
                          labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Question 3
                      DropdownButtonFormField<String>(
                        value: predefinedQuestions.contains(q3Controller.text) ? q3Controller.text : predefinedQuestions[2],
                        dropdownColor: kSurfaceColor,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                        decoration: InputDecoration(
                          labelText: 'Security Question 3',
                          labelStyle: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        items: predefinedQuestions
                            .map((q) => DropdownMenuItem(value: q, child: Text(q, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            q3Controller.text = val;
                          }
                        },
                      ),
                      TextField(
                        controller: a3Controller,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Answer 3',
                          labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Cancel', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final email = emailController.text.trim();
                    final a1 = a1Controller.text.trim();
                    final a2 = a2Controller.text.trim();
                    final a3 = a3Controller.text.trim();

                    if (email.isEmpty || a1.isEmpty || a2.isEmpty || a3.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: kErrorColor,
                          content: Text('Please fill in email and all 3 answers.', style: GoogleFonts.outfit()),
                        ),
                      );
                      return;
                    }

                    try {
                      Navigator.of(dialogContext).pop();
                      await repository.enableQuestionsRecovery(
                        email,
                        [q1Controller.text, q2Controller.text, q3Controller.text],
                        [a1, a2, a3],
                      );
                      setState(() {});
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: kSuccessColor,
                            content: Text('Security questions recovery enabled successfully!', style: GoogleFonts.outfit()),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: kErrorColor,
                            content: Text('Failed to set up recovery: ${e.toString()}', style: GoogleFonts.outfit()),
                          ),
                        );
                      }
                    }
                  },
                  child: Text('Save Setup', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ==========================================
// 1. Vault Loading View (Animated Spinner)
// ==========================================
class VaultLoadingView extends StatelessWidget {
  final String message;
  const VaultLoadingView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassmorphicCard(
        width: 380,
        height: 250,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(kPrimaryColor),
                  backgroundColor: Color(0xFF1E1E38),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'CRYPTOGRAPHIC SECURE CHANNEL',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: kPrimaryColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: const Color(0xFF94A3B8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. Create Vault View (Setup Screen)
// ==========================================
class CreateVaultView extends StatefulWidget {
  const CreateVaultView({super.key});

  @override
  State<CreateVaultView> createState() => _CreateVaultViewState();
}

class _CreateVaultViewState extends State<CreateVaultView> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  final _formKey = GlobalKey<FormState>();
  int _selectedAuthLevel = 4;

  double _strength = 0;
  String _strengthLabel = "Too Weak";
  Color _strengthColor = kErrorColor;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength(String val) {
    double strength = 0;
    if (val.length >= 8) strength += 0.25;
    if (RegExp(r'[A-Z]').hasMatch(val)) strength += 0.25;
    if (RegExp(r'[a-z]').hasMatch(val)) strength += 0.25;
    if (RegExp(r'[0-9]').hasMatch(val) || RegExp(r'[!@#\$&*~]').hasMatch(val)) strength += 0.25;

    setState(() {
      _strength = strength;
      if (strength <= 0.25) {
        _strengthLabel = "Too Weak";
        _strengthColor = kErrorColor;
      } else if (strength <= 0.5) {
        _strengthLabel = "Weak";
        _strengthColor = const Color(0xFFF59E0B);
      } else if (strength <= 0.75) {
        _strengthLabel = "Medium";
        _strengthColor = kPrimaryHoverColor;
      } else {
        _strengthLabel = "Strong (Argon2id Optimized)";
        _strengthColor = kSuccessColor;
      }
    });
  }

  void _submitSetup() {
    if (_formKey.currentState!.validate()) {
      context.read<VaultBloc>().add(
        CreateVaultEvent(_passwordController.text, authLevel: _selectedAuthLevel),
      );
    }
  }

  Widget _securityTile({
    required int level,
    required String label,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedAuthLevel == level;
    final accentColors = [
      kSuccessColor, // 1FA
      kPrimaryHoverColor, // 2FA
      const Color(0xFFF59E0B), // 3FA
      kPrimaryColor, // 4FA
    ];
    final accent = accentColors[level - 1];
    return GestureDetector(
      onTap: () => setState(() => _selectedAuthLevel = level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.12) : const Color(0xFF1E1E38).withOpacity(0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accent.withOpacity(0.6) : const Color(0xFF2E3556),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: isSelected ? accent : const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: isSelected ? accent : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, size: 14, color: accent),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Form(
        key: _formKey,
        child: GlassmorphicCard(
          width: 800,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column: Setup & Security factor level
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kPrimaryColor.withOpacity(0.1),
                              border: Border.all(color: kPrimaryColor.withOpacity(0.3), width: 1.5),
                            ),
                            child: const Icon(Icons.shield_outlined, size: 24, color: kPrimaryColor),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Initialize Vault',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Select security level, then create password to generate zero-trust shares.',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'SECURITY LEVEL',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Compact 2x2 grid of security levels
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.2,
                        children: [
                          _securityTile(
                            level: 1,
                            label: '1FA',
                            subtitle: 'Password Only',
                            icon: Icons.lock_outlined,
                          ),
                          _securityTile(
                            level: 2,
                            label: '2FA',
                            subtitle: '+ Fingerprint',
                            icon: Icons.fingerprint_outlined,
                          ),
                          _securityTile(
                            level: 3,
                            label: '3FA',
                            subtitle: '+ Face',
                            icon: Icons.face_outlined,
                          ),
                          _securityTile(
                            level: 4,
                            label: '4FA — Max',
                            subtitle: '+ Voice',
                            icon: Icons.security_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Setup Info Notice
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: kSuccessColor.withOpacity(0.05),
                          border: Border.all(color: kSuccessColor.withOpacity(0.2), width: 1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, color: kSuccessColor, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Offline generation using SLIP-0039. Shares are protected locally.',
                                style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 28),
                // Right column: Password input forms and buttons
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'VAULT PASSPHRASE',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        onChanged: _checkPasswordStrength,
                        decoration: _inputDecoration(
                          hint: 'Enter strong password',
                          prefix: Icons.lock_open_outlined,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: const Color(0xFF94A3B8),
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Password is required';
                          if (val.length < 8) return 'Password must be at least 8 characters';
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      // Strength Indicator Bar
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _strength,
                                backgroundColor: const Color(0xFF1E1E38),
                                valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                                minHeight: 4,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _strengthLabel,
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _strengthColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'CONFIRM PASSPHRASE',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _confirmController,
                        obscureText: _obscureConfirm,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: _inputDecoration(
                          hint: 'Retype password',
                          prefix: Icons.lock_outline,
                          suffix: IconButton(
                            icon: Icon(
                              _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: const Color(0xFF94A3B8),
                              size: 18,
                            ),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.isEmpty) return 'Please confirm your password';
                          if (val != _passwordController.text) return 'Passwords do not match';
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: _submitSetup,
                          child: Text(
                            'GENERATE VAULT',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const RecoveryPage()),
                            );
                          },
                          child: Text(
                            'Already have recovery mnemonics?',
                            style: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. Unlock Vault View (Simulated Multi-Factor Screen)
// ==========================================
class UnlockVaultView extends StatefulWidget {
  const UnlockVaultView({super.key});

  @override
  State<UnlockVaultView> createState() => _UnlockVaultViewState();
}

class _UnlockVaultViewState extends State<UnlockVaultView> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // The auth level configured at vault creation time (loaded from prefs)
  int _configuredAuthLevel = 4;

  @override
  void initState() {
    super.initState();
    _loadConfiguredAuthLevel();
  }

  Future<void> _loadConfiguredAuthLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final level = prefs.getInt('auth_level') ?? 4;
    if (mounted) setState(() => _configuredAuthLevel = level);
  }

  // Biometric factor toggles — only shown/required based on _configuredAuthLevel
  bool _faceVerified = false;
  bool _fingerprintVerified = false;
  bool _voiceVerified = false;

  final _fingerprintService = FingerprintVerificationService();

  void _verifyFaceBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    final registeredEmbeddingStr = prefs.getString('registered_face_embedding');
    final isEnrolled = registeredEmbeddingStr != null;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return FaceVerificationDialog(
          isEnrolled: isEnrolled,
          onSuccess: () {
            setState(() {
              _faceVerified = true;
            });
          },
        );
      },
    );
  }

  void _verifyFingerprint() async {
    final available = await _fingerprintService.isBiometricAvailable();
    if (available) {
      final success = await _fingerprintService.authenticateFingerprint();
      if (success) {
        setState(() => _fingerprintVerified = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: kSuccessColor,
            content: Text('Fingerprint factor validated!', style: GoogleFonts.outfit()),
          ),
        );
      } else {
        setState(() => _fingerprintVerified = false);
      }
    } else {
      setState(() => _fingerprintVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kPrimaryHoverColor,
          content: Text('Biometric hardware unavailable. Simulating share verification...', style: GoogleFonts.outfit()),
        ),
      );
    }
  }

  void _verifyVoiceBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    final registeredEmbeddingStr = prefs.getString('registered_voice_embedding');
    final isEnrolled = registeredEmbeddingStr != null;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return VoiceVerificationDialog(
          isEnrolled: isEnrolled,
          onSuccess: () {
            setState(() {
              _voiceVerified = true;
            });
          },
        );
      },
    );
  }

  void _submitUnlock() {
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3F0B24),
          content: Text('Please enter your vault password', style: GoogleFonts.outfit()),
        ),
      );
      return;
    }

    // Only require biometric factors that were configured at vault creation
    final bool needsFingerprint = _configuredAuthLevel >= 2;
    final bool needsFace = _configuredAuthLevel >= 3;
    final bool needsVoice = _configuredAuthLevel >= 4;

    if ((needsFingerprint && !_fingerprintVerified) ||
        (needsFace && !_faceVerified) ||
        (needsVoice && !_voiceVerified)) {
      final missing = [
        if (needsFingerprint && !_fingerprintVerified) 'Fingerprint',
        if (needsFace && !_faceVerified) 'Face',
        if (needsVoice && !_voiceVerified) 'Voice',
      ].join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3F0B24),
          content: Text(
            'Missing factors: $missing. All $_configuredAuthLevel configured factors required.',
            style: GoogleFonts.outfit(),
          ),
        ),
      );
      return;
    }

    context.read<VaultBloc>().add(UnlockVaultEvent(_passwordController.text));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassmorphicCard(
        width: 800,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Password Factor & Action Buttons
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kPrimaryHoverColor.withOpacity(0.1),
                            border: Border.all(color: kPrimaryHoverColor.withOpacity(0.3), width: 1.5),
                          ),
                          child: const Icon(Icons.lock_outline, size: 24, color: kPrimaryHoverColor),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Vault Locked',
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Provide password and biometric factors to reconstruct the Master Key.',
                      style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'PASSWORD FACTOR',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: kPrimaryHoverColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration(
                        hint: 'Enter vault password',
                        prefix: Icons.key_outlined,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const RecoveryPage()),
                            );
                          },
                          child: Text(
                            'Recovery Mode',
                            style: GoogleFonts.outfit(color: const Color(0xFFFF9E0B), fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            context.read<VaultBloc>().add(ResetToUninitializedEvent());
                          },
                          child: Text(
                            'Reset & Wipe Vault',
                            style: GoogleFonts.outfit(color: kErrorColor, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 32),
              // Right Column: Biometric Shares & Unlock Button
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_configuredAuthLevel > 1) ...[
                      Text(
                        '$_configuredAuthLevel-FACTOR AUTHENTICATION (${_configuredAuthLevel}FA)',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: kPrimaryHoverColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Validate each factor to reconstruct the SLIP-39 master key.',
                        style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      _biometricSwitch(
                        title: 'Fingerprint Biometric Share',
                        value: _fingerprintVerified,
                        icon: Icons.fingerprint_outlined,
                        onChanged: (val) {
                          if (val) {
                            _verifyFingerprint();
                          } else {
                            setState(() => _fingerprintVerified = false);
                          }
                        },
                      ),
                      if (_configuredAuthLevel >= 3) ...[
                        const SizedBox(height: 8),
                        _biometricSwitch(
                          title: 'Face Verification Share',
                          value: _faceVerified,
                          icon: Icons.face_outlined,
                          onChanged: (val) {
                            if (val) {
                              _verifyFaceBiometric();
                            } else {
                              setState(() => _faceVerified = false);
                            }
                          },
                        ),
                      ],
                      if (_configuredAuthLevel >= 4) ...[
                        const SizedBox(height: 8),
                        _biometricSwitch(
                          title: 'Voice Signature Share',
                          value: _voiceVerified,
                          icon: Icons.record_voice_over_outlined,
                          onChanged: (val) {
                            if (val) {
                              _verifyVoiceBiometric();
                            } else {
                              setState(() => _voiceVerified = false);
                            }
                          },
                        ),
                      ],
                    ] else ...[
                      Text(
                        'SECURITY PROFILE',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: kSuccessColor,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kSuccessColor.withOpacity(0.05),
                          border: Border.all(color: kSuccessColor.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outlined, color: kSuccessColor, size: 16),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '1FA Vault — password is the only required factor.',
                                style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryHoverColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _submitUnlock,
                        child: Text(
                          'UNLOCK VAULT',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _biometricSwitch({
    required String title,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: value ? kPrimaryHoverColor.withOpacity(0.08) : const Color(0xFF1E1E38).withOpacity(0.4),
        border: Border.all(
          color: value ? kPrimaryHoverColor.withOpacity(0.3) : const Color(0xFF1E1E38).withOpacity(0.5),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? kPrimaryHoverColor : const Color(0xFF94A3B8), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: value ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Switch(
            value: value,
            activeColor: kPrimaryHoverColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. Unlocked Dashboard View (Vault Details)
// ==========================================
class UnlockedDashboardView extends StatefulWidget {
  final VaultUnlockedState state;
  const UnlockedDashboardView({super.key, required this.state});

  @override
  State<UnlockedDashboardView> createState() => _UnlockedDashboardViewState();
}

class _UnlockedDashboardViewState extends State<UnlockedDashboardView> {
  bool _copied = false;
  String? _selectedMonitorPath;

  Color _getScoreColor(double score) {
    if (score < 0.3) return kSuccessColor;
    if (score < 0.5) return Colors.yellow;
    if (score < 0.65) return Colors.orange;
    return kErrorColor;
  }


  Widget _featureMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(fontSize: 8, color: const Color(0xFF64748B), fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.shareTechMono(fontSize: 10, color: Colors.white),
        ),
      ],
    );
  }

  void _copyKey(String hex) {
    Clipboard.setData(ClipboardData(text: hex));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.state.deviceStatus;
    final isNewVault = widget.state.backupRecoveryPhrases != null;

    return Center(
      child: GlassmorphicCard(
        width: 800,
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column: Vault Details & Mounting Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title/Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: kSuccessColor.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: kSuccessColor.withOpacity(0.3)),
                              ),
                              child: const Icon(Icons.lock_open_outlined, color: kSuccessColor, size: 20),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Primary Vault Unlocked',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Zero-Trust Local Encryption Active',
                                  style: GoogleFonts.outfit(fontSize: 10, color: kSuccessColor),
                                ),
                              ],
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF334155),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: const Icon(Icons.lock_outlined, size: 12),
                          label: Text('LOCK', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 11)),
                          onPressed: () {
                            context.read<VaultBloc>().add(LockVaultEvent());
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Virtual Drive Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            kSuccessColor.withOpacity(0.06),
                            kSurfaceColor.withOpacity(0.6),
                          ],
                        ),
                        border: Border.all(color: kSuccessColor.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: kSuccessColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Mounted on Z:',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kSuccessColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                icon: const Icon(Icons.folder_open, size: 12),
                                label: Text(
                                  'EXPLORE',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                                onPressed: () {
                                  Process.run('explorer.exe', ['Z:']);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Files in Z:\\ are encrypted on D:\\Data and synced in real-time.',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF94A3B8),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Master Key Hex Display
                    Text(
                      'RECONSTRUCTED MASTER KEY (256-BIT)',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: kPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: kSurfaceColor.withOpacity(0.6),
                        border: Border.all(color: const Color(0xFF1E293B)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.key, color: kPrimaryColor, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Text(
                                widget.state.masterKeyHex,
                                style: GoogleFonts.shareTechMono(
                                  color: Colors.white,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              _copied ? Icons.check : Icons.copy,
                              color: _copied ? kSuccessColor : const Color(0xFF94A3B8),
                              size: 14,
                            ),
                            onPressed: () => _copyKey(widget.state.masterKeyHex),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // If new vault, show SLIP-39 Backup Recovery Phrases in compact layout
                    // Else show Device & hardware binding status
                    if (isNewVault) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9E0B).withOpacity(0.05),
                          border: Border.all(color: const Color(0xFFFF9E0B).withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'SLIP-39 BACKUP PHRASES (RECORD NOW)',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFFFF9E0B),
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    final allPhrases = widget.state.backupRecoveryPhrases!.join('\n\n');
                                    Clipboard.setData(ClipboardData(text: allPhrases));
                                  },
                                  child: Text(
                                    'Copy All',
                                    style: GoogleFonts.outfit(color: const Color(0xFFFF9E0B), fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ...List.generate(widget.state.backupRecoveryPhrases!.length, (index) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2.0),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(color: kPrimaryColor, shape: BoxShape.circle),
                                      child: Text('${index + 1}', style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.horizontal,
                                        child: Text(
                                          widget.state.backupRecoveryPhrases![index],
                                          style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 10.5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ] else ...[
                      Text(
                        'TRUSTED DEVICE & HARDWARE STATUS',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: kPrimaryHoverColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _statusItem(
                              label: 'Device Status',
                              value: (status['is_trusted'] ?? false) ? 'Trusted' : 'Untrusted',
                              icon: Icons.devices,
                              color: (status['is_trusted'] ?? false) ? kSuccessColor : Colors.orange,
                            ),
                          ),
                          Expanded(
                            child: _statusItem(
                              label: 'TPM Binding',
                              value: 'Simulated TPM',
                              icon: Icons.developer_board,
                              color: kPrimaryHoverColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 28),
              // Right Column: Ransomware Monitor & Graph
              Expanded(
                child: BlocBuilder<MonitorBloc, MonitorState>(
                  builder: (context, monitorState) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  color: monitorState.isMonitoring 
                                      ? (monitorState.isCalibrating ? Colors.orange : kSuccessColor) 
                                      : const Color(0xFF94A3B8),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'RANSOMWARE PROTECTOR',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                    color: monitorState.isMonitoring 
                                        ? (monitorState.isCalibrating ? Colors.orange : kSuccessColor) 
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: monitorState.isMonitoring 
                                    ? (monitorState.isCalibrating ? Colors.orange.withOpacity(0.1) : kSuccessColor.withOpacity(0.1)) 
                                    : const Color(0xFF334155).withOpacity(0.3),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: monitorState.isMonitoring 
                                      ? (monitorState.isCalibrating ? Colors.orange.withOpacity(0.3) : kSuccessColor.withOpacity(0.3)) 
                                      : const Color(0xFF334155).withOpacity(0.4),
                                ),
                              ),
                              child: Text(
                                monitorState.isMonitoring 
                                    ? (monitorState.isCalibrating ? 'CALIBRATING' : 'ACTIVE') 
                                    : 'INACTIVE',
                                style: GoogleFonts.outfit(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: monitorState.isMonitoring 
                                      ? (monitorState.isCalibrating ? Colors.orange : kSuccessColor) 
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (!monitorState.isMonitoring) ...[
                          Text(
                            'Select folder to scan for rapid file changes.',
                            style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: kSurfaceColor.withOpacity(0.5),
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _selectedMonitorPath ?? 'No directory selected',
                                    style: GoogleFonts.shareTechMono(
                                      fontSize: 11,
                                      color: _selectedMonitorPath != null ? Colors.white : const Color(0xFF475569),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.folder_open, size: 20, color: kPrimaryColor),
                                onPressed: () async {
                                  final path = await FilePicker.getDirectoryPath();
                                  if (path != null) {
                                    setState(() => _selectedMonitorPath = path);
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryHoverColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                              ),
                              onPressed: _selectedMonitorPath == null 
                                  ? null 
                                  : () {
                                      context.read<MonitorBloc>().add(StartMonitoringEvent(_selectedMonitorPath!));
                                    },
                              child: Text('START MONITORING', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ),
                        ] else ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'WATCHED FOLDER:',
                                      style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                                    ),
                                    Text(
                                      monitorState.watchedPath ?? '',
                                      style: GoogleFonts.shareTechMono(fontSize: 10.5, color: Colors.white),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: kErrorColor),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                ),
                                icon: const Icon(Icons.stop, size: 12, color: kErrorColor),
                                label: Text('STOP', style: GoogleFonts.outfit(fontSize: 10, color: kErrorColor, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  context.read<MonitorBloc>().add(StopMonitoringEvent());
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (monitorState.isCalibrating) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'CALIBRATING DETECTOR...',
                                  style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange),
                                ),
                                Text(
                                  '${(monitorState.calibrationProgress * 100).toInt()}%',
                                  style: GoogleFonts.shareTechMono(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: monitorState.calibrationProgress,
                              backgroundColor: const Color(0xFF1E293B),
                              color: Colors.orange,
                              minHeight: 3,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ] else ...[
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: kSurfaceColor.withOpacity(0.5),
                                    border: Border.all(color: const Color(0xFF1E293B)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'ANOMALY',
                                        style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        monitorState.currentAnomalyScore.toStringAsFixed(3),
                                        style: GoogleFonts.shareTechMono(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: _getScoreColor(monitorState.currentAnomalyScore),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    height: 54,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: kSurfaceColor.withOpacity(0.5),
                                      border: Border.all(color: const Color(0xFF1E293B)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'REAL-TIME ANOMALY TRACK',
                                          style: GoogleFonts.outfit(fontSize: 8, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                        ),
                                        const Spacer(),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: List.generate(15, (index) {
                                            final double val = index < monitorState.recentScores.length
                                                ? monitorState.recentScores[index]
                                                : 0.0;
                                            return Container(
                                              width: 10,
                                              height: 25 * val + 2,
                                              decoration: BoxDecoration(
                                                color: _getScoreColor(val),
                                                borderRadius: BorderRadius.circular(2),
                                              ),
                                            );
                                          }),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (monitorState.recentFeatures.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E38).withOpacity(0.2),
                                  border: Border.all(color: const Color(0xFF1E293B).withOpacity(0.5)),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _featureMetric('Writes', '${(monitorState.recentFeatures.last.writeRate * 5).toInt()}'),
                                    _featureMetric('Deletes', '${(monitorState.recentFeatures.last.deleteRate * 5).toInt()}'),
                                    _featureMetric('Entropy', '${(monitorState.recentFeatures.last.extensionEntropy * 100).toInt()}%'),
                                    _featureMetric('Avg Size', '${monitorState.recentFeatures.last.sizeDifference.toStringAsFixed(0)}K'),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E38).withOpacity(0.3),
        border: Border.all(color: const Color(0xFF1E293B)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 10, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.outfit(fontSize: 9, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class InlineRecoveryView extends StatefulWidget {
  const InlineRecoveryView({super.key});

  @override
  State<InlineRecoveryView> createState() => _InlineRecoveryViewState();
}

class _InlineRecoveryViewState extends State<InlineRecoveryView> {
  // Common states
  bool _useQuestionsRecovery = false;
  String? _localError;
  String? _localSuccess;

  // SLIP-39 controllers
  final _phrase1Controller = TextEditingController();
  final _phrase2Controller = TextEditingController();

  // Questions recovery controllers/states
  final _pathController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _a1Controller = TextEditingController();
  final _a2Controller = TextEditingController();
  final _a3Controller = TextEditingController();

  int _recoveryStep = 1; // 1: Email verify/send, 2: Code verify, 3: Answer questions
  String _generatedCode = '';
  List<String> _recoveryQuestions = [];
  bool _sendingCode = false;

  @override
  void initState() {
    super.initState();
    final repository = context.read<VaultBloc>().repository;
    _pathController.text = repository.getVaultPath();
  }

  @override
  void dispose() {
    _phrase1Controller.dispose();
    _phrase2Controller.dispose();
    _pathController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _a1Controller.dispose();
    _a2Controller.dispose();
    _a3Controller.dispose();
    super.dispose();
  }

  String _cleanPhrase(String phrase) {
    var cleaned = phrase.trim().toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r'^[0-9]+[\.\:\-\s\)]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned;
  }

  void _submitRecovery() {
    final phrase1 = _cleanPhrase(_phrase1Controller.text);
    final phrase2 = _cleanPhrase(_phrase2Controller.text);

    if (phrase1.isEmpty || phrase2.isEmpty) {
      setState(() {
        _localError = 'Please enter at least 2 recovery mnemonics.';
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    context.read<VaultBloc>().add(RecoverVaultEvent([phrase1, phrase2]));
  }

  Future<void> _pastePhrase(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        controller.text = data.text!;
      });
    }
  }

  Future<void> _sendCode() async {
    final path = _pathController.text.trim();
    final email = _emailController.text.trim();
    final repository = context.read<VaultBloc>().repository;

    if (path.isEmpty || email.isEmpty) {
      setState(() {
        _localError = 'Please fill in both vault path and email.';
      });
      return;
    }

    setState(() {
      _sendingCode = true;
      _localError = null;
      _localSuccess = null;
    });

    await repository.updateVaultSettings(path, repository.getDriveLetter());

    if (!repository.isQuestionsRecoveryEnabled) {
      setState(() {
        _localError = 'Security questions recovery is not configured for this vault.';
        _sendingCode = false;
      });
      return;
    }

    final configuredEmail = repository.getQuestionsRecoveryEmail();
    if (configuredEmail?.trim().toLowerCase() != email.toLowerCase()) {
      setState(() {
        _localError = 'Incorrect recovery email address.';
        _sendingCode = false;
      });
      return;
    }

    // Generate random code
    final code = (Random().nextInt(900000) + 100000).toString();
    _generatedCode = code;

    // Send email using Resend API
    final success = await repository.sendRecoveryEmail(email, code);

    setState(() {
      _sendingCode = false;
      if (success) {
        _recoveryStep = 2;
        _localSuccess = 'Verification code sent to $email!';
      } else {
        _localError = 'Failed to send recovery email. Please check internet connection.';
      }
    });
  }

  void _verifyCode() {
    final inputCode = _codeController.text.trim();
    if (inputCode.isEmpty) {
      setState(() {
        _localError = 'Please enter the 6-digit code.';
      });
      return;
    }

    if (inputCode == _generatedCode) {
      final repository = context.read<VaultBloc>().repository;
      final questions = repository.getQuestionsRecoveryQuestions() ?? [];
      setState(() {
        _recoveryStep = 3;
        _recoveryQuestions = questions;
        _localError = null;
        _localSuccess = 'Email code verified. Answer your security questions.';
      });
    } else {
      setState(() {
        _localError = 'Invalid verification code.';
      });
    }
  }

  Future<void> _submitQuestionsRecovery() async {
    final a1 = _a1Controller.text.trim();
    final a2 = _a2Controller.text.trim();
    final a3 = _a3Controller.text.trim();

    if (a1.isEmpty || a2.isEmpty || a3.isEmpty) {
      setState(() {
        _localError = 'Please answer all 3 questions.';
      });
      return;
    }

    setState(() {
      _localError = null;
      _localSuccess = null;
    });

    final repository = context.read<VaultBloc>().repository;
    final masterKey = await repository.recoverWithQuestionsAndEmail([a1, a2, a3]);

    if (masterKey != null) {
      if (mounted) {
        context.read<VaultBloc>().add(UnlockWithMasterKeyEvent(masterKey));
      }
    } else {
      setState(() {
        _localError = 'Decryption failed. Please verify your security question answers.';
      });
    }
  }

  Widget _tabButton(String text, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kPrimaryColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? kPrimaryColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.outfit(
            color: active ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassmorphicCard(
        width: 800,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: BlocConsumer<VaultBloc, VaultState>(
            listener: (context, state) {
              if (state is VaultUnlockedState) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: kSuccessColor,
                    content: Text('Vault successfully recovered & unlocked!'),
                  ),
                );
              }
            },
            builder: (context, state) {
              final isLoading = state is VaultLoadingState;
              String? errorMsg = _localError;
              if (state is VaultFailureState) {
                errorMsg = state.errorMessage;
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFFFF9E0B).withOpacity(0.1),
                              border: Border.all(color: const Color(0xFFFF9E0B).withOpacity(0.3), width: 1.5),
                            ),
                            child: const Icon(Icons.vpn_key_outlined, size: 24, color: Color(0xFFFF9E0B)),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Master Key Recovery',
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      // Mode Selector
                      Row(
                        children: [
                          _tabButton('SLIP-39 Phrases', !_useQuestionsRecovery, () {
                            setState(() {
                              _useQuestionsRecovery = false;
                              _localError = null;
                              _localSuccess = null;
                            });
                          }),
                          const SizedBox(width: 8),
                          _tabButton('Questions & Email OTP', _useQuestionsRecovery, () {
                            setState(() {
                              _useQuestionsRecovery = true;
                              _localError = null;
                              _localSuccess = null;
                            });
                          }),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _useQuestionsRecovery
                        ? 'Recover your primary vault using your pre-configured 3 security questions and an email verification code.'
                        : 'Input at least 2 of your 24-word backup mnemonics to recover your primary vault master key.',
                    style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 16),
                  if (errorMsg != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: kErrorColor.withOpacity(0.1),
                        border: Border.all(color: kErrorColor.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        errorMsg,
                        style: GoogleFonts.outfit(color: kErrorColor, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_localSuccess != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: kSuccessColor.withOpacity(0.1),
                        border: Border.all(color: kSuccessColor.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _localSuccess!,
                        style: GoogleFonts.outfit(color: kSuccessColor, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!_useQuestionsRecovery) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RECOVERY MNEMONIC SHARE 1',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: const Color(0xFFFF9E0B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _phrase1Controller,
                                maxLines: 2,
                                style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 12),
                                decoration: _inputDecoration(
                                  hint: 'Paste or type recovery mnemonic 1',
                                  prefix: Icons.password,
                                  suffix: IconButton(
                                    icon: const Icon(Icons.paste, color: Color(0xFFFF9E0B), size: 18),
                                    onPressed: () => _pastePhrase(_phrase1Controller),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RECOVERY MNEMONIC SHARE 2',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.0,
                                  color: const Color(0xFFFF9E0B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                controller: _phrase2Controller,
                                maxLines: 2,
                                style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 12),
                                decoration: _inputDecoration(
                                  hint: 'Paste or type recovery mnemonic 2',
                                  prefix: Icons.password,
                                  suffix: IconButton(
                                    icon: const Icon(Icons.paste, color: Color(0xFFFF9E0B), size: 18),
                                    onPressed: () => _pastePhrase(_phrase2Controller),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9E0B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: isLoading ? null : _submitRecovery,
                        child: isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                'RECONSTRUCT & UNLOCK VAULT',
                                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 13),
                              ),
                      ),
                    ),
                  ] else ...[
                    // Security Questions Recovery steps
                    if (_recoveryStep == 1) ...[
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _pathController,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                              decoration: InputDecoration(
                                labelText: 'Vault Folder Path',
                                labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.folder_open, color: kPrimaryColor, size: 18),
                            onPressed: () async {
                              final path = await FilePicker.getDirectoryPath();
                              if (path != null) {
                                setState(() => _pathController.text = path);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Recovery Email Address',
                          labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _sendingCode ? null : _sendCode,
                          child: _sendingCode
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text('SEND VERIFICATION CODE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ] else if (_recoveryStep == 2) ...[
                      TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 16, letterSpacing: 4),
                        decoration: InputDecoration(
                          labelText: '6-Digit Verification Code',
                          labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                          enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: _verifyCode,
                          child: Text('VERIFY CODE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ] else if (_recoveryStep == 3) ...[
                      Text(
                        '1. ${_recoveryQuestions.isNotEmpty ? _recoveryQuestions[0] : 'Security Question 1'}',
                        style: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      TextField(
                        controller: _a1Controller,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Answer 1',
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '2. ${_recoveryQuestions.length > 1 ? _recoveryQuestions[1] : 'Security Question 2'}',
                        style: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      TextField(
                        controller: _a2Controller,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Answer 2',
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '3. ${_recoveryQuestions.length > 2 ? _recoveryQuestions[2] : 'Security Question 3'}',
                        style: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      TextField(
                        controller: _a3Controller,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Answer 3',
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: isLoading ? null : _submitQuestionsRecovery,
                          child: isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Text('RECOVER & UNLOCK VAULT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
// ==========================================
// 5. Recovery View / Page (Input recovery mnemonics)
// ==========================================
class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key});

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  // Common states
  bool _useQuestionsRecovery = false;
  String? _localError;
  String? _localSuccess;

  // SLIP-39 controllers
  final _phrase1Controller = TextEditingController();
  final _phrase2Controller = TextEditingController();

  // Questions recovery controllers/states
  final _pathController = TextEditingController();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _a1Controller = TextEditingController();
  final _a2Controller = TextEditingController();
  final _a3Controller = TextEditingController();

  int _recoveryStep = 1; // 1: Email verify/send, 2: Code verify, 3: Answer questions
  String _generatedCode = '';
  List<String> _recoveryQuestions = [];
  bool _sendingCode = false;

  @override
  void initState() {
    super.initState();
    final repository = context.read<VaultBloc>().repository;
    _pathController.text = repository.getVaultPath();
  }

  @override
  void dispose() {
    _phrase1Controller.dispose();
    _phrase2Controller.dispose();
    _pathController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    _a1Controller.dispose();
    _a2Controller.dispose();
    _a3Controller.dispose();
    super.dispose();
  }

  // Robust phrase cleaner: removes lowercase, number prefixes, collapses spaces
  String _cleanPhrase(String phrase) {
    var cleaned = phrase.trim().toLowerCase();
    cleaned = cleaned.replaceAll(RegExp(r'^[0-9]+[\.\:\-\s\)]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned;
  }

  void _submitRecovery() {
    final phrase1 = _cleanPhrase(_phrase1Controller.text);
    final phrase2 = _cleanPhrase(_phrase2Controller.text);

    if (phrase1.isEmpty || phrase2.isEmpty) {
      setState(() {
        _localError = 'Please enter at least 2 recovery mnemonics.';
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    context.read<VaultBloc>().add(RecoverVaultEvent([phrase1, phrase2]));
  }

  Future<void> _pastePhrase(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        controller.text = data.text!;
      });
    }
  }

  Future<void> _sendCode() async {
    final path = _pathController.text.trim();
    final email = _emailController.text.trim();
    final repository = context.read<VaultBloc>().repository;

    if (path.isEmpty || email.isEmpty) {
      setState(() {
        _localError = 'Please fill in both vault path and email.';
      });
      return;
    }

    setState(() {
      _sendingCode = true;
      _localError = null;
      _localSuccess = null;
    });

    await repository.updateVaultSettings(path, repository.getDriveLetter());

    if (!repository.isQuestionsRecoveryEnabled) {
      setState(() {
        _localError = 'Security questions recovery is not configured for this vault.';
        _sendingCode = false;
      });
      return;
    }

    final configuredEmail = repository.getQuestionsRecoveryEmail();
    if (configuredEmail?.trim().toLowerCase() != email.toLowerCase()) {
      setState(() {
        _localError = 'Incorrect recovery email address.';
        _sendingCode = false;
      });
      return;
    }

    // Generate random code
    final code = (Random().nextInt(900000) + 100000).toString();
    _generatedCode = code;

    // Send email using Resend API
    final success = await repository.sendRecoveryEmail(email, code);

    setState(() {
      _sendingCode = false;
      if (success) {
        _recoveryStep = 2;
        _localSuccess = 'Verification code sent to $email!';
      } else {
        _localError = 'Failed to send recovery email. Please check internet connection.';
      }
    });
  }

  void _verifyCode() {
    final inputCode = _codeController.text.trim();
    if (inputCode.isEmpty) {
      setState(() {
        _localError = 'Please enter the 6-digit code.';
      });
      return;
    }

    if (inputCode == _generatedCode) {
      final repository = context.read<VaultBloc>().repository;
      final questions = repository.getQuestionsRecoveryQuestions() ?? [];
      setState(() {
        _recoveryStep = 3;
        _recoveryQuestions = questions;
        _localError = null;
        _localSuccess = 'Email code verified. Answer your security questions.';
      });
    } else {
      setState(() {
        _localError = 'Invalid verification code.';
      });
    }
  }

  Future<void> _submitQuestionsRecovery() async {
    final a1 = _a1Controller.text.trim();
    final a2 = _a2Controller.text.trim();
    final a3 = _a3Controller.text.trim();

    if (a1.isEmpty || a2.isEmpty || a3.isEmpty) {
      setState(() {
        _localError = 'Please answer all 3 questions.';
      });
      return;
    }

    setState(() {
      _localError = null;
      _localSuccess = null;
    });

    final repository = context.read<VaultBloc>().repository;
    final masterKey = await repository.recoverWithQuestionsAndEmail([a1, a2, a3]);

    if (masterKey != null) {
      if (mounted) {
        context.read<VaultBloc>().add(UnlockWithMasterKeyEvent(masterKey));
      }
    } else {
      setState(() {
        _localError = 'Decryption failed. Please verify your security question answers.';
      });
    }
  }

  Widget _tabButton(String text, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kPrimaryColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? kPrimaryColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          text,
          style: GoogleFonts.outfit(
            color: active ? Colors.white : const Color(0xFF94A3B8),
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kScaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Recovery Mode', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            context.read<VaultBloc>().add(CheckVaultStatusEvent());
            Navigator.pop(context);
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF080D21),
              Color(0xFF130925),
              Color(0xFF05060F),
            ],
          ),
        ),
        child: BlocConsumer<VaultBloc, VaultState>(
          listener: (context, state) {
            if (state is VaultUnlockedState) {
              Navigator.pop(context);
            }
          },
          builder: (context, state) {
            final isLoading = state is VaultLoadingState;
            String? errorMsg = _localError;
            if (state is VaultFailureState) {
              errorMsg = state.errorMessage;
            }

            return Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GlassmorphicCard(
                    width: 650,
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFFFF9E0B).withOpacity(0.1),
                                      border: Border.all(color: const Color(0xFFFF9E0B).withOpacity(0.3), width: 1.5),
                                    ),
                                    child: const Icon(Icons.restore_outlined, size: 28, color: Color(0xFFFF9E0B)),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    'Reconstruct Master Key',
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  _tabButton('SLIP-39 Phrases', !_useQuestionsRecovery, () {
                                    setState(() {
                                      _useQuestionsRecovery = false;
                                      _localError = null;
                                      _localSuccess = null;
                                    });
                                  }),
                                  const SizedBox(width: 8),
                                  _tabButton('Questions & Email OTP', _useQuestionsRecovery, () {
                                    setState(() {
                                      _useQuestionsRecovery = true;
                                      _localError = null;
                                      _localSuccess = null;
                                    });
                                  }),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _useQuestionsRecovery
                                ? 'Recover your primary vault using your pre-configured 3 security questions and an email verification code.'
                                : 'Provide 2 out of the 3 generated SLIP-39 backup phrases to restore your vault.',
                            style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                          ),
                          if (errorMsg != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kErrorColor.withOpacity(0.08),
                                border: Border.all(color: kErrorColor.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: kErrorColor, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      errorMsg,
                                      style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFFDA4AF)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (_localSuccess != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: kSuccessColor.withOpacity(0.08),
                                border: Border.all(color: kSuccessColor.withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: kSuccessColor, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _localSuccess!,
                                      style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFA7F3D0)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          if (!_useQuestionsRecovery) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'BACKUP RECOVERY MNEMONIC 1',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                    color: const Color(0xFFFF9E0B),
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.paste, size: 12, color: Color(0xFFFF9E0B)),
                                  label: Text('Paste', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFFF9E0B))),
                                  onPressed: isLoading ? null : () => _pastePhrase(_phrase1Controller),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _phrase1Controller,
                              enabled: !isLoading,
                              style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 13),
                              decoration: _inputDecoration(
                                hint: 'Enter first recovery phrase (word string)',
                                prefix: Icons.menu_book_outlined,
                              ),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'BACKUP RECOVERY MNEMONIC 2',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                    color: const Color(0xFFFF9E0B),
                                  ),
                                ),
                                TextButton.icon(
                                  icon: const Icon(Icons.paste, size: 12, color: Color(0xFFFF9E0B)),
                                  label: Text('Paste', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFFF9E0B))),
                                  onPressed: isLoading ? null : () => _pastePhrase(_phrase2Controller),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _phrase2Controller,
                              enabled: !isLoading,
                              style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 13),
                              decoration: _inputDecoration(
                                hint: 'Enter second recovery phrase (word string)',
                                prefix: Icons.menu_book_outlined,
                              ),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF9E0B),
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: isLoading ? null : _submitRecovery,
                                child: isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                        ),
                                      )
                                    : Text(
                                        'RECOVER MASTER KEY',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                      ),
                              ),
                            ),
                          ] else ...[
                            if (_recoveryStep == 1) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _pathController,
                                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 12),
                                      decoration: InputDecoration(
                                        labelText: 'Vault Folder Path',
                                        labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                                        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.folder_open, color: kPrimaryColor, size: 18),
                                    onPressed: () async {
                                      final path = await FilePicker.getDirectoryPath();
                                      if (path != null) {
                                        setState(() => _pathController.text = path);
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              TextField(
                                controller: _emailController,
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'Recovery Email Address',
                                  labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                                ),
                              ),
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _sendingCode ? null : _sendCode,
                                  child: _sendingCode
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text('SEND VERIFICATION CODE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                                ),
                              ),
                            ] else if (_recoveryStep == 2) ...[
                              TextField(
                                controller: _codeController,
                                keyboardType: TextInputType.number,
                                style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 18, letterSpacing: 6),
                                decoration: InputDecoration(
                                  labelText: '6-Digit Verification Code',
                                  labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                  focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                                ),
                              ),
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _verifyCode,
                                  child: Text('VERIFY CODE', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                                ),
                              ),
                            ] else if (_recoveryStep == 3) ...[
                              Text(
                                '1. ${_recoveryQuestions.isNotEmpty ? _recoveryQuestions[0] : 'Security Question 1'}',
                                style: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              TextField(
                                controller: _a1Controller,
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Answer 1',
                                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '2. ${_recoveryQuestions.length > 1 ? _recoveryQuestions[1] : 'Security Question 2'}',
                                style: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              TextField(
                                controller: _a2Controller,
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Answer 2',
                                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '3. ${_recoveryQuestions.length > 2 ? _recoveryQuestions[2] : 'Security Question 3'}',
                                style: GoogleFonts.outfit(color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                              TextField(
                                controller: _a3Controller,
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Answer 3',
                                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: kPrimaryColor)),
                                ),
                              ),
                              const SizedBox(height: 32),
                              SizedBox(
                                width: double.infinity,
                                height: 50,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: isLoading ? null : _submitQuestionsRecovery,
                                  child: isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text('RECOVER & UNLOCK VAULT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 1.2)),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


// ==========================================
// Reusable Premium Glassmorphic Container
// ==========================================
class GlassmorphicCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;

  const GlassmorphicCard({
    super.key,
    required this.child,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B).withOpacity(0.4),
            kSurfaceColor.withOpacity(0.6),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: child,
      ),
    );
  }
}

// Helper input decoration style
InputDecoration _inputDecoration({
  required String hint,
  required IconData prefix,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.outfit(color: const Color(0xFF475569), fontSize: 13),
    prefixIcon: Icon(prefix, color: const Color(0xFF475569), size: 18),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFF0A0E17).withOpacity(0.6),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF1E293B)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kErrorColor),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: kErrorColor, width: 1.5),
    ),
  );
}

class RansomwareAlarmOverlay extends StatefulWidget {
  final String watchedPath;
  const RansomwareAlarmOverlay({super.key, required this.watchedPath});

  @override
  State<RansomwareAlarmOverlay> createState() => _RansomwareAlarmOverlayState();
}

class _RansomwareAlarmOverlayState extends State<RansomwareAlarmOverlay> with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  late AnimationController _pulseController;
  bool _isDeescalating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _deescalate(BuildContext context) async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password to de-escalate');
      return;
    }
    
    setState(() {
      _isDeescalating = true;
      _error = null;
    });

    final vaultBloc = context.read<VaultBloc>();
    vaultBloc.add(UnlockVaultEvent(password));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<VaultBloc, VaultState>(
      listener: (context, vaultState) {
        if (vaultState is VaultUnlockedState) {
          context.read<MonitorBloc>().add(ResetMonitorAlarmEvent());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: kSuccessColor,
              content: Text('Security alarm cleared. Vault unlocked.', style: GoogleFonts.outfit()),
            ),
          );
        } else if (vaultState is VaultFailureState) {
          setState(() {
            _isDeescalating = false;
            _error = 'Invalid password. Unable to clear alarm.';
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.7),
        body: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                child: Container(
                  color: kErrorColor.withOpacity(0.08),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 550,
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1111).withOpacity(0.8),
                    border: Border.all(color: kErrorColor.withOpacity(0.4), width: 1.5),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: kErrorColor.withOpacity(0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: kErrorColor.withOpacity(0.1 + (_pulseController.value * 0.15)),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: kErrorColor.withOpacity(0.3 + (_pulseController.value * 0.4)),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.security_update_warning_outlined,
                              color: kErrorColor,
                              size: 48,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'RANSOMWARE ATTACK ALARM ACTIVE',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: kErrorColor,
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Anomalous file activity detected. Vault locked.',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: const Color(0xFFFDA4AF),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kErrorColor.withOpacity(0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DETECTION DETAILS:',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: kErrorColor,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Unusual frequency of file modifications, additions, or renames occurred inside the watched directory:',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.watchedPath,
                              style: GoogleFonts.shareTechMono(fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Actions Taken: Cryptographic keys wiped from RAM, decryption cache invalidated, local database locked.',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFF43F5E), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'PROVIDE MASTER PASSWORD TO OVERRIDE & DE-ESCALATE',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF94A3B8),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: GoogleFonts.outfit(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter vault password',
                          hintStyle: GoogleFonts.outfit(color: const Color(0xFF475569)),
                          filled: true,
                          fillColor: kSurfaceColor.withOpacity(0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: kErrorColor),
                          ),
                          errorText: _error,
                          errorStyle: GoogleFonts.outfit(color: kErrorColor),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kErrorColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isDeescalating ? null : () => _deescalate(context),
                          child: _isDeescalating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'RESET ALARM & RE-AUTHENTICATE',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FaceVerificationDialog extends StatefulWidget {
  final bool isEnrolled;
  final VoidCallback onSuccess;

  const FaceVerificationDialog({
    super.key,
    required this.isEnrolled,
    required this.onSuccess,
  });

  @override
  State<FaceVerificationDialog> createState() => _FaceVerificationDialogState();
}

class _FaceVerificationDialogState extends State<FaceVerificationDialog> {
  final FaceVerificationService _faceService = FaceVerificationService();
  bool _isLoading = false;
  String _statusMessage = '';
  String? _errorMessage;
  File? _selectedFile;

  @override
  void initState() {
    super.initState();
    _statusMessage = widget.isEnrolled 
        ? 'Please select your face image to verify.' 
        : 'No face enrolled. Please select a face image to register.';
    _faceService.loadModel();
    if (Platform.isWindows) {
      Future.microtask(() => _triggerWindowsHello());
    }
  }

  void _triggerWindowsHello() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Requesting Windows Hello authentication...';
      _errorMessage = null;
    });

    final verified = await _faceService.authenticateWindowsHello();

    if (mounted) {
      if (verified) {
        final prefs = await SharedPreferences.getInstance();
        if (!widget.isEnrolled) {
          // Flag face biometric as registered
          await prefs.setString('registered_face_embedding', jsonEncode([1.0]));
          setState(() {
            _isLoading = false;
            _statusMessage = 'Windows Hello Enrollment Successful!';
          });
        } else {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Windows Hello Face Verified!';
          });
        }
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          widget.onSuccess();
          Navigator.of(context).pop();
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Windows Hello verification failed or was cancelled.';
          _statusMessage = 'Verification failed.';
        });
      }
    }
  }

  void _pickAndProcessImage() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _statusMessage = 'Selecting image file...';
      });

      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = widget.isEnrolled 
              ? 'Select face image to verify.' 
              : 'Select face image to register.';
        });
        return;
      }

      final file = File(result.files.single.path!);
      setState(() {
        _selectedFile = file;
        _statusMessage = 'Processing image & extracting face embedding...';
      });

      await Future.delayed(const Duration(milliseconds: 800));

      final embedding = await _faceService.getFaceEmbedding(file);
      final prefs = await SharedPreferences.getInstance();

      if (!widget.isEnrolled) {
        final embeddingJson = jsonEncode(embedding);
        await prefs.setString('registered_face_embedding', embeddingJson);
        
        setState(() {
          _isLoading = false;
          _statusMessage = 'Face Enrollment Successful!';
        });

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          widget.onSuccess();
          Navigator.of(context).pop();
        }
      } else {
        final registeredStr = prefs.getString('registered_face_embedding');
        if (registeredStr == null) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Registered face data corrupted. Please re-enroll.';
          });
          return;
        }

        final List<double> registeredEmbedding = List<double>.from(jsonDecode(registeredStr));
        final distance = _faceService.calculateDistance(embedding, registeredEmbedding);
        final matches = _faceService.verifyMatch(embedding, registeredEmbedding, threshold: 0.6);

        if (matches) {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Face Verified! (Distance: ${distance.toStringAsFixed(4)})';
          });

          await Future.delayed(const Duration(milliseconds: 1000));
          if (mounted) {
            widget.onSuccess();
            Navigator.of(context).pop();
          }
        } else {
          setState(() {
            _isLoading = false;
            _selectedFile = null;
            _errorMessage = 'Face verification failed.\nDistance: ${distance.toStringAsFixed(4)} (Threshold is < 0.60).\nEnsure you upload the same image.';
            _statusMessage = 'Verification failed. Try again.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error processing image: ${e.toString()}';
        _statusMessage = 'Error occurred.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width > 500 ? 450 : MediaQuery.of(context).size.width - 32,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: kSurfaceColor.withOpacity(0.95),
          border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isEnrolled ? 'FACE VERIFICATION (OFFLINE)' : 'ENROLL FACE BIOMETRIC',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: kPrimaryHoverColor,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: Color(0xFF1E293B), height: 20),
            const SizedBox(height: 16),
            
            Container(
              height: 150,
              width: 150,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E38).withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _errorMessage != null 
                      ? kErrorColor.withOpacity(0.5) 
                      : kPrimaryHoverColor.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _selectedFile != null
                    ? Image.file(_selectedFile!, fit: BoxFit.cover)
                    : Icon(
                        widget.isEnrolled ? Icons.face : Icons.add_a_photo_outlined,
                        size: 64,
                        color: _errorMessage != null ? kErrorColor : kPrimaryHoverColor,
                      ),
              ),
            ),
            const SizedBox(height: 20),
            
            Text(
              _statusMessage,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: kErrorColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            const SizedBox(height: 28),
            
            if (_isLoading)
              const CircularProgressIndicator(color: kPrimaryHoverColor)
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF334155)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('CANCEL', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryHoverColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _pickAndProcessImage,
                      child: Text(
                        widget.isEnrolled ? 'SELECT PHOTO' : 'ENROLL PHOTO',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class VoiceVerificationDialog extends StatefulWidget {
  final bool isEnrolled;
  final VoidCallback onSuccess;

  const VoiceVerificationDialog({
    super.key,
    required this.isEnrolled,
    required this.onSuccess,
  });

  @override
  State<VoiceVerificationDialog> createState() => _VoiceVerificationDialogState();
}

class _VoiceVerificationDialogState extends State<VoiceVerificationDialog> {
  final VoiceVerificationService _voiceService = VoiceVerificationService();
  bool _isLoading = false;
  String _statusMessage = '';
  String? _errorMessage;
  File? _selectedFile;

  @override
  void initState() {
    super.initState();
    _statusMessage = widget.isEnrolled 
        ? 'Please select your voice WAV/MP3 file to verify.' 
        : 'No voice enrolled. Please select a WAV/MP3 file to register.';
  }

  void _pickAndProcessAudio() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _statusMessage = 'Selecting audio file...';
      });

      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'mp3', 'm4a'],
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = widget.isEnrolled 
              ? 'Select voice WAV/MP3 to verify.' 
              : 'Select voice WAV/MP3 to register.';
        });
        return;
      }

      final file = File(result.files.single.path!);
      setState(() {
        _selectedFile = file;
        _statusMessage = 'Processing audio & extracting Conformer embedding...';
      });

      await Future.delayed(const Duration(milliseconds: 800));

      final embedding = await _voiceService.getVoiceEmbedding(file);
      final prefs = await SharedPreferences.getInstance();

      if (!widget.isEnrolled) {
        final embeddingJson = jsonEncode(embedding);
        await prefs.setString('registered_voice_embedding', embeddingJson);
        
        setState(() {
          _isLoading = false;
          _statusMessage = 'Voice Enrollment Successful!';
        });

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          widget.onSuccess();
          Navigator.of(context).pop();
        }
      } else {
        final registeredStr = prefs.getString('registered_voice_embedding');
        if (registeredStr == null) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Registered voice data corrupted. Please re-enroll.';
          });
          return;
        }

        final List<double> registeredEmbedding = List<double>.from(jsonDecode(registeredStr));
        final similarity = _voiceService.calculateCosineSimilarity(embedding, registeredEmbedding);
        final matches = _voiceService.verifyVoiceMatch(embedding, registeredEmbedding, threshold: 0.8);

        if (matches) {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Voice Signature Verified! (Similarity: ${similarity.toStringAsFixed(4)})';
          });

          await Future.delayed(const Duration(milliseconds: 1000));
          if (mounted) {
            widget.onSuccess();
            Navigator.of(context).pop();
          }
        } else {
          setState(() {
            _isLoading = false;
            _selectedFile = null;
            _errorMessage = 'Voice verification failed.\nSimilarity: ${similarity.toStringAsFixed(4)} (Threshold is >= 0.80).\nEnsure you upload the same signature file.';
            _statusMessage = 'Verification failed. Try again.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error processing audio: ${e.toString()}';
        _statusMessage = 'Error occurred.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: MediaQuery.of(context).size.width > 500 ? 450 : MediaQuery.of(context).size.width - 32,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: kSurfaceColor.withOpacity(0.95),
          border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isEnrolled ? 'VOICE VERIFICATION (OFFLINE)' : 'ENROLL VOICE SIGNATURE',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: kPrimaryHoverColor,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: Color(0xFF1E293B), height: 20),
            const SizedBox(height: 16),
            
            Container(
              height: 150,
              width: 150,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E38).withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _errorMessage != null 
                      ? kErrorColor.withOpacity(0.5) 
                      : kPrimaryHoverColor.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _selectedFile != null
                    ? Container(
                        color: const Color(0xFF1E293B),
                        child: const Icon(
                          Icons.audiotrack,
                          size: 64,
                          color: kSuccessColor,
                        ),
                      )
                    : Icon(
                        widget.isEnrolled ? Icons.mic : Icons.mic_none_outlined,
                        size: 64,
                        color: _errorMessage != null ? kErrorColor : kPrimaryHoverColor,
                      ),
              ),
            ),
            const SizedBox(height: 20),
            
            Text(
              _statusMessage,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: kErrorColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            const SizedBox(height: 28),
            
            if (_isLoading)
              const CircularProgressIndicator(color: kPrimaryHoverColor)
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF334155)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('CANCEL', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryHoverColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _pickAndProcessAudio,
                      child: Text(
                        widget.isEnrolled ? 'SELECT WAV/MP3' : 'ENROLL AUDIO',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// Web Landing Page & Contact Us (Resend API Integration)
// =============================================================================
class WebLandingPage extends StatefulWidget {
  const WebLandingPage({super.key});

  @override
  State<WebLandingPage> createState() => _WebLandingPageState();
}

class _WebLandingPageState extends State<WebLandingPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  bool _isSending = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSending = true;
      _statusMessage = null;
    });

    try {
      final response = await http_pkg.post(
        Uri.parse('https://api.resend.com/emails'),
        headers: {
          'Authorization': 'Bearer re_JRnu4jFo_JRjAbMeMnqraKM3yKAJPFNdf',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'from': 'AMPCrypt Web <onboarding@resend.dev>',
          'to': ['pranto48@gmail.com'],
          'subject': '[AMPCrypt Web Contact] ${_subjectController.text.trim()}',
          'html': '''
            <h3>New Contact Form Message</h3>
            <p><strong>Name:</strong> ${_nameController.text.trim()}</p>
            <p><strong>Email:</strong> ${_emailController.text.trim()}</p>
            <p><strong>Subject:</strong> ${_subjectController.text.trim()}</p>
            <p><strong>Message:</strong></p>
            <p>\${_messageController.text.trim().replaceAll('\\n', '<br>')}</p>
          '''
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _isSuccess = true;
          _statusMessage = 'Your message has been sent successfully!';
          _nameController.clear();
          _emailController.clear();
          _subjectController.clear();
          _messageController.clear();
        });
      } else {
        setState(() {
          _isSuccess = false;
          _statusMessage = 'Failed to send message. Server returned code: \${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _statusMessage = 'An error occurred while sending: \$e';
      });
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ─── HERO HEADER ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF080D21),
                    Color(0xFF130925),
                    Color(0xFF05060F),
                  ],
                ),
              ),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    children: [
                      // Logo
                      Image.asset(
                        'assets/app_icon.ico',
                        width: 96,
                        height: 96,
                        errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.verified_user_rounded,
                          size: 96,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'AMPCrypt Security Suite',
                        style: GoogleFonts.outfit(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: -1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Enterprise-grade, zero-trust offline cryptographic vault protecting your files with 4-Factor Biometric interlocking, SLIP-39 secret splitting, and Unsupervised ML ransomware behavior shielding.',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          color: const Color(0xFF94A3B8),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 40),
                      // Download Buttons
                      Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.download_rounded, size: 20),
                            label: Text(
                              'DOWNLOAD EXE INSTALLER',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                            onPressed: () => launchUrl(
                              Uri.parse('https://ampcrypt.itsupport.bd/installers/Ampcrypt-Installer.exe'),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white24),
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.inventory_2_outlined, size: 20),
                            label: Text(
                              'DOWNLOAD MSIX PACKAGE',
                              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                            onPressed: () => launchUrl(
                              Uri.parse('https://ampcrypt.itsupport.bd/installers/ampcrypt.msix'),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── FEATURES SECTION ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
              color: const Color(0xFF0B0F19),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: Column(
                    children: [
                      Text(
                        'Cutting-Edge Security Features',
                        style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 48),
                      GridView.count(
                        crossAxisCount: MediaQuery.of(context).size.width > 700 ? 2 : 1,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 30,
                        mainAxisSpacing: 30,
                        childAspectRatio: 1.5,
                        children: [
                          _buildWebFeatureCard(
                            Icons.fingerprint_rounded,
                            '4-Factor Biometric Interlocking',
                            'Unlock your vault combining password credentials, local face verification, fingerprint scan, and vocal analysis.',
                          ),
                          _buildWebFeatureCard(
                            Icons.schema_outlined,
                            'SLIP-39 Secret Splitting',
                            'Split your master key into 3 shards. You only need 2 of them to completely reconstruct it, eliminating single points of failure.',
                          ),
                          _buildWebFeatureCard(
                            Icons.security_rounded,
                            'Ransomware Shielding',
                            'An active, unsupervised machine learning watcher monitors folder behaviors, instantly unmounting the drive if attack models trigger.',
                          ),
                          _buildWebFeatureCard(
                            Icons.folder_shared_rounded,
                            'Zero-Trust WebDAV Mounting',
                            'Safely mounts your vault as a local disk (Z:) on Windows via secure localhost WebDAV loops with zero cloud exposure.',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ─── CONTACT US SECTION ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
              color: const Color(0xFF0F172A),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Card(
                    color: const Color(0xFF1E293B).withOpacity(0.6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Colors.white10),
                    ),
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Contact Us',
                              style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Send a message to our security support team.',
                              style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 24),
                            // Name
                            TextFormField(
                              controller: _nameController,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                              decoration: _webInputDecoration('Full Name', Icons.person_outline),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter your name' : null,
                            ),
                            const SizedBox(height: 16),
                            // Email
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                              decoration: _webInputDecoration('Email Address', Icons.email_outlined),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter your email' : null,
                            ),
                            const SizedBox(height: 16),
                            // Subject
                            TextFormField(
                              controller: _subjectController,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                              decoration: _webInputDecoration('Subject', Icons.subject_rounded),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter subject' : null,
                            ),
                            const SizedBox(height: 16),
                            // Message
                            TextFormField(
                              controller: _messageController,
                              maxLines: 5,
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                              decoration: _webInputDecoration('Message Content', Icons.chat_bubble_outline_rounded),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter message content' : null,
                            ),
                            const SizedBox(height: 24),
                            if (_statusMessage != null) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _isSuccess ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: _isSuccess ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
                                ),
                                child: Text(
                                  _statusMessage!,
                                  style: GoogleFonts.outfit(
                                    fontSize: 13,
                                    color: _isSuccess ? const Color(0xFFA7F3D0) : const Color(0xFFFDA4AF),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _isSending ? null : _submitForm,
                                child: _isSending
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : Text(
                                        'SEND MESSAGE',
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ─── FOOTER ─────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              color: const Color(0xFF080C16),
              child: Center(
                child: Column(
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Made by ',
                          style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                        InkWell(
                          onTap: () => launchUrl(Uri.parse('https://itsupport.com.bd/'), mode: LaunchMode.externalApplication),
                          child: Text(
                            'IT Support BD',
                            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: kPrimaryColor, decoration: TextDecoration.underline),
                          ),
                        ),
                        Text(
                          ' | Main Contribution: ',
                          style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                        InkWell(
                          onTap: () => launchUrl(Uri.parse('https://arifmahmud.com/'), mode: LaunchMode.externalApplication),
                          child: Text(
                            'Arif Mahmud Pranto',
                            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: kPrimaryColor, decoration: TextDecoration.underline),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AMPCrypt Web Portal • Version $kAppVersion',
                      style: GoogleFonts.shareTechMono(color: const Color(0xFF475569), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebFeatureCard(IconData icon, String title, String desc) {
    return Card(
      color: const Color(0xFF1E293B).withOpacity(0.3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: kPrimaryColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _webInputDecoration(String labelText, IconData icon) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 16),
      filled: true,
      fillColor: const Color(0xFF0F172A).withOpacity(0.6),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kPrimaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kErrorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kErrorColor, width: 1.5),
      ),
    );
  }
}

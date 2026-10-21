/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

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
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:ampcrypt/core/version.dart';
import 'package:ampcrypt/core/portable_state_sync.dart';
import 'package:ampcrypt/core/platform/windows_shell_service.dart';
import 'package:http/http.dart' as http_pkg;
import 'web_landing_page.dart';

import '../bloc/vault_bloc.dart';
import '../bloc/vault_event.dart';
import '../bloc/vault_state.dart';
import '../widgets/cryptomator_title_bar.dart';
import '../widgets/cryptomator_banners.dart';
import '../widgets/preferences_dialog.dart';
import '../widgets/cipher_tools_dialog.dart';
import '../widgets/backup_restore_dialog.dart';
import '../widgets/delete_vault_dialog.dart';
import '../widgets/create_vault_dialog.dart';
import '../widgets/vault_sidebar.dart';
import '../widgets/vault_main_content.dart';
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

// ─── Liquid Blue Glass Palette ───────────────────────────────────────────────
Color get kPrimaryColor => const Color(0xFF0284C7); // Azure Cyan Liquid Blue
Color get kPrimaryHoverColor =>
    const Color(0xFF38BDF8); // Electric Sky Blue Hover
Color get kScaffoldBackgroundColor =>
    isSystemDark ? const Color(0xFF070D1E) : const Color(0xFFF0F7FF);
Color get kSurfaceColor => const Color(0xFF0F172A); // Liquid Sapphire Surface
Color get kSidebarBackgroundColor =>
    isSystemDark ? const Color(0xFF0B132B) : const Color(0xFFE2E8F0);
Color get kSuccessColor =>
    const Color(0xFF38BDF8); // Soft Electric Cyan — unlocked / OK
Color get kErrorColor =>
    const Color(0xFFF43F5E); // Rose Red — warnings / errors

Future<void> openVaultDriveInExplorer({
  required BuildContext context,
  required VaultRepository repository,
  required String driveLetter,
}) async {
  String cleanLetter = driveLetter.replaceAll(':', '').replaceAll('\\', '').replaceAll('/', '').trim();
  if (cleanLetter.isEmpty) {
    final configured = repository.getDriveLetter();
    cleanLetter = configured.replaceAll(':', '').replaceAll('\\', '').replaceAll('/', '').trim();
  }
  if (cleanLetter.isEmpty) cleanLetter = 'Z';

  final drivePath = '${cleanLetter.toUpperCase()}:\\';

  if (Platform.isWindows) {
    // 1. Wait briefly (up to 1.5 seconds) if virtual drive is currently attaching
    bool isMounted = false;
    for (int i = 0; i < 5; i++) {
      if (Directory(drivePath).existsSync()) {
        isMounted = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    if (isMounted || Directory(drivePath).existsSync()) {
      final opened = await WindowsShellService().openInExplorer(drivePath);
      if (opened) return;
    }

    // Try opening directly in case Directory.existsSync() returned false due to sandbox/permissions
    final openedDirectly = await WindowsShellService().openInExplorer(drivePath);
    if (openedDirectly) return;
  }

  // 2. Fallback: If virtual drive is not ready/mounted, check for active local vault folder
  final vaultPath = repository.getVaultPath();
  final storageType = repository.storageType;
  if (storageType == 'local' && vaultPath.isNotEmpty && Directory(vaultPath).existsSync()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0284C7),
          duration: const Duration(seconds: 4),
          content: Text(
            'Virtual Drive $cleanLetter: is preparing. Opening vault folder in Explorer instead...',
            style: GoogleFonts.outfit(color: Colors.white),
          ),
        ),
      );
    }
    await WindowsShellService().openInExplorer(vaultPath);
    return;
  }

  // 3. Fallback notification if drive cannot be opened
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF06B6D4),
        duration: const Duration(seconds: 4),
        content: Text(
          'Virtual Drive $cleanLetter: is preparing. You can also explore files directly in "In-App Secure Files".',
          style: GoogleFonts.outfit(color: Colors.white),
        ),
      ),
    );
  }
}

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}


class _VaultPageState extends State<VaultPage>
    with WindowListener, TrayListener {
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


  void _showWinFspMissingDialog() {
    bool isInstalling = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kSurfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: kErrorColor.withValues(alpha: 0.8),
              width: 1.5,
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: kErrorColor, size: 24),
              const SizedBox(width: 12),
              Text(
                'WinFsp Driver Missing',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AMPCrypt requires the WinFsp (Windows File System Proxy) driver to mount secure vaults as native local drives under "Devices and Drives".',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF94A3B8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Click "AUTO-INSTALL WINFSP NOW" to install the driver automatically.',
                style: GoogleFonts.outfit(
                  color: const Color(0xFFE2E8F0),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (isInstalling) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kPrimaryColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Installing built-in WinFsp driver...',
                        style: GoogleFonts.outfit(
                          color: kPrimaryColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            if (!isInstalling)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  'CLOSE',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isInstalling
                  ? null
                  : () async {
                      setDialogState(() {
                        isInstalling = true;
                      });

                      try {
                        final repository = context.read<VaultBloc>().repository;
                        final installed = await repository.installWinFsp();

                        if (mounted) {
                          Navigator.pop(dialogContext);
                          if (installed) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: kSuccessColor,
                                content: Text(
                                  'WinFsp Driver installed successfully! Vault drive mounting is active.',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            );
                          } else {
                            await launchUrl(
                              Uri.parse('https://winfsp.dev/rel/'),
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        }
                      } catch (_) {
                        if (mounted) {
                          Navigator.pop(dialogContext);
                          await launchUrl(
                            Uri.parse('https://winfsp.dev/rel/'),
                            mode: LaunchMode.externalApplication,
                          );
                        }
                      }
                    },
              child: Text(
                isInstalling ? 'INSTALLING...' : 'AUTO-INSTALL WINFSP NOW',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  /// Rebuilds the system tray context menu to reflect the current vault lock state.
  Future<void> _initSystemTray({bool isVaultUnlocked = false}) async {
    if (kIsWeb ||
        (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux))
      return;

    try {
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/app_icon.ico'
            : 'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png',
      );

      // Build tray tooltip to show vault status
      await trayManager.setToolTip(
        isVaultUnlocked
            ? 'AMPCrypt — Vault Unlocked 🔓'
            : 'AMPCrypt — Vault Locked 🔒',
      );

      final menu = Menu(
        items: [
          MenuItem(key: 'open', label: 'Open AMPCrypt'),
          MenuItem(
            key: 'lock',
            label: isVaultUnlocked
                ? '🔒  Lock Vault Now'
                : '🔒  Vault is Locked',
          ),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'Exit AMPCrypt'),
        ],
      );
      await trayManager.setContextMenu(menu);
      trayManager.addListener(this);
    } catch (e) {
      debugPrint('Failed to initialize system tray: $e');
    }
  }

  /// Call this after vault state changes to keep the tray menu in sync.
  Future<void> _updateTrayMenu(bool isUnlocked) async {
    await _initSystemTray(isVaultUnlocked: isUnlocked);
  }

  // --- WindowListener overrides ---
  @override
  void onWindowClose() async {
    final prefs = await SharedPreferences.getInstance();
    final lockOnQuit = prefs.getBool('lock_on_quit') ?? false;
    if (lockOnQuit && mounted) {
      context.read<VaultBloc>().add(LockVaultEvent());
    }
    if (_minimizeToTray) {
      await windowManager.hide();
    } else {
      await _quitApp();
    }
  }

  @override
  void onWindowMinimize() async {
    if (_minimizeToTray) {
      await windowManager.hide();
    }
  }

  // --- TrayListener overrides ---
  @override
  void onTrayIconMouseDown() {
    _restoreWindow();
  }

  @override
  void onTrayIconMouseUp() {
    // No-op
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {
    // No-op: menu already shown on MouseDown
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
          content: Text(
            'All vaults locked from system tray.',
            style: GoogleFonts.outfit(),
          ),
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
    // 1. Immediately hide window and remove tray icon for instant user responsiveness (0ms feedback)
    try {
      await windowManager.hide();
      await trayManager.destroy();
    } catch (_) {}

    // 2. Fast synchronous lock & background unmount
    try {
      final repository = context.read<VaultBloc>().repository;
      repository.lockVault();
    } catch (_) {}

    try {
      context.read<VaultBloc>().add(LockVaultEvent());
      // Parallel fast unmount
      await Future.wait([
        Process.run('subst.exe', ['Z:', '/d']),
        Process.run('net.exe', ['use', 'Z:', '/delete', '/y']),
        PortableStateSync.syncToPortable(),
      ]).timeout(const Duration(milliseconds: 300), onTimeout: () => []);
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    } catch (_) {}
    exit(0);
  }


  void _showCreateVaultDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return CreateVaultDialog(
          onCreate:
              (
                password,
                authLevel,
                vaultName,
                vaultPath,
                questions,
                answers,
              ) async {
                final repo = context.read<VaultBloc>().repository;
                final targetDir = (vaultPath != null && vaultPath.isNotEmpty)
                    ? vaultPath
                    : p.join(
                        Directory.systemTemp.path,
                        '.ampcrypt_vault_$vaultName',
                      );
                await repo.relocateVaultFolder(targetDir);

                if (context.mounted) {
                  context.read<VaultBloc>().add(
                    CreateVaultEvent(
                      password,
                      authLevel: authLevel,
                      questions: questions,
                      answers: answers,
                    ),
                  );

                  // Add to remembered vault profiles
                  await repo.addRememberedVault(
                    VaultProfile(
                      name: vaultName,
                      path: targetDir,
                      storageType: 'local',
                      driveLetter: repo.getDriveLetter(),
                    ),
                  );

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: kSuccessColor,
                      content: Text(
                        'Vault "$vaultName" created with 3 Security Questions recovery!',
                        style: GoogleFonts.outfit(),
                      ),
                    ),
                  );
                }
              },
        );
      },
    );
  }

  void _showOpenVaultDialog(BuildContext context) async {
    String? selectedDirectory = await FilePicker.getDirectoryPath();
    if (selectedDirectory != null) {
      if (context.mounted) {
        _showMountDialogForPath(context, selectedDirectory);
      }
    }
  }

  void _showVaultsManagerDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return VaultsManagerDialog(
          onAddFtpVault: () {
            _showAddFtpDriveDialog(context);
          },
        );
      },
    );
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(
                'Open Existing Vault',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected folder:',
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    path,
                    style: GoogleFonts.shareTechMono(
                      color: kPrimaryColor,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDrive,
                    dropdownColor: kSurfaceColor,
                    decoration: InputDecoration(
                      labelText: 'Virtual Drive Letter',
                      labelStyle: GoogleFonts.outfit(
                        color: const Color(0xFF94A3B8),
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                    style: GoogleFonts.outfit(color: Colors.white),
                    items:
                        [
                              'D:',
                              'E:',
                              'F:',
                              'G:',
                              'H:',
                              'V:',
                              'W:',
                              'X:',
                              'Y:',
                              'Z:',
                            ]
                            .map(
                              (drive) => DropdownMenuItem(
                                value: drive,
                                child: Text(
                                  drive,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
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
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await repository.updateVaultSettings(path, selectedDrive);
                    if (context.mounted) {
                      context.read<VaultBloc>().add(CheckVaultStatusEvent());
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: kSuccessColor,
                          content: Text(
                            'Vault profile loaded. Unlock to mount.',
                            style: GoogleFonts.outfit(),
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(
                    'Open Vault',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSecurityRecoveryDialog(BuildContext context) {
    final repo = context.read<VaultBloc>().repository;
    final vaultPath = repo.getVaultPath().isNotEmpty
        ? repo.getVaultPath()
        : 'F:\\OneDrive - arifmahmud\\Forestsong';

    showDialog(
      context: context,
      builder: (dialogContext) => BackupRestoreDialog(
        vaultPath: vaultPath,
        onRecoverSLIP39: (phrases) {
          context.read<VaultBloc>().add(RecoverVaultEvent(phrases));
        },
        onRestoreBackupFile: (restoredPath) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: kSuccessColor,
              content: Text(
                'Backup configuration restored.',
                style: GoogleFonts.outfit(),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showDeleteVaultDialog(BuildContext context, [String? targetPath]) {
    final repo = context.read<VaultBloc>().repository;
    final vaultPath = (targetPath != null && targetPath.isNotEmpty)
        ? targetPath
        : repo.getVaultPath();
    String rawName = p.basename(vaultPath).replaceAll('.ampcrypt_vault_', '');
    if (rawName.isEmpty || rawName == '.' || rawName == '/') rawName = 'Data';

    showDialog<bool>(
      context: context,
      builder: (dialogContext) => DeleteVaultDialog(
        vaultName: rawName,
        vaultPath: vaultPath,
        onRemoveFromApp: () async {
          context.read<VaultBloc>().add(RemoveVaultFromAppEvent(vaultPath));
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: kPrimaryColor,
                content: Text(
                  'Vault removed from app list. Files on disk remain safe.',
                  style: GoogleFonts.outfit(),
                ),
              ),
            );
          }
        },
        onForceDeleteConfirm: (password) async {
          final isVerified = await repo.verifyVaultPassword(password);
          if (isVerified && mounted) {
            context.read<VaultBloc>().add(
              ForceDeleteVaultEvent(password, vaultPath),
            );
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: kErrorColor,
                content: Text(
                  'Vault and all physical files deleted from disk.',
                  style: GoogleFonts.outfit(),
                ),
              ),
            );
            return true;
          }
          return false;
        },
      ),
    );
  }

  void _showPreferencesDialog(BuildContext context, {int initialTab = 0}) {
    showDialog(
      context: context,
      builder: (dialogContext) =>
          PreferencesDialog(initialTabIndex: initialTab),
    );
  }

  Widget _buildEmptyVaultsView(BuildContext context, bool isDark) {
    final bg = isDark ? const Color(0xFF070D1E) : const Color(0xFFF0F7FF);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);

    return Container(
      color: bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF0072FF), Color(0xFF00F0FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00F0FF).withValues(alpha: 0.35),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_outlined,
                size: 48,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'No Vaults Available',
              style: GoogleFonts.outfit(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a new vault or open an existing vault on your computer.',
              style: GoogleFonts.outfit(color: subtitleColor, fontSize: 13),
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0072FF), Color(0xFF00F0FF)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0072FF).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text(
                      'Create New Vault',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: () => _showCreateVaultDialog(context),
                  ),
                ),
                const SizedBox(width: 14),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textColor,
                    side: BorderSide(
                      color: isDark
                          ? const Color(0x3300F0FF)
                          : const Color(0xFFCBD5E1),
                      width: 1.2,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(
                    'Open Existing Vault',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  onPressed: () => _showOpenVaultDialog(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showLocateVaultDialog(BuildContext context) async {
    try {
      final selectedPath = await FilePicker.getDirectoryPath();
      if (selectedPath != null && mounted) {
        final repo = context.read<VaultBloc>().repository;
        final isValid = repo.isVaultPathValid(selectedPath);
        if (isValid) {
          await repo.relocateVaultFolder(selectedPath);
          if (mounted) {
            setState(() {});
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: kSuccessColor,
                content: Text(
                  'Vault reconnected to: $selectedPath',
                  style: GoogleFonts.outfit(),
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: kErrorColor,
                content: Text(
                  'Selected folder does not contain AMPCrypt vault files.',
                  style: GoogleFonts.outfit(),
                ),
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  void _openDriveInExplorer(String driveLetter) {
    openVaultDriveInExplorer(
      context: context,
      repository: context.read<VaultBloc>().repository,
      driveLetter: driveLetter,
    );
  }

  void _showAddFtpDriveDialog(BuildContext context) {
    final repository = context.read<VaultBloc>().repository;
    final hostController = TextEditingController(text: '127.0.0.1');
    final portController = TextEditingController(text: '21');
    final usernameController = TextEditingController(text: 'anonymous');
    final passwordController = TextEditingController(text: 'anonymous');
    final pathController = TextEditingController(text: '/');
    final driveController = TextEditingController(text: 'Z:');
    final vaultPasswordController = TextEditingController();

    bool isOpenMode = true;
    int selectedAuthLevel = 4;
    bool isTesting = false;
    bool isConnecting = false;
    String? connectionError;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kSurfaceColor,
              title: Text(
                'Add FTP Drive',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isOpenMode
                                    ? kPrimaryColor
                                    : const Color(0xFF1E2228),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: () =>
                                  setDialogState(() => isOpenMode = true),
                              child: Text(
                                'Open Existing Vault',
                                style: GoogleFonts.outfit(fontSize: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: !isOpenMode
                                    ? kPrimaryColor
                                    : const Color(0xFF1E2228),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              onPressed: () =>
                                  setDialogState(() => isOpenMode = false),
                              child: Text(
                                'Create New Vault',
                                style: GoogleFonts.outfit(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'FTP CONNECTION SETTINGS',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: hostController,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                labelText: 'FTP Server Host',
                                labelStyle: GoogleFonts.outfit(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: kPrimaryColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: portController,
                              keyboardType: TextInputType.number,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Port',
                                labelStyle: GoogleFonts.outfit(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: kPrimaryColor),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: usernameController,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Username',
                                labelStyle: GoogleFonts.outfit(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: kPrimaryColor),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextField(
                              controller: passwordController,
                              obscureText: true,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                labelStyle: GoogleFonts.outfit(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF334155),
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: kPrimaryColor),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: pathController,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Remote Vault Directory Path',
                                      labelStyle: GoogleFonts.outfit(
                                        color: const Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                      enabledBorder: const UnderlineInputBorder(
                                        borderSide: BorderSide(
                                          color: Color(0xFF334155),
                                        ),
                                      ),
                                      focusedBorder: UnderlineInputBorder(
                                        borderSide: BorderSide(
                                          color: kPrimaryColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.folder_open,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  tooltip: 'Browse FTP Directories',
                                  onPressed: () {
                                    final host = hostController.text;
                                    final port =
                                        int.tryParse(portController.text) ?? 21;
                                    final user = usernameController.text;
                                    final pass = passwordController.text;

                                    if (host.isEmpty) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Please enter FTP Host first.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }

                                    showDialog(
                                      context: context,
                                      builder: (browseContext) {
                                        return _FtpDirectoryExplorerDialog(
                                          host: host,
                                          port: port,
                                          user: user,
                                          pass: pass,
                                          initialPath:
                                              pathController.text.isEmpty
                                              ? '/'
                                              : pathController.text,
                                          onPathSelected: (selectedPath) {
                                            setDialogState(() {
                                              pathController.text =
                                                  selectedPath;
                                            });
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              initialValue: driveController.text,
                              dropdownColor: const Color(0xFF1E293B),
                              decoration: InputDecoration(
                                labelText: 'Drive',
                                labelStyle: GoogleFonts.outfit(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 12,
                                ),
                                enabledBorder: const UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF334155),
                                  ),
                                ),
                              ),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              items:
                                  [
                                        'D:',
                                        'E:',
                                        'F:',
                                        'G:',
                                        'H:',
                                        'V:',
                                        'W:',
                                        'X:',
                                        'Y:',
                                        'Z:',
                                      ]
                                      .map(
                                        (drive) => DropdownMenuItem(
                                          value: drive,
                                          child: Text(
                                            drive,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() {
                                    driveController.text = val;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'SECURE VAULT KEY',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: kPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: vaultPasswordController,
                        obscureText: true,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Vault Password',
                          labelStyle: GoogleFonts.outfit(
                            color: const Color(0xFF94A3B8),
                            fontSize: 12,
                          ),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: kPrimaryColor),
                          ),
                        ),
                      ),
                      if (!isOpenMode) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '4FA Biometric Protection Level',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            DropdownButton<int>(
                              value: selectedAuthLevel,
                              dropdownColor: const Color(0xFF1E293B),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 1,
                                  child: Text('1FA (Password Only)'),
                                ),
                                DropdownMenuItem(
                                  value: 2,
                                  child: Text('2FA (+Fingerprint)'),
                                ),
                                DropdownMenuItem(
                                  value: 3,
                                  child: Text('3FA (+Face Scan)'),
                                ),
                                DropdownMenuItem(
                                  value: 4,
                                  child: Text('4FA (+Voice Print)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() => selectedAuthLevel = val);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                      if (connectionError != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          connectionError!,
                          style: GoogleFonts.outfit(
                            color: kPrimaryHoverColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isTesting
                      ? null
                      : () async {
                          setDialogState(() {
                            isTesting = true;
                            connectionError = null;
                          });
                          final host = hostController.text;
                          final port = int.tryParse(portController.text) ?? 21;
                          final user = usernameController.text;
                          final pass = passwordController.text;
                          final remotePath = pathController.text;
                          final success = await repository.testFtpConnection(
                            host,
                            port,
                            user,
                            pass,
                            remotePath,
                          );
                          setDialogState(() {
                            isTesting = false;
                            if (success) {
                              connectionError = "Connection successful!";
                            } else {
                              connectionError =
                                  "Failed to connect to FTP server.";
                            }
                          });
                        },
                  child: Text(
                    isTesting ? 'Testing...' : 'Test Connection',
                    style: GoogleFonts.outfit(
                      color: kPrimaryHoverColor,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: isConnecting
                      ? null
                      : () async {
                          if (vaultPasswordController.text.isEmpty) {
                            setDialogState(
                              () => connectionError =
                                  "Please enter vault password.",
                            );
                            return;
                          }
                          setDialogState(() {
                            isConnecting = true;
                            connectionError = null;
                          });

                          final host = hostController.text;
                          final port = int.tryParse(portController.text) ?? 21;
                          final user = usernameController.text;
                          final pass = passwordController.text;
                          final remotePath = pathController.text;
                          final driveLetter = driveController.text;
                          final vaultPassword = vaultPasswordController.text;

                          bool success = false;
                          if (isOpenMode) {
                            success = await repository.openFtpVault(
                              vaultPassword,
                              host: host,
                              port: port,
                              user: user,
                              pass: pass,
                              path: remotePath,
                              driveLetter: driveLetter,
                            );
                            if (!success) {
                              setDialogState(() {
                                isConnecting = false;
                                connectionError =
                                    "Failed to open vault. Check FTP settings or password.";
                              });
                            } else {
                              Navigator.pop(dialogContext);
                              context.read<VaultBloc>().add(
                                CheckVaultStatusEvent(),
                              );
                            }
                          } else {
                            try {
                              final recoveryPhrases = await repository
                                  .createFtpVault(
                                    vaultPassword,
                                    host: host,
                                    port: port,
                                    user: user,
                                    pass: pass,
                                    path: remotePath,
                                    driveLetter: driveLetter,
                                    authLevel: selectedAuthLevel,
                                  );
                              Navigator.pop(dialogContext);
                              context.read<VaultBloc>().add(
                                CheckVaultStatusEvent(),
                              );

                              showDialog(
                                context: context,
                                builder: (phrasesContext) => AlertDialog(
                                  backgroundColor: kSurfaceColor,
                                  title: Text(
                                    'Recovery Phrases',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                    ),
                                  ),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Please write down these backup recovery phrases (2-of-3 required to restore):',
                                        style: GoogleFonts.outfit(
                                          color: const Color(0xFF94A3B8),
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      ...List.generate(recoveryPhrases.length, (
                                        index,
                                      ) {
                                        return Text(
                                          '${index + 1}. ${recoveryPhrases[index]}',
                                          style: GoogleFonts.shareTechMono(
                                            color: Colors.white,
                                            fontSize: 12,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(phrasesContext),
                                      child: Text(
                                        'OK',
                                        style: GoogleFonts.outfit(
                                          color: kPrimaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            } catch (e) {
                              setDialogState(() {
                                isConnecting = false;
                                connectionError = "Failed to create vault: $e";
                              });
                            }
                          }
                        },
                  child: Text(
                    isConnecting
                        ? 'Connecting...'
                        : (isOpenMode ? 'Open & Mount' : 'Create & Setup'),
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
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
    final showCustomTitleBar =
        !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      body: Column(
        children: [
          if (showCustomTitleBar)
            CryptomatorTitleBar(isDark: isDark, onClose: () => onWindowClose()),
          CryptomatorBanners(
            onUpdateTap: () => _showPreferencesDialog(context, initialTab: 4),
            onSupportTap: () => _showPreferencesDialog(context, initialTab: 5),
          ),
          Expanded(
            child: BlocConsumer<VaultBloc, VaultState>(
              listener: (context, state) {
                _updateTrayMenu(state is VaultUnlockedState);
                if (state is VaultFailureState) {
                  if (state.errorMessage == 'WINFSP_MISSING') {
                    _showWinFspMissingDialog();
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF3F0B24),
                        content: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Color(0xFFFF4D88),
                            ),
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
                }
              },
              builder: (context, state) {
                final repo = context.read<VaultBloc>().repository;
                final isUnlocked = state is VaultUnlockedState;
                final isLoading = state is VaultLoadingState;
                final loadingMessage = state is VaultLoadingState
                    ? state.message
                    : null;

                final rememberedVaults = repo.getRememberedVaults();
                final sidebarVaults = rememberedVaults
                    .map(
                      (v) => VaultSidebarItem(
                        id: v.path,
                        name: v.name,
                        path: v.path,
                        isUnlocked: isUnlocked && repo.getVaultPath() == v.path,
                      ),
                    )
                    .toList();

                if (state is VaultUninitializedState ||
                    sidebarVaults.isEmpty ||
                    !repo.isVaultCreated) {
                  return Row(
                    children: [
                      VaultSidebar(
                        vaults: sidebarVaults,
                        selectedVaultId: null,
                        onSelectVault: (id) {},
                        onCreateVault: () => _showCreateVaultDialog(context),
                        onOpenVault: () => _showOpenVaultDialog(context),
                        onAddFtpDrive: () => _showAddFtpDriveDialog(context),
                        onOpenAlerts: () =>
                            _showSecurityRecoveryDialog(context),
                        onOpenPreferences: () =>
                            _showPreferencesDialog(context),
                        onDeleteVault: (id) => _showDeleteVaultDialog(context),
                      ),
                      Expanded(child: _buildEmptyVaultsView(context, isDark)),
                    ],
                  );
                }

                String rawName = p
                    .basename(repo.getVaultPath())
                    .replaceAll('.ampcrypt_vault_', '');
                if (rawName.isEmpty || rawName == '.' || rawName == '/')
                  rawName = 'Data';
                final vaultName = rawName;
                final vaultPath = repo.getVaultPath();
                final driveLetter = repo.getDriveLetter().isNotEmpty
                    ? repo.getDriveLetter()
                    : 'G:';

                return Row(
                  children: [
                    VaultSidebar(
                      vaults: sidebarVaults,
                      selectedVaultId: vaultPath,
                      onSelectVault: (id) async {
                        await repo.relocateVaultFolder(id);
                        setState(() {});
                      },
                      onCreateVault: () => _showCreateVaultDialog(context),
                      onOpenVault: () => _showOpenVaultDialog(context),
                      onAddFtpDrive: () => _showAddFtpDriveDialog(context),
                      onOpenAlerts: () => _showSecurityRecoveryDialog(context),
                      onOpenPreferences: () => _showPreferencesDialog(context),
                      onDeleteVault: (id) => _showDeleteVaultDialog(context),
                    ),
                    Expanded(
                      child: VaultMainContent(
                        vaultName: vaultName,
                        vaultPath: vaultPath,
                        driveLetter: driveLetter,
                        isUnlocked: isUnlocked,
                        isLoading: isLoading,
                        loadingMessage: loadingMessage,
                        onRevealDrive: () => _openDriveInExplorer(driveLetter),
                        onLock: () {
                          context.read<VaultBloc>().add(LockVaultEvent());
                        },
                        onUnlock: (password) {
                          context.read<VaultBloc>().add(
                            UnlockVaultEvent(password),
                          );
                        },
                        onLocateEncryptedFile: () {
                          CipherToolsDialog.showLocateEncryptedFileDialog(
                            context,
                            vaultPath,
                          );
                        },
                        onDecryptFileName: () {
                          CipherToolsDialog.showDecryptFileNameDialog(context);
                        },
                        onLocateVault: () => _showLocateVaultDialog(context),
                        onRecoveryTap: () {
                          _showSecurityRecoveryDialog(context);
                        },
                        repository: repo,
                      ),
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
    );
  }
}

class RansomwareAlarmOverlay extends StatefulWidget {
  final String watchedPath;
  const RansomwareAlarmOverlay({super.key, required this.watchedPath});

  @override
  State<RansomwareAlarmOverlay> createState() => _RansomwareAlarmOverlayState();
}

class _RansomwareAlarmOverlayState extends State<RansomwareAlarmOverlay>
    with SingleTickerProviderStateMixin {
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
              content: Text(
                'Security alarm cleared. Vault unlocked.',
                style: GoogleFonts.outfit(),
              ),
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
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        body: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                child: Container(color: kErrorColor.withValues(alpha: 0.08)),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 550,
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1111).withValues(alpha: 0.8),
                    border: Border.all(
                      color: kErrorColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: kErrorColor.withValues(alpha: 0.2),
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
                              color: kErrorColor.withValues(
                                alpha: 0.1 + (_pulseController.value * 0.15),
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: kErrorColor.withValues(
                                  alpha: 0.3 + (_pulseController.value * 0.4),
                                ),
                                width: 2,
                              ),
                            ),
                            child: Icon(
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
                          color: Colors.black.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: kErrorColor.withValues(alpha: 0.15),
                          ),
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
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.watchedPath,
                              style: GoogleFonts.shareTechMono(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Actions Taken: Cryptographic keys wiped from RAM, decryption cache invalidated, local database locked.',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: const Color(0xFFF43F5E),
                                fontWeight: FontWeight.w600,
                              ),
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
                          hintStyle: GoogleFonts.outfit(
                            color: const Color(0xFF475569),
                          ),
                          filled: true,
                          fillColor: kSurfaceColor.withValues(alpha: 0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF334155),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: kErrorColor),
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
                          onPressed: _isDeescalating
                              ? null
                              : () => _deescalate(context),
                          child: _isDeescalating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'RESET ALARM & RE-AUTHENTICATE',
                                  style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
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

class _FtpDirectoryExplorerDialog extends StatefulWidget {
  final String host;
  final int port;
  final String user;
  final String pass;
  final String initialPath;
  final ValueChanged<String> onPathSelected;

  const _FtpDirectoryExplorerDialog({
    required this.host,
    required this.port,
    required this.user,
    required this.pass,
    required this.initialPath,
    required this.onPathSelected,
  });

  @override
  State<_FtpDirectoryExplorerDialog> createState() =>
      _FtpDirectoryExplorerDialogState();
}

class _FtpDirectoryExplorerDialogState
    extends State<_FtpDirectoryExplorerDialog> {
  late String _currentPath;
  List<String> _folders = [];
  bool _isLoading = true;
  String? _errorMessage;
  final _newFolderController = TextEditingController();
  bool _isCreatingFolder = false;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath.isEmpty ? '/' : widget.initialPath;
    if (!_currentPath.startsWith('/')) {
      _currentPath = '/$_currentPath';
    }
    _loadFolders();
  }

  @override
  void dispose() {
    _newFolderController.dispose();
    super.dispose();
  }

  Future<void> _loadFolders() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final repository = context.read<VaultBloc>().repository;
      final dirs = await repository.listFtpDirectories(
        widget.host,
        widget.port,
        widget.user,
        widget.pass,
        _currentPath,
      );
      if (mounted) {
        setState(() {
          _folders = dirs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll("Exception: ", "");
          _isLoading = false;
        });
      }
    }
  }

  void _navigateInto(String folder) {
    if (_currentPath == '/') {
      _currentPath = '/$folder';
    } else if (_currentPath.endsWith('/')) {
      _currentPath = '$_currentPath$folder';
    } else {
      _currentPath = '$_currentPath/$folder';
    }
    _loadFolders();
  }

  void _navigateUp() {
    if (_currentPath == '/' || _currentPath.isEmpty) return;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      _currentPath = '/';
    } else {
      parts.removeLast();
      _currentPath = '/${parts.join('/')}';
    }
    _loadFolders();
  }

  Future<void> _createNewFolder() async {
    final name = _newFolderController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isCreatingFolder = true;
    });

    try {
      final repository = context.read<VaultBloc>().repository;
      final success = await repository.createFtpDirectory(
        widget.host,
        widget.port,
        widget.user,
        widget.pass,
        _currentPath,
        name,
      );
      if (success) {
        _newFolderController.clear();
        await _loadFolders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create folder. Check permissions.'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error creating folder: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingFolder = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kSurfaceColor,
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Browse FTP Server',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 450,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1613),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder, color: Color(0xFFE2E8F0), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentPath,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_currentPath != '/')
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_upward,
                        color: Colors.white,
                        size: 14,
                      ),
                      tooltip: 'Go Up',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _navigateUp,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1009),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF16A34A),
                        ),
                      )
                    : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: kErrorColor,
                                size: 36,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _loadFolders,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kPrimaryColor,
                                ),
                                child: Text(
                                  'Retry',
                                  style: GoogleFonts.outfit(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _folders.isEmpty
                    ? Center(
                        child: Text(
                          'Empty Folder',
                          style: GoogleFonts.outfit(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _folders.length,
                        itemBuilder: (context, index) {
                          final name = _folders[index];
                          return ListTile(
                            leading: const Icon(
                              Icons.folder,
                              color: Color(0xFFFBBF24),
                              size: 20,
                            ),
                            title: Text(
                              name,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            hoverColor: Colors.white.withValues(alpha: 0.05),
                            onTap: () => _navigateInto(name),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newFolderController,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                    decoration: InputDecoration(
                      hintText: 'New Folder Name',
                      hintStyle: GoogleFonts.outfit(
                        color: const Color(0xFF64748B),
                        fontSize: 12,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF334155)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: kPrimaryColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _isCreatingFolder
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF16A34A),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: _createNewFolder,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E2228),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 14),
                        label: Text(
                          'Create',
                          style: GoogleFonts.outfit(fontSize: 11),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: GoogleFonts.outfit(
              color: const Color(0xFF94A3B8),
              fontSize: 12,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            widget.onPathSelected(_currentPath);
            Navigator.pop(context);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: Colors.white,
          ),
          child: Text('Select Folder', style: GoogleFonts.outfit(fontSize: 12)),
        ),
      ],
    );
  }
}

// ==========================================
// Vaults Manager Dialog & Support
// ==========================================

class VaultsManagerDialog extends StatefulWidget {
  final VoidCallback onAddFtpVault;
  const VaultsManagerDialog({super.key, required this.onAddFtpVault});

  @override
  State<VaultsManagerDialog> createState() => _VaultsManagerDialogState();
}

class _VaultsManagerDialogState extends State<VaultsManagerDialog> {
  List<VaultProfile> _vaults = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVaults();
  }

  Future<void> _loadVaults() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final repo = context.read<VaultBloc>().repository;
      final list = repo.getRememberedVaults();
      if (mounted) {
        setState(() {
          _vaults = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<VaultBloc>().repository;
    final activePath = repo.getVaultPath();
    final activeType = repo.storageType;
    final activeFtpHost = repo.getFtpHost();

    return AlertDialog(
      backgroundColor: kSurfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Secure Vault Registry',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF64748B), size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select a remembered vault profile to load, or import/register a new vault folder.',
              style: GoogleFonts.outfit(
                color: const Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_vaults.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.01),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.04),
                  ),
                ),
                child: Center(
                  child: Text(
                    'No registered vault profiles. Use options below.',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ),
              )
            else
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _vaults.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final vault = _vaults[index];
                    final isActive =
                        vault.storageType == activeType &&
                        (vault.storageType == 'local'
                            ? vault.path == activePath
                            : vault.path == activePath &&
                                  vault.ftpHost == activeFtpHost);

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? kPrimaryColor.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? kPrimaryColor.withValues(alpha: 0.4)
                              : Colors.white.withValues(alpha: 0.05),
                          width: isActive ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            vault.storageType == 'ftp'
                                ? Icons.cloud_outlined
                                : Icons.folder_open_outlined,
                            color: isActive
                                ? kPrimaryColor
                                : const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  vault.name,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  vault.path,
                                  style: GoogleFonts.shareTechMono(
                                    color: const Color(0xFF64748B),
                                    fontSize: 10,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: vault.storageType == 'ftp'
                                  ? Colors.blue.withValues(alpha: 0.15)
                                  : Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              vault.storageType.toUpperCase(),
                              style: GoogleFonts.outfit(
                                color: vault.storageType == 'ftp'
                                    ? Colors.blue
                                    : Colors.green,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            vault.driveLetter,
                            style: GoogleFonts.shareTechMono(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isActive) ...[
                            IconButton(
                              icon: Icon(
                                Icons.login,
                                color: kPrimaryHoverColor,
                                size: 16,
                              ),
                              tooltip: 'Select Vault',
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                Navigator.pop(context);
                                await repo.selectVault(vault);
                                if (context.mounted) {
                                  context.read<VaultBloc>().add(
                                    CheckVaultStatusEvent(),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: kSuccessColor,
                                      content: Text(
                                        'Vault profile loaded: ${vault.name}',
                                        style: GoogleFonts.outfit(),
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: kErrorColor,
                                size: 16,
                              ),
                              tooltip: 'Forget Vault',
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                await repo.removeRememberedVault(vault.path);
                                _loadVaults();
                                if (context.mounted) {
                                  context.read<VaultBloc>().add(
                                    CheckVaultStatusEvent(),
                                  );
                                }
                              },
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8.0,
                              ),
                              child: Icon(
                                Icons.check_circle,
                                color: kPrimaryColor,
                                size: 16,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'VAULT PROFILE ACTIONS',
              style: GoogleFonts.outfit(
                color: const Color(0xFF64748B),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.folder_open_outlined, size: 14),
                  label: Text(
                    'Add Existing Vault',
                    style: GoogleFonts.outfit(fontSize: 11),
                  ),
                  onPressed: () async {
                    String? selectedDirectory =
                        await FilePicker.getDirectoryPath();
                    if (selectedDirectory != null) {
                      if (mounted) {
                        _showAddExistingVaultVerifyDialog(
                          context,
                          selectedDirectory,
                        );
                      }
                    }
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.cloud_outlined, size: 14),
                  label: Text(
                    'Setup FTP Vault',
                    style: GoogleFonts.outfit(fontSize: 11),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onAddFtpVault();
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.04),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 14),
                  label: Text(
                    'Create New',
                    style: GoogleFonts.outfit(fontSize: 11),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    context.read<VaultBloc>().add(ResetToUninitializedEvent());
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.01),
                      foregroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.upload_file_outlined, size: 13),
                    label: Text(
                      'Import Registry File',
                      style: GoogleFonts.outfit(fontSize: 11),
                    ),
                    onPressed: () async {
                      final result = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (result != null && result.files.single.path != null) {
                        await repo.importVaultsHistory(
                          result.files.single.path!,
                        );
                        _loadVaults();
                        if (context.mounted) {
                          context.read<VaultBloc>().add(
                            CheckVaultStatusEvent(),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: kSuccessColor,
                              content: Text(
                                'Vault registry imported successfully.',
                                style: GoogleFonts.outfit(),
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.01),
                      foregroundColor: const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.download_outlined, size: 13),
                    label: Text(
                      'Backup Registry File',
                      style: GoogleFonts.outfit(fontSize: 11),
                    ),
                    onPressed: () async {
                      final result = await FilePicker.saveFile(
                        dialogTitle: 'Export AMPCrypt Vault Registry',
                        fileName: 'ampcrypt_registry.json',
                        type: FileType.custom,
                        allowedExtensions: ['json'],
                      );
                      if (result != null) {
                        await repo.exportVaultsHistory(result);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: kSuccessColor,
                              content: Text(
                                'Vault registry backed up successfully.',
                                style: GoogleFonts.outfit(),
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddExistingVaultVerifyDialog(BuildContext context, String path) {
    final repo = context.read<VaultBloc>().repository;
    final passwordController = TextEditingController();
    final nameController = TextEditingController(text: p.basename(path));
    String selectedDrive = 'W:';
    bool isVerifying = false;
    String? verifyError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: kSurfaceColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                  width: 1.5,
                ),
              ),
              title: Text(
                'Verify & Import Vault',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Folder Path:',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF94A3B8),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    path,
                    style: GoogleFonts.shareTechMono(
                      color: kPrimaryColor,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameController,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Vault Name',
                      labelStyle: GoogleFonts.outfit(
                        color: const Color(0xFF94A3B8),
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordController,
                    obscureText: true,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Vault Passphrase',
                      labelStyle: GoogleFonts.outfit(
                        color: const Color(0xFF94A3B8),
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedDrive,
                    dropdownColor: kSurfaceColor,
                    decoration: InputDecoration(
                      labelText: 'Virtual Drive Letter',
                      labelStyle: GoogleFonts.outfit(
                        color: const Color(0xFF94A3B8),
                      ),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF334155)),
                      ),
                    ),
                    style: GoogleFonts.outfit(color: Colors.white),
                    items:
                        [
                              'D:',
                              'E:',
                              'F:',
                              'G:',
                              'H:',
                              'V:',
                              'W:',
                              'X:',
                              'Y:',
                              'Z:',
                            ]
                            .map(
                              (drive) => DropdownMenuItem(
                                value: drive,
                                child: Text(
                                  drive,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedDrive = val;
                        });
                      }
                    },
                  ),
                  if (verifyError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      verifyError!,
                      style: GoogleFonts.outfit(
                        color: kErrorColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isVerifying
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.outfit(color: const Color(0xFF94A3B8)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isVerifying
                      ? null
                      : () async {
                          if (passwordController.text.isEmpty) {
                            setDialogState(
                              () => verifyError = 'Passphrase is required',
                            );
                            return;
                          }
                          setDialogState(() {
                            isVerifying = true;
                            verifyError = null;
                          });

                          final success = await repo.verifyAndAddExistingVault(
                            name: nameController.text.trim(),
                            path: path,
                            password: passwordController.text,
                            driveLetter: selectedDrive,
                          );

                          if (success) {
                            Navigator.of(dialogContext).pop();
                            _loadVaults();
                            if (context.mounted) {
                              context.read<VaultBloc>().add(
                                CheckVaultStatusEvent(),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: kSuccessColor,
                                  content: Text(
                                    'Vault verified and registered successfully.',
                                    style: GoogleFonts.outfit(),
                                  ),
                                ),
                              );
                            }
                          } else {
                            setDialogState(() {
                              isVerifying = false;
                              verifyError =
                                  'Failed to verify Master Key. Check passphrase or directory structure.';
                            });
                          }
                        },
                  child: Text(
                    isVerifying ? 'Verifying...' : 'Verify & Import',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

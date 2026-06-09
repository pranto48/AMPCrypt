import 'dart:convert';
import 'dart:io';
import 'dart:ui';
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

import '../bloc/vault_bloc.dart';
import '../bloc/vault_event.dart';
import '../bloc/vault_state.dart';
import '../../../biometrics/data/datasources/face_verification_service.dart';
import '../../../biometrics/data/datasources/fingerprint_verification_service.dart';
import '../../../biometrics/data/datasources/voice_verification_service.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_bloc.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_event.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_state.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  late bool _showAbout;

  @override
  void initState() {
    super.initState();
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
    _showAbout = !isDesktop;
    // Check initial vault status
    context.read<VaultBloc>().add(CheckVaultStatusEvent());
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: Stack(
        children: [
          Container(
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
                  setState(() {
                    _showAbout = false;
                  });
                }
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
                if (isDesktop) {
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
                }

                if (state is VaultUnlockedState) {
                  return UnlockedDashboardView(state: state);
                }

                // If in initial/loading state and not showing about, or FailureState, handle below
                return Column(
                  children: [
                    _buildTopHeader(state),
                    Expanded(
                      child: _showAbout
                          ? _buildAboutProjectView(context, state)
                          : _buildVaultConsoleView(context, state),
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

  Widget _buildTopHeader(VaultState state) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.5),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.08),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF8B5CF6).withOpacity(0.15),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: const Icon(Icons.shield, color: Color(0xFF8B5CF6), size: 20),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'AMPCrypt',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!isCompact)
                        Text(
                          'Zero-Trust Security Console',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isDesktop) ...[
                _buildHeaderTab(
                  label: 'About Project',
                  isActive: _showAbout,
                  onTap: () => setState(() => _showAbout = true),
                ),
                const SizedBox(width: 16),
              ],
              _buildHeaderTab(
                label: state is VaultLockedState ? 'Unlock Vault' : 'Initialize Vault',
                isActive: !_showAbout,
                onTap: () => setState(() => _showAbout = false),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderTab({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF8B5CF6).withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? const Color(0xFF8B5CF6).withOpacity(0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 13,
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, VaultState state) {
    final isUnlocked = state is VaultUnlockedState;
    final isCreated = state is! VaultUninitializedState && state is! VaultInitialState;

    return Container(
      width: 260,
      color: const Color(0xFF070A16),
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
                    color: const Color(0xFF8B5CF6).withOpacity(0.15),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  child: const Icon(Icons.shield, color: Color(0xFF8B5CF6), size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  'AMPCrypt',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
          Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 8),
            child: Text(
              'VAULTS',
              style: GoogleFonts.outfit(
                fontSize: 11,
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
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFF8B5CF6).withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: Icon(
                        isUnlocked ? Icons.lock_open : Icons.lock,
                        color: isUnlocked ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                        size: 22,
                      ),
                      title: Text(
                        'Primary Vault',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      subtitle: Text(
                        context.read<VaultBloc>().repository.getVaultPath(),
                        style: GoogleFonts.shareTechMono(
                          fontSize: 11,
                          color: const Color(0xFF94A3B8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(
                      'No vaults initialized.',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.add, color: Color(0xFF94A3B8)),
                  tooltip: 'Create/Add Vault',
                  onPressed: () => _showCreateVaultDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Color(0xFF94A3B8)),
                  tooltip: 'Settings',
                  onPressed: () => _showSettingsDialog(context),
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
              backgroundColor: const Color(0xFF0F172A),
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
                          icon: const Icon(Icons.folder_open, color: Color(0xFF8B5CF6)),
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
                    backgroundColor: const Color(0xFF8B5CF6),
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
                            backgroundColor: const Color(0xFF10B981),
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

  void _showSettingsDialog(BuildContext context) {
    final repository = context.read<VaultBloc>().repository;
    final currentPath = repository.getVaultPath();
    final currentDrive = repository.getDriveLetter();
    final currentSensitivity = repository.monitorSensitivity;
    final currentAutoLock = repository.autoLockMinutes;

    final pathController = TextEditingController(text: currentPath);
    String selectedDrive = currentDrive;
    double selectedSensitivity = currentSensitivity;
    int selectedAutoLock = currentAutoLock;

    int activeTab = 0;
    bool isScanning = false;
    bool? hasFingerprint;
    bool? hasCamera;
    bool? hasMic;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> runDiagnostic() async {
              setDialogState(() {
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

              setDialogState(() {
                hasFingerprint = fingerprint;
                hasCamera = cameraAvailable;
                hasMic = micAvailable;
                isScanning = false;
              });
            }

            if (hasFingerprint == null && hasCamera == null && hasMic == null && !isScanning) {
              Future.microtask(() => runDiagnostic());
            }

            Widget tabButton(int tabIndex, String label, IconData icon) {
              final isSelected = activeTab == tabIndex;
              return InkWell(
                onTap: () => setDialogState(() => activeTab = tabIndex),
                hoverColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: 15, color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 70,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF8B5CF6) : Colors.transparent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget buildGeneralTab() {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: pathController,
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Vault Folder Path',
                            labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.folder_open, color: Color(0xFF8B5CF6)),
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
                      labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
                    ),
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: selectedAutoLock,
                    dropdownColor: const Color(0xFF1E293B),
                    decoration: InputDecoration(
                      labelText: 'Auto-Lock Inactivity Limit',
                      labelStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF334155))),
                      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF8B5CF6))),
                    ),
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('Never')),
                      const DropdownMenuItem(value: 5, child: Text('5 Minutes')),
                      const DropdownMenuItem(value: 15, child: Text('15 Minutes')),
                      const DropdownMenuItem(value: 30, child: Text('30 Minutes')),
                      const DropdownMenuItem(value: 60, child: Text('60 Minutes')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          selectedAutoLock = val;
                        });
                      }
                    },
                  ),
                ],
              );
            }

            Widget buildSecurityTab() {
              final authLevel = repository.isVaultCreated ? repository.configuredAuthLevel : 1;
              final authLabels = [
                '1FA — Password only',
                '2FA — Password + Fingerprint',
                '3FA — Password + Fingerprint + Face',
                '4FA — Password + Fingerprint + Face + Voice',
              ];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Ransomware Watcher Sensitivity',
                        style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 13),
                      ),
                      Text(
                        selectedSensitivity.toStringAsFixed(2),
                        style: GoogleFonts.shareTechMono(color: const Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Slider(
                    value: selectedSensitivity,
                    min: 0.3,
                    max: 0.9,
                    activeColor: const Color(0xFF8B5CF6),
                    inactiveColor: const Color(0xFF334155),
                    onChanged: (val) {
                      setDialogState(() {
                        selectedSensitivity = val;
                      });
                    },
                  ),
                  Text(
                    'Lower value = higher protection, Higher value = fewer false alarms.',
                    style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 11),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFF1E293B)),
                  const SizedBox(height: 10),
                  Text(
                    'ENROLLED SECURITY FACTOR LEVEL',
                    style: GoogleFonts.shareTechMono(color: const Color(0xFF8B5CF6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined, color: Color(0xFF10B981), size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            authLabels[authLevel - 1],
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            Widget buildHardwareTab() {
              Widget deviceRow(String name, IconData icon, bool? detected) {
                Widget statusWidget;
                if (detected == null) {
                  statusWidget = Row(
                    children: [
                      const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF8B5CF6))),
                      const SizedBox(width: 8),
                      Text('Checking...', style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 12)),
                    ],
                  );
                } else if (detected) {
                  statusWidget = Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 6),
                      Text('Detected', style: GoogleFonts.outfit(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  );
                } else {
                  statusWidget = Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFFEF4444), size: 16),
                      const SizedBox(width: 6),
                      Text('Not Detected / Supported', style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontSize: 12)),
                    ],
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(icon, color: const Color(0xFF94A3B8), size: 18),
                          const SizedBox(width: 12),
                          Text(name, style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                        ],
                      ),
                      statusWidget,
                    ],
                  ),
                );
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  deviceRow('Fingerprint Reader', Icons.fingerprint, hasFingerprint),
                  deviceRow('Webcam / Camera', Icons.camera_alt_outlined, hasCamera),
                  deviceRow('Microphone (Mic)', Icons.mic_none_outlined, hasMic),
                  const SizedBox(height: 16),
                  const Divider(color: Color(0xFF1E293B)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Offline hardware scans via native APIs',
                        style: GoogleFonts.outfit(color: const Color(0xFF64748B), fontSize: 11),
                      ),
                      TextButton.icon(
                        onPressed: isScanning ? null : () => runDiagnostic(),
                        icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF8B5CF6)),
                        label: Text('Scan Again', style: GoogleFonts.outfit(color: const Color(0xFF8B5CF6), fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              );
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF0F172A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AMPCrypt Settings',
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      tabButton(0, 'General', Icons.settings_outlined),
                      tabButton(1, 'Security', Icons.shield_outlined),
                      tabButton(2, 'Hardware', Icons.developer_board),
                    ],
                  ),
                  const Divider(color: Color(0xFF1E293B)),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: IndexedStack(
                  index: activeTab,
                  children: [
                    buildGeneralTab(),
                    buildSecurityTab(),
                    buildHardwareTab(),
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
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    if (pathController.text.isNotEmpty) {
                      final path = pathController.text;
                      final drive = selectedDrive;
                      final sensitivity = selectedSensitivity;
                      final autoLock = selectedAutoLock;
                      Navigator.of(dialogContext).pop();
                      
                      await repository.updateVaultSettings(path, drive);
                      await repository.setMonitorSensitivity(sensitivity);
                      await repository.setAutoLockMinutes(autoLock);
                      
                      if (context.mounted) {
                        context.read<VaultBloc>().add(CheckVaultStatusEvent());
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF10B981),
                            content: Text(
                              'Settings saved successfully.',
                              style: GoogleFonts.outfit(),
                            ),
                          ),
                        );
                      }
                    }
                  },
                  child: Text('Save Settings', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isCreated ? 'Primary Vault' : 'Welcome to AMPCrypt',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    isCreated 
                        ? (isUnlocked ? Icons.lock_open : Icons.lock)
                        : Icons.shield,
                    size: 14,
                    color: isUnlocked ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isCreated
                        ? (isUnlocked ? 'Unlocked' : 'Locked')
                        : 'Secure Zero-Trust System',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: isUnlocked ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (isCreated) ...[
                    const SizedBox(width: 12),
                    Text(
                      '•  Directory: ${context.read<VaultBloc>().repository.getVaultPath()}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Divider(color: Colors.white.withOpacity(0.06), height: 1),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: isUnlocked ? 800 : 500,
                ),
                child: isUnlocked 
                    ? UnlockedDashboardView(state: state)
                    : _buildVaultConsoleView(context, state),
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

  Widget _buildAboutProjectView(BuildContext context, VaultState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'STATUS: ONLINE & VERIFIED',
                      style: GoogleFonts.shareTechMono(
                        color: const Color(0xFF10B981),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Next-Gen Zero-Trust Vault',
                style: GoogleFonts.outfit(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: -1.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Simultaneous Multi-Factor Interlocking (4FA) & Heuristic Ransomware Shielding',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  color: const Color(0xFF94A3B8),
                  fontWeight: FontWeight.w400,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () => setState(() => _showAbout = false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      children: [
                        Text(
                          state is VaultLockedState ? 'UNLOCK SECURE CONSOLE' : 'INITIALIZE SECURE VAULT',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 16),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF94A3B8),
                      side: BorderSide(color: Colors.white.withOpacity(0.12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'VIEW ON GITHUB',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 56),
              _buildVisualDiagram(),
              const SizedBox(height: 56),
              GridView.count(
                crossAxisCount: MediaQuery.of(context).size.width > 700 ? 2 : 1,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: MediaQuery.of(context).size.width > 700 ? 1.5 : 1.8,
                children: [
                  _buildAboutFeatureCard(
                    icon: Icons.shield_outlined,
                    iconColor: const Color(0xFF8B5CF6),
                    title: 'SLIP-39 Secret Splitting',
                    description:
                        'The master key is mathematically split into multiple cryptographic shares using a threshold scheme. No single share can expose the vault.',
                  ),
                  _buildAboutFeatureCard(
                    icon: Icons.vpn_key_outlined,
                    iconColor: const Color(0xFF3B82F6),
                    title: 'Memory-Hard Argon2id Hashing',
                    description:
                        'Protects your passphrase using the industry-leading password hashing algorithm, configured with custom memory and iteration parameters to defeat GPU brute-forcing.',
                  ),
                  _buildAboutFeatureCard(
                    icon: Icons.face_outlined,
                    iconColor: const Color(0xFF10B981),
                    title: 'Edge TFLite Face Embedding',
                    description:
                        'Runs local MobileFaceNet models within your browser or desktop environment to extract biometric signatures without uploading photos to any server.',
                  ),
                  _buildAboutFeatureCard(
                    icon: Icons.bug_report_outlined,
                    iconColor: const Color(0xFFEF4444),
                    title: 'Heuristic Ransomware Monitor',
                    description:
                        'A background engine watches specified directories for rapid writes/deletions. An unsupervised Isolation Forest ML model flags anomalies and locks the vault.',
                  ),
                ],
              ),
              const SizedBox(height: 56),
              GlassmorphicCard(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(28.0),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_user_outlined, color: Color(0xFF10B981), size: 28),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Zero-Data-Leak Guarantee',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'AMPCrypt runs entirely client-side. Cryptographic keys and biometric embeddings are never stored in the database. Firebase handles only trusted device signatures in SHA-256 format.',
                              style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8)),
                            ),
                          ],
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
    );
  }

  Widget _buildAboutFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return GlassmorphicCard(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                description,
                style: GoogleFonts.outfit(
                  fontSize: 12.5,
                  color: const Color(0xFF94A3B8),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualDiagram() {
    return Column(
      children: [
        Text(
          '4-OF-4 OPERATIONAL MULTI-FACTOR INTERLOCKING',
          style: GoogleFonts.shareTechMono(
            fontSize: 12,
            letterSpacing: 2.0,
            color: const Color(0xFF8B5CF6),
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24),
        Container(
          height: 180,
          width: 600,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 100,
                right: 100,
                top: 90,
                child: Container(
                  height: 2,
                  color: const Color(0xFF8B5CF6).withOpacity(0.3),
                ),
              ),
              Positioned(
                left: 300,
                top: 20,
                bottom: 20,
                child: Container(
                  width: 2,
                  color: const Color(0xFF8B5CF6).withOpacity(0.3),
                ),
              ),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0F172A),
                  border: Border.all(color: const Color(0xFF8B5CF6), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8B5CF6).withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.vpn_key, color: Color(0xFF8B5CF6), size: 28),
                    const SizedBox(height: 4),
                    Text(
                      'MASTER KEY',
                      style: GoogleFonts.shareTechMono(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Reconstructed',
                      style: GoogleFonts.outfit(fontSize: 8, color: const Color(0xFF10B981)),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 0,
                child: _buildDiagramNode('Face Share', Icons.face_outlined, const Color(0xFF10B981)),
              ),
              Positioned(
                bottom: 0,
                child: _buildDiagramNode('Voice Share', Icons.record_voice_over_outlined, const Color(0xFF3B82F6)),
              ),
              Positioned(
                left: 10,
                child: _buildDiagramNode('Passphrase Share', Icons.password_outlined, const Color(0xFF8B5CF6)),
              ),
              Positioned(
                right: 10,
                child: _buildDiagramNode('Fingerprint Share', Icons.fingerprint, const Color(0xFFFF9E0B)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiagramNode(String label, IconData icon, Color color) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
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
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
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
                  color: const Color(0xFF8B5CF6),
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
  Color _strengthColor = const Color(0xFFEF4444);

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
        _strengthColor = const Color(0xFFEF4444);
      } else if (strength <= 0.5) {
        _strengthLabel = "Weak";
        _strengthColor = const Color(0xFFF59E0B);
      } else if (strength <= 0.75) {
        _strengthLabel = "Medium";
        _strengthColor = const Color(0xFF3B82F6);
      } else {
        _strengthLabel = "Strong (Argon2id Optimized)";
        _strengthColor = const Color(0xFF10B981);
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
      const Color(0xFF10B981), // 1FA
      const Color(0xFF3B82F6), // 2FA
      const Color(0xFFF59E0B), // 3FA
      const Color(0xFF8B5CF6), // 4FA
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
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
          child: Form(
            key: _formKey,
            child: GlassmorphicCard(
              width: MediaQuery.of(context).size.width > 500 ? 450 : MediaQuery.of(context).size.width - 32,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF8B5CF6).withOpacity(0.1),
                          border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3), width: 1.5),
                        ),
                        child: const Icon(Icons.shield_outlined, size: 40, color: Color(0xFF8B5CF6)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Initialize AMPCrypt Vault',
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Select your security level, then create a master password to generate SLIP-39 zero-trust shares.',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // ─── N-Factor Security Level Selector ───────────────────
                    Text(
                      'SECURITY LEVEL',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: 2.6,
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
                    const SizedBox(height: 28),
                    Text(
                      'VAULT PASSPHRASE',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: GoogleFonts.outfit(color: Colors.white),
                      onChanged: _checkPasswordStrength,
                      decoration: _inputDecoration(
                        hint: 'Enter strong password',
                        prefix: Icons.lock_open_outlined,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 20,
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
                    const SizedBox(height: 12),
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
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _strengthLabel,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _strengthColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'CONFIRM PASSPHRASE',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
                      style: GoogleFonts.outfit(color: Colors.white),
                      decoration: _inputDecoration(
                        hint: 'Retype password',
                        prefix: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 20,
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
                    const SizedBox(height: 32),
                    // Setup Info Notice
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.05),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2), width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Offline generation using SLIP-0039. Your Master Key is split and protected locally. No data leaves your machine.',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _submitSetup,
                        child: Text(
                          'GENERATE VAULT',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          // Jump straight to recovery screen if they already have backup phrases
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RecoveryPage()),
                          );
                        },
                        child: Text(
                          'Already have recovery mnemonics?',
                          style: GoogleFonts.outfit(color: const Color(0xFF8B5CF6), fontSize: 13),
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
            backgroundColor: const Color(0xFF10B981),
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
          backgroundColor: const Color(0xFF3B82F6),
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
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: GlassmorphicCard(
            width: MediaQuery.of(context).size.width > 500 ? 450 : MediaQuery.of(context).size.width - 32,
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3), width: 1.5),
                      ),
                      child: const Icon(Icons.lock_outline, size: 40, color: Color(0xFF3B82F6)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Vault Locked',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Provide password and biometric factors to reconstruct the Master Key.',
                      style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Password Input
                  Text(
                    'PASSWORD FACTOR',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: _inputDecoration(
                      hint: 'Enter vault password',
                      prefix: Icons.key_outlined,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // ─── Dynamic Security Factors (based on auth level) ────────
                  if (_configuredAuthLevel > 1) ...[
                    Text(
                      '$_configuredAuthLevel-FACTOR AUTHENTICATION (${_configuredAuthLevel}FA)',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: const Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Validate each factor to reconstruct the SLIP-39 master key.',
                      style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    // Factor 1: Fingerprint (2FA+)
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
                    // Factor 2: Face (3FA+)
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
                    // Factor 3: Voice (4FA)
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
                    // 1FA: password-only notice
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.05),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outlined, color: Color(0xFF10B981), size: 16),
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
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _submitUnlock,
                      child: Text(
                        'UNLOCK VAULT',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 8,
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
                          style: GoogleFonts.outfit(color: const Color(0xFFFF9E0B), fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Clear everything (Reset)
                          context.read<VaultBloc>().add(ResetToUninitializedEvent());
                        },
                        child: Text(
                          'Reset & Wipe Vault',
                          style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: value ? const Color(0xFF3B82F6).withOpacity(0.08) : const Color(0xFF1E1E38).withOpacity(0.4),
        border: Border.all(
          color: value ? const Color(0xFF3B82F6).withOpacity(0.3) : const Color(0xFF1E1E38).withOpacity(0.5),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: value ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFF3B82F6),
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
    if (score < 0.3) return const Color(0xFF10B981);
    if (score < 0.5) return Colors.yellow;
    if (score < 0.65) return Colors.orange;
    return const Color(0xFFEF4444);
  }

  String _getRiskLevelText(double score) {
    if (score < 0.3) return 'LOW RISK';
    if (score < 0.5) return 'NORMAL';
    if (score < 0.65) return 'ELEVATED';
    return 'CRITICAL';
  }

  Widget _featureMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(fontSize: 8, color: const Color(0xFF64748B), fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.shareTechMono(fontSize: 11, color: Colors.white),
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
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Vault Header Card
              GlassmorphicCard(
                width: 700,
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                                ),
                                child: const Icon(Icons.lock_open_outlined, color: Color(0xFF10B981), size: 28),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AMPCrypt Vault Decrypted',
                                    style: GoogleFonts.outfit(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Zero-Trust Local-First Encryption Active',
                                    style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF10B981)),
                                  ),
                                  const SizedBox(height: 6),
                                  // Security level badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B5CF6).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4)),
                                    ),
                                    child: Text(
                                      '${widget.state.authLevel}FA — ${const ['', 'Password Only', 'Password + Fingerprint', 'Password + Fingerprint + Face', 'All Factors (Max)'][widget.state.authLevel]}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF8B5CF6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF334155),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.lock_outlined, size: 16),
                            label: Text('LOCK', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              context.read<VaultBloc>().add(LockVaultEvent());
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Reconstructed Master Key disclosure
                      Text(
                        'RECONSTRUCTED MASTER KEY (256-BIT)',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.7),
                          border: Border.all(color: const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.key, color: Color(0xFF8B5CF6), size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.state.masterKeyHex,
                                style: GoogleFonts.shareTechMono(
                                  color: Colors.white,
                                  fontSize: 14,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _copied ? Icons.check : Icons.copy,
                                color: _copied ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                size: 18,
                              ),
                              onPressed: () => _copyKey(widget.state.masterKeyHex),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),
                      // WebDAV Virtual Drive Status Card
                      if (widget.state.webDavPort != null) ...[
                        Text(
                          'SECURE VIRTUAL DRIVE',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: const Color(0xFF10B981),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFF10B981).withOpacity(0.08),
                                const Color(0xFF0F172A).withOpacity(0.8),
                              ],
                            ),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.25)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Color(0xFF10B981),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Mounted on drive Z:',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your vault files are securely serving locally. Any changes made to Z:\\ are automatically encrypted with AES-256-GCM and persisted on your local disk.',
                                style: GoogleFonts.outfit(
                                  color: const Color(0xFF94A3B8),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.lan_outlined, color: Color(0xFF64748B), size: 14),
                                      const SizedBox(width: 6),
                                      Text(
                                        'http://localhost:${widget.state.webDavPort}',
                                        style: GoogleFonts.shareTechMono(
                                          color: const Color(0xFF64748B),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    ),
                                    icon: const Icon(Icons.folder_open, size: 16),
                                    label: Text(
                                      'OPEN VIRTUAL DRIVE',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    onPressed: () {
                                      Process.run('explorer.exe', ['Z:']);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Text(
                          'SECURE VIRTUAL DRIVE',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: const Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.05),
                            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_outlined, color: Color(0xFFEF4444), size: 24),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Virtual Drive Inactive',
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'The local WebDAV mounting server is not active. Drive Z: cannot be mounted.',
                                      style: GoogleFonts.outfit(
                                        color: const Color(0xFF94A3B8),
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Warn if newly created and show Backup Recovery mnemonics
                      if (isNewVault) ...[
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.05),
                            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9E0B), size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'SLIP-39 BACKUP RECOVERY PHRASES (MUST RECORD)',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFFFF9E0B),
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.copy_all, size: 14, color: Color(0xFFFF9E0B)),
                                    label: Text(
                                      'Copy All',
                                      style: GoogleFonts.outfit(color: const Color(0xFFFF9E0B), fontSize: 12),
                                    ),
                                    onPressed: () {
                                      final allPhrases = widget.state.backupRecoveryPhrases!.join('\n\n');
                                      Clipboard.setData(ClipboardData(text: allPhrases));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF1E293B),
                                          content: Text(
                                            'All recovery phrases copied to clipboard',
                                            style: GoogleFonts.outfit(color: Colors.white),
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Write down these phrases in order. Any 2 of these 3 phrases can recover your master key offline if you lose biometrics or device access.',
                                style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                              ),
                              const SizedBox(height: 16),
                              Column(
                                children: List.generate(widget.state.backupRecoveryPhrases!.length, (index) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E1E38).withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF334155).withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 10,
                                          backgroundColor: const Color(0xFF8B5CF6),
                                          child: Text(
                                            '${index + 1}',
                                            style: GoogleFonts.outfit(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: SelectableText(
                                            widget.state.backupRecoveryPhrases![index],
                                            style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 13),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 16, color: Color(0xFF94A3B8)),
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: widget.state.backupRecoveryPhrases![index]));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                backgroundColor: const Color(0xFF1E293B),
                                                content: Text(
                                                  'Recovery phrase ${index + 1} copied to clipboard',
                                                  style: GoogleFonts.outfit(color: Colors.white),
                                                ),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 2. Device Status Card
              GlassmorphicCard(
                width: 700,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRUSTED DEVICE & CRYPTO STATUS (LOCAL MOCK)',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _statusItem(
                              label: 'Device Status',
                              value: (status['is_trusted'] ?? false) ? 'Trusted' : 'Untrusted',
                              icon: Icons.devices,
                              color: (status['is_trusted'] ?? false) ? const Color(0xFF10B981) : Colors.orange,
                            ),
                          ),
                          Expanded(
                            child: _statusItem(
                              label: 'Hardware Binding',
                              value: 'Simulated TPM',
                              icon: Icons.developer_board,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                          Expanded(
                            child: _statusItem(
                              label: 'Fingerprint ID',
                              value: status['device_fingerprint'] ?? 'N/A',
                              icon: Icons.fingerprint,
                              color: const Color(0xFF8B5CF6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // 3. Ransomware Protection Monitor Card
              BlocBuilder<MonitorBloc, MonitorState>(
                builder: (context, monitorState) {
                  return GlassmorphicCard(
                    width: 700,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    color: monitorState.isMonitoring 
                                        ? (monitorState.isCalibrating ? Colors.orange : const Color(0xFF10B981)) 
                                        : const Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'HEURISTIC RANSOMWARE PROTECTOR',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                      color: monitorState.isMonitoring 
                                          ? (monitorState.isCalibrating ? Colors.orange : const Color(0xFF10B981)) 
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: monitorState.isMonitoring 
                                      ? (monitorState.isCalibrating ? Colors.orange.withOpacity(0.1) : const Color(0xFF10B981).withOpacity(0.1)) 
                                      : const Color(0xFF334155).withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: monitorState.isMonitoring 
                                        ? (monitorState.isCalibrating ? Colors.orange.withOpacity(0.3) : const Color(0xFF10B981).withOpacity(0.3)) 
                                        : const Color(0xFF334155).withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  monitorState.isMonitoring 
                                      ? (monitorState.isCalibrating ? 'CALIBRATING' : 'PROTECTION ACTIVE') 
                                      : 'MONITOR INACTIVE',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: monitorState.isMonitoring 
                                        ? (monitorState.isCalibrating ? Colors.orange : const Color(0xFF10B981)) 
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Color(0xFF1E293B), height: 30),
                          
                          if (!monitorState.isMonitoring) ...[
                            Text(
                              'Select a local directory to watch and analyze for ransomware-like behavior (unsupervised anomaly detection).',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A).withOpacity(0.5),
                                      border: Border.all(color: const Color(0xFF1E293B)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _selectedMonitorPath ?? 'No directory selected',
                                      style: GoogleFonts.shareTechMono(
                                        fontSize: 12,
                                        color: _selectedMonitorPath != null ? Colors.white : const Color(0xFF475569),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E293B),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  icon: const Icon(Icons.folder_open, size: 16),
                                  label: Text('CHOOSE', style: GoogleFonts.outfit(fontSize: 12)),
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
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed: _selectedMonitorPath == null 
                                    ? null 
                                    : () {
                                        context.read<MonitorBloc>().add(StartMonitoringEvent(_selectedMonitorPath!));
                                      },
                                child: Text('START ACTIVE MONITORING', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
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
                                        style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        monitorState.watchedPath ?? '',
                                        style: GoogleFonts.shareTechMono(fontSize: 12, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFEF4444)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  icon: const Icon(Icons.stop, size: 16, color: Color(0xFFEF4444)),
                                  label: Text('STOP MONITOR', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFEF4444))),
                                  onPressed: () {
                                    context.read<MonitorBloc>().add(StopMonitoringEvent());
                                  },
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 20),
                            
                            if (monitorState.isCalibrating) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'CALIBRATING DETECTOR BASELINE...',
                                    style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange),
                                  ),
                                  Text(
                                    '${(monitorState.calibrationProgress * 100).toInt()}%',
                                    style: GoogleFonts.shareTechMono(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: monitorState.calibrationProgress,
                                backgroundColor: const Color(0xFF1E293B),
                                color: Colors.orange,
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Recording normal filesystem actions. Do not execute bulk renames or large edits yet.',
                                style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
                              ),
                            ] else ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A).withOpacity(0.5),
                                      border: Border.all(color: const Color(0xFF1E293B)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          'ANOMALY SCORE',
                                          style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          monitorState.currentAnomalyScore.toStringAsFixed(3),
                                          style: GoogleFonts.shareTechMono(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: _getScoreColor(monitorState.currentAnomalyScore),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _getRiskLevelText(monitorState.currentAnomalyScore),
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _getScoreColor(monitorState.currentAnomalyScore),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Container(
                                      height: 105,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A).withOpacity(0.5),
                                        border: Border.all(color: const Color(0xFF1E293B)),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'REAL-TIME ANOMALY TRACK (LAST 20 SECONDS)',
                                            style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                          ),
                                          const Spacer(),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: List.generate(20, (index) {
                                              final double val = index < monitorState.recentScores.length
                                                  ? monitorState.recentScores[index]
                                                  : 0.0;
                                              return Container(
                                                width: 18,
                                                height: 55 * val + 3,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.bottomCenter,
                                                    end: Alignment.topCenter,
                                                    colors: [
                                                      const Color(0xFF3B82F6).withOpacity(0.3),
                                                      _getScoreColor(val),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(3),
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
                              
                              const SizedBox(height: 20),
                              
                              if (monitorState.recentFeatures.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1E38).withOpacity(0.2),
                                    border: Border.all(color: const Color(0xFF1E293B).withOpacity(0.5)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _featureMetric('Write rate', '${(monitorState.recentFeatures.last.writeRate * 5).toInt()} events/5s'),
                                      _featureMetric('Delete rate', '${(monitorState.recentFeatures.last.deleteRate * 5).toInt()} events/5s'),
                                      _featureMetric('Suspicious Ext', '${(monitorState.recentFeatures.last.extensionEntropy * 100).toInt()}%'),
                                      _featureMetric('Avg size', '${monitorState.recentFeatures.last.sizeDifference.toStringAsFixed(1)} KB'),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ],
                      ),
                    ),
                  );
                },
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
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E38).withOpacity(0.3),
        border: Border.all(color: const Color(0xFF1E293B)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 13,
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

// ==========================================
// 5. Recovery View / Page (Input recovery mnemonics)
// ==========================================
class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key});

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final _phrase1Controller = TextEditingController();
  final _phrase2Controller = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _phrase1Controller.dispose();
    _phrase2Controller.dispose();
    super.dispose();
  }

  // Robust phrase cleaner: removes lowercase, number prefixes, collapses spaces
  String _cleanPhrase(String phrase) {
    var cleaned = phrase.trim().toLowerCase();
    // Strip starting number prefixes like "1. ", "1: ", "1 - ", "[1] " or "1 "
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      appBar: AppBar(
        title: Text('Recovery Mode', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Recheck state on back navigation to clear error states if present
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
              // Successfully unlocked, pop back to main page (which will now display UnlockedDashboardView)
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
                    width: 550,
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFF9E0B).withOpacity(0.1),
                                border: Border.all(color: const Color(0xFFFF9E0B).withOpacity(0.3), width: 1.5),
                              ),
                              child: const Icon(Icons.restore_outlined, size: 40, color: Color(0xFFFF9E0B)),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: Text(
                              'Reconstruct Master Key',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Provide 2 out of the 3 generated SLIP-39 backup phrases to restore your vault.',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (errorMsg != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withOpacity(0.08),
                                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
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
                          const SizedBox(height: 32),
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
            const Color(0xFF0F172A).withOpacity(0.6),
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
      borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFEF4444)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
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
              backgroundColor: const Color(0xFF10B981),
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
                  color: const Color(0xFFEF4444).withOpacity(0.08),
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
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4), width: 1.5),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withOpacity(0.2),
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
                              color: const Color(0xFFEF4444).withOpacity(0.1 + (_pulseController.value * 0.15)),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFEF4444).withOpacity(0.3 + (_pulseController.value * 0.4)),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.security_update_warning_outlined,
                              color: Color(0xFFEF4444),
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
                          color: const Color(0xFFEF4444),
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
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DETECTION DETAILS:',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFEF4444),
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
                          fillColor: const Color(0xFF0F172A).withOpacity(0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFEF4444)),
                          ),
                          errorText: _error,
                          errorStyle: GoogleFonts.outfit(color: const Color(0xFFEF4444)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
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
          color: const Color(0xFF0F172A).withOpacity(0.95),
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
                    color: const Color(0xFF3B82F6),
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
                      ? const Color(0xFFEF4444).withOpacity(0.5) 
                      : const Color(0xFF3B82F6).withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _selectedFile != null
                    ? Image.file(_selectedFile!, fit: BoxFit.cover)
                    : Icon(
                        widget.isEnrolled ? Icons.face : Icons.add_a_photo_outlined,
                        size: 64,
                        color: _errorMessage != null ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
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
                  color: const Color(0xFFEF4444),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            const SizedBox(height: 28),
            
            if (_isLoading)
              const CircularProgressIndicator(color: Color(0xFF3B82F6))
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
                        backgroundColor: const Color(0xFF3B82F6),
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
          color: const Color(0xFF0F172A).withOpacity(0.95),
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
                    color: const Color(0xFF3B82F6),
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
                      ? const Color(0xFFEF4444).withOpacity(0.5) 
                      : const Color(0xFF3B82F6).withOpacity(0.3),
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
                          color: Color(0xFF10B981),
                        ),
                      )
                    : Icon(
                        widget.isEnrolled ? Icons.mic : Icons.mic_none_outlined,
                        size: 64,
                        color: _errorMessage != null ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
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
                  color: const Color(0xFFEF4444),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            const SizedBox(height: 28),
            
            if (_isLoading)
              const CircularProgressIndicator(color: Color(0xFF3B82F6))
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
                        backgroundColor: const Color(0xFF3B82F6),
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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../../../main.dart';

class PreferencesDialog extends StatefulWidget {
  final int initialTabIndex;
  final Function(ThemeMode)? onThemeChanged;

  const PreferencesDialog({
    super.key,
    this.initialTabIndex = 0,
    this.onThemeChanged,
  });

  @override
  State<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends State<PreferencesDialog> {
  late int _activeTabIndex;

  // Settings State
  bool _launchOnStart = true;
  bool _hideOnStart = false;
  bool _lockOnQuit = false;
  bool _storePasswords = true;
  String _passwordStoreType = 'Windows Data Protection';
  bool _addToQuickAccess = true;
  String _quickAccessLocation = 'Explorer Navigation Pane';
  bool _debugLogging = false;

  String _lookAndFeel = 'Light';
  String _language = 'System Default';
  String _orientation = 'LTR';
  bool _showTrayIcon = true;
  bool _compactVaultList = false;

  String _volumeType = 'Automatic';

  bool _autoCheckUpdates = true;
  String _appVersion = '0.65.0';

  @override
  void initState() {
    super.initState();
    _activeTabIndex = widget.initialTabIndex;
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pkg = await PackageInfo.fromPlatform();
      setState(() {
        _launchOnStart = prefs.getBool('launch_on_start') ?? true;
        _hideOnStart = prefs.getBool('hide_on_start') ?? false;
        _lockOnQuit = prefs.getBool('lock_on_quit') ?? false;
        _storePasswords = prefs.getBool('store_passwords') ?? true;
        _passwordStoreType = prefs.getString('password_store_type') ?? 'Windows Data Protection';
        _addToQuickAccess = prefs.getBool('add_to_quick_access') ?? true;
        _quickAccessLocation = prefs.getString('quick_access_location') ?? 'Explorer Navigation Pane';
        _debugLogging = prefs.getBool('debug_logging') ?? false;

        _lookAndFeel = prefs.getString('look_and_feel') ?? 'Light';
        _language = prefs.getString('language') ?? 'System Default';
        _orientation = prefs.getString('orientation') ?? 'LTR';
        _showTrayIcon = prefs.getBool('show_tray_icon') ?? true;
        _compactVaultList = prefs.getBool('compact_vault_list') ?? false;

        _volumeType = prefs.getString('volume_type') ?? 'Automatic';
        _autoCheckUpdates = prefs.getBool('auto_check_updates') ?? true;
        _appVersion = pkg.version.isNotEmpty ? pkg.version : '0.65.0';
      });
    } catch (_) {}
  }

  Future<void> _saveBoolPref(String key, bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, val);
  }

  Future<void> _saveStringPref(String key, String val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, val);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFFAFAFA);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: dialogBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: SizedBox(
        width: 720,
        height: 480,
        child: Column(
          children: [
            // Top Window Title Bar for Preferences
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  Image.asset(
                    'assets/app_icon.ico',
                    width: 16,
                    height: 16,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.security_rounded,
                      color: Color(0xFF22C55E),
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Preferences',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 16),
                    color: subtitleColor,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Preference Navigation Tabs (6 Tabs)
            Container(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  _buildTabItem(0, Icons.build_rounded, 'General'),
                  _buildTabItem(1, Icons.visibility_rounded, 'Interface'),
                  _buildTabItem(2, Icons.storage_rounded, 'Virtual Drive'),
                  _buildTabItem(3, Icons.refresh_rounded, 'Updates'),
                  _buildTabItem(4, Icons.favorite_rounded, 'Support Us'),
                  _buildTabItem(5, Icons.info_rounded, 'About'),
                ],
              ),
            ),

            // Tab View Body
            Expanded(
              child: Container(
                color: cardBg,
                padding: const EdgeInsets.all(24),
                child: IndexedStack(
                  index: _activeTabIndex,
                  children: [
                    _buildGeneralTab(textColor, subtitleColor, borderColor),
                    _buildInterfaceTab(textColor, subtitleColor, borderColor),
                    _buildVirtualDriveTab(textColor, subtitleColor, borderColor),
                    _buildUpdatesTab(textColor, subtitleColor),
                    _buildSupportTab(textColor, subtitleColor),
                    _buildAboutTab(textColor, subtitleColor),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int index, IconData icon, String label) {
    final isSelected = _activeTabIndex == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const activeColor = Color(0xFF22C55E); // Cryptomator Green
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeTabIndex = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? activeColor : Colors.transparent,
                width: 3.0,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected ? activeColor : inactiveColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? activeColor : inactiveColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 1: GENERAL ---
  Widget _buildGeneralTab(Color textColor, Color subtitleColor, Color borderColor) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _checkboxRow(
            'Launch AMPCrypt on system start',
            _launchOnStart,
            (val) async {
              final enabled = val ?? false;
              setState(() => _launchOnStart = enabled);
              await _saveBoolPref('launch_on_start', enabled);
              try {
                if (enabled) {
                  await launchAtStartup.enable();
                } else {
                  await launchAtStartup.disable();
                }
              } catch (_) {}
            },
            textColor,
          ),
          const SizedBox(height: 12),
          _checkboxRow(
            'Hide window when starting AMPCrypt',
            _hideOnStart,
            (val) {
              final enabled = val ?? false;
              setState(() => _hideOnStart = enabled);
              _saveBoolPref('hide_on_start', enabled);
            },
            textColor,
          ),
          const SizedBox(height: 12),
          _checkboxRow(
            'Lock vaults without asking when quitting application',
            _lockOnQuit,
            (val) {
              final enabled = val ?? false;
              setState(() => _lockOnQuit = enabled);
              _saveBoolPref('lock_on_quit', enabled);
            },
            textColor,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _storePasswords,
                activeColor: const Color(0xFF22C55E),
                onChanged: (val) {
                  final enabled = val ?? false;
                  setState(() => _storePasswords = enabled);
                  _saveBoolPref('store_passwords', enabled);
                },
              ),
              Text(
                'Store passwords with',
                style: GoogleFonts.outfit(color: textColor, fontSize: 13),
              ),
              const SizedBox(width: 12),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _passwordStoreType,
                    style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                    items: ['Windows Data Protection', 'Keyring / Keychain', 'Memory Only']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: _storePasswords ? (val) {
                      if (val != null) {
                        setState(() => _passwordStoreType = val);
                        _saveStringPref('password_store_type', val);
                      }
                    } : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Checkbox(
                value: _addToQuickAccess,
                activeColor: const Color(0xFF22C55E),
                onChanged: (val) {
                  final enabled = val ?? false;
                  setState(() => _addToQuickAccess = enabled);
                  _saveBoolPref('add_to_quick_access', enabled);
                },
              ),
              Text(
                'Add unlocked vaults to the quick access area',
                style: GoogleFonts.outfit(color: textColor, fontSize: 13),
              ),
              const SizedBox(width: 12),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _quickAccessLocation,
                    style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                    items: ['Explorer Navigation Pane', 'Desktop Shortcut', 'Disabled']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: _addToQuickAccess ? (val) {
                      if (val != null) {
                        setState(() => _quickAccessLocation = val);
                        _saveStringPref('quick_access_location', val);
                      }
                    } : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: borderColor),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('trusted_hosts');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF22C55E),
                    content: Text('Trusted hosts reset.', style: GoogleFonts.outfit()),
                  ),
                );
              }
            },
            child: Text(
              'Reset trusted hosts',
              style: GoogleFonts.outfit(color: textColor, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Checkbox(
                value: _debugLogging,
                activeColor: const Color(0xFF22C55E),
                onChanged: (val) {
                  final enabled = val ?? false;
                  setState(() => _debugLogging = enabled);
                  _saveBoolPref('debug_logging', enabled);
                },
              ),
              Text(
                'Enable debug logging',
                style: GoogleFonts.outfit(color: textColor, fontSize: 13),
              ),
              const SizedBox(width: 16),
              InkWell(
                onTap: () async {
                  try {
                    final dir = await getApplicationSupportDirectory();
                    final logFile = File(p.join(dir.path, 'ampcrypt_debug.log'));
                    if (!await logFile.exists()) {
                      await logFile.writeAsString('=== AMPCrypt Debug Log ===\nInitialized at ${DateTime.now()}\n');
                    }
                    await launchUrl(Uri.file(logFile.path));
                  } catch (_) {}
                },
                child: Text(
                  'Reveal log files',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF2563EB),
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- TAB 2: INTERFACE ---
  Widget _buildInterfaceTab(Color textColor, Color subtitleColor, Color borderColor) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  'Look & Feel',
                  style: GoogleFonts.outfit(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _lookAndFeel,
                    style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                    items: ['Light', 'Dark', 'System Default']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _lookAndFeel = val);
                        _saveStringPref('look_and_feel', val);
                        ThemeMode mode = ThemeMode.system;
                        if (val == 'Light') mode = ThemeMode.light;
                        if (val == 'Dark') mode = ThemeMode.dark;
                        if (widget.onThemeChanged != null) {
                          widget.onThemeChanged!(mode);
                        }
                        MyApp.of(context)?.setThemeMode(mode);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 16),
              InkWell(
                onTap: () {
                  setState(() => _lookAndFeel = 'Dark');
                  _saveStringPref('look_and_feel', 'Dark');
                  MyApp.of(context)?.setThemeMode(ThemeMode.dark);
                },
                child: Text(
                  'Unlock dark mode',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF2563EB),
                    fontSize: 13,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  'Language (requires restart)',
                  style: GoogleFonts.outfit(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _language,
                    style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                    items: ['System Default', 'English', 'Spanish', 'German', 'French']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _language = val);
                        _saveStringPref('language', val);
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  'Interface Orientation',
                  style: GoogleFonts.outfit(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              Radio<String>(
                value: 'LTR',
                groupValue: _orientation,
                activeColor: const Color(0xFF22C55E),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _orientation = val);
                    _saveStringPref('orientation', val);
                  }
                },
              ),
              Text('Left to Right', style: GoogleFonts.outfit(color: textColor, fontSize: 13)),
              const SizedBox(width: 20),
              Radio<String>(
                value: 'RTL',
                groupValue: _orientation,
                activeColor: const Color(0xFF22C55E),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _orientation = val);
                    _saveStringPref('orientation', val);
                  }
                },
              ),
              Text('Right to Left', style: GoogleFonts.outfit(color: textColor, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 18),
          _checkboxRow(
            'Show tray icon (requires restart)',
            _showTrayIcon,
            (val) {
              final enabled = val ?? false;
              setState(() => _showTrayIcon = enabled);
              _saveBoolPref('show_tray_icon', enabled);
            },
            textColor,
          ),
          const SizedBox(height: 12),
          _checkboxRow(
            'Enable compact vault list',
            _compactVaultList,
            (val) {
              final enabled = val ?? false;
              setState(() => _compactVaultList = enabled);
              _saveBoolPref('compact_vault_list', enabled);
            },
            textColor,
          ),
        ],
      ),
    );
  }

  // --- TAB 3: VIRTUAL DRIVE ---
  Widget _buildVirtualDriveTab(Color textColor, Color subtitleColor, Color borderColor) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 150,
                child: Text(
                  'Default Volume Type',
                  style: GoogleFonts.outfit(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _volumeType,
                    style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                    items: ['Automatic', 'WinFsp (Preferred)', 'WebDAV']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _volumeType = val);
                        _saveStringPref('volume_type', val);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.help_outline_rounded, size: 18, color: subtitleColor),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: borderColor, height: 1),
          const SizedBox(height: 20),
          Text(
            'The chosen volume type supports the following features:',
            style: GoogleFonts.outfit(color: textColor, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          _featureCheckRow('Automatic mount point selection', textColor),
          const SizedBox(height: 10),
          _featureCheckRow('Drive letter as mount point', textColor),
          const SizedBox(height: 10),
          _featureCheckRow('Custom mount options', textColor),
          const SizedBox(height: 10),
          _featureCheckRow('Read-only mount', textColor),
        ],
      ),
    );
  }

  Widget _featureCheckRow(String feature, Color textColor) {
    return Row(
      children: [
        const Icon(Icons.check_rounded, color: Color(0xFF22C55E), size: 18),
        const SizedBox(width: 10),
        Text(feature, style: GoogleFonts.outfit(color: textColor, fontSize: 13)),
      ],
    );
  }

  // --- TAB 4: UPDATES ---
  Widget _buildUpdatesTab(Color textColor, Color subtitleColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Current Version: $_appVersion',
            style: GoogleFonts.outfit(color: textColor, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _autoCheckUpdates,
                activeColor: const Color(0xFF22C55E),
                onChanged: (val) {
                  final enabled = val ?? false;
                  setState(() => _autoCheckUpdates = enabled);
                  _saveBoolPref('auto_check_updates', enabled);
                },
              ),
              Text(
                'Check for updates automatically',
                style: GoogleFonts.outfit(color: textColor, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'AMPCrypt is up to date (Version $_appVersion).',
            style: GoogleFonts.outfit(color: subtitleColor, fontSize: 13),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF388E3C), // Vibrant Green
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              try {
                await launchUrl(Uri.parse('https://github.com/pranto48/AMPCrypt/releases'));
              } catch (_) {}
            },
            child: Text(
              'Visit Download Page',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 5: SUPPORT US ---
  Widget _buildSupportTab(Color textColor, Color subtitleColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite_rounded, color: Color(0xFFE11D48), size: 44),
          const SizedBox(height: 14),
          Text(
            'Support AMPCrypt Development',
            style: GoogleFonts.outfit(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'AMPCrypt is an open-source zero-trust encryption project designed to protect your privacy and shield data from ransomware.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: subtitleColor, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.volunteer_activism, size: 16),
            label: Text('Donate / Sponsor AMPCrypt', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            onPressed: () async {
              try {
                await launchUrl(Uri.parse('https://github.com/pranto48/AMPCrypt'));
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }

  // --- TAB 6: ABOUT ---
  Widget _buildAboutTab(Color textColor, Color subtitleColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF22C55E),
            ),
            child: const Icon(Icons.security_rounded, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            'AMPCrypt Zero-Trust Vault',
            style: GoogleFonts.outfit(color: textColor, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Version $_appVersion (Build 65)',
            style: GoogleFonts.outfit(color: subtitleColor, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            '© 2026 IT Support BD. Distributed under the MIT License.',
            style: GoogleFonts.outfit(color: subtitleColor, fontSize: 11),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              try {
                await launchUrl(Uri.parse('https://github.com/pranto48/AMPCrypt'));
              } catch (_) {}
            },
            child: Text(
              'https://github.com/pranto48/AMPCrypt',
              style: GoogleFonts.outfit(
                color: const Color(0xFF2563EB),
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkboxRow(String label, bool value, ValueChanged<bool?> onChanged, Color textColor) {
    return Row(
      children: [
        Checkbox(
          value: value,
          activeColor: const Color(0xFF22C55E),
          onChanged: onChanged,
        ),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.outfit(color: textColor, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

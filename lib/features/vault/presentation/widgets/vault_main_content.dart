import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VaultMainContent extends StatelessWidget {
  final String vaultName;
  final String vaultPath;
  final String driveLetter;
  final bool isUnlocked;
  final bool isLoading;
  final String? loadingMessage;
  final VoidCallback onRevealDrive;
  final VoidCallback onLock;
  final Function(String password) onUnlock;
  final VoidCallback onLocateEncryptedFile;
  final VoidCallback onDecryptFileName;
  final VoidCallback? onRecoveryTap;
  final VoidCallback? onLocateVault;

  const VaultMainContent({
    super.key,
    required this.vaultName,
    required this.vaultPath,
    required this.driveLetter,
    required this.isUnlocked,
    this.isLoading = false,
    this.loadingMessage,
    required this.onRevealDrive,
    required this.onLock,
    required this.onUnlock,
    required this.onLocateEncryptedFile,
    required this.onDecryptFileName,
    this.onRecoveryTap,
    this.onLocateVault,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B101D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    final passwordController = TextEditingController();
    final isDirectoryMissing = !Directory(vaultPath).existsSync();

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDirectoryMissing
                      ? const Color(0xFFE11D48)
                      : (isUnlocked ? const Color(0xFF388E3C) : const Color(0xFF388E3C)),
                ),
                child: Icon(
                  isDirectoryMissing
                      ? Icons.folder_off_rounded
                      : (isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded),
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vaultName,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vaultPath,
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: isDirectoryMissing ? const Color(0xFFE11D48) : subtitleColor,
                        fontWeight: isDirectoryMissing ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Status Pill Badge Top Right
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isDirectoryMissing
                      ? const Color(0xFFE11D48)
                      : (isUnlocked ? const Color(0xFF388E3C) : (isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8))),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isDirectoryMissing ? 'MISSING' : (isUnlocked ? 'UNLOCKED' : 'LOCKED'),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),

          const Spacer(),

          // Main Center Content
          if (isLoading)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF388E3C)),
                  const SizedBox(height: 16),
                  Text(
                    loadingMessage ?? 'Processing cryptography operation...',
                    style: GoogleFonts.outfit(color: subtitleColor, fontSize: 13),
                  ),
                ],
              ),
            )
          else if (isDirectoryMissing)
            Center(
              child: Container(
                width: 440,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1B2E) : const Color(0xFFFFF1F2),
                  border: Border.all(color: isDark ? const Color(0xFF881337) : const Color(0xFFFECDD3)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFE11D48), size: 40),
                    const SizedBox(height: 12),
                    Text(
                      'Vault Folder Not Found',
                      style: GoogleFonts.outfit(
                        color: isDark ? Colors.white : const Color(0xFF9F1239),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Vault folder missing at "$vaultPath". The directory may have been renamed or moved.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: isDark ? const Color(0xFFFDA4AF) : const Color(0xFFBE123C),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: Text(
                        'Locate Vault Folder...',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: onLocateVault,
                    ),
                  ],
                ),
              ),
            )
          else if (isUnlocked) ...[
            // Vault Unlocked Content View
            Center(
              child: Column(
                children: [
                  Text(
                    "Your vault's contents are accessible here:",
                    style: GoogleFonts.outfit(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Big Action Button: Reveal Drive
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF388E3C),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(220, 64),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 2,
                    ),
                    onPressed: onRevealDrive,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.dns_rounded, size: 28),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Reveal Drive',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              driveLetter,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Lock Button
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: borderColor, width: 1.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                    ),
                    icon: const Icon(Icons.vpn_key_outlined, size: 16),
                    label: Text(
                      'Lock',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    onPressed: onLock,
                  ),
                ],
              ),
            ),
          ] else ...[
            // Vault Locked View
            Center(
              child: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter Master Password to Unlock Vault',
                      style: GoogleFonts.outfit(
                        color: textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      style: GoogleFonts.outfit(color: textColor, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Master Password',
                        hintStyle: GoogleFonts.outfit(color: subtitleColor, fontSize: 13),
                        prefixIcon: const Icon(Icons.lock_outline, size: 18),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: Color(0xFF388E3C), width: 1.5),
                        ),
                      ),
                      onSubmitted: (val) => onUnlock(val),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF388E3C),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => onUnlock(passwordController.text),
                      child: Text(
                        'Unlock Vault',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: onRecoveryTap,
                      child: Text(
                        'SLIP-39 Recovery Mnemonics',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF2563EB),
                          fontSize: 12,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const Spacer(),

          // Bottom Action Tools Bar
          Row(
            children: [
              Expanded(
                child: _buildToolCard(
                  context,
                  title: 'abc ➔ 101010',
                  subtitle: 'Locate Encrypted File',
                  icon: Icons.search_rounded,
                  onTap: onLocateEncryptedFile,
                  isDark: isDark,
                  borderColor: borderColor,
                  textColor: textColor,
                  subtitleColor: subtitleColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildToolCard(
                  context,
                  title: '101010 ➔ abc',
                  subtitle: 'Decrypt File Name',
                  icon: Icons.font_download_outlined,
                  onTap: onDecryptFileName,
                  isDark: isDark,
                  borderColor: borderColor,
                  textColor: textColor,
                  subtitleColor: subtitleColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildToolCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
    required Color borderColor,
    required Color textColor,
    required Color subtitleColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: subtitleColor,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(icon, size: 18, color: subtitleColor),
          ],
        ),
      ),
    );
  }
}

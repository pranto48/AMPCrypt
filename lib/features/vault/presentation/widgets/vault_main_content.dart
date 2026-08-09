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
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B101D) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    final passwordController = TextEditingController();

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
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF388E3C), // Cryptomator Green Icon
                ),
                child: Icon(
                  isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
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
                        color: subtitleColor,
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
                  color: isUnlocked ? const Color(0xFF388E3C) : (isDark ? const Color(0xFF334155) : const Color(0xFF94A3B8)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isUnlocked ? 'UNLOCKED' : 'LOCKED',
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
          else if (isUnlocked) ...[
            // Vault Unlocked Content View (Matching Screenshot 1)
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
                      backgroundColor: const Color(0xFF388E3C), // Vibrant Cryptomator Green
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
            // Vault Locked View (Password Unlock Form)
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
                    if (onRecoveryTap != null) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: onRecoveryTap,
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
                  ],
                ),
              ),
            ),
          ],

          const Spacer(),

          // Bottom Cards Row (3 Cards matching Screenshot 1)
          Row(
            children: [
              // Card 1: Dotted Box (Locate Encrypted File)
              Expanded(
                child: _DottedToolBox(
                  isDark: isDark,
                  borderColor: borderColor,
                  title: 'abc ➔ 101010',
                  subtitle: 'Locate Encrypted File',
                  onTap: onLocateEncryptedFile,
                ),
              ),
              const SizedBox(width: 14),

              // Card 2: Dotted Box (Decrypt File Name)
              Expanded(
                child: _DottedToolBox(
                  isDark: isDark,
                  borderColor: borderColor,
                  title: '101010 ➔ abc',
                  subtitle: 'Decrypt File Name',
                  onTap: onDecryptFileName,
                ),
              ),
              const SizedBox(width: 14),

              // Card 3: Solid Box (Vault Statistics)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor, width: 1.0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vault Statistics',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Read:', style: GoogleFonts.outfit(fontSize: 11, color: subtitleColor)),
                          Text('idle', style: GoogleFonts.outfit(fontSize: 11, color: subtitleColor)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Write:', style: GoogleFonts.outfit(fontSize: 11, color: subtitleColor)),
                          Text('idle', style: GoogleFonts.outfit(fontSize: 11, color: subtitleColor)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DottedToolBox extends StatelessWidget {
  final bool isDark;
  final Color borderColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _DottedToolBox({
    required this.isDark,
    required this.borderColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
            width: 1.0,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: GoogleFonts.shareTechMono(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: subtitleColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

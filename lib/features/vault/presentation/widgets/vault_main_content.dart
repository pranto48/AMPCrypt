/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../domain/repositories/vault_repository.dart';
import 'vault_file_manager.dart';

class VaultMainContent extends StatefulWidget {
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
  final VaultRepository? repository;

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
    this.repository,
  });

  @override
  State<VaultMainContent> createState() => _VaultMainContentState();
}

class _VaultMainContentState extends State<VaultMainContent> {
  int _selectedTab = 0; // 0 = In-App File Explorer, 1 = Virtual Drive (Explorer)

  @override
  Widget build(BuildContext context) {
    final vaultName = widget.vaultName;
    final vaultPath = widget.vaultPath;
    final driveLetter = widget.driveLetter;
    final isUnlocked = widget.isUnlocked;
    final isLoading = widget.isLoading;
    final loadingMessage = widget.loadingMessage;
    final onRevealDrive = widget.onRevealDrive;
    final onLock = widget.onLock;
    final onUnlock = widget.onUnlock;
    final onLocateVault = widget.onLocateVault;
    final onRecoveryTap = widget.onRecoveryTap;
    final onLocateEncryptedFile = widget.onLocateEncryptedFile;
    final onDecryptFileName = widget.onDecryptFileName;
    final repository = widget.repository;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF070D1E) : const Color(0xFFF0F7FF);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0x3300F0FF) : const Color(0xFFE2E8F0);

    final passwordController = TextEditingController();
    final isDirectoryMissing = !Directory(vaultPath).existsSync();

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Section with Animated Pulsing Sphere Icon
          Row(
            children: [
              _PulsingVaultIcon(
                isUnlocked: isUnlocked,
                isDirectoryMissing: isDirectoryMissing,
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
                        color: isDirectoryMissing ? const Color(0xFFF43F5E) : subtitleColor,
                        fontWeight: isDirectoryMissing ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Status Pill Badge Top Right with 20% Liquid Glass Effect
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isDirectoryMissing
                      ? const Color(0xFFF43F5E)
                      : (isUnlocked ? const Color.fromRGBO(2, 132, 199, 0.85) : (isDark ? const Color.fromRGBO(15, 23, 42, 0.60) : const Color(0xFF94A3B8))),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark ? const Color.fromRGBO(0, 240, 255, 0.40) : Colors.transparent,
                    width: 1.0,
                  ),
                  boxShadow: isUnlocked
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00F0FF).withValues(alpha: 0.3),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDirectoryMissing
                          ? Icons.error_outline_rounded
                          : (isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isDirectoryMissing ? 'MISSING' : (isUnlocked ? 'UNLOCKED' : 'LOCKED'),
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Main Center Content
          if (isLoading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF00F0FF)),
                    const SizedBox(height: 16),
                    Text(
                      loadingMessage ?? 'Processing cryptography operation...',
                      style: GoogleFonts.outfit(color: subtitleColor, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          else if (isDirectoryMissing)
            Expanded(
              child: Center(
                child: Container(
                  width: 440,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? const Color.fromRGBO(30, 27, 46, 0.60) : const Color(0xFFFFF1F2),
                    border: Border.all(color: isDark ? const Color(0xFF881337) : const Color(0xFFFECDD3)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFF43F5E), size: 40),
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
                          backgroundColor: const Color(0xFFF43F5E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              ),
            )
          else if (isUnlocked) ...[
            // Dual-Mode View Switcher (In-App File Explorer vs Virtual Drive)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _selectedTab = 0),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTab == 0
                                ? const Color(0xFF06B6D4)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_copy_rounded,
                                size: 16,
                                color: _selectedTab == 0 ? Colors.black : subtitleColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'In-App Secure Files',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: _selectedTab == 0 ? Colors.black : subtitleColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => setState(() => _selectedTab = 1),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: _selectedTab == 1
                                ? const Color(0xFF06B6D4)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.dns_rounded,
                                size: 16,
                                color: _selectedTab == 1 ? Colors.black : subtitleColor,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Virtual Drive ($driveLetter)',
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: _selectedTab == 1 ? Colors.black : subtitleColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Quick Lock Button in toolbar
                ElevatedButton.icon(
                  onPressed: onLock,
                  icon: const Icon(Icons.lock_rounded, size: 16),
                  label: Text('Lock Vault', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.redAccent,
                    elevation: 0,
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Tab 0: In-App File Manager
            if (_selectedTab == 0 && repository != null)
              Expanded(
                child: VaultFileManager(
                  repository: repository,
                  onLockRequested: onLock,
                ),
              )
            else
              // Tab 1: Windows Virtual Drive Controls
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "Your vault is active on Windows Virtual Drive $driveLetter",
                        style: GoogleFonts.outfit(
                          color: textColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _LiquidGlassButton(
                        onPressed: onRevealDrive,
                        minWidth: 260,
                        minHeight: 64,
                        gradientColors: const [Color(0xFF0072FF), Color(0xFF00F0FF)],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.dns_rounded, size: 28, color: Colors.white),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Reveal Drive in Explorer',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  driveLetter,
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ] else ...[
            // Vault Locked View with 20% Liquid Glass Input & Button
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
                        prefixIcon: const Icon(Icons.lock_outline, size: 18, color: Color(0xFF00F0FF)),
                        filled: true,
                        fillColor: isDark ? const Color.fromRGBO(15, 23, 42, 0.40) : const Color(0xFFF8FAFC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Color(0xFF00F0FF), width: 1.8),
                        ),
                      ),
                      onSubmitted: (val) => onUnlock(val),
                    ),
                    const SizedBox(height: 16),
                    _LiquidGlassButton(
                      onPressed: () => onUnlock(passwordController.text),
                      minWidth: double.infinity,
                      minHeight: 46,
                      gradientColors: const [Color(0xFF0072FF), Color(0xFF00F0FF)],
                      child: Text(
                        'Unlock Vault',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: onRecoveryTap,
                      child: Text(
                        'SLIP-39 Recovery Mnemonics',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF38BDF8),
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

          // Bottom Action Tools Bar with 20% Liquid Glass Translucent Effect
          Row(
            children: [
              Expanded(
                child: _LiquidGlassToolCard(
                  title: 'abc ➔ 101010',
                  subtitle: 'Locate Encrypted File',
                  icon: Icons.search_rounded,
                  onTap: onLocateEncryptedFile,
                  isDark: isDark,
                  textColor: textColor,
                  subtitleColor: subtitleColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _LiquidGlassToolCard(
                  title: '101010 ➔ abc',
                  subtitle: 'Decrypt File Name',
                  icon: Icons.font_download_outlined,
                  onTap: onDecryptFileName,
                  isDark: isDark,
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
}

// ─── Pulsing Vault Icon Animation Widget ────────────────────────────────────
class _PulsingVaultIcon extends StatefulWidget {
  final bool isUnlocked;
  final bool isDirectoryMissing;

  const _PulsingVaultIcon({
    required this.isUnlocked,
    required this.isDirectoryMissing,
  });

  @override
  State<_PulsingVaultIcon> createState() => _PulsingVaultIconState();
}

class _PulsingVaultIconState extends State<_PulsingVaultIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _glowAnimation = Tween<double>(begin: 14.0, end: 24.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: widget.isDirectoryMissing
                  ? const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFE11D48)])
                  : const LinearGradient(colors: [Color(0xFF0072FF), Color(0xFF00F0FF)]),
              boxShadow: [
                BoxShadow(
                  color: widget.isDirectoryMissing
                      ? const Color(0xFFF43F5E).withValues(alpha: 0.35)
                      : const Color(0xFF00F0FF).withValues(alpha: 0.40),
                  blurRadius: _glowAnimation.value,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(
              widget.isDirectoryMissing
                  ? Icons.folder_off_rounded
                  : (widget.isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded),
              color: Colors.white,
              size: 28,
            ),
          ),
        );
      },
    );
  }
}

// ─── Liquid Glass Button with Micro-Animation ────────────────────────────────
class _LiquidGlassButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;
  final double minWidth;
  final double minHeight;
  final List<Color> gradientColors;

  const _LiquidGlassButton({
    required this.onPressed,
    required this.child,
    this.minWidth = 200,
    this.minHeight = 48,
    required this.gradientColors,
  });

  @override
  State<_LiquidGlassButton> createState() => _LiquidGlassButtonState();
}

class _LiquidGlassButtonState extends State<_LiquidGlassButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: widget.minWidth == double.infinity ? double.infinity : null,
          height: widget.minHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(colors: widget.gradientColors),
            boxShadow: [
              BoxShadow(
                color: widget.gradientColors.last.withValues(alpha: _isHovered ? 0.50 : 0.30),
                blurRadius: _isHovered ? 20 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              minimumSize: Size(widget.minWidth, widget.minHeight),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: widget.onPressed,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ─── Liquid Glass Outline Button with Micro-Animation ────────────────────────
class _LiquidGlassOutlineButton extends StatefulWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;
  final bool isDark;
  final Color textColor;
  final Color borderColor;

  const _LiquidGlassOutlineButton({
    required this.onPressed,
    required this.label,
    required this.icon,
    required this.isDark,
    required this.textColor,
    required this.borderColor,
  });

  @override
  State<_LiquidGlassOutlineButton> createState() => _LiquidGlassOutlineButtonState();
}

class _LiquidGlassOutlineButtonState extends State<_LiquidGlassOutlineButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.textColor,
            backgroundColor: _isHovered
                ? (widget.isDark ? const Color.fromRGBO(0, 240, 255, 0.15) : const Color.fromRGBO(2, 132, 199, 0.10))
                : Colors.transparent,
            side: BorderSide(
              color: _isHovered ? const Color(0xFF00F0FF) : widget.borderColor,
              width: 1.2,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          icon: Icon(widget.icon, size: 16, color: _isHovered ? const Color(0xFF00F0FF) : widget.textColor),
          label: Text(
            widget.label,
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: _isHovered ? const Color(0xFF00F0FF) : widget.textColor,
            ),
          ),
          onPressed: widget.onPressed,
        ),
      ),
    );
  }
}

// ─── 20% Liquid Glass Tool Card with Hover Animations ────────────────────────
class _LiquidGlassToolCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;
  final Color textColor;
  final Color subtitleColor;

  const _LiquidGlassToolCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.isDark,
    required this.textColor,
    required this.subtitleColor,
  });

  @override
  State<_LiquidGlassToolCard> createState() => _LiquidGlassToolCardState();
}

class _LiquidGlassToolCardState extends State<_LiquidGlassToolCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final glassBg = widget.isDark
        ? (_isHovered ? const Color.fromRGBO(15, 23, 42, 0.45) : const Color.fromRGBO(15, 23, 42, 0.20))
        : (_isHovered ? const Color.fromRGBO(255, 255, 255, 0.90) : const Color.fromRGBO(248, 250, 252, 0.70));

    final borderColor = _isHovered
        ? const Color.fromRGBO(0, 240, 255, 0.60)
        : (widget.isDark ? const Color.fromRGBO(0, 240, 255, 0.20) : const Color(0xFFCBD5E1));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: glassBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor, width: 1.2),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: const Color(0xFF00F0FF).withValues(alpha: 0.25),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: widget.textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: widget.subtitleColor,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    AnimatedScale(
                      scale: _isHovered ? 1.2 : 1.0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        widget.icon,
                        size: 18,
                        color: _isHovered ? const Color(0xFF00F0FF) : widget.subtitleColor,
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

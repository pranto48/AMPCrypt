/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

class CryptomatorTitleBar extends StatelessWidget {
  final bool isDark;
  final VoidCallback onClose;

  const CryptomatorTitleBar({
    super.key,
    required this.isDark,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF0B132B) : const Color(0xFFE2E8F0);
    final borderColor = isDark ? const Color(0x3300F0FF) : const Color(0xFFCBD5E1);
    final textColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);

    return Container(
      height: 38,
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                colors: [Color(0xFF0B132B), Color(0xFF0F172A)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        color: isDark ? null : bgColor,
        border: Border(
          bottom: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/app_icon.ico',
                      width: 18,
                      height: 18,
                      errorBuilder: (context, error, stackTrace) => Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [Color(0xFF0072FF), Color(0xFF00F0FF)]),
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          color: Colors.white,
                          size: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'AMPCrypt',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _TitleBarButton(
            icon: Icons.remove_rounded,
            isDark: isDark,
            onPressed: () => windowManager.minimize(),
          ),
          _TitleBarButton(
            icon: Icons.crop_square_rounded,
            isDark: isDark,
            onPressed: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _TitleBarButton(
            icon: Icons.close_rounded,
            isDark: isDark,
            isClose: true,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final bool isClose;
  final VoidCallback onPressed;

  const _TitleBarButton({
    required this.icon,
    required this.isDark,
    this.isClose = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final defaultIconColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final hoverBg = isClose 
        ? const Color(0xFFE11D48) 
        : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        hoverColor: hoverBg,
        child: SizedBox(
          width: 46,
          height: 38,
          child: Icon(
            icon,
            size: 15,
            color: isClose ? (isDark ? Colors.white : const Color(0xFF475569)) : defaultIconColor,
          ),
        ),
      ),
    );
  }
}

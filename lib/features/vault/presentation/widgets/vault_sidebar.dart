/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class VaultSidebarItem {
  final String id;
  final String name;
  final String path;
  final bool isUnlocked;

  const VaultSidebarItem({
    required this.id,
    required this.name,
    required this.path,
    required this.isUnlocked,
  });
}

class VaultSidebar extends StatelessWidget {
  final List<VaultSidebarItem> vaults;
  final String? selectedVaultId;
  final ValueChanged<String> onSelectVault;
  final VoidCallback onCreateVault;
  final VoidCallback onOpenVault;
  final VoidCallback onAddFtpDrive;
  final VoidCallback onOpenAlerts;
  final VoidCallback onOpenPreferences;
  final Function(String vaultId)? onDeleteVault;

  const VaultSidebar({
    super.key,
    required this.vaults,
    required this.selectedVaultId,
    required this.onSelectVault,
    required this.onCreateVault,
    required this.onOpenVault,
    required this.onAddFtpDrive,
    required this.onOpenAlerts,
    required this.onOpenPreferences,
    this.onDeleteVault,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF070D1E) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0x3300F0FF) : const Color(0xFFE2E8F0);

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(
          right: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      child: Column(
        children: [
          // Vaults List
          Expanded(
            child: vaults.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open_outlined,
                            size: 36,
                            color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No Vaults Added',
                            style: GoogleFonts.outfit(
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: vaults.length,
                    itemBuilder: (context, index) {
                      final item = vaults[index];
                      final isSelected = selectedVaultId == item.id;

                      return _LiquidGlassVaultItem(
                        item: item,
                        isSelected: isSelected,
                        isDark: isDark,
                        onTap: () => onSelectVault(item.id),
                        onDelete: onDeleteVault != null ? () => onDeleteVault!(item.id) : null,
                      );
                    },
                  ),
          ),

          // Bottom Action Dock Bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0B132B) : Colors.white,
              border: Border(
                top: BorderSide(color: borderColor, width: 1.0),
              ),
            ),
            child: Row(
              children: [
                // Plus Action Button (Add / Open Vault)
                Expanded(
                  child: PopupMenuButton<String>(
                    tooltip: 'Add Vault',
                    offset: const Offset(0, -120),
                    onSelected: (value) {
                      if (value == 'new') onCreateVault();
                      if (value == 'open') onOpenVault();
                      if (value == 'recover') onOpenAlerts();
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'new',
                        child: Row(
                          children: [
                            const Icon(Icons.add, color: Color(0xFF1E293B), size: 16),
                            const SizedBox(width: 8),
                            Text('Create New Vault...', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'open',
                        child: Row(
                          children: [
                            const Icon(Icons.folder_outlined, color: Color(0xFF1E293B), size: 16),
                            const SizedBox(width: 8),
                            Text('Open Existing Vault...', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'recover',
                        child: Row(
                          children: [
                            const Icon(Icons.sync_rounded, color: Color(0xFF1E293B), size: 16),
                            const SizedBox(width: 8),
                            Text('Recover Existing Vault...', style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.add,
                        size: 20,
                        color: isDark ? Colors.white : const Color(0xFF334155),
                      ),
                    ),
                  ),
                ),
                Container(width: 1, height: 24, color: borderColor),

                // Blank / Spacer slot
                Expanded(
                  child: Container(),
                ),
                Container(width: 1, height: 24, color: borderColor),

                // Security Alerts Button
                Expanded(
                  child: IconButton(
                    tooltip: 'Security Alerts',
                    icon: Icon(
                      Icons.notifications_none_rounded,
                      size: 19,
                      color: isDark ? Colors.white : const Color(0xFF334155),
                    ),
                    onPressed: onOpenAlerts,
                  ),
                ),
                Container(width: 1, height: 24, color: borderColor),

                // Preferences Gear Button
                Expanded(
                  child: IconButton(
                    tooltip: 'Preferences',
                    icon: Icon(
                      Icons.settings_outlined,
                      size: 19,
                      color: isDark ? Colors.white : const Color(0xFF334155),
                    ),
                    onPressed: onOpenPreferences,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiquidGlassVaultItem extends StatefulWidget {
  final VaultSidebarItem item;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _LiquidGlassVaultItem({
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
    this.onDelete,
  });

  @override
  State<_LiquidGlassVaultItem> createState() => _LiquidGlassVaultItemState();
}

class _LiquidGlassVaultItemState extends State<_LiquidGlassVaultItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final titleColor = widget.isSelected
        ? (widget.isDark ? const Color(0xFF00F0FF) : const Color(0xFF0284C7))
        : (widget.isDark ? Colors.white : const Color(0xFF1E293B));
    final subtitleColor = widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final glassBg = widget.isSelected
        ? (widget.isDark ? const Color.fromRGBO(0, 114, 255, 0.20) : const Color.fromRGBO(224, 242, 254, 0.70))
        : (_isHovered
            ? (widget.isDark ? const Color.fromRGBO(15, 23, 42, 0.40) : const Color.fromRGBO(241, 245, 249, 0.80))
            : Colors.transparent);

    final borderColor = (widget.isSelected || _isHovered) && widget.isDark
        ? const Color.fromRGBO(0, 240, 255, 0.50)
        : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: glassBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.2),
              boxShadow: (widget.isSelected || _isHovered) && widget.isDark
                  ? [
                      BoxShadow(
                        color: const Color(0xFF00F0FF).withValues(alpha: 0.20),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                AnimatedScale(
                  scale: _isHovered ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    widget.item.isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                    color: const Color(0xFF00F0FF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.item.name,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: titleColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.item.path,
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
                if (widget.onDelete != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    color: widget.isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    tooltip: 'Delete Vault',
                    onPressed: widget.onDelete,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

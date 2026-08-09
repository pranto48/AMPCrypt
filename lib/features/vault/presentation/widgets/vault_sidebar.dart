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
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

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
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
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
                      final selectedBg = isDark ? const Color(0xFF143823) : const Color(0xFFE8F5E9);
                      final titleColor = isSelected 
                          ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF22C55E))
                          : (isDark ? Colors.white : const Color(0xFF1E293B));
                      final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

                      return InkWell(
                        onTap: () => onSelectVault(item.id),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? selectedBg : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                item.isUnlocked ? Icons.lock_open_rounded : Icons.lock_rounded,
                                color: const Color(0xFF22C55E),
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.name,
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
                                      item.path,
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
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Action Dock Bar (Matching Screenshot 1 dock footer)
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
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
                      if (value == 'recover') onOpenAlerts(); // launches Recovery & Backup
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

                // Blank / Spacer slot matching Screenshot 1
                Expanded(
                  child: Container(),
                ),
                Container(width: 1, height: 24, color: borderColor),

                // Ransomware Notification Bell Button
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

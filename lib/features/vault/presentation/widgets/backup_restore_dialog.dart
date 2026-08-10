/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class BackupRestoreDialog extends StatefulWidget {
  final String vaultPath;
  final Function(List<String> recoveryPhrases)? onRecoverSLIP39;
  final Function(String restoredConfigPath)? onRestoreBackupFile;

  const BackupRestoreDialog({
    super.key,
    required this.vaultPath,
    this.onRecoverSLIP39,
    this.onRestoreBackupFile,
  });

  @override
  State<BackupRestoreDialog> createState() => _BackupRestoreDialogState();
}

class _BackupRestoreDialogState extends State<BackupRestoreDialog> {
  int _activeTab = 0; // 0: Backup Files, 1: Restore from File, 2: SLIP-39 Mnemonics
  List<FileSystemEntity> _backupFiles = [];
  final _phrasesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scanBackupFiles();
  }

  void _scanBackupFiles() {
    try {
      final dir = Directory(widget.vaultPath);
      if (dir.existsSync()) {
        final files = dir.listSync().where((e) {
          final name = p.basename(e.path);
          return name.endsWith('.bkup') || name.endsWith('.ampcrypt');
        }).toList();
        setState(() {
          _backupFiles = files;
        });
      }
    } catch (_) {}
  }

  Future<void> _createManualBackup() async {
    try {
      final hash = DateTime.now().millisecondsSinceEpoch.toRadixString(16).toUpperCase().padLeft(8, '0').substring(0, 8);
      final masterkey = File(p.join(widget.vaultPath, 'masterkey.ampcrypt'));
      final vault = File(p.join(widget.vaultPath, 'vault.ampcrypt'));

      if (masterkey.existsSync()) {
        await masterkey.copy(p.join(widget.vaultPath, 'masterkey.ampcrypt.$hash.bkup'));
      }
      if (vault.existsSync()) {
        await vault.copy(p.join(widget.vaultPath, 'vault.ampcrypt.$hash.bkup'));
      }
      _scanBackupFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF22C55E),
            content: Text('Created backup files (.bkup)', style: GoogleFonts.outfit()),
          ),
        );
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Dialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Container(
        width: 620,
        height: 440,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sync_rounded, color: Color(0xFF22C55E), size: 24),
                const SizedBox(width: 10),
                Text(
                  'Vault Backup & Recovery Options',
                  style: GoogleFonts.outfit(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: subtitleColor,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Tab Bar Header
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                children: [
                  _tabButton(0, 'Backup Files (.bkup)'),
                  _tabButton(1, 'Restore from Backup'),
                  _tabButton(2, 'SLIP-39 Recovery'),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Tab Body Content
            Expanded(
              child: IndexedStack(
                index: _activeTab,
                children: [
                  // TAB 0: BACKUP FILES
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Vault Folder Backup Items:',
                            style: GoogleFonts.outfit(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF22C55E),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: Text('Create Backup Now', style: GoogleFonts.outfit(fontSize: 12)),
                            onPressed: _createManualBackup,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _backupFiles.isEmpty
                            ? Center(
                                child: Text('No backup files found.', style: GoogleFonts.outfit(color: subtitleColor, fontSize: 13)),
                              )
                            : ListView.builder(
                                itemCount: _backupFiles.length,
                                itemBuilder: (context, index) {
                                  final file = _backupFiles[index];
                                  final name = p.basename(file.path);
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.file_present_rounded, color: Color(0xFF22C55E), size: 18),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: GoogleFonts.shareTechMono(color: textColor, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),

                  // TAB 1: RESTORE FROM BACKUP
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Restore Master Key / Metadata from Backup File:',
                        style: GoogleFonts.outfit(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Select a .bkup backup file from your vault directory to restore corrupted or missing masterkey configurations.',
                        style: GoogleFonts.outfit(color: subtitleColor, fontSize: 12),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: Text('Browse for .bkup File', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          final path = await FilePicker.getDirectoryPath();
                          if (path != null && widget.onRestoreBackupFile != null) {
                            widget.onRestoreBackupFile!(path);
                            if (context.mounted) Navigator.of(context).pop();
                          }
                        },
                      ),
                    ],
                  ),

                  // TAB 2: SLIP-39 RECOVERY
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SLIP-39 Mnemonic Phrase Recovery:',
                        style: GoogleFonts.outfit(color: textColor, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter 2 of 3 SLIP-39 recovery phrases separated by line breaks or commas:',
                        style: GoogleFonts.outfit(color: subtitleColor, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _phrasesController,
                        maxLines: 4,
                        style: GoogleFonts.shareTechMono(color: textColor, fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'phrase 1...\nphrase 2...',
                          hintStyle: GoogleFonts.outfit(color: subtitleColor, fontSize: 12),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF22C55E),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        onPressed: () {
                          final text = _phrasesController.text.trim();
                          if (text.isNotEmpty && widget.onRecoverSLIP39 != null) {
                            final phrases = text.split(RegExp(r'[,\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                            widget.onRecoverSLIP39!(phrases);
                            Navigator.of(context).pop();
                          }
                        },
                        child: Text('Recover Vault Key', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(int index, String label) {
    final isSelected = _activeTab == index;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = const Color(0xFF22C55E);
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return InkWell(
      onTap: () => setState(() => _activeTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? activeColor : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? activeColor : inactiveColor,
          ),
        ),
      ),
    );
  }
}

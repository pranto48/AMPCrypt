/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * This program is free software under the GNU Affero General Public License.
 * (Project website: https://ampcrypt.itsupport.com.bd)
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../domain/repositories/vault_repository.dart';
import 'secure_file_preview_dialog.dart';

class VaultFileManager extends StatefulWidget {
  final VaultRepository repository;
  final VoidCallback? onLockRequested;

  const VaultFileManager({
    super.key,
    required this.repository,
    this.onLockRequested,
  });

  @override
  State<VaultFileManager> createState() => _VaultFileManagerState();
}

class _VaultFileManagerState extends State<VaultFileManager> {
  String _currentPath = '/';
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  bool _isGridView = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadDirectory() {
    setState(() => _isLoading = true);
    try {
      final items = widget.repository.listVaultDirectory(_currentPath);
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  void _navigateTo(String path) {
    setState(() {
      _currentPath = path;
      _searchQuery = '';
      _searchController.clear();
    });
    _loadDirectory();
  }

  void _navigateUp() {
    if (_currentPath == '/') return;
    final parts = _currentPath.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 1) {
      _navigateTo('/');
    } else {
      parts.removeLast();
      _navigateTo('/${parts.join('/')}');
    }
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_searchQuery.trim().isEmpty) return _items;
    final query = _searchQuery.toLowerCase();
    return _items.where((item) {
      final name = (item['name'] as String? ?? '').toLowerCase();
      return name.contains(query);
    }).toList();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  IconData _getFileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['mp4', 'mkv', 'avi', 'mov'].contains(ext)) {
      return Icons.movie_outlined;
    }
    if (['mp3', 'wav', 'flac', 'm4a'].contains(ext)) {
      return Icons.audiotrack_rounded;
    }
    if (['pdf'].contains(ext)) {
      return Icons.picture_as_pdf_rounded;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.folder_zip_rounded;
    }
    if (['txt', 'json', 'dart', 'md', 'csv', 'log', 'xml', 'html', 'css', 'js', 'py'].contains(ext)) {
      return Icons.code_rounded;
    }
    if (['doc', 'docx'].contains(ext)) {
      return Icons.description_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(ext)) {
      return const Color(0xFF38BDF8); // Sky blue
    }
    if (['mp4', 'mkv', 'avi', 'mov'].contains(ext)) {
      return const Color(0xFFF43F5E); // Rose
    }
    if (['mp3', 'wav', 'flac', 'm4a'].contains(ext)) {
      return const Color(0xFFA855F7); // Purple
    }
    if (['pdf'].contains(ext)) {
      return const Color(0xFFEF4444); // Red
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return const Color(0xFFF59E0B); // Amber
    }
    if (['txt', 'json', 'dart', 'md', 'csv', 'log', 'xml', 'html', 'css', 'js', 'py'].contains(ext)) {
      return const Color(0xFF10B981); // Emerald
    }
    return const Color(0xFF94A3B8); // Slate
  }

  Future<void> _handleFileClick(Map<String, dynamic> item) async {
    final isDir = item['isDirectory'] as bool? ?? false;
    final path = item['path'] as String;
    final name = item['name'] as String;

    if (isDir) {
      _navigateTo(path);
      return;
    }

    // File: preview in RAM
    setState(() => _isLoading = true);
    final bytes = await widget.repository.getVaultFileBytes(path);
    setState(() => _isLoading = false);

    if (bytes != null && mounted) {
      SecureFilePreviewDialog.show(
        context: context,
        fileName: name,
        virtualPath: path,
        fileBytes: bytes,
        onExport: (vPath, localPath) => widget.repository.exportFileFromVault(vPath, localPath),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text('Failed to read decrypted file.', style: GoogleFonts.outfit(color: Colors.white)),
        ),
      );
    }
  }

  Future<void> _importLocalFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _isLoading = true);
      int imported = 0;
      for (final f in result.files) {
        if (f.path != null) {
          final success = await widget.repository.importFileToVault(f.path!, _currentPath);
          if (success) imported++;
        }
      }
      _loadDirectory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text(
              'Successfully imported and encrypted $imported file(s) with Self-Healing Headers.',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
        );
      }
    }
  }

  Future<void> _createNewFolder() async {
    final folderController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)),
        ),
        title: Text(
          'New Virtual Folder',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: folderController,
          autofocus: true,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Folder name...',
            hintStyle: GoogleFonts.outfit(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(folderController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF06B6D4),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Create', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final newPath = _currentPath == '/' ? '/$result' : '$_currentPath/$result';
      await widget.repository.createVaultDirectory(newPath);
      _loadDirectory();
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final name = item['name'] as String;
    final path = item['path'] as String;
    final isDir = item['isDirectory'] as bool? ?? false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
        ),
        title: Row(
          children: [
            const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Text(
              'Permanent Delete',
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "$name"${isDir ? ' and all its contents' : ''}?\nThis action cannot be undone.',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Delete', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      await widget.repository.deleteVaultPath(path);
      _loadDirectory();
    }
  }

  Future<void> _scavengeRepairVault() async {
    setState(() => _isLoading = true);
    final count = await widget.repository.scavengeVaultFiles();
    _loadDirectory();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text(
            count > 0
                ? 'Self-Healing Scan complete! Recovered and verified $count file(s).'
                : 'Self-Healing Scan complete. Vault index is 100% consistent.',
            style: GoogleFonts.outfit(color: Colors.white),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgDark = const Color(0xFF0F172A);
    final cardDark = const Color(0xFF1E293B);
    final accentCyan = const Color(0xFF06B6D4);
    final accentGreen = const Color(0xFF10B981);

    return Container(
      decoration: BoxDecoration(
        color: bgDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          // ─── TOP TOOLBAR ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: cardDark.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Row(
              children: [
                // Up / Back Button
                IconButton(
                  onPressed: _currentPath == '/' ? null : _navigateUp,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                  color: accentCyan,
                  disabledColor: Colors.white24,
                  tooltip: 'Up One Level',
                ),
                // Home Button
                IconButton(
                  onPressed: _currentPath == '/' ? null : () => _navigateTo('/'),
                  icon: const Icon(Icons.home_rounded, size: 20),
                  color: accentCyan,
                  disabledColor: Colors.white24,
                  tooltip: 'Vault Root',
                ),
                const SizedBox(width: 8),

                // Breadcrumb Path Display
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1120),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: _buildBreadcrumbs(),
                  ),
                ),
                const SizedBox(width: 12),

                // Search Bar
                SizedBox(
                  width: 180,
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                      contentPadding: EdgeInsets.zero,
                      filled: true,
                      fillColor: const Color(0xFF0B1120),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: accentCyan.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // New Folder Button
                IconButton(
                  onPressed: _createNewFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                  color: Colors.white70,
                  tooltip: 'New Virtual Folder',
                ),

                // Import Files Button
                ElevatedButton.icon(
                  onPressed: _importLocalFiles,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Import', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentCyan,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 8),

                // Grid / List View Toggle
                IconButton(
                  onPressed: () => setState(() => _isGridView = !_isGridView),
                  icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, size: 20),
                  color: Colors.white70,
                  tooltip: _isGridView ? 'List View' : 'Grid View',
                ),

                // Scavenge / Repair Button
                IconButton(
                  onPressed: _scavengeRepairVault,
                  icon: const Icon(Icons.healing_rounded, size: 20),
                  color: accentGreen,
                  tooltip: 'Self-Healing Auto-Repair',
                ),

                // Refresh Button
                IconButton(
                  onPressed: _loadDirectory,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  color: Colors.white70,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

          // ─── MAIN CONTENT AREA ─────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4)))
                : (_filteredItems.isEmpty
                    ? _buildEmptyState()
                    : (_isGridView ? _buildGridView() : _buildListView())),
          ),

          // ─── STATUS FOOTER ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: cardDark.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(15)),
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: accentGreen, size: 14),
                const SizedBox(width: 6),
                Text(
                  'Zero-Trace RAM File Explorer  •  64KB Chunked AES-GCM Streams',
                  style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11),
                ),
                const Spacer(),
                Text(
                  '${_filteredItems.length} item(s) in $_currentPath',
                  style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    final segments = _currentPath.split('/').where((s) => s.isNotEmpty).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          InkWell(
            onTap: () => _navigateTo('/'),
            child: Text(
              'vault:',
              style: GoogleFonts.outfit(
                color: const Color(0xFF06B6D4),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          if (segments.isEmpty)
            Text(
              ' /',
              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
            ),
          for (int i = 0; i < segments.length; i++) ...[
            Text(' / ', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 13)),
            InkWell(
              onTap: () {
                final target = '/${segments.sublist(0, i + 1).join('/')}';
                _navigateTo(target);
              },
              child: Text(
                segments[i],
                style: GoogleFonts.outfit(
                  color: i == segments.length - 1 ? Colors.white : const Color(0xFF38BDF8),
                  fontWeight: i == segments.length - 1 ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white10),
            ),
            child: const Icon(
              Icons.folder_open_rounded,
              size: 48,
              color: Color(0xFF06B6D4),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No matching files found' : 'This folder is empty',
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Click "Import" above or add files to your virtual drive.',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _filteredItems.length,
      separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.05), height: 1),
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        final isDir = item['isDirectory'] as bool? ?? false;
        final name = item['name'] as String;
        final size = item['size'] as int? ?? 0;
        final lastModified = item['lastModified'] as String?;

        return ListTile(
          onTap: () => _handleFileClick(item),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          hoverColor: Colors.white.withValues(alpha: 0.04),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDir
                  ? const Color(0xFF06B6D4).withValues(alpha: 0.15)
                  : _getFileColor(name).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isDir ? Icons.folder_rounded : _getFileIcon(name),
              color: isDir ? const Color(0xFF06B6D4) : _getFileColor(name),
              size: 20,
            ),
          ),
          title: Text(
            name,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14,
              fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: Text(
            isDir
                ? 'Directory'
                : '${_formatSize(size)}${lastModified != null ? '  •  ${lastModified.substring(0, 10)}' : ''}',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
          ),
          trailing: _buildItemMenu(item),
        );
      },
    );
  }

  Widget _buildGridView() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: _filteredItems.length,
      itemBuilder: (context, index) {
        final item = _filteredItems[index];
        final isDir = item['isDirectory'] as bool? ?? false;
        final name = item['name'] as String;
        final size = item['size'] as int? ?? 0;

        return InkWell(
          onTap: () => _handleFileClick(item),
          borderRadius: BorderRadius.circular(12),
          hoverColor: Colors.white.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: _buildItemMenu(item),
                ),
                Icon(
                  isDir ? Icons.folder_rounded : _getFileIcon(name),
                  color: isDir ? const Color(0xFF06B6D4) : _getFileColor(name),
                  size: 44,
                ),
                const SizedBox(height: 10),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isDir ? 'Folder' : _formatSize(size),
                  style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemMenu(Map<String, dynamic> item) {
    final isDir = item['isDirectory'] as bool? ?? false;
    final path = item['path'] as String;
    final name = item['name'] as String;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 18),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Colors.white12),
      ),
      onSelected: (val) async {
        if (val == 'preview') {
          await _handleFileClick(item);
        } else if (val == 'export') {
          final result = await FilePicker.saveFile(
            dialogTitle: 'Export Decrypted Copy',
            fileName: name,
          );
          if (result != null) {
            final success = await widget.repository.exportFileFromVault(path, result);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: success ? const Color(0xFF10B981) : Colors.redAccent,
                  content: Text(
                    success ? 'Exported to $result' : 'Failed to export file.',
                    style: GoogleFonts.outfit(color: Colors.white),
                  ),
                ),
              );
            }
          }
        } else if (val == 'copy_path') {
          Clipboard.setData(ClipboardData(text: path));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF06B6D4),
              content: Text('Virtual path copied: $path', style: GoogleFonts.outfit(color: Colors.white)),
            ),
          );
        } else if (val == 'delete') {
          await _deleteItem(item);
        }
      },
      itemBuilder: (ctx) => [
        if (!isDir)
          PopupMenuItem(
            value: 'preview',
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Text('Preview in RAM', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        if (!isDir)
          PopupMenuItem(
            value: 'export',
            child: Row(
              children: [
                const Icon(Icons.file_download_outlined, size: 16, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text('Export Decrypted Copy', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'copy_path',
          child: Row(
            children: [
              const Icon(Icons.copy_rounded, size: 16, color: Colors.white70),
              const SizedBox(width: 8),
              Text('Copy Virtual Path', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_forever_rounded, size: 16, color: Colors.redAccent),
              const SizedBox(width: 8),
              Text('Permanent Delete', style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    );
  }
}

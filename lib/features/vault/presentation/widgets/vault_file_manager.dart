/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 * This program is free software under the GNU Affero General Public License.
 * (Project website: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import '../../domain/repositories/vault_repository.dart';
import 'secure_file_preview_dialog.dart';

enum ExplorerViewMode { details, tiles, list }
enum ExplorerSortColumn { name, date, type, size }

class VaultFileManager extends StatefulWidget {
  final VaultRepository repository;
  final VoidCallback? onLockRequested;
  final bool isFullscreenMode;
  final VoidCallback? onToggleFullscreen;

  const VaultFileManager({
    super.key,
    required this.repository,
    this.onLockRequested,
    this.isFullscreenMode = false,
    this.onToggleFullscreen,
  });

  @override
  State<VaultFileManager> createState() => _VaultFileManagerState();
}

class _VaultFileManagerState extends State<VaultFileManager> {
  String _currentPath = '/';
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  ExplorerViewMode _viewMode = ExplorerViewMode.details;
  ExplorerSortColumn _sortColumn = ExplorerSortColumn.name;
  bool _sortAscending = true;
  bool _showSidebar = true;
  bool _showDetailsPane = true;
  bool _isEditingAddress = false;

  final Set<String> _selectedPaths = {};
  final List<String> _history = ['/'];
  int _historyIndex = 0;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _addressController.dispose();
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _loadDirectory({int retryCount = 0}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final items = widget.repository.listVaultDirectory(_currentPath);
      if (items.isEmpty && _currentPath == '/' && retryCount < 3) {
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
          _loadDirectory(retryCount: retryCount + 1);
          return;
        }
      }
      if (mounted) {
        setState(() {
          _items = items;
          _isLoading = false;
          _selectedPaths.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _selectedPaths.clear();
        });
      }
    }
  }

  void _navigateTo(String path, {bool addToHistory = true}) {
    final normPath = path.isEmpty || path == '/'
        ? '/'
        : (path.endsWith('/') ? path.substring(0, path.length - 1) : path);

    if (addToHistory && normPath != _currentPath) {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(normPath);
      _historyIndex = _history.length - 1;
    }

    setState(() {
      _currentPath = normPath;
      _searchQuery = '';
      _searchController.clear();
      _isEditingAddress = false;
    });
    _loadDirectory();
  }

  void _navigateBack() {
    if (_historyIndex > 0) {
      _historyIndex--;
      _navigateTo(_history[_historyIndex], addToHistory: false);
    }
  }

  void _navigateForward() {
    if (_historyIndex < _history.length - 1) {
      _historyIndex++;
      _navigateTo(_history[_historyIndex], addToHistory: false);
    }
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

  // ─── SORTING & FILTERING ───────────────────────────────────────────────────

  List<Map<String, dynamic>> get _displayItems {
    var list = _items.toList();

    // 1. Filter by search query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((item) {
        final name = (item['name'] as String? ?? '').toLowerCase();
        return name.contains(q);
      }).toList();
    }

    // 2. Sort items
    list.sort((a, b) {
      final aIsDir = a['isDirectory'] as bool? ?? false;
      final bIsDir = b['isDirectory'] as bool? ?? false;

      // Folders always precede files in Windows File Explorer
      if (aIsDir != bIsDir) {
        return aIsDir ? -1 : 1;
      }

      int cmp = 0;
      switch (_sortColumn) {
        case ExplorerSortColumn.name:
          cmp = (a['name'] as String? ?? '')
              .toLowerCase()
              .compareTo((b['name'] as String? ?? '').toLowerCase());
          break;
        case ExplorerSortColumn.date:
          final aDate = a['lastModified'] as String? ?? '';
          final bDate = b['lastModified'] as String? ?? '';
          cmp = aDate.compareTo(bDate);
          break;
        case ExplorerSortColumn.type:
          final aExt = (a['name'] as String? ?? '').split('.').last.toLowerCase();
          final bExt = (b['name'] as String? ?? '').split('.').last.toLowerCase();
          cmp = aExt.compareTo(bExt);
          break;
        case ExplorerSortColumn.size:
          final aSize = a['size'] as int? ?? 0;
          final bSize = b['size'] as int? ?? 0;
          cmp = aSize.compareTo(bSize);
          break;
      }

      return _sortAscending ? cmp : -cmp;
    });

    return list;
  }

  void _toggleSort(ExplorerSortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  // ─── FILE TYPE METADATA & ICONS ────────────────────────────────────────────

  String _getFileTypeDescription(String name, bool isDir) {
    if (isDir) return 'File folder';
    final parts = name.split('.');
    if (parts.length <= 1) return 'File';
    final ext = parts.last.toLowerCase();

    switch (ext) {
      case 'png':
        return 'PNG Image';
      case 'jpg':
      case 'jpeg':
        return 'JPEG Image';
      case 'webp':
        return 'WEBP Image';
      case 'gif':
        return 'GIF Image';
      case 'svg':
        return 'SVG Document';
      case 'pdf':
        return 'PDF Document';
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
        return 'Video File';
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'm4a':
        return 'Audio File';
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return 'Compressed Archive';
      case 'txt':
        return 'Text Document';
      case 'md':
        return 'Markdown Document';
      case 'json':
        return 'JSON File';
      case 'dart':
        return 'Dart Source File';
      case 'py':
        return 'Python Script';
      case 'js':
      case 'ts':
        return 'JavaScript / TypeScript';
      case 'html':
      case 'htm':
        return 'HTML Document';
      case 'css':
        return 'StyleSheet File';
      case 'doc':
      case 'docx':
        return 'Microsoft Word Document';
      case 'xls':
      case 'xlsx':
        return 'Microsoft Excel Sheet';
      case 'ppt':
      case 'pptx':
        return 'PowerPoint Presentation';
      case 'exe':
      case 'msi':
        return 'Windows Application';
      default:
        return '${ext.toUpperCase()} File';
    }
  }

  IconData _getFileIcon(String name, bool isDir) {
    if (isDir) return Icons.folder_rounded;
    final ext = name.split('.').last.toLowerCase();

    if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) {
      return Icons.image_rounded;
    }
    if (['mp4', 'mkv', 'avi', 'mov', 'wmv'].contains(ext)) {
      return Icons.movie_outlined;
    }
    if (['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'].contains(ext)) {
      return Icons.audiotrack_rounded;
    }
    if (['pdf'].contains(ext)) {
      return Icons.picture_as_pdf_rounded;
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return Icons.folder_zip_rounded;
    }
    if (['txt', 'json', 'dart', 'md', 'csv', 'log', 'xml', 'html', 'css', 'js', 'py', 'cpp', 'h'].contains(ext)) {
      return Icons.description_rounded;
    }
    if (['doc', 'docx'].contains(ext)) {
      return Icons.article_rounded;
    }
    if (['xls', 'xlsx'].contains(ext)) {
      return Icons.table_chart_rounded;
    }
    if (['ppt', 'pptx'].contains(ext)) {
      return Icons.slideshow_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  Color _getFileColor(String name, bool isDir) {
    if (isDir) return const Color(0xFFFBBF24); // Amber Windows folder
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
      return const Color(0xFFEF4444); // Crimson
    }
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) {
      return const Color(0xFFF59E0B); // Amber
    }
    if (['txt', 'json', 'dart', 'md', 'csv', 'log', 'xml', 'html', 'css', 'js', 'py'].contains(ext)) {
      return const Color(0xFF10B981); // Emerald
    }
    if (['doc', 'docx'].contains(ext)) {
      return const Color(0xFF3B82F6); // Word blue
    }
    if (['xls', 'xlsx'].contains(ext)) {
      return const Color(0xFF10B981); // Excel green
    }
    return const Color(0xFF94A3B8); // Slate
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return '—';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final y = dt.year.toString();
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hr = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$y-$m-$d $hr:$min';
    } catch (_) {
      return isoString.length >= 10 ? isoString.substring(0, 10) : isoString;
    }
  }

  // ─── ACTION HANDLERS ────────────────────────────────────────────────────────

  Future<void> _handleFileClick(Map<String, dynamic> item) async {
    final isDir = item['isDirectory'] as bool? ?? false;
    final path = item['path'] as String;
    final name = item['name'] as String;

    if (isDir) {
      _navigateTo(path);
      return;
    }

    // File: Zero-trace preview in RAM
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
          content: Text('Failed to read decrypted file stream.', style: GoogleFonts.outfit(color: Colors.white)),
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
              'Successfully encrypted and imported $imported file(s) with Self-Healing Header.',
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
        title: Row(
          children: [
            const Icon(Icons.create_new_folder_rounded, color: Color(0xFF06B6D4), size: 22),
            const SizedBox(width: 10),
            Text('New Folder', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF06B6D4)),
            ),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
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

  Future<void> _createNewTextDocument() async {
    final nameController = TextEditingController(text: 'New Document.txt');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            const Icon(Icons.note_add_rounded, color: Color(0xFF10B981), size: 22),
            const SizedBox(width: 10),
            Text('New Text Document', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Document name...',
            hintStyle: GoogleFonts.outfit(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF10B981)),
            ),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(nameController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Create File', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final docPath = _currentPath == '/' ? '/$result' : '$_currentPath/$result';
      final defaultBytes = Uint8List.fromList(utf8.encode('AMPCrypt Secure Text Document\nCreated: ${DateTime.now()}\n'));
      await widget.repository.createVaultFile(docPath, defaultBytes);
      _loadDirectory();
    }
  }

  Future<void> _renameItem(Map<String, dynamic> item) async {
    final oldPath = item['path'] as String;
    final oldName = item['name'] as String;
    final isDir = item['isDirectory'] as bool? ?? false;

    final controller = TextEditingController(text: oldName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
        ),
        title: Row(
          children: [
            const Icon(Icons.drive_file_rename_outline_rounded, color: Color(0xFF38BDF8), size: 22),
            const SizedBox(width: 10),
            Text('Rename ${isDir ? 'Folder' : 'File'}', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.outfit(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter new name...',
            hintStyle: GoogleFonts.outfit(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0F172A),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white12),
            ),
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: GoogleFonts.outfit(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('Rename', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != oldName) {
      final parent = oldPath.substring(0, oldPath.lastIndexOf('/'));
      final newPath = parent.isEmpty ? '/$newName' : '$parent/$newName';
      setState(() => _isLoading = true);
      final success = await widget.repository.renameVaultPath(oldPath, newPath);
      setState(() => _isLoading = false);

      if (success) {
        _loadDirectory();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to rename path.', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
    }
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedPaths.isEmpty) return;

    final count = _selectedPaths.length;
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
            Text('Permanent Secure Delete', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          count == 1
              ? 'Are you sure you want to permanently delete the selected item?\nThis action cannot be undone.'
              : 'Are you sure you want to permanently delete $count selected items and their contents?\nThis action cannot be undone.',
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
            child: Text('Delete ($count)', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      for (final p in _selectedPaths) {
        await widget.repository.deleteVaultPath(p);
      }
      _selectedPaths.clear();
      _loadDirectory();
    }
  }

  Future<void> _exportItem(Map<String, dynamic> item) async {
    final path = item['path'] as String;
    final name = item['name'] as String;

    final result = await FilePicker.saveFile(
      dialogTitle: 'Export Decrypted File',
      fileName: name,
    );
    if (result != null) {
      setState(() => _isLoading = true);
      final success = await widget.repository.exportFileFromVault(path, result);
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: success ? const Color(0xFF10B981) : Colors.redAccent,
            content: Text(
              success ? 'Successfully exported to $result' : 'Failed to export decrypted file.',
              style: GoogleFonts.outfit(color: Colors.white),
            ),
          ),
        );
      }
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
                ? 'Self-Healing Scan complete! Recovered and indexed $count file(s).'
                : 'Self-Healing Scan complete. Vault index is 100% consistent.',
            style: GoogleFonts.outfit(color: Colors.white),
          ),
        ),
      );
    }
  }

  void _openFullscreenExplorer() {
    if (widget.onToggleFullscreen != null) {
      widget.onToggleFullscreen!();
      return;
    }

    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (ctx, anim, secAnim) => Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          body: SafeArea(
            child: VaultFileManager(
              repository: widget.repository,
              onLockRequested: widget.onLockRequested,
              isFullscreenMode: true,
              onToggleFullscreen: () => Navigator.of(ctx).pop(),
            ),
          ),
        ),
        transitionsBuilder: (ctx, anim, secAnim, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  // ─── UI BUILD ROOT ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bgDark = const Color(0xFF0F172A);
    final cardDark = const Color(0xFF1E293B);
    final accentCyan = const Color(0xFF06B6D4);

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.f11) {
            _openFullscreenExplorer();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (_selectedPaths.isNotEmpty) {
              setState(() => _selectedPaths.clear());
              return KeyEventResult.handled;
            }
            if (widget.isFullscreenMode && widget.onToggleFullscreen != null) {
              widget.onToggleFullscreen!();
              return KeyEventResult.handled;
            }
          }
          if (event.logicalKey == LogicalKeyboardKey.delete && _selectedPaths.isNotEmpty) {
            _deleteSelectedItems();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        decoration: BoxDecoration(
          color: bgDark,
          borderRadius: widget.isFullscreenMode ? BorderRadius.zero : BorderRadius.circular(16),
          border: widget.isFullscreenMode
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            // ─── WINDOWS 11 TITLE / BANNER (FULLSCREEN ONLY) ──────────────────
            if (widget.isFullscreenMode) _buildFullscreenHeader(),

            // ─── TOP COMMAND BAR & RIBBON ──────────────────────────────────────
            _buildWindowsCommandBar(cardDark, accentCyan),

            // ─── ADDRESS & BREADCRUMB ROW ──────────────────────────────────────
            _buildAddressAndSearchRow(cardDark, accentCyan),

            // ─── MAIN FILE EXPLORER WORKSPACE (SIDEBAR + FILES + DETAILS) ──────
            Expanded(
              child: Row(
                children: [
                  // Left Navigation Pane (Folders Tree & Quick Access)
                  if (_showSidebar) _buildNavigationSidebar(cardDark, accentCyan),

                  // Main View Area (Details Table / Tiles / List)
                  Expanded(
                    child: Container(
                      color: const Color(0xFF0B132B).withValues(alpha: 0.35),
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4)))
                          : (_displayItems.isEmpty
                              ? _buildEmptyState()
                              : _buildMainViewports()),
                    ),
                  ),

                  // Right Details Inspector Pane
                  if (_showDetailsPane && _selectedPaths.length == 1)
                    _buildDetailsInspectorPane(cardDark, accentCyan),
                ],
              ),
            ),

            // ─── WINDOWS FILE EXPLORER STATUS BAR ─────────────────────────────
            _buildWindowsStatusBar(cardDark),
          ],
        ),
      ),
    );
  }

  // ─── FULLSCREEN HEADER ─────────────────────────────────────────────────────

  Widget _buildFullscreenHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_shared_rounded, color: Color(0xFF06B6D4), size: 18),
          const SizedBox(width: 8),
          Text(
            'AMPCrypt File Explorer — Fullscreen Zero-Trace Mode',
            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const Spacer(),
          IconButton(
            onPressed: widget.onToggleFullscreen,
            icon: const Icon(Icons.fullscreen_exit_rounded, size: 20, color: Colors.white70),
            tooltip: 'Exit Fullscreen (Esc)',
          ),
          if (widget.onLockRequested != null)
            IconButton(
              onPressed: widget.onLockRequested,
              icon: const Icon(Icons.lock_rounded, size: 18, color: Colors.redAccent),
              tooltip: 'Lock Vault',
            ),
        ],
      ),
    );
  }

  // ─── WINDOWS COMMAND BAR (RIBBON) ──────────────────────────────────────────

  Widget _buildWindowsCommandBar(Color cardDark, Color accentCyan) {
    final singleSelected = _selectedPaths.length == 1;
    final anySelected = _selectedPaths.isNotEmpty;
    final selectedItem = singleSelected
        ? _items.firstWhere((it) => it['path'] == _selectedPaths.first, orElse: () => {})
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cardDark.withValues(alpha: 0.65),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // New Dropdown Menu
            PopupMenuButton<String>(
              tooltip: 'New Item',
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white12)),
              onSelected: (val) {
                if (val == 'folder') _createNewFolder();
                if (val == 'text') _createNewTextDocument();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'folder',
                  child: Row(
                    children: [
                      const Icon(Icons.create_new_folder_rounded, size: 18, color: Color(0xFF06B6D4)),
                      const SizedBox(width: 10),
                      Text('New Folder', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'text',
                  child: Row(
                    children: [
                      const Icon(Icons.note_add_rounded, size: 18, color: Color(0xFF10B981)),
                      const SizedBox(width: 10),
                      Text('New Text Document', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: accentCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: accentCyan.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: accentCyan, size: 18),
                    const SizedBox(width: 6),
                    Text('New', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white60, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Import Files Button
            _buildRibbonButton(
              icon: Icons.upload_file_rounded,
              label: 'Import',
              color: const Color(0xFF38BDF8),
              onTap: _importLocalFiles,
              tooltip: 'Encrypt & Import Local Files to Vault',
            ),
            const SizedBox(width: 6),

            // Export Button (Active when single item selected)
            _buildRibbonButton(
              icon: Icons.file_download_outlined,
              label: 'Export',
              color: const Color(0xFF10B981),
              enabled: singleSelected && selectedItem != null && (selectedItem['isDirectory'] != true),
              onTap: () {
                if (selectedItem != null) _exportItem(selectedItem);
              },
              tooltip: 'Export Decrypted Copy to Local Disk',
            ),
            const SizedBox(width: 6),

            // Rename Button
            _buildRibbonButton(
              icon: Icons.drive_file_rename_outline_rounded,
              label: 'Rename',
              color: const Color(0xFFFBBF24),
              enabled: singleSelected && selectedItem != null,
              onTap: () {
                if (selectedItem != null) _renameItem(selectedItem);
              },
              tooltip: 'Rename File or Folder',
            ),
            const SizedBox(width: 6),

            // Delete Button
            _buildRibbonButton(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: Colors.redAccent,
              enabled: anySelected,
              onTap: _deleteSelectedItems,
              tooltip: 'Permanently Shred Selected Item(s)',
            ),

            const SizedBox(width: 12),
            Container(height: 20, width: 1, color: Colors.white12),
            const SizedBox(width: 12),

            // Sort Dropdown
            PopupMenuButton<ExplorerSortColumn>(
              tooltip: 'Sort items',
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white12)),
              onSelected: _toggleSort,
              itemBuilder: (ctx) => [
                _buildSortMenuItem(ExplorerSortColumn.name, 'Name'),
                _buildSortMenuItem(ExplorerSortColumn.date, 'Date modified'),
                _buildSortMenuItem(ExplorerSortColumn.type, 'Type'),
                _buildSortMenuItem(ExplorerSortColumn.size, 'Size'),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.sort_rounded, color: Colors.white70, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Sort by ${_sortColumn.name.toUpperCase()} ${_sortAscending ? '▲' : '▼'}',
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // View Mode Dropdown (Details / Tiles / List)
            PopupMenuButton<ExplorerViewMode>(
              tooltip: 'Change Layout View',
              color: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white12)),
              onSelected: (mode) => setState(() => _viewMode = mode),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: ExplorerViewMode.details,
                  child: Row(
                    children: [
                      Icon(Icons.view_headline_rounded, size: 16, color: _viewMode == ExplorerViewMode.details ? accentCyan : Colors.white70),
                      const SizedBox(width: 8),
                      Text('Details (Table)', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: ExplorerViewMode.tiles,
                  child: Row(
                    children: [
                      Icon(Icons.grid_view_rounded, size: 16, color: _viewMode == ExplorerViewMode.tiles ? accentCyan : Colors.white70),
                      const SizedBox(width: 8),
                      Text('Tiles (Large Icons)', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: ExplorerViewMode.list,
                  child: Row(
                    children: [
                      Icon(Icons.format_list_bulleted_rounded, size: 16, color: _viewMode == ExplorerViewMode.list ? accentCyan : Colors.white70),
                      const SizedBox(width: 8),
                      Text('Compact List', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _viewMode == ExplorerViewMode.details
                          ? Icons.view_headline_rounded
                          : (_viewMode == ExplorerViewMode.tiles ? Icons.grid_view_rounded : Icons.format_list_bulleted_rounded),
                      color: Colors.white70,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _viewMode == ExplorerViewMode.details
                          ? 'Details'
                          : (_viewMode == ExplorerViewMode.tiles ? 'Tiles' : 'List'),
                      style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: 16),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),
            Container(height: 20, width: 1, color: Colors.white12),
            const SizedBox(width: 12),

            // Toggle Navigation Sidebar
            IconButton(
              icon: Icon(_showSidebar ? Icons.view_sidebar_rounded : Icons.view_sidebar_outlined, size: 18),
              color: _showSidebar ? accentCyan : Colors.white60,
              tooltip: _showSidebar ? 'Hide Navigation Pane' : 'Show Navigation Pane',
              onPressed: () => setState(() => _showSidebar = !_showSidebar),
            ),

            // Toggle Details Pane
            IconButton(
              icon: Icon(_showDetailsPane ? Icons.info_rounded : Icons.info_outline_rounded, size: 18),
              color: _showDetailsPane ? accentCyan : Colors.white60,
              tooltip: _showDetailsPane ? 'Hide Details Pane' : 'Show Details Pane',
              onPressed: () => setState(() => _showDetailsPane = !_showDetailsPane),
            ),

            // Scavenge / Auto-Repair
            IconButton(
              icon: const Icon(Icons.healing_rounded, size: 18),
              color: const Color(0xFF10B981),
              tooltip: 'Self-Healing Auto-Repair Vault Index',
              onPressed: _scavengeRepairVault,
            ),

            // Fullscreen Button
            IconButton(
              icon: Icon(
                widget.isFullscreenMode ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                size: 20,
              ),
              color: const Color(0xFF38BDF8),
              tooltip: widget.isFullscreenMode ? 'Exit Fullscreen (Esc)' : 'Enter Fullscreen (F11)',
              onPressed: _openFullscreenExplorer,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<ExplorerSortColumn> _buildSortMenuItem(ExplorerSortColumn col, String label) {
    final active = _sortColumn == col;
    return PopupMenuItem(
      value: col,
      child: Row(
        children: [
          Text(label, style: GoogleFonts.outfit(color: active ? const Color(0xFF06B6D4) : Colors.white, fontSize: 13)),
          const Spacer(),
          if (active)
            Text(_sortAscending ? '▲' : '▼', style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildRibbonButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
    String? tooltip,
  }) {
    final widgetChild = InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: enabled ? color.withValues(alpha: 0.25) : Colors.white10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: enabled ? color : Colors.white24),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: enabled ? Colors.white : Colors.white24,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: widgetChild);
    }
    return widgetChild;
  }

  // ─── WINDOWS ADDRESS BAR & SEARCH BAR ──────────────────────────────────────

  Widget _buildAddressAndSearchRow(Color cardDark, Color accentCyan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B).withValues(alpha: 0.7),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          // Back button
          IconButton(
            onPressed: _historyIndex > 0 ? _navigateBack : null,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            color: Colors.white,
            disabledColor: Colors.white24,
            tooltip: 'Back (Alt+Left)',
          ),
          // Forward button
          IconButton(
            onPressed: _historyIndex < _history.length - 1 ? _navigateForward : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            color: Colors.white,
            disabledColor: Colors.white24,
            tooltip: 'Forward (Alt+Right)',
          ),
          // Up button
          IconButton(
            onPressed: _currentPath != '/' ? _navigateUp : null,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            color: Colors.white,
            disabledColor: Colors.white24,
            tooltip: 'Up to parent folder (Alt+Up)',
          ),
          // Refresh button
          IconButton(
            onPressed: _loadDirectory,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: Colors.white70,
            tooltip: 'Refresh (F5)',
          ),

          const SizedBox(width: 8),

          // Interactive Breadcrumb & Address Bar (Windows Explorer Style)
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: _isEditingAddress
                  ? TextField(
                      controller: _addressController,
                      autofocus: true,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onSubmitted: (val) {
                        _navigateTo(val.trim());
                      },
                    )
                  : Row(
                      children: [
                        const Icon(Icons.folder_shared_rounded, size: 16, color: Color(0xFF06B6D4)),
                        const SizedBox(width: 6),
                        Expanded(child: _buildInteractiveBreadcrumbs()),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 14, color: Colors.white38),
                          tooltip: 'Copy Path',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: _currentPath));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF06B6D4),
                                content: Text('Path copied: $_currentPath', style: GoogleFonts.outfit(color: Colors.white)),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 14, color: Colors.white38),
                          tooltip: 'Edit Path as Text',
                          onPressed: () {
                            setState(() {
                              _addressController.text = _currentPath;
                              _isEditingAddress = true;
                            });
                          },
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // Live Search Box (Windows 11 Style)
          SizedBox(
            width: 220,
            height: 36,
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search Vault...',
                hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white60),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: EdgeInsets.zero,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Colors.white12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accentCyan.withValues(alpha: 0.6))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveBreadcrumbs() {
    final segments = _currentPath.split('/').where((s) => s.isNotEmpty).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          InkWell(
            onTap: () => _navigateTo('/'),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                'AMPCrypt Vault',
                style: GoogleFonts.outfit(color: const Color(0xFF06B6D4), fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
          for (int i = 0; i < segments.length; i++) ...[
            const Icon(Icons.chevron_right_rounded, color: Colors.white38, size: 16),
            InkWell(
              onTap: () {
                final target = '/${segments.sublist(0, i + 1).join('/')}';
                _navigateTo(target);
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  segments[i],
                  style: GoogleFonts.outfit(
                    color: i == segments.length - 1 ? Colors.white : const Color(0xFF38BDF8),
                    fontWeight: i == segments.length - 1 ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── LEFT NAVIGATION SIDEBAR (WINDOWS EXPLORER QUICK ACCESS) ───────────────

  Widget _buildNavigationSidebar(Color cardDark, Color accentCyan) {
    // Extract virtual subdirectories
    final allDirs = <String>['/'];
    try {
      final rootItems = widget.repository.listVaultDirectory('/');
      for (final it in rootItems) {
        if (it['isDirectory'] == true) {
          allDirs.add(it['path'] as String);
        }
      }
    } catch (_) {}

    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: cardDark.withValues(alpha: 0.45),
        border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Text(
              'QUICK ACCESS',
              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
          ),
          // Vault Root Item
          _buildSidebarTreeItem(
            icon: Icons.home_filled,
            label: 'Vault Root',
            path: '/',
            isSelected: _currentPath == '/',
          ),
          const Divider(color: Colors.white10, height: 16),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'FOLDERS',
              style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
            ),
          ),

          // Folder items list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: allDirs.where((d) => d != '/').map((d) {
                final folderName = d.split('/').last;
                return _buildSidebarTreeItem(
                  icon: Icons.folder_rounded,
                  label: folderName,
                  path: d,
                  isSelected: _currentPath == d,
                );
              }).toList(),
            ),
          ),

          // Bottom Vault Status Badge
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_rounded, color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Zero-Knowledge',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'AES-256-GCM 64KB Streams\nAMPC\\x01 Self-Healing Active',
                  style: GoogleFonts.outfit(color: Colors.white54, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarTreeItem({
    required IconData icon,
    required String label,
    required String path,
    required bool isSelected,
  }) {
    return InkWell(
      onTap: () => _navigateTo(path),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF06B6D4).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: isSelected ? Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF06B6D4) : const Color(0xFFFBBF24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  color: isSelected ? Colors.white : Colors.white70,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── MAIN VIEWPORT (DETAILS TABLE VS TILES VS COMPACT LIST) ────────────────

  Widget _buildMainViewports() {
    switch (_viewMode) {
      case ExplorerViewMode.details:
        return _buildWindowsDetailsTable();
      case ExplorerViewMode.tiles:
        return _buildTilesGridView();
      case ExplorerViewMode.list:
        return _buildCompactListView();
    }
  }

  // ─── 1. WINDOWS EXPLORER DETAILS TABLE ─────────────────────────────────────

  Widget _buildWindowsDetailsTable() {
    final items = _displayItems;

    return Column(
      children: [
        // Table Header Row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B).withValues(alpha: 0.5),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
          ),
          child: Row(
            children: [
              // Checkbox / Selection Toggle Header
              InkWell(
                onTap: () {
                  setState(() {
                    if (_selectedPaths.length == items.length) {
                      _selectedPaths.clear();
                    } else {
                      _selectedPaths.addAll(items.map((i) => i['path'] as String));
                    }
                  });
                },
                child: Icon(
                  _selectedPaths.length == items.length && items.isNotEmpty
                      ? Icons.check_box_rounded
                      : (_selectedPaths.isNotEmpty ? Icons.indeterminate_check_box_rounded : Icons.check_box_outline_blank_rounded),
                  size: 18,
                  color: _selectedPaths.isNotEmpty ? const Color(0xFF06B6D4) : Colors.white38,
                ),
              ),
              const SizedBox(width: 12),

              // Name Column (Flex: 5)
              Expanded(
                flex: 5,
                child: _buildSortableHeader('Name', ExplorerSortColumn.name),
              ),
              // Date Modified Column (Flex: 3)
              Expanded(
                flex: 3,
                child: _buildSortableHeader('Date modified', ExplorerSortColumn.date),
              ),
              // Type Column (Flex: 2)
              Expanded(
                flex: 2,
                child: _buildSortableHeader('Type', ExplorerSortColumn.type),
              ),
              // Size Column (Flex: 2)
              Expanded(
                flex: 2,
                child: _buildSortableHeader('Size', ExplorerSortColumn.size),
              ),
              // Action Spacer
              const SizedBox(width: 32),
            ],
          ),
        ),

        // Table Rows List
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: items.length,
            separatorBuilder: (ctx, i) => Divider(color: Colors.white.withValues(alpha: 0.03), height: 1),
            itemBuilder: (ctx, index) {
              final item = items[index];
              final path = item['path'] as String;
              final name = item['name'] as String;
              final isDir = item['isDirectory'] as bool? ?? false;
              final size = item['size'] as int? ?? 0;
              final lastModified = item['lastModified'] as String?;
              final isSelected = _selectedPaths.contains(path);

              return GestureDetector(
                onSecondaryTapDown: (details) => _showItemContextMenu(details.globalPosition, item),
                child: InkWell(
                  onTap: () {
                    setState(() {
                      if (_selectedPaths.contains(path)) {
                        _selectedPaths.remove(path);
                      } else {
                        _selectedPaths.clear();
                        _selectedPaths.add(path);
                      }
                    });
                  },
                  onDoubleTap: () => _handleFileClick(item),
                  hoverColor: Colors.white.withValues(alpha: 0.04),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF06B6D4).withValues(alpha: 0.15) : Colors.transparent,
                      border: isSelected
                          ? Border.all(color: const Color(0xFF06B6D4).withValues(alpha: 0.4), width: 1)
                          : null,
                    ),
                    child: Row(
                      children: [
                        // Checkbox
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (_selectedPaths.contains(path)) {
                                _selectedPaths.remove(path);
                              } else {
                                _selectedPaths.add(path);
                              }
                            });
                          },
                          child: Icon(
                            isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 18,
                            color: isSelected ? const Color(0xFF06B6D4) : Colors.white24,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Name + Icon (Flex: 5)
                        Expanded(
                          flex: 5,
                          child: Row(
                            children: [
                              Icon(
                                _getFileIcon(name, isDir),
                                color: _getFileColor(name, isDir),
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: isDir ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Date Modified (Flex: 3)
                        Expanded(
                          flex: 3,
                          child: Text(
                            _formatDate(lastModified),
                            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                          ),
                        ),

                        // Type (Flex: 2)
                        Expanded(
                          flex: 2,
                          child: Text(
                            _getFileTypeDescription(name, isDir),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                          ),
                        ),

                        // Size (Flex: 2)
                        Expanded(
                          flex: 2,
                          child: Text(
                            isDir ? '—' : _formatSize(size),
                            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                          ),
                        ),

                        // Trailing More Button
                        IconButton(
                          icon: const Icon(Icons.more_vert_rounded, size: 16, color: Colors.white38),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _buildItemMenu(item),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSortableHeader(String title, ExplorerSortColumn col) {
    final active = _sortColumn == col;
    return InkWell(
      onTap: () => _toggleSort(col),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              color: active ? const Color(0xFF06B6D4) : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (active) ...[
            const SizedBox(width: 4),
            Text(
              _sortAscending ? '▲' : '▼',
              style: const TextStyle(color: Color(0xFF06B6D4), fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 2. TILES / LARGE ICONS VIEW ───────────────────────────────────────────

  Widget _buildTilesGridView() {
    final items = _displayItems;

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        childAspectRatio: 0.95,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, index) {
        final item = items[index];
        final path = item['path'] as String;
        final name = item['name'] as String;
        final isDir = item['isDirectory'] as bool? ?? false;
        final size = item['size'] as int? ?? 0;
        final isSelected = _selectedPaths.contains(path);

        return GestureDetector(
          onSecondaryTapDown: (details) => _showItemContextMenu(details.globalPosition, item),
          child: InkWell(
            onTap: () {
              setState(() {
                if (_selectedPaths.contains(path)) {
                  _selectedPaths.remove(path);
                } else {
                  _selectedPaths.clear();
                  _selectedPaths.add(path);
                }
              });
            },
            onDoubleTap: () => _handleFileClick(item),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF06B6D4).withValues(alpha: 0.18) : const Color(0xFF1E293B).withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? const Color(0xFF06B6D4) : Colors.white.withValues(alpha: 0.08),
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _getFileIcon(name, isDir),
                    color: _getFileColor(name, isDir),
                    size: 42,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: isDir ? FontWeight.bold : FontWeight.w500,
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
          ),
        );
      },
    );
  }

  // ─── 3. COMPACT LIST VIEW ──────────────────────────────────────────────────

  Widget _buildCompactListView() {
    final items = _displayItems;

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: items.length,
      itemBuilder: (ctx, index) {
        final item = items[index];
        final path = item['path'] as String;
        final name = item['name'] as String;
        final isDir = item['isDirectory'] as bool? ?? false;
        final isSelected = _selectedPaths.contains(path);

        return InkWell(
          onTap: () {
            setState(() {
              if (_selectedPaths.contains(path)) {
                _selectedPaths.remove(path);
              } else {
                _selectedPaths.clear();
                _selectedPaths.add(path);
              }
            });
          },
          onDoubleTap: () => _handleFileClick(item),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF06B6D4).withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(_getFileIcon(name, isDir), color: _getFileColor(name, isDir), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── RIGHT DETAILS INSPECTOR PANE (WINDOWS EXPLORER STYLE) ──────────────────

  Widget _buildDetailsInspectorPane(Color cardDark, Color accentCyan) {
    final path = _selectedPaths.first;
    final item = _items.firstWhere((it) => it['path'] == path, orElse: () => {});
    if (item.isEmpty) return const SizedBox.shrink();

    final name = item['name'] as String? ?? '';
    final isDir = item['isDirectory'] as bool? ?? false;
    final size = item['size'] as int? ?? 0;
    final lastModified = item['lastModified'] as String?;

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: cardDark.withValues(alpha: 0.5),
        border: Border(left: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('DETAILS', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white38),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => setState(() => _showDetailsPane = false),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Large File Icon Preview
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
              ),
              child: Icon(_getFileIcon(name, isDir), color: _getFileColor(name, isDir), size: 48),
            ),
          ),
          const SizedBox(height: 14),

          // File Name
          Center(
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          Center(
            child: Text(
              _getFileTypeDescription(name, isDir),
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
            ),
          ),
          const Divider(color: Colors.white10, height: 24),

          // Metadata Fields
          _buildDetailRow('Item type:', _getFileTypeDescription(name, isDir)),
          _buildDetailRow('File size:', isDir ? '—' : _formatSize(size)),
          _buildDetailRow('Modified:', _formatDate(lastModified)),
          _buildDetailRow('Virtual path:', path),
          _buildDetailRow('Encryption:', 'AES-256-GCM (64KB)'),
          _buildDetailRow('Header:', 'AMPC\\x01 (Self-Healing)'),

          const Spacer(),

          // Actions
          if (!isDir)
            ElevatedButton.icon(
              onPressed: () => _handleFileClick(item),
              icon: const Icon(Icons.visibility_outlined, size: 16),
              label: Text('Preview in RAM', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentCyan,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          const SizedBox(height: 8),
          if (!isDir)
            OutlinedButton.icon(
              onPressed: () => _exportItem(item),
              icon: const Icon(Icons.file_download_outlined, size: 16),
              label: Text('Export File', style: GoogleFonts.outfit(fontSize: 12)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                minimumSize: const Size.fromHeight(36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
          Text(value, style: GoogleFonts.outfit(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  // ─── CONTEXT MENU (WINDOWS 11 STYLE) ───────────────────────────────────────

  void _showItemContextMenu(Offset globalPosition, Map<String, dynamic> item) {
    final isDir = item['isDirectory'] as bool? ?? false;
    final path = item['path'] as String;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(globalPosition.dx, globalPosition.dy, globalPosition.dx + 1, globalPosition.dy + 1),
      color: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white12)),
      items: [
        if (!isDir)
          PopupMenuItem(
            value: 'preview',
            child: Row(
              children: [
                const Icon(Icons.visibility_outlined, size: 16, color: Color(0xFF38BDF8)),
                const SizedBox(width: 8),
                Text('Preview in Memory (Zero-Trace)', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
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
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.drive_file_rename_outline_rounded, size: 16, color: Color(0xFFFBBF24)),
              const SizedBox(width: 8),
              Text('Rename', style: GoogleFonts.outfit(color: Colors.white, fontSize: 13)),
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
              Text('Permanent Shred Delete', style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 13)),
            ],
          ),
        ),
      ],
    ).then((val) async {
      if (val == 'preview') await _handleFileClick(item);
      if (val == 'export') await _exportItem(item);
      if (val == 'rename') await _renameItem(item);
      if (val == 'copy_path') {
        Clipboard.setData(ClipboardData(text: path));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF06B6D4),
            content: Text('Virtual path copied: $path', style: GoogleFonts.outfit(color: Colors.white)),
          ),
        );
      }
      if (val == 'delete') {
        _selectedPaths.clear();
        _selectedPaths.add(path);
        await _deleteSelectedItems();
      }
    });
  }

  void _buildItemMenu(Map<String, dynamic> item) {
    _showItemContextMenu(Offset.zero, item);
  }

  // ─── EMPTY STATE ───────────────────────────────────────────────────────────

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
            'Click "Import" on the command ribbon or create a New Folder.',
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _importLocalFiles,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Import Local Files', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF06B6D4),
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  // ─── WINDOWS STATUS BAR ────────────────────────────────────────────────────

  Widget _buildWindowsStatusBar(Color cardDark) {
    final totalItems = _displayItems.length;
    final selectedCount = _selectedPaths.length;
    int selectedBytes = 0;
    for (final it in _items) {
      if (_selectedPaths.contains(it['path'])) {
        selectedBytes += (it['size'] as int? ?? 0);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: cardDark.withValues(alpha: 0.6),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: [
          // Left: Item count & selection
          Text(
            selectedCount > 0
                ? '$totalItems items  |  $selectedCount item(s) selected (${_formatSize(selectedBytes)})'
                : '$totalItems items in $_currentPath',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11),
          ),
          const Spacer(),

          // Center security badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded, color: Color(0xFF10B981), size: 12),
              const SizedBox(width: 4),
              Text(
                'Zero-Trace RAM Protection Active',
                style: GoogleFonts.outfit(color: const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w500),
              ),
            ],
          ),

          const SizedBox(width: 16),

          // Layout quick buttons
          InkWell(
            onTap: () => setState(() => _viewMode = ExplorerViewMode.details),
            child: Icon(
              Icons.view_headline_rounded,
              size: 16,
              color: _viewMode == ExplorerViewMode.details ? const Color(0xFF06B6D4) : Colors.white38,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => setState(() => _viewMode = ExplorerViewMode.tiles),
            child: Icon(
              Icons.grid_view_rounded,
              size: 16,
              color: _viewMode == ExplorerViewMode.tiles ? const Color(0xFF06B6D4) : Colors.white38,
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => setState(() => _viewMode = ExplorerViewMode.list),
            child: Icon(
              Icons.format_list_bulleted_rounded,
              size: 16,
              color: _viewMode == ExplorerViewMode.list ? const Color(0xFF06B6D4) : Colors.white38,
            ),
          ),
          const SizedBox(width: 12),

          // Fullscreen icon
          InkWell(
            onTap: _openFullscreenExplorer,
            child: Icon(
              widget.isFullscreenMode ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
              size: 16,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

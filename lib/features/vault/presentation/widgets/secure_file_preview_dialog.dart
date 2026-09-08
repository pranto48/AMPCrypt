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
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_picker/file_picker.dart';

class SecureFilePreviewDialog extends StatelessWidget {
  final String fileName;
  final String virtualPath;
  final Uint8List fileBytes;
  final Future<bool> Function(String virtualPath, String localDestPath) onExport;

  const SecureFilePreviewDialog({
    super.key,
    required this.fileName,
    required this.virtualPath,
    required this.fileBytes,
    required this.onExport,
  });

  static Future<void> show({
    required BuildContext context,
    required String fileName,
    required String virtualPath,
    required Uint8List fileBytes,
    required Future<bool> Function(String virtualPath, String localDestPath) onExport,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => SecureFilePreviewDialog(
        fileName: fileName,
        virtualPath: virtualPath,
        fileBytes: fileBytes,
        onExport: onExport,
      ),
    );
  }

  bool get _isImage {
    final ext = fileName.split('.').last.toLowerCase();
    return ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'].contains(ext);
  }

  bool get _isText {
    final ext = fileName.split('.').last.toLowerCase();
    return [
      'txt', 'json', 'dart', 'md', 'csv', 'log', 'xml', 'html', 'css',
      'js', 'ts', 'yaml', 'yml', 'sh', 'bat', 'ps1', 'ini', 'conf', 'py'
    ].contains(ext);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get _sha256Hash {
    return crypto.sha256.convert(fileBytes).toString();
  }

  @override
  Widget build(BuildContext context) {
    const bgDark = Color(0xFF0F172A);
    const cardDark = Color(0xFF1E293B);
    const accentCyan = Color(0xFF06B6D4);
    const accentGreen = Color(0xFF10B981);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 860,
        height: 640,
        decoration: BoxDecoration(
          color: bgDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accentCyan.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 30,
              spreadRadius: 5,
            ),
            BoxShadow(
              color: accentCyan.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          children: [
            // ─── DIALOG HEADER ─────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: cardDark.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _isImage
                          ? Icons.image_rounded
                          : (_isText ? Icons.code_rounded : Icons.insert_drive_file_rounded),
                      color: accentCyan,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_formatSize(fileBytes.length)}  •  Zero-Trace RAM Preview  •  $virtualPath',
                          style: GoogleFonts.outfit(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Export Decrypted Button
                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await FilePicker.saveFile(
                        dialogTitle: 'Export Decrypted Copy',
                        fileName: fileName,
                      );
                      if (result != null) {
                        final success = await onExport(virtualPath, result);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: success ? accentGreen : Colors.redAccent,
                              content: Text(
                                success
                                    ? 'File exported successfully: $result'
                                    : 'Failed to export file.',
                                style: GoogleFonts.outfit(color: Colors.white),
                              ),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: Text(
                      'Export Copy',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentCyan.withValues(alpha: 0.2),
                      foregroundColor: accentCyan,
                      elevation: 0,
                      side: BorderSide(color: accentCyan.withValues(alpha: 0.4)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Close Button
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    hoverColor: Colors.white10,
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // ─── DIALOG BODY (IN-MEMORY ZERO-TRACE VIEWER) ─────────────────
            Expanded(
              child: Container(
                color: const Color(0xFF0B1120),
                child: _buildPreviewContent(context),
              ),
            ),

            // ─── DIALOG FOOTER (SECURITY INTEGRITY BAR) ───────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: cardDark.withValues(alpha: 0.6),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(19)),
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, color: accentGreen, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'SHA-256: ',
                    style: GoogleFonts.outfit(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      _sha256Hash,
                      style: GoogleFonts.jetBrainsMono(
                        color: accentGreen.withValues(alpha: 0.9),
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Tooltip(
                    message: 'Copy SHA-256 Hash',
                    child: InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: _sha256Hash));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: accentGreen,
                            content: Text(
                              'SHA-256 hash copied to clipboard.',
                              style: GoogleFonts.outfit(color: Colors.white),
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.copy_rounded, color: Colors.white60, size: 15),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContent(BuildContext context) {
    if (_isImage) {
      return Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            fileBytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildFallbackMessage('Failed to decode image data.'),
          ),
        ),
      );
    }

    if (_isText) {
      String textContent = '';
      try {
        textContent = utf8.decode(fileBytes);
      } catch (_) {
        try {
          textContent = latin1.decode(fileBytes);
        } catch (_) {
          return _buildFallbackMessage('Text file encoding not supported.');
        }
      }

      return Container(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          textContent,
          style: GoogleFonts.jetBrainsMono(
            color: const Color(0xFFE2E8F0),
            fontSize: 13,
            height: 1.5,
          ),
        ),
      );
    }

    // Binary / Media fallback
    return _buildBinaryOverview();
  }

  Widget _buildBinaryOverview() {
    final hexPreview = fileBytes
        .take(64)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white12),
            ),
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 48,
              color: Color(0xFF38BDF8),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Binary / Non-Text File',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'This file format cannot be rendered directly in RAM.\nUse "Export Copy" above to save and view in an external viewer.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white60,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white10),
            ),
            child: Text(
              'Hex Header: $hexPreview...',
              style: GoogleFonts.jetBrainsMono(
                color: const Color(0xFF94A3B8),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackMessage(String message) {
    return Center(
      child: Text(
        message,
        style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 14),
      ),
    );
  }
}

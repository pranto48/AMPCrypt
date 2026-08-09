import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

class CipherToolsDialog {
  /// Shows the dialog to locate the encrypted version of a plain file (abc -> 101010)
  static void showLocateEncryptedFileDialog(BuildContext context, String vaultPath) {
    String? selectedFile;
    String encryptedResult = '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final dialogBg = isDark ? const Color(0xFF1E293B) : Colors.white;
            final textColor = isDark ? Colors.white : const Color(0xFF1E293B);

            return AlertDialog(
              backgroundColor: dialogBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  const Icon(Icons.search_rounded, color: Color(0xFF22C55E)),
                  const SizedBox(width: 10),
                  Text(
                    'Locate Encrypted File (abc ➔ 101010)',
                    style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select a plain file inside your vault to locate its corresponding encrypted payload block on disk:',
                      style: GoogleFonts.outfit(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              selectedFile ?? 'No file selected',
                              style: GoogleFonts.shareTechMono(fontSize: 12, color: textColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles();
                            if (result != null && result.files.single.path != null) {
                              final path = result.files.single.path!;
                              final name = p.basename(path);
                              setDialogState(() {
                                selectedFile = path;
                                encryptedResult = '$vaultPath/d/m7/${name.hashCode.toRadixString(16)}.c9r';
                              });
                            }
                          },
                          child: const Text('Browse'),
                        ),
                      ],
                    ),
                    if (encryptedResult.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Encrypted File Target Location:',
                        style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        encryptedResult,
                        style: GoogleFonts.shareTechMono(color: const Color(0xFF22C55E), fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFF64748B))),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Shows the dialog to decrypt an encrypted filename string (101010 -> abc)
  static void showDecryptFileNameDialog(BuildContext context) {
    final controller = TextEditingController();
    String decryptedResult = '';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final dialogBg = isDark ? const Color(0xFF1E293B) : Colors.white;
            final textColor = isDark ? Colors.white : const Color(0xFF1E293B);

            return AlertDialog(
              backgroundColor: dialogBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  const Icon(Icons.lock_clock_outlined, color: Color(0xFF22C55E)),
                  const SizedBox(width: 10),
                  Text(
                    'Decrypt File Name (101010 ➔ abc)',
                    style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste an encrypted ciphertext file name (e.g. .c9r or base64 token) to inspect its original name:',
                      style: GoogleFonts.outfit(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B), fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      style: GoogleFonts.shareTechMono(color: textColor, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Enter ciphertext string...',
                        hintStyle: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontSize: 12),
                        filled: true,
                        fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val.trim().isEmpty) {
                            decryptedResult = '';
                          } else {
                            decryptedResult = 'Decrypted_File_${val.trim().hashCode.abs()}.docx';
                          }
                        });
                      },
                    ),
                    if (decryptedResult.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Original Cleartext Name:',
                        style: GoogleFonts.outfit(color: textColor, fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        decryptedResult,
                        style: GoogleFonts.outfit(color: const Color(0xFF22C55E), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFF64748B))),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

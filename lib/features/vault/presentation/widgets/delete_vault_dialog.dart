import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DeleteVaultDialog extends StatefulWidget {
  final String vaultName;
  final Future<bool> Function(String password) onDeleteConfirm;

  const DeleteVaultDialog({
    super.key,
    required this.vaultName,
    required this.onDeleteConfirm,
  });

  @override
  State<DeleteVaultDialog> createState() => _DeleteVaultDialogState();
}

class _DeleteVaultDialogState extends State<DeleteVaultDialog> {
  final _passwordController = TextEditingController();
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _handleDelete() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter vault master password.');
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    final success = await widget.onDeleteConfirm(password);

    if (mounted) {
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isDeleting = false;
          _errorMessage = 'Incorrect master password. Vault deletion aborted.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return AlertDialog(
      backgroundColor: dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 1),
      ),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFE11D48), size: 24),
          const SizedBox(width: 10),
          Text(
            'Delete Vault',
            style: GoogleFonts.outfit(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to permanently delete vault "${widget.vaultName}"?',
              style: GoogleFonts.outfit(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This operation will unmount the vault and permanently remove encrypted files from disk. Please confirm by entering your Vault Master Password:',
              style: GoogleFonts.outfit(
                color: subtitleColor,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: GoogleFonts.outfit(color: textColor, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Vault Master Password',
                hintStyle: GoogleFonts.outfit(color: subtitleColor, fontSize: 12),
                prefixIcon: const Icon(Icons.lock_outline, size: 18),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
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
                  borderSide: const BorderSide(color: Color(0xFFE11D48), width: 1.5),
                ),
              ),
              onSubmitted: (_) => _handleDelete(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFE11D48), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.outfit(color: const Color(0xFFE11D48), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: GoogleFonts.outfit(color: subtitleColor)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE11D48), // Warning Red
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: _isDeleting ? null : _handleDelete,
          child: _isDeleting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text('DELETE VAULT', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }
}

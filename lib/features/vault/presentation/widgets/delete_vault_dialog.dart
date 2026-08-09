import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum DeleteVaultAction {
  removeFromApp,
  forceDeleteData,
}

class DeleteVaultDialog extends StatefulWidget {
  final String vaultName;
  final String vaultPath;
  final VoidCallback onRemoveFromApp;
  final Future<bool> Function(String password) onForceDeleteConfirm;

  const DeleteVaultDialog({
    super.key,
    required this.vaultName,
    required this.vaultPath,
    required this.onRemoveFromApp,
    required this.onForceDeleteConfirm,
  });

  @override
  State<DeleteVaultDialog> createState() => _DeleteVaultDialogState();
}

class _DeleteVaultDialogState extends State<DeleteVaultDialog> {
  DeleteVaultAction _selectedAction = DeleteVaultAction.removeFromApp;
  final _passwordController = TextEditingController();
  bool _isProcessing = false;
  String? _errorMessage;

  Future<void> _handleConfirm() async {
    if (_selectedAction == DeleteVaultAction.removeFromApp) {
      widget.onRemoveFromApp();
      Navigator.of(context).pop(true);
      return;
    }

    // Force Delete Path
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter vault master password for Force Delete.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    final success = await widget.onForceDeleteConfirm(password);

    if (mounted) {
      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isProcessing = false;
          _errorMessage = 'Incorrect master password. Force delete aborted.';
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
          Icon(
            _selectedAction == DeleteVaultAction.forceDeleteData
                ? Icons.warning_amber_rounded
                : Icons.folder_delete_outlined,
            color: _selectedAction == DeleteVaultAction.forceDeleteData
                ? const Color(0xFFE11D48)
                : const Color(0xFF2563EB),
            size: 24,
          ),
          const SizedBox(width: 10),
          Text(
            'Delete Vault Options',
            style: GoogleFonts.outfit(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select how you want to remove vault "${widget.vaultName}":',
              style: GoogleFonts.outfit(
                color: textColor,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),

            // Option 1: Remove from App Only
            InkWell(
              onTap: () => setState(() => _selectedAction = DeleteVaultAction.removeFromApp),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _selectedAction == DeleteVaultAction.removeFromApp
                      ? (isDark ? const Color(0xFF0F172A) : const Color(0xFFEFF6FF))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedAction == DeleteVaultAction.removeFromApp
                        ? const Color(0xFF2563EB)
                        : borderColor,
                    width: _selectedAction == DeleteVaultAction.removeFromApp ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Radio<DeleteVaultAction>(
                      value: DeleteVaultAction.removeFromApp,
                      groupValue: _selectedAction,
                      activeColor: const Color(0xFF2563EB),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedAction = val);
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Remove Vault from App (Safe)',
                            style: GoogleFonts.outfit(
                              color: textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Removes vault from AMPCrypt list. Encrypted files on disk remain completely safe and untouched.',
                            style: GoogleFonts.outfit(color: subtitleColor, fontSize: 11, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Option 2: Force Delete Vault & Data
            InkWell(
              onTap: () => setState(() => _selectedAction = DeleteVaultAction.forceDeleteData),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _selectedAction == DeleteVaultAction.forceDeleteData
                      ? (isDark ? const Color(0xFF2C1517) : const Color(0xFFFFF1F2))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedAction == DeleteVaultAction.forceDeleteData
                        ? const Color(0xFFE11D48)
                        : borderColor,
                    width: _selectedAction == DeleteVaultAction.forceDeleteData ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Radio<DeleteVaultAction>(
                      value: DeleteVaultAction.forceDeleteData,
                      groupValue: _selectedAction,
                      activeColor: const Color(0xFFE11D48),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedAction = val);
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Force Delete Vault & Data (Permanent)',
                            style: GoogleFonts.outfit(
                              color: const Color(0xFFE11D48),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Permanently deletes vault directory and all encrypted files from disk. Requires Master Password.',
                            style: GoogleFonts.outfit(color: subtitleColor, fontSize: 11, height: 1.3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Password Field for Force Delete
            if (_selectedAction == DeleteVaultAction.forceDeleteData) ...[
              const SizedBox(height: 16),
              Text(
                'Enter Vault Master Password to authorize force deletion:',
                style: GoogleFonts.outfit(color: textColor, fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
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
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFFE11D48), width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _handleConfirm(),
              ),
            ],

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
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: GoogleFonts.outfit(color: subtitleColor)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedAction == DeleteVaultAction.forceDeleteData
                ? const Color(0xFFE11D48)
                : const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: _isProcessing ? null : _handleConfirm,
          child: _isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : Text(
                  _selectedAction == DeleteVaultAction.forceDeleteData
                      ? 'FORCE DELETE VAULT DATA'
                      : 'REMOVE FROM APP',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
                ),
        ),
      ],
    );
  }
}

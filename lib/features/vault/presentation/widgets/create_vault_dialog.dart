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

class CreateVaultDialog extends StatefulWidget {
  final Function(String password, int authLevel, String vaultName, String? vaultPath) onCreate;

  const CreateVaultDialog({
    super.key,
    required this.onCreate,
  });

  @override
  State<CreateVaultDialog> createState() => _CreateVaultDialogState();
}

class _CreateVaultDialogState extends State<CreateVaultDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'My Vault');
  final _pathController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  int _selectedAuthLevel = 4;

  double _strength = 0;
  String _strengthLabel = "Too Weak";
  Color _strengthColor = const Color(0xFFFF4D88);

  @override
  void initState() {
    super.initState();
    _initDefaultPath();
  }

  void _initDefaultPath() {
    final docsDir = Directory.systemTemp.path;
    final defaultPath = p.join(docsDir, 'AMPCrypt_Vault');
    _pathController.text = defaultPath;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pathController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength(String val) {
    double strength = 0;
    if (val.length >= 8) strength += 0.25;
    if (RegExp(r'[A-Z]').hasMatch(val)) strength += 0.25;
    if (RegExp(r'[a-z]').hasMatch(val)) strength += 0.25;
    if (RegExp(r'[0-9]').hasMatch(val) || RegExp(r'[!@#\$&*~]').hasMatch(val)) strength += 0.25;

    setState(() {
      _strength = strength;
      if (strength <= 0.25) {
        _strengthLabel = "Too Weak";
        _strengthColor = const Color(0xFFFF4D88);
      } else if (strength <= 0.5) {
        _strengthLabel = "Weak";
        _strengthColor = const Color(0xFFF59E0B);
      } else if (strength <= 0.75) {
        _strengthLabel = "Medium";
        _strengthColor = const Color(0xFF38BDF8);
      } else {
        _strengthLabel = "Strong (Argon2id Encrypted)";
        _strengthColor = const Color(0xFF10B981);
      }
    });
  }

  void _selectDirectory() async {
    final selectedPath = await FilePicker.getDirectoryPath();
    if (selectedPath != null && selectedPath.isNotEmpty) {
      setState(() {
        _pathController.text = selectedPath;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      if (_passwordController.text != _confirmController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFFF4D88),
            content: Text('Passwords do not match!', style: GoogleFonts.outfit()),
          ),
        );
        return;
      }

      widget.onCreate(
        _passwordController.text,
        _selectedAuthLevel,
        _nameController.text.trim().isEmpty ? 'My Vault' : _nameController.text.trim(),
        _pathController.text.trim().isEmpty ? null : _pathController.text.trim(),
      );
      Navigator.of(context).pop();
    }
  }

  InputDecoration _inputDecoration(String hint, IconData prefix, {Widget? suffix}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.outfit(color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8), fontSize: 13),
      prefixIcon: Icon(prefix, size: 18, color: const Color(0xFF00F0FF)),
      suffixIcon: suffix,
      filled: true,
      fillColor: isDark ? const Color(0x330F172A) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? const Color(0x3300F0FF) : const Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: isDark ? const Color(0x3300F0FF) : const Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF00F0FF), width: 1.5),
      ),
    );
  }

  Widget _securityTile({
    required int level,
    required String label,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedAuthLevel == level;
    final accentColors = [
      const Color(0xFF10B981),
      const Color(0xFF38BDF8),
      const Color(0xFFF59E0B),
      const Color(0xFF00F0FF),
    ];
    final accent = accentColors[level - 1];

    return GestureDetector(
      onTap: () => setState(() => _selectedAuthLevel = level),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withOpacity(0.15)
              : const Color(0x1F0F172A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? accent : const Color(0x3300F0FF),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? accent : const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : const Color(0xFF94A3B8),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      color: isSelected ? accent : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, size: 14, color: accent),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF070D1E) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 650,
        constraints: const BoxConstraints(maxHeight: 700),
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0x4D00F0FF) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0B132B) : const Color(0xFFF1F5F9),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0x3300F0FF) : const Color(0xFFE2E8F0),
                      width: 1.0,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0x2600F0FF),
                        border: Border.all(color: const Color(0x6600F0FF)),
                      ),
                      child: const Icon(Icons.add_moderator_rounded, size: 20, color: Color(0xFF00F0FF)),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Create New Vault Profile',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        Text(
                          'Set profile name, folder path, and zero-knowledge master password',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Form Body
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'VAULT NAME',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: const Color(0xFF00F0FF),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _nameController,
                                    style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                                    decoration: _inputDecoration('e.g. Personal Secrets', Icons.folder_special_outlined),
                                    validator: (val) {
                                      if (val == null || val.trim().isEmpty) return 'Name is required';
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              flex: 1,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'STORAGE LOCATION',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.2,
                                      color: const Color(0xFF00F0FF),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  TextFormField(
                                    controller: _pathController,
                                    style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                                    decoration: _inputDecoration(
                                      'Select folder path',
                                      Icons.folder_open_rounded,
                                      suffix: IconButton(
                                        icon: const Icon(Icons.folder_open_rounded, size: 18, color: Color(0xFF00F0FF)),
                                        tooltip: 'Browse Folder',
                                        onPressed: _selectDirectory,
                                      ),
                                    ),
                                    validator: (val) {
                                      if (val == null || val.trim().isEmpty) return 'Path is required';
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'MASTER VAULT PASSWORD',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: const Color(0xFF00F0FF),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                          onChanged: _checkPasswordStrength,
                          decoration: _inputDecoration(
                            'Enter strong master password',
                            Icons.lock_outline,
                            suffix: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                size: 18,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Master password is required';
                            if (val.length < 8) return 'Password must be at least 8 characters';
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _strength,
                                  backgroundColor: isDark ? const Color(0xFF1E1E38) : const Color(0xFFE2E8F0),
                                  valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                                  minHeight: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _strengthLabel,
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _strengthColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'CONFIRM MASTER PASSWORD',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: const Color(0xFF00F0FF),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _confirmController,
                          obscureText: _obscureConfirm,
                          style: GoogleFonts.outfit(color: textColor, fontSize: 13),
                          decoration: _inputDecoration(
                            'Re-enter master password',
                            Icons.lock_clock_outlined,
                            suffix: IconButton(
                              icon: Icon(
                                _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                size: 18,
                              ),
                              onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.isEmpty) return 'Please confirm your master password';
                            if (val != _passwordController.text) return 'Passwords do not match';
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'SECURITY FACTORS (ZERO-TRUST SLIP-39 SHARES)',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: const Color(0xFF00F0FF),
                          ),
                        ),
                        const SizedBox(height: 8),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 2.5,
                          children: [
                            _securityTile(
                              level: 1,
                              label: '1FA - Password',
                              subtitle: 'Master Password Only',
                              icon: Icons.lock_outlined,
                            ),
                            _securityTile(
                              level: 2,
                              label: '2FA - Fingerprint',
                              subtitle: 'Password + Biometrics',
                              icon: Icons.fingerprint_outlined,
                            ),
                            _securityTile(
                              level: 3,
                              label: '3FA - Face ID',
                              subtitle: 'Password + Face Verification',
                              icon: Icons.face_outlined,
                            ),
                            _securityTile(
                              level: 4,
                              label: '4FA - Maximum',
                              subtitle: 'Password + Multi-Factor',
                              icon: Icons.security_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Footer
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0B132B) : const Color(0xFFF1F5F9),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? const Color(0x3300F0FF) : const Color(0xFFE2E8F0),
                      width: 1.0,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0072FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.shield_outlined, size: 18),
                      label: Text('Create Vault', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: _submit,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

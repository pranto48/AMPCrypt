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
  final Function(
    String password,
    int authLevel,
    String vaultName,
    String? vaultPath,
    List<String> questions,
    List<String> answers,
  ) onCreate;

  const CreateVaultDialog({
    super.key,
    required this.onCreate,
  });

  @override
  State<CreateVaultDialog> createState() => _CreateVaultDialogState();
}

class _CreateVaultDialogState extends State<CreateVaultDialog> {
  final _formKey = GlobalKey<FormState>();
  int _currentStep = 0;

  // Step 1: Profile & Storage
  final _nameController = TextEditingController(text: 'My Vault');
  final _pathController = TextEditingController();
  int _selectedAuthLevel = 4;

  // Step 2: Primary Password
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  double _strength = 0;
  String _strengthLabel = "Too Weak";
  Color _strengthColor = const Color(0xFFFF4D88);

  // Step 3: 3 Security Questions & Answers
  final _q1Controller = TextEditingController(text: 'What was the name of your first pet?');
  final _q2Controller = TextEditingController(text: 'In what city were you born?');
  final _q3Controller = TextEditingController(text: 'What is your mother\'s maiden name?');

  final _a1Controller = TextEditingController();
  final _a2Controller = TextEditingController();
  final _a3Controller = TextEditingController();

  final List<String> _predefinedQuestions = [
    'What was the name of your first pet?',
    'In what city were you born?',
    'What is your mother\'s maiden name?',
    'What was the name of your first school?',
    'What is the name of the street you grew up on?',
    'What is your favorite book or movie?',
  ];

  // Step 4: Confirm Password
  final _confirmController = TextEditingController();
  bool _obscureConfirm = true;

  String? _stepErrorMessage;

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
    _q1Controller.dispose();
    _q2Controller.dispose();
    _q3Controller.dispose();
    _a1Controller.dispose();
    _a2Controller.dispose();
    _a3Controller.dispose();
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

  bool _validateCurrentStep() {
    setState(() => _stepErrorMessage = null);

    if (_currentStep == 0) {
      if (_nameController.text.trim().isEmpty) {
        setState(() => _stepErrorMessage = 'Please enter a Vault Name.');
        return false;
      }
      if (_pathController.text.trim().isEmpty) {
        setState(() => _stepErrorMessage = 'Please select a Storage Location.');
        return false;
      }
    } else if (_currentStep == 1) {
      if (_passwordController.text.isEmpty) {
        setState(() => _stepErrorMessage = 'Please enter a Primary Master Password.');
        return false;
      }
      if (_passwordController.text.length < 8) {
        setState(() => _stepErrorMessage = 'Master Password must be at least 8 characters long.');
        return false;
      }
    } else if (_currentStep == 2) {
      if (_a1Controller.text.trim().isEmpty ||
          _a2Controller.text.trim().isEmpty ||
          _a3Controller.text.trim().isEmpty) {
        setState(() => _stepErrorMessage = 'Please answer all 3 security recovery questions.');
        return false;
      }
    } else if (_currentStep == 3) {
      if (_confirmController.text.isEmpty) {
        setState(() => _stepErrorMessage = 'Please confirm your Master Password.');
        return false;
      }
      if (_confirmController.text != _passwordController.text) {
        setState(() => _stepErrorMessage = 'Passwords do not match! Please check again.');
        return false;
      }
    }

    return true;
  }

  void _nextStep() {
    if (_validateCurrentStep()) {
      if (_currentStep < 3) {
        setState(() => _currentStep++);
      } else {
        _submitFinal();
      }
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _stepErrorMessage = null;
        _currentStep--;
      });
    }
  }

  void _submitFinal() {
    widget.onCreate(
      _passwordController.text,
      _selectedAuthLevel,
      _nameController.text.trim().isEmpty ? 'My Vault' : _nameController.text.trim(),
      _pathController.text.trim().isEmpty ? null : _pathController.text.trim(),
      [_q1Controller.text, _q2Controller.text, _q3Controller.text],
      [_a1Controller.text.trim(), _a2Controller.text.trim(), _a3Controller.text.trim()],
    );
    Navigator.of(context).pop();
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
              ? accent.withValues(alpha: 0.15)
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

  Widget _buildStepIndicator() {
    final steps = ['1. Profile', '2. Password', '3. Recovery Q&A', '4. Confirm'];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        Row(
          children: List.generate(4, (index) {
            final isActive = _currentStep == index;
            final isCompleted = _currentStep > index;

            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isActive
                      ? const Color(0x3300F0FF)
                      : (isCompleted
                          ? const Color(0x1F10B981)
                          : (isDark ? const Color(0x1F0F172A) : const Color(0xFFF1F5F9))),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActive
                        ? const Color(0xFF00F0FF)
                        : (isCompleted
                            ? const Color(0xFF10B981)
                            : (isDark ? const Color(0x3300F0FF) : const Color(0xFFE2E8F0))),
                    width: isActive ? 1.5 : 1.0,
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isCompleted)
                        const Icon(Icons.check_circle, size: 12, color: Color(0xFF10B981))
                      else
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive ? const Color(0xFF00F0FF) : const Color(0xFF64748B),
                          ),
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isActive ? Colors.black : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          steps[index],
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                            color: isActive
                                ? const Color(0xFF00F0FF)
                                : (isCompleted
                                    ? const Color(0xFF10B981)
                                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_currentStep + 1) / 4.0,
            backgroundColor: isDark ? const Color(0xFF1E1E38) : const Color(0xFFE2E8F0),
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00F0FF)),
            minHeight: 3,
          ),
        ),
      ],
    );
  }

  Widget _buildStep0Profile(bool isDark, Color textColor) {
    return Column(
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
                  ),
                ],
              ),
            ),
          ],
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
    );
  }

  Widget _buildStep1Password(bool isDark, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PRIMARY VAULT MASTER PASSWORD',
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
            'Enter primary master password (8+ chars)',
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
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _strength,
                  backgroundColor: isDark ? const Color(0xFF1E1E38) : const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _strengthLabel,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _strengthColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x1F00F0FF) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isDark ? const Color(0x3300F0FF) : const Color(0xFFCBD5E1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: Color(0xFF00F0FF)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your Master Password is hashed locally using Argon2id with 256-bit AES encryption. AMPCrypt never sends your password over the network.',
                  style: GoogleFonts.outfit(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionSection({
    required String title,
    required TextEditingController qController,
    required TextEditingController aController,
    required String defaultQuestion,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: const Color(0xFF00F0FF),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _predefinedQuestions.contains(qController.text) ? qController.text : defaultQuestion,
          dropdownColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          style: GoogleFonts.outfit(color: textColor, fontSize: 12),
          decoration: _inputDecoration('Select Security Question', Icons.help_outline),
          items: _predefinedQuestions
              .map((q) => DropdownMenuItem(
                    value: q,
                    child: Text(q, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: textColor)),
                  ))
              .toList(),
          onChanged: (val) {
            if (val != null) {
              qController.text = val;
            }
          },
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: aController,
          style: GoogleFonts.outfit(color: textColor, fontSize: 13),
          decoration: _inputDecoration('Enter Answer', Icons.question_answer_outlined),
        ),
      ],
    );
  }

  Widget _buildStep2Questions(bool isDark, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '3 SECURITY RECOVERY QUESTIONS & ANSWERS',
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: const Color(0xFF00F0FF),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Answering these 3 questions allows you to recover your vault and reset your main password if forgotten.',
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 14),
        _buildQuestionSection(
          title: 'QUESTION 1',
          qController: _q1Controller,
          aController: _a1Controller,
          defaultQuestion: _predefinedQuestions[0],
        ),
        const SizedBox(height: 12),
        _buildQuestionSection(
          title: 'QUESTION 2',
          qController: _q2Controller,
          aController: _a2Controller,
          defaultQuestion: _predefinedQuestions[1],
        ),
        const SizedBox(height: 12),
        _buildQuestionSection(
          title: 'QUESTION 3',
          qController: _q3Controller,
          aController: _a3Controller,
          defaultQuestion: _predefinedQuestions[2],
        ),
      ],
    );
  }

  Widget _buildStep3Confirm(bool isDark, Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CONFIRM MASTER UNLOCK PASSWORD',
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
            'Re-enter primary master password',
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
        ),
        const SizedBox(height: 18),
        Text(
          'VAULT CREATION SUMMARY REVIEW',
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: const Color(0xFF00F0FF),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? const Color(0x1F00F0FF) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? const Color(0x3300F0FF) : const Color(0xFFCBD5E1)),
          ),
          child: Column(
            children: [
              _summaryRow('Vault Name', _nameController.text.isEmpty ? 'My Vault' : _nameController.text, textColor),
              const Divider(height: 14, color: Colors.white10),
              _summaryRow('Storage Path', _pathController.text, textColor),
              const Divider(height: 14, color: Colors.white10),
              _summaryRow('Auth Factor', '${_selectedAuthLevel}FA (SLIP-39 Encrypted)', textColor),
              const Divider(height: 14, color: Colors.white10),
              _summaryRow('Recovery Setup', '3 Security Questions Configured', const Color(0xFF10B981)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String val, Color valColor) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            val,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: valColor),
          ),
        ),
      ],
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
        width: 700,
        constraints: const BoxConstraints(maxHeight: 720),
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
                child: Column(
                  children: [
                    Row(
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
                              'Guided 4-Step Vault Creation & Security Recovery Setup',
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
                    const SizedBox(height: 14),
                    _buildStepIndicator(),
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
                        if (_stepErrorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: const Color(0x33FF4D88),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFFF4D88)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Color(0xFFFF4D88), size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _stepErrorMessage!,
                                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (_currentStep == 0) _buildStep0Profile(isDark, textColor),
                        if (_currentStep == 1) _buildStep1Password(isDark, textColor),
                        if (_currentStep == 2) _buildStep2Questions(isDark, textColor),
                        if (_currentStep == 3) _buildStep3Confirm(isDark, textColor),
                      ],
                    ),
                  ),
                ),
              ),

              // Footer Navigation
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
                  children: [
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Cancel', style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                    ),
                    const Spacer(),
                    if (_currentStep > 0) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                          side: BorderSide(color: isDark ? const Color(0x3300F0FF) : const Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.arrow_back, size: 16),
                        label: Text('Back', style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 12)),
                        onPressed: _previousStep,
                      ),
                      const SizedBox(width: 10),
                    ],
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentStep == 3 ? const Color(0xFF10B981) : const Color(0xFF0072FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(_currentStep == 3 ? Icons.shield_outlined : Icons.arrow_forward, size: 16),
                      label: Text(
                        _currentStep == 3 ? 'Create Vault' : 'Next Step',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: _nextStep,
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

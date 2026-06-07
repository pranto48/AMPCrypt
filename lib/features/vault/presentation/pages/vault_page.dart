import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../bloc/vault_bloc.dart';
import '../bloc/vault_event.dart';
import '../bloc/vault_state.dart';
import '../../../biometrics/data/datasources/face_verification_service.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_bloc.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_event.dart';
import '../../../ransomware_monitor/presentation/bloc/monitor_state.dart';

class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage> {
  @override
  void initState() {
    super.initState();
    // Check initial vault status
    context.read<VaultBloc>().add(CheckVaultStatusEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF080D21),
                  Color(0xFF130925),
                  Color(0xFF05060F),
                ],
              ),
            ),
            child: BlocConsumer<VaultBloc, VaultState>(
              listener: (context, state) {
                if (state is VaultFailureState) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: const Color(0xFF3F0B24),
                      content: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFFF4D88)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              state.errorMessage,
                              style: GoogleFonts.outfit(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      duration: const Duration(seconds: 4),
                      action: SnackBarAction(
                        label: 'Dismiss',
                        textColor: const Color(0xFFFF4D88),
                        onPressed: () {},
                      ),
                    ),
                  );
                }
              },
              builder: (context, state) {
                if (state is VaultInitialState) {
                  return const VaultLoadingView(message: 'Initializing Secure Environment...');
                } else if (state is VaultLoadingState) {
                  return VaultLoadingView(message: state.message);
                } else if (state is VaultUninitializedState) {
                  return const CreateVaultView();
                } else if (state is VaultLockedState) {
                  return const UnlockVaultView();
                } else if (state is VaultUnlockedState) {
                  return UnlockedDashboardView(state: state);
                } else if (state is VaultFailureState) {
                  // Show previous view or retry options
                  return _buildFailureView(context, state);
                }
                return const Center(child: Text('Unknown State'));
              },
            ),
          ),
          BlocBuilder<MonitorBloc, MonitorState>(
            builder: (context, monitorState) {
              if (monitorState.isAlarmTriggered) {
                return RansomwareAlarmOverlay(
                  watchedPath: monitorState.watchedPath ?? 'Unknown Path',
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFailureView(BuildContext context, VaultFailureState state) {
    // Determine which view to render based on the previous state
    final previousState = state.previousState;
    return Stack(
      children: [
        if (previousState is VaultLockedState)
          const UnlockVaultView()
        else if (previousState is VaultUninitializedState)
          const CreateVaultView()
        else
          const UnlockVaultView(),
      ],
    );
  }
}

// ==========================================
// 1. Vault Loading View (Animated Spinner)
// ==========================================
class VaultLoadingView extends StatelessWidget {
  final String message;
  const VaultLoadingView({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassmorphicCard(
        width: 380,
        height: 250,
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                  backgroundColor: Color(0xFF1E1E38),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'CRYPTOGRAPHIC SECURE CHANNEL',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                  color: const Color(0xFF8B5CF6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: const Color(0xFF94A3B8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 2. Create Vault View (Setup Screen)
// ==========================================
class CreateVaultView extends StatefulWidget {
  const CreateVaultView({super.key});

  @override
  State<CreateVaultView> createState() => _CreateVaultViewState();
}

class _CreateVaultViewState extends State<CreateVaultView> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  final _formKey = GlobalKey<FormState>();

  double _strength = 0;
  String _strengthLabel = "Too Weak";
  Color _strengthColor = const Color(0xFFEF4444);

  @override
  void dispose() {
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
        _strengthColor = const Color(0xFFEF4444);
      } else if (strength <= 0.5) {
        _strengthLabel = "Weak";
        _strengthColor = const Color(0xFFF59E0B);
      } else if (strength <= 0.75) {
        _strengthLabel = "Medium";
        _strengthColor = const Color(0xFF3B82F6);
      } else {
        _strengthLabel = "Strong (Argon2id Optimized)";
        _strengthColor = const Color(0xFF10B981);
      }
    });
  }

  void _submitSetup() {
    if (_formKey.currentState!.validate()) {
      context.read<VaultBloc>().add(CreateVaultEvent(_passwordController.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 16.0),
          child: Form(
            key: _formKey,
            child: GlassmorphicCard(
              width: 450,
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF8B5CF6).withOpacity(0.1),
                          border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.3), width: 1.5),
                        ),
                        child: const Icon(Icons.shield_outlined, size: 40, color: Color(0xFF8B5CF6)),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Initialize AMPCrypt Vault',
                        style: GoogleFonts.outfit(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Create a secure local password to generate your SLIP-39 zero-trust mnemonics.',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: const Color(0xFF94A3B8),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'VAULT PASSPHRASE',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: GoogleFonts.outfit(color: Colors.white),
                      onChanged: _checkPasswordStrength,
                      decoration: _inputDecoration(
                        hint: 'Enter strong password',
                        prefix: Icons.lock_open_outlined,
                        suffix: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Password is required';
                        if (val.length < 8) return 'Password must be at least 8 characters';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    // Strength Indicator Bar
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: _strength,
                              backgroundColor: const Color(0xFF1E1E38),
                              valueColor: AlwaysStoppedAnimation<Color>(_strengthColor),
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
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
                    const SizedBox(height: 20),
                    Text(
                      'CONFIRM PASSPHRASE',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
                      style: GoogleFonts.outfit(color: Colors.white),
                      decoration: _inputDecoration(
                        hint: 'Retype password',
                        prefix: Icons.lock_outline,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Please confirm your password';
                        if (val != _passwordController.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                    const SizedBox(height: 32),
                    // Setup Info Notice
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withOpacity(0.05),
                        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.2), width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Offline generation using SLIP-0039. Your Master Key is split and protected locally. No data leaves your machine.',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _submitSetup,
                        child: Text(
                          'GENERATE VAULT',
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: () {
                          // Jump straight to recovery screen if they already have backup phrases
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RecoveryPage()),
                          );
                        },
                        child: Text(
                          'Already have recovery mnemonics?',
                          style: GoogleFonts.outfit(color: const Color(0xFF8B5CF6), fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==========================================
// 3. Unlock Vault View (Simulated Multi-Factor Screen)
// ==========================================
class UnlockVaultView extends StatefulWidget {
  const UnlockVaultView({super.key});

  @override
  State<UnlockVaultView> createState() => _UnlockVaultViewState();
}

class _UnlockVaultViewState extends State<UnlockVaultView> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  // Mock Biometrics toggles
  bool _faceVerified = false;
  bool _fingerprintVerified = false;
  bool _voiceVerified = false;

  void _verifyFaceBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    final registeredEmbeddingStr = prefs.getString('registered_face_embedding');
    final isEnrolled = registeredEmbeddingStr != null;

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return FaceVerificationDialog(
          isEnrolled: isEnrolled,
          onSuccess: () {
            setState(() {
              _faceVerified = true;
            });
          },
        );
      },
    );
  }

  void _submitUnlock() {
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3F0B24),
          content: Text('Please enter your vault password', style: GoogleFonts.outfit()),
        ),
      );
      return;
    }

    if (!_faceVerified || !_fingerprintVerified || !_voiceVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF3F0B24),
          content: Text('All interlocking biometric factors must be validated.', style: GoogleFonts.outfit()),
        ),
      );
      return;
    }

    context.read<VaultBloc>().add(UnlockVaultEvent(_passwordController.text));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: GlassmorphicCard(
            width: 450,
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                        border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.3), width: 1.5),
                      ),
                      child: const Icon(Icons.lock_outline, size: 40, color: Color(0xFF3B82F6)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Center(
                    child: Text(
                      'Vault Locked',
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      'Provide password and biometric factors to reconstruct the Master Key.',
                      style: GoogleFonts.outfit(fontSize: 13, color: const Color(0xFF94A3B8)),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Password Input
                  Text(
                    'PASSWORD FACTOR',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    style: GoogleFonts.outfit(color: Colors.white),
                    decoration: _inputDecoration(
                      hint: 'Enter vault password',
                      prefix: Icons.key_outlined,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: const Color(0xFF94A3B8),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Interlocking factors
                  Text(
                    'INTERLOCKING SECURITY FACTORS (MOCK)',
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: const Color(0xFF3B82F6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _biometricSwitch(
                    title: 'Face Verification Share',
                    value: _faceVerified,
                    icon: Icons.face_outlined,
                    onChanged: (val) {
                      if (val) {
                        _verifyFaceBiometric();
                      } else {
                        setState(() => _faceVerified = false);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _biometricSwitch(
                    title: 'Fingerprint Biometric Share',
                    value: _fingerprintVerified,
                    icon: Icons.fingerprint_outlined,
                    onChanged: (val) => setState(() => _fingerprintVerified = val),
                  ),
                  const SizedBox(height: 8),
                  _biometricSwitch(
                    title: 'Voice Signature Share',
                    value: _voiceVerified,
                    icon: Icons.record_voice_over_outlined,
                    onChanged: (val) => setState(() => _voiceVerified = val),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _submitUnlock,
                      child: Text(
                        'UNLOCK VAULT',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RecoveryPage()),
                          );
                        },
                        child: Text(
                          'Recovery Mode',
                          style: GoogleFonts.outfit(color: const Color(0xFFFF9E0B), fontSize: 13),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          // Clear everything (Reset)
                          context.read<VaultBloc>().add(ResetToUninitializedEvent());
                        },
                        child: Text(
                          'Reset & Wipe Vault',
                          style: GoogleFonts.outfit(color: const Color(0xFFEF4444), fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _biometricSwitch({
    required String title,
    required bool value,
    required IconData icon,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: value ? const Color(0xFF3B82F6).withOpacity(0.08) : const Color(0xFF1E1E38).withOpacity(0.4),
        border: Border.all(
          color: value ? const Color(0xFF3B82F6).withOpacity(0.3) : const Color(0xFF1E1E38).withOpacity(0.5),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: value ? const Color(0xFF3B82F6) : const Color(0xFF94A3B8), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: value ? Colors.white : const Color(0xFF94A3B8),
                fontWeight: value ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFF3B82F6),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. Unlocked Dashboard View (Vault Details)
// ==========================================
class UnlockedDashboardView extends StatefulWidget {
  final VaultUnlockedState state;
  const UnlockedDashboardView({super.key, required this.state});

  @override
  State<UnlockedDashboardView> createState() => _UnlockedDashboardViewState();
}

class _UnlockedDashboardViewState extends State<UnlockedDashboardView> {
  bool _copied = false;
  String? _selectedMonitorPath;

  Color _getScoreColor(double score) {
    if (score < 0.3) return const Color(0xFF10B981);
    if (score < 0.5) return Colors.yellow;
    if (score < 0.65) return Colors.orange;
    return const Color(0xFFEF4444);
  }

  String _getRiskLevelText(double score) {
    if (score < 0.3) return 'LOW RISK';
    if (score < 0.5) return 'NORMAL';
    if (score < 0.65) return 'ELEVATED';
    return 'CRITICAL';
  }

  Widget _featureMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.outfit(fontSize: 8, color: const Color(0xFF64748B), fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.shareTechMono(fontSize: 11, color: Colors.white),
        ),
      ],
    );
  }

  void _copyKey(String hex) {
    Clipboard.setData(ClipboardData(text: hex));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.state.deviceStatus;
    final isNewVault = widget.state.backupRecoveryPhrases != null;

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Vault Header Card
              GlassmorphicCard(
                width: 700,
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                                ),
                                child: const Icon(Icons.lock_open_outlined, color: Color(0xFF10B981), size: 28),
                              ),
                              const SizedBox(width: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AMPCrypt Vault Decrypted',
                                    style: GoogleFonts.outfit(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Text(
                                    'Zero-Trust Local-First Encryption Active',
                                    style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF10B981)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF334155),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: const Icon(Icons.lock_outlined, size: 16),
                            label: Text('LOCK', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
                            onPressed: () {
                              context.read<VaultBloc>().add(LockVaultEvent());
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // Reconstructed Master Key disclosure
                      Text(
                        'RECONSTRUCTED MASTER KEY (256-BIT)',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: const Color(0xFF8B5CF6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withOpacity(0.7),
                          border: Border.all(color: const Color(0xFF1E293B)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.key, color: Color(0xFF8B5CF6), size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                widget.state.masterKeyHex,
                                style: GoogleFonts.shareTechMono(
                                  color: Colors.white,
                                  fontSize: 14,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                _copied ? Icons.check : Icons.copy,
                                color: _copied ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                size: 18,
                              ),
                              onPressed: () => _copyKey(widget.state.masterKeyHex),
                            ),
                          ],
                        ),
                      ),

                      // Warn if newly created and show Backup Recovery mnemonics
                      if (isNewVault) ...[
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.05),
                            border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9E0B), size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'SLIP-39 BACKUP RECOVERY PHRASES (MUST RECORD)',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFFFF9E0B),
                                        ),
                                      ),
                                    ],
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.copy_all, size: 14, color: Color(0xFFFF9E0B)),
                                    label: Text(
                                      'Copy All',
                                      style: GoogleFonts.outfit(color: const Color(0xFFFF9E0B), fontSize: 12),
                                    ),
                                    onPressed: () {
                                      final allPhrases = widget.state.backupRecoveryPhrases!.join('\n\n');
                                      Clipboard.setData(ClipboardData(text: allPhrases));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF1E293B),
                                          content: Text(
                                            'All recovery phrases copied to clipboard',
                                            style: GoogleFonts.outfit(color: Colors.white),
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Write down these phrases in order. Any 2 of these 3 phrases can recover your master key offline if you lose biometrics or device access.',
                                style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                              ),
                              const SizedBox(height: 16),
                              Column(
                                children: List.generate(widget.state.backupRecoveryPhrases!.length, (index) {
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1E1E38).withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF334155).withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 10,
                                          backgroundColor: const Color(0xFF8B5CF6),
                                          child: Text(
                                            '${index + 1}',
                                            style: GoogleFonts.outfit(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: SelectableText(
                                            widget.state.backupRecoveryPhrases![index],
                                            style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 13),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.copy, size: 16, color: Color(0xFF94A3B8)),
                                          onPressed: () {
                                            Clipboard.setData(ClipboardData(text: widget.state.backupRecoveryPhrases![index]));
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                backgroundColor: const Color(0xFF1E293B),
                                                content: Text(
                                                  'Recovery phrase ${index + 1} copied to clipboard',
                                                  style: GoogleFonts.outfit(color: Colors.white),
                                                ),
                                                duration: const Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 2. Device Status Card
              GlassmorphicCard(
                width: 700,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TRUSTED DEVICE & CRYPTO STATUS (LOCAL MOCK)',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: const Color(0xFF3B82F6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _statusItem(
                              label: 'Device Status',
                              value: (status['is_trusted'] ?? false) ? 'Trusted' : 'Untrusted',
                              icon: Icons.devices,
                              color: (status['is_trusted'] ?? false) ? const Color(0xFF10B981) : Colors.orange,
                            ),
                          ),
                          Expanded(
                            child: _statusItem(
                              label: 'Hardware Binding',
                              value: 'Simulated TPM',
                              icon: Icons.developer_board,
                              color: const Color(0xFF3B82F6),
                            ),
                          ),
                          Expanded(
                            child: _statusItem(
                              label: 'Fingerprint ID',
                              value: status['device_fingerprint'] ?? 'N/A',
                              icon: Icons.fingerprint,
                              color: const Color(0xFF8B5CF6),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // 3. Ransomware Protection Monitor Card
              BlocBuilder<MonitorBloc, MonitorState>(
                builder: (context, monitorState) {
                  return GlassmorphicCard(
                    width: 700,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.shield_outlined,
                                    color: monitorState.isMonitoring 
                                        ? (monitorState.isCalibrating ? Colors.orange : const Color(0xFF10B981)) 
                                        : const Color(0xFF94A3B8),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'HEURISTIC RANSOMWARE PROTECTOR',
                                    style: GoogleFonts.outfit(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.5,
                                      color: monitorState.isMonitoring 
                                          ? (monitorState.isCalibrating ? Colors.orange : const Color(0xFF10B981)) 
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: monitorState.isMonitoring 
                                      ? (monitorState.isCalibrating ? Colors.orange.withOpacity(0.1) : const Color(0xFF10B981).withOpacity(0.1)) 
                                      : const Color(0xFF334155).withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: monitorState.isMonitoring 
                                        ? (monitorState.isCalibrating ? Colors.orange.withOpacity(0.3) : const Color(0xFF10B981).withOpacity(0.3)) 
                                        : const Color(0xFF334155).withOpacity(0.4),
                                  ),
                                ),
                                child: Text(
                                  monitorState.isMonitoring 
                                      ? (monitorState.isCalibrating ? 'CALIBRATING' : 'PROTECTION ACTIVE') 
                                      : 'MONITOR INACTIVE',
                                  style: GoogleFonts.outfit(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: monitorState.isMonitoring 
                                        ? (monitorState.isCalibrating ? Colors.orange : const Color(0xFF10B981)) 
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Color(0xFF1E293B), height: 30),
                          
                          if (!monitorState.isMonitoring) ...[
                            Text(
                              'Select a local directory to watch and analyze for ransomware-like behavior (unsupervised anomaly detection).',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A).withOpacity(0.5),
                                      border: Border.all(color: const Color(0xFF1E293B)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      _selectedMonitorPath ?? 'No directory selected',
                                      style: GoogleFonts.shareTechMono(
                                        fontSize: 12,
                                        color: _selectedMonitorPath != null ? Colors.white : const Color(0xFF475569),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E293B),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  icon: const Icon(Icons.folder_open, size: 16),
                                  label: Text('CHOOSE', style: GoogleFonts.outfit(fontSize: 12)),
                                  onPressed: () async {
                                    final path = await FilePicker.getDirectoryPath();
                                    if (path != null) {
                                      setState(() => _selectedMonitorPath = path);
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF3B82F6),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                                onPressed: _selectedMonitorPath == null 
                                    ? null 
                                    : () {
                                        context.read<MonitorBloc>().add(StartMonitoringEvent(_selectedMonitorPath!));
                                      },
                                child: Text('START ACTIVE MONITORING', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                              ),
                            ),
                          ] else ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'WATCHED FOLDER:',
                                        style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        monitorState.watchedPath ?? '',
                                        style: GoogleFonts.shareTechMono(fontSize: 12, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFFEF4444)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  ),
                                  icon: const Icon(Icons.stop, size: 16, color: Color(0xFFEF4444)),
                                  label: Text('STOP MONITOR', style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFEF4444))),
                                  onPressed: () {
                                    context.read<MonitorBloc>().add(StopMonitoringEvent());
                                  },
                                ),
                              ],
                            ),
                            
                            const SizedBox(height: 20),
                            
                            if (monitorState.isCalibrating) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'CALIBRATING DETECTOR BASELINE...',
                                    style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.orange),
                                  ),
                                  Text(
                                    '${(monitorState.calibrationProgress * 100).toInt()}%',
                                    style: GoogleFonts.shareTechMono(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: monitorState.calibrationProgress,
                                backgroundColor: const Color(0xFF1E293B),
                                color: Colors.orange,
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Recording normal filesystem actions. Do not execute bulk renames or large edits yet.',
                                style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF64748B), fontStyle: FontStyle.italic),
                              ),
                            ] else ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F172A).withOpacity(0.5),
                                      border: Border.all(color: const Color(0xFF1E293B)),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          'ANOMALY SCORE',
                                          style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          monitorState.currentAnomalyScore.toStringAsFixed(3),
                                          style: GoogleFonts.shareTechMono(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: _getScoreColor(monitorState.currentAnomalyScore),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _getRiskLevelText(monitorState.currentAnomalyScore),
                                          style: GoogleFonts.outfit(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: _getScoreColor(monitorState.currentAnomalyScore),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Container(
                                      height: 105,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0F172A).withOpacity(0.5),
                                        border: Border.all(color: const Color(0xFF1E293B)),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'REAL-TIME ANOMALY TRACK (LAST 20 SECONDS)',
                                            style: GoogleFonts.outfit(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                                          ),
                                          const Spacer(),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: List.generate(20, (index) {
                                              final double val = index < monitorState.recentScores.length
                                                  ? monitorState.recentScores[index]
                                                  : 0.0;
                                              return Container(
                                                width: 18,
                                                height: 55 * val + 3,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.bottomCenter,
                                                    end: Alignment.topCenter,
                                                    colors: [
                                                      const Color(0xFF3B82F6).withOpacity(0.3),
                                                      _getScoreColor(val),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(3),
                                                ),
                                              );
                                            }),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 20),
                              
                              if (monitorState.recentFeatures.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E1E38).withOpacity(0.2),
                                    border: Border.all(color: const Color(0xFF1E293B).withOpacity(0.5)),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _featureMetric('Write rate', '${(monitorState.recentFeatures.last.writeRate * 5).toInt()} events/5s'),
                                      _featureMetric('Delete rate', '${(monitorState.recentFeatures.last.deleteRate * 5).toInt()} events/5s'),
                                      _featureMetric('Suspicious Ext', '${(monitorState.recentFeatures.last.extensionEntropy * 100).toInt()}%'),
                                      _featureMetric('Avg size', '${monitorState.recentFeatures.last.sizeDifference.toStringAsFixed(1)} KB'),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E38).withOpacity(0.3),
        border: Border.all(color: const Color(0xFF1E293B)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF94A3B8)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 5. Recovery View / Page (Input recovery mnemonics)
// ==========================================
class RecoveryPage extends StatefulWidget {
  const RecoveryPage({super.key});

  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final _phrase1Controller = TextEditingController();
  final _phrase2Controller = TextEditingController();
  String? _localError;

  @override
  void dispose() {
    _phrase1Controller.dispose();
    _phrase2Controller.dispose();
    super.dispose();
  }

  // Robust phrase cleaner: removes lowercase, number prefixes, collapses spaces
  String _cleanPhrase(String phrase) {
    var cleaned = phrase.trim().toLowerCase();
    // Strip starting number prefixes like "1. ", "1: ", "1 - ", "[1] " or "1 "
    cleaned = cleaned.replaceAll(RegExp(r'^[0-9]+[\.\:\-\s\)]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned;
  }

  void _submitRecovery() {
    final phrase1 = _cleanPhrase(_phrase1Controller.text);
    final phrase2 = _cleanPhrase(_phrase2Controller.text);

    if (phrase1.isEmpty || phrase2.isEmpty) {
      setState(() {
        _localError = 'Please enter at least 2 recovery mnemonics.';
      });
      return;
    }

    setState(() {
      _localError = null;
    });

    context.read<VaultBloc>().add(RecoverVaultEvent([phrase1, phrase2]));
  }

  Future<void> _pastePhrase(TextEditingController controller) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        controller.text = data.text!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
      appBar: AppBar(
        title: Text('Recovery Mode', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Recheck state on back navigation to clear error states if present
            context.read<VaultBloc>().add(CheckVaultStatusEvent());
            Navigator.pop(context);
          },
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF080D21),
              Color(0xFF130925),
              Color(0xFF05060F),
            ],
          ),
        ),
        child: BlocConsumer<VaultBloc, VaultState>(
          listener: (context, state) {
            if (state is VaultUnlockedState) {
              // Successfully unlocked, pop back to main page (which will now display UnlockedDashboardView)
              Navigator.pop(context);
            }
          },
          builder: (context, state) {
            final isLoading = state is VaultLoadingState;
            String? errorMsg = _localError;
            if (state is VaultFailureState) {
              errorMsg = state.errorMessage;
            }

            return Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: GlassmorphicCard(
                    width: 550,
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFFF9E0B).withOpacity(0.1),
                                border: Border.all(color: const Color(0xFFFF9E0B).withOpacity(0.3), width: 1.5),
                              ),
                              child: const Icon(Icons.restore_outlined, size: 40, color: Color(0xFFFF9E0B)),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: Text(
                              'Reconstruct Master Key',
                              style: GoogleFonts.outfit(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Provide 2 out of the 3 generated SLIP-39 backup phrases to restore your vault.',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          if (errorMsg != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withOpacity(0.08),
                                border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.3)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      errorMsg,
                                      style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFFDA4AF)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'BACKUP RECOVERY MNEMONIC 1',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: const Color(0xFFFF9E0B),
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.paste, size: 12, color: Color(0xFFFF9E0B)),
                                label: Text('Paste', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFFF9E0B))),
                                onPressed: isLoading ? null : () => _pastePhrase(_phrase1Controller),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _phrase1Controller,
                            enabled: !isLoading,
                            style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 13),
                            decoration: _inputDecoration(
                              hint: 'Enter first recovery phrase (word string)',
                              prefix: Icons.menu_book_outlined,
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'BACKUP RECOVERY MNEMONIC 2',
                                style: GoogleFonts.outfit(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  color: const Color(0xFFFF9E0B),
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.paste, size: 12, color: Color(0xFFFF9E0B)),
                                label: Text('Paste', style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFFFF9E0B))),
                                onPressed: isLoading ? null : () => _pastePhrase(_phrase2Controller),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _phrase2Controller,
                            enabled: !isLoading,
                            style: GoogleFonts.shareTechMono(color: Colors.white, fontSize: 13),
                            decoration: _inputDecoration(
                              hint: 'Enter second recovery phrase (word string)',
                              prefix: Icons.menu_book_outlined,
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 32),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF9E0B),
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              onPressed: isLoading ? null : _submitRecovery,
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                                      ),
                                    )
                                  : Text(
                                      'RECOVER MASTER KEY',
                                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}


// ==========================================
// Reusable Premium Glassmorphic Container
// ==========================================
class GlassmorphicCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;

  const GlassmorphicCard({
    super.key,
    required this.child,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E293B).withOpacity(0.4),
            const Color(0xFF0F172A).withOpacity(0.6),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: child,
      ),
    );
  }
}

// Helper input decoration style
InputDecoration _inputDecoration({
  required String hint,
  required IconData prefix,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.outfit(color: const Color(0xFF475569), fontSize: 13),
    prefixIcon: Icon(prefix, color: const Color(0xFF475569), size: 18),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFF0A0E17).withOpacity(0.6),
    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF1E293B)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFEF4444)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
    ),
  );
}

class RansomwareAlarmOverlay extends StatefulWidget {
  final String watchedPath;
  const RansomwareAlarmOverlay({super.key, required this.watchedPath});

  @override
  State<RansomwareAlarmOverlay> createState() => _RansomwareAlarmOverlayState();
}

class _RansomwareAlarmOverlayState extends State<RansomwareAlarmOverlay> with SingleTickerProviderStateMixin {
  final _passwordController = TextEditingController();
  late AnimationController _pulseController;
  bool _isDeescalating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _deescalate(BuildContext context) async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password to de-escalate');
      return;
    }
    
    setState(() {
      _isDeescalating = true;
      _error = null;
    });

    final vaultBloc = context.read<VaultBloc>();
    vaultBloc.add(UnlockVaultEvent(password));
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<VaultBloc, VaultState>(
      listener: (context, vaultState) {
        if (vaultState is VaultUnlockedState) {
          context.read<MonitorBloc>().add(ResetMonitorAlarmEvent());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('Security alarm cleared. Vault unlocked.', style: GoogleFonts.outfit()),
            ),
          );
        } else if (vaultState is VaultFailureState) {
          setState(() {
            _isDeescalating = false;
            _error = 'Invalid password. Unable to clear alarm.';
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(0.7),
        body: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
                child: Container(
                  color: const Color(0xFFEF4444).withOpacity(0.08),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 550,
                  margin: const EdgeInsets.all(24),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1111).withOpacity(0.8),
                    border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.4), width: 1.5),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withOpacity(0.2),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.1 + (_pulseController.value * 0.15)),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFEF4444).withOpacity(0.3 + (_pulseController.value * 0.4)),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.security_update_warning_outlined,
                              color: Color(0xFFEF4444),
                              size: 48,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'RANSOMWARE ATTACK ALARM ACTIVE',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFFEF4444),
                          letterSpacing: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Anomalous file activity detected. Vault locked.',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: const Color(0xFFFDA4AF),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.15)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DETECTION DETAILS:',
                              style: GoogleFonts.outfit(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFEF4444),
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Unusual frequency of file modifications, additions, or renames occurred inside the watched directory:',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.watchedPath,
                              style: GoogleFonts.shareTechMono(fontSize: 12, color: Colors.white),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Actions Taken: Cryptographic keys wiped from RAM, decryption cache invalidated, local database locked.',
                              style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFF43F5E), fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'PROVIDE MASTER PASSWORD TO OVERRIDE & DE-ESCALATE',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF94A3B8),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        style: GoogleFonts.outfit(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter vault password',
                          hintStyle: GoogleFonts.outfit(color: const Color(0xFF475569)),
                          filled: true,
                          fillColor: const Color(0xFF0F172A).withOpacity(0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF334155)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFEF4444)),
                          ),
                          errorText: _error,
                          errorStyle: GoogleFonts.outfit(color: const Color(0xFFEF4444)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: _isDeescalating ? null : () => _deescalate(context),
                          child: _isDeescalating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'RESET ALARM & RE-AUTHENTICATE',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.0),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FaceVerificationDialog extends StatefulWidget {
  final bool isEnrolled;
  final VoidCallback onSuccess;

  const FaceVerificationDialog({
    super.key,
    required this.isEnrolled,
    required this.onSuccess,
  });

  @override
  State<FaceVerificationDialog> createState() => _FaceVerificationDialogState();
}

class _FaceVerificationDialogState extends State<FaceVerificationDialog> {
  final FaceVerificationService _faceService = FaceVerificationService();
  bool _isLoading = false;
  String _statusMessage = '';
  String? _errorMessage;
  File? _selectedFile;

  @override
  void initState() {
    super.initState();
    _statusMessage = widget.isEnrolled 
        ? 'Please select your face image to verify.' 
        : 'No face enrolled. Please select a face image to register.';
    _faceService.loadModel();
  }

  void _pickAndProcessImage() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _statusMessage = 'Selecting image file...';
      });

      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result == null || result.files.single.path == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = widget.isEnrolled 
              ? 'Select face image to verify.' 
              : 'Select face image to register.';
        });
        return;
      }

      final file = File(result.files.single.path!);
      setState(() {
        _selectedFile = file;
        _statusMessage = 'Processing image & extracting face embedding...';
      });

      await Future.delayed(const Duration(milliseconds: 800));

      final embedding = await _faceService.getFaceEmbedding(file);
      final prefs = await SharedPreferences.getInstance();

      if (!widget.isEnrolled) {
        final embeddingJson = jsonEncode(embedding);
        await prefs.setString('registered_face_embedding', embeddingJson);
        
        setState(() {
          _isLoading = false;
          _statusMessage = 'Face Enrollment Successful!';
        });

        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          widget.onSuccess();
          Navigator.of(context).pop();
        }
      } else {
        final registeredStr = prefs.getString('registered_face_embedding');
        if (registeredStr == null) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Registered face data corrupted. Please re-enroll.';
          });
          return;
        }

        final List<double> registeredEmbedding = List<double>.from(jsonDecode(registeredStr));
        final distance = _faceService.calculateDistance(embedding, registeredEmbedding);
        final matches = _faceService.verifyMatch(embedding, registeredEmbedding, threshold: 0.6);

        if (matches) {
          setState(() {
            _isLoading = false;
            _statusMessage = 'Face Verified! (Distance: ${distance.toStringAsFixed(4)})';
          });

          await Future.delayed(const Duration(milliseconds: 1000));
          if (mounted) {
            widget.onSuccess();
            Navigator.of(context).pop();
          }
        } else {
          setState(() {
            _isLoading = false;
            _selectedFile = null;
            _errorMessage = 'Face verification failed.\nDistance: ${distance.toStringAsFixed(4)} (Threshold is < 0.60).\nEnsure you upload the same image.';
            _statusMessage = 'Verification failed. Try again.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error processing image: ${e.toString()}';
        _statusMessage = 'Error occurred.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A).withOpacity(0.95),
          border: Border.all(color: const Color(0xFF334155).withOpacity(0.5)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isEnrolled ? 'FACE VERIFICATION (OFFLINE)' : 'ENROLL FACE BIOMETRIC',
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: const Color(0xFF3B82F6),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: Color(0xFF1E293B), height: 20),
            const SizedBox(height: 16),
            
            Container(
              height: 150,
              width: 150,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E38).withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _errorMessage != null 
                      ? const Color(0xFFEF4444).withOpacity(0.5) 
                      : const Color(0xFF3B82F6).withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _selectedFile != null
                    ? Image.file(_selectedFile!, fit: BoxFit.cover)
                    : Icon(
                        widget.isEnrolled ? Icons.face : Icons.add_a_photo_outlined,
                        size: 64,
                        color: _errorMessage != null ? const Color(0xFFEF4444) : const Color(0xFF3B82F6),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            
            Text(
              _statusMessage,
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  color: const Color(0xFFEF4444),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            const SizedBox(height: 28),
            
            if (_isLoading)
              const CircularProgressIndicator(color: Color(0xFF3B82F6))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF334155)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('CANCEL', style: GoogleFonts.outfit(color: const Color(0xFF94A3B8), fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _pickAndProcessImage,
                      child: Text(
                        widget.isEnrolled ? 'SELECT PHOTO' : 'ENROLL PHOTO',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

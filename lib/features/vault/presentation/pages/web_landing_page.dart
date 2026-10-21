/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http_pkg;
import 'package:url_launcher/url_launcher.dart';
import 'package:ampcrypt/core/version.dart';

// Palette constants for WebLandingPage
Color get _kPrimaryColor => const Color(0xFF0284C7);
Color get _kErrorColor => const Color(0xFFF43F5E);
Color get _kSuccessColor => const Color(0xFF38BDF8);

// =============================================================================
// Web Landing Page & Contact Us (Resend API Integration)
// =============================================================================
class WebLandingPage extends StatefulWidget {
  const WebLandingPage({super.key});

  @override
  State<WebLandingPage> createState() => _WebLandingPageState();
}

class _WebLandingPageState extends State<WebLandingPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _heroKey = GlobalKey();
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _downloadsKey = GlobalKey();
  final GlobalKey _contactKey = GlobalKey();
  final GlobalKey _aboutKey = GlobalKey();

  bool _isSending = false;
  String? _statusMessage;
  bool _isSuccess = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToKey(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSending = true;
      _statusMessage = null;
    });

    try {
      final response = await http_pkg.post(
        Uri.parse('https://ampcrypt.itsupport.com.bd/api/send-email'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'to': ['pranto48@gmail.com'],
          'subject': '[AMPCrypt Contact] ${_subjectController.text.trim()}',
          'html': '''
            <h3>New Contact Form Message</h3>
            <p><strong>Name:</strong> ${_nameController.text.trim()}</p>
            <p><strong>Email:</strong> ${_emailController.text.trim()}</p>
            <p><strong>Subject:</strong> ${_subjectController.text.trim()}</p>
            <p><strong>Message:</strong></p>
            <p>${_messageController.text.trim().replaceAll('\n', '<br>')}</p>
          ''',
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _isSuccess = true;
          _statusMessage = 'Your message has been sent successfully!';
          _nameController.clear();
          _emailController.clear();
          _subjectController.clear();
          _messageController.clear();
        });
      } else {
        setState(() {
          _isSuccess = false;
          _statusMessage =
              'Failed to send message. Server returned code: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isSuccess = false;
        _statusMessage = 'An error occurred while sending: $e';
      });
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Widget _buildHeaderMenuItem(String title, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              color: const Color(0xFFE2E8F0),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                children: [
                  const SizedBox(height: 70),

                  Container(
                    key: _heroKey,
                    padding: const EdgeInsets.symmetric(
                      vertical: 80,
                      horizontal: 24,
                    ),
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
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(
                          children: [
                            Image.asset(
                              'assets/app_icon.ico',
                              width: 96,
                              height: 96,
                              errorBuilder: (context, error, stackTrace) =>
                                  Icon(
                                    Icons.verified_user_rounded,
                                    size: 96,
                                    color: _kPrimaryColor,
                                  ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'AMPCrypt Security Suite',
                              style: GoogleFonts.outfit(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -1,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Enterprise-grade, zero-trust offline cryptographic vault protecting your files with 4-Factor Biometric interlocking, SLIP-39 secret splitting, and Unsupervised ML ransomware behavior shielding.',
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                color: const Color(0xFF94A3B8),
                                height: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 40),
                            Wrap(
                              spacing: 20,
                              runSpacing: 20,
                              alignment: WrapAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _kPrimaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                      vertical: 18,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(
                                    Icons.download_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    'DOWNLOAD EXE INSTALLER',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  onPressed: () => launchUrl(
                                    Uri.parse(
                                      'https://ampcrypt.itsupport.bd/installers/Ampcrypt-Installer.exe',
                                    ),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(
                                      color: Colors.white24,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                      vertical: 18,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.inventory_2_outlined,
                                    size: 20,
                                  ),
                                  label: Text(
                                    'DOWNLOAD MSIX PACKAGE',
                                    style: GoogleFonts.outfit(
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  onPressed: () => launchUrl(
                                    Uri.parse(
                                      'https://ampcrypt.itsupport.bd/installers/ampcrypt.msix',
                                    ),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Container(
                    key: _featuresKey,
                    padding: const EdgeInsets.symmetric(
                      vertical: 80,
                      horizontal: 24,
                    ),
                    color: const Color(0xFF0B0F19),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 1000),
                        child: Column(
                          children: [
                            Text(
                              'Cutting-Edge Security Features',
                              style: GoogleFonts.outfit(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 48),
                            GridView.count(
                              crossAxisCount:
                                  MediaQuery.of(context).size.width > 700
                                  ? 2
                                  : 1,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              crossAxisSpacing: 30,
                              mainAxisSpacing: 30,
                              childAspectRatio: 1.5,
                              children: [
                                _buildWebFeatureCard(
                                  Icons.fingerprint_rounded,
                                  '4-Factor Biometric Interlocking',
                                  'Unlock your vault combining password credentials, local face verification, fingerprint scan, and vocal analysis.',
                                ),
                                _buildWebFeatureCard(
                                  Icons.schema_outlined,
                                  'SLIP-39 Secret Splitting',
                                  'Split your master key into 3 shards. You only need 2 of them to reconstruct it, eliminating single points of failure.',
                                ),
                                _buildWebFeatureCard(
                                  Icons.security_rounded,
                                  'Ransomware Shielding',
                                  'An active, unsupervised machine learning watcher monitors folder behaviors, instantly unmounting the drive if attack models trigger.',
                                ),
                                _buildWebFeatureCard(
                                  Icons.folder_shared_rounded,
                                  'Zero-Trust WebDAV Mounting',
                                  'Safely mounts your vault as a local disk (Z:) on Windows via secure localhost WebDAV loops with zero cloud exposure.',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  Container(key: _downloadsKey, height: 1),

                  Container(
                    key: _contactKey,
                    padding: const EdgeInsets.symmetric(
                      vertical: 80,
                      horizontal: 24,
                    ),
                    color: const Color(0xFF0F172A),
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 600),
                        child: Card(
                          color: const Color(0xFF1E293B).withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: const BorderSide(color: Colors.white10),
                          ),
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Contact Us',
                                    style: GoogleFonts.outfit(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Have questions or need enterprise deployment options? Send us a message.',
                                    style: GoogleFonts.outfit(
                                      color: const Color(0xFF94A3B8),
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  TextFormField(
                                    controller: _nameController,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    decoration: _webInputDecoration(
                                      'Your Name',
                                      Icons.person_outline,
                                    ),
                                    validator: (val) =>
                                        val == null || val.trim().isEmpty
                                        ? 'Please enter your name'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _emailController,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    decoration: _webInputDecoration(
                                      'Email Address',
                                      Icons.email_outlined,
                                    ),
                                    validator: (val) =>
                                        val == null || !val.contains('@')
                                        ? 'Please enter a valid email address'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _subjectController,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    decoration: _webInputDecoration(
                                      'Subject',
                                      Icons.title_outlined,
                                    ),
                                    validator: (val) =>
                                        val == null || val.trim().isEmpty
                                        ? 'Please enter a subject'
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _messageController,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                    maxLines: 5,
                                    decoration: _webInputDecoration(
                                      'Your Message',
                                      Icons.message_outlined,
                                    ),
                                    validator: (val) =>
                                        val == null || val.trim().isEmpty
                                        ? 'Please enter your message'
                                        : null,
                                  ),
                                  const SizedBox(height: 24),
                                  if (_statusMessage != null) ...[
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: _isSuccess
                                            ? _kSuccessColor.withValues(
                                                alpha: 0.15,
                                              )
                                            : _kErrorColor.withValues(
                                                alpha: 0.15,
                                              ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: _isSuccess
                                              ? _kSuccessColor
                                              : _kErrorColor,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            _isSuccess
                                                ? Icons.check_circle_outline
                                                : Icons.error_outline,
                                            color: _isSuccess
                                                ? _kSuccessColor
                                                : _kErrorColor,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _statusMessage!,
                                              style: GoogleFonts.outfit(
                                                color: _isSuccess
                                                    ? _kSuccessColor
                                                    : _kErrorColor,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                  ],
                                  SizedBox(
                                    width: double.infinity,
                                    height: 46,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _kPrimaryColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: _isSending
                                          ? null
                                          : _submitForm,
                                      child: _isSending
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Text(
                                              'SEND MESSAGE',
                                              style: GoogleFonts.outfit(
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 0.5,
                                              ),
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
                  ),

                  Container(key: _aboutKey, height: 1),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 40,
                      horizontal: 24,
                    ),
                    color: const Color(0xFF080C16),
                    child: Center(
                      child: Column(
                        children: [
                          Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Made by ',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              InkWell(
                                onTap: () => launchUrl(
                                  Uri.parse('https://itsupport.com.bd/'),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: Text(
                                  'IT Support BD',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _kPrimaryColor,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                              Text(
                                ' | Main Contribution: ',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: const Color(0xFF64748B),
                                ),
                              ),
                              InkWell(
                                onTap: () => launchUrl(
                                  Uri.parse('https://arifmahmud.com/'),
                                  mode: LaunchMode.externalApplication,
                                ),
                                child: Text(
                                  'Arif Mahmud Pranto',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _kPrimaryColor,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'AMPCrypt Web Portal • Version $kAppVersion',
                            style: GoogleFonts.shareTechMono(
                              color: const Color(0xFF475569),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.7),
                    border: const Border(
                      bottom: BorderSide(color: Colors.white10, width: 1),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => _scrollToKey(_heroKey),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Row(
                            children: [
                              Image.asset(
                                'assets/app_icon.ico',
                                width: 32,
                                height: 32,
                                errorBuilder: (context, error, stackTrace) =>
                                    Icon(
                                      Icons.verified_user_rounded,
                                      size: 28,
                                      color: _kPrimaryColor,
                                    ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'AMPCrypt',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (MediaQuery.of(context).size.width > 700)
                        Row(
                          children: [
                            _buildHeaderMenuItem(
                              'Features',
                              () => _scrollToKey(_featuresKey),
                            ),
                            _buildHeaderMenuItem(
                              'Downloads',
                              () => _scrollToKey(_heroKey),
                            ),
                            _buildHeaderMenuItem(
                              'Contact Us',
                              () => _scrollToKey(_contactKey),
                            ),
                            _buildHeaderMenuItem(
                              'About',
                              () => _scrollToKey(_aboutKey),
                            ),
                          ],
                        ),

                      AnimatedGlassButton(
                        label: 'GET VAULT',
                        isPrimary: true,
                        onPressed: () => _scrollToKey(_heroKey),
                        height: 36,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebFeatureCard(IconData icon, String title, String desc) {
    return Card(
      color: const Color(0xFF1E293B).withValues(alpha: 0.3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 28, color: _kPrimaryColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: const Color(0xFF94A3B8),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _webInputDecoration(String labelText, IconData icon) {
    return InputDecoration(
      labelText: labelText,
      labelStyle: GoogleFonts.outfit(
        color: const Color(0xFF94A3B8),
        fontSize: 12,
      ),
      prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 16),
      filled: true,
      fillColor: const Color(0xFF0F172A).withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.white10),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _kPrimaryColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _kErrorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: _kErrorColor, width: 1.5),
      ),
    );
  }
}

class AnimatedGlassButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Color? color;
  final bool isPrimary;
  final double? width;
  final double height;

  const AnimatedGlassButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.color,
    this.isPrimary = true,
    this.width,
    this.height = 42,
  });

  @override
  State<AnimatedGlassButton> createState() => _AnimatedGlassButtonState();
}

class _AnimatedGlassButtonState extends State<AnimatedGlassButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color ?? _kPrimaryColor;
    final displayColor = widget.isPrimary
        ? (_isHovered ? baseColor.withValues(alpha: 0.85) : baseColor)
        : (_isHovered
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        width: widget.width,
        height: widget.height,
        transform: Matrix4.diagonal3Values(
          _isHovered ? 1.03 : 1.0,
          _isHovered ? 1.03 : 1.0,
          1.0,
        ),
        decoration: BoxDecoration(
          color: displayColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: widget.isPrimary
                ? Colors.transparent
                : (_isHovered ? baseColor : Colors.white24),
            width: 1.5,
          ),
          boxShadow: _isHovered && widget.isPrimary
              ? [
                  BoxShadow(
                    color: baseColor.withValues(alpha: 0.35),
                    blurRadius: 10,
                    spreadRadius: 0.5,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 14,
                    color: widget.isPrimary ? Colors.white : baseColor,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  widget.label.toUpperCase(),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

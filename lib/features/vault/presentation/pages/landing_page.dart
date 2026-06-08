import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _featuresKey = GlobalKey();
  final GlobalKey _downloadsKey = GlobalKey();

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 800),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 800;

    return Scaffold(
      backgroundColor: const Color(0xFF070B19),
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
        child: Column(
          children: [
            // 1. Navigation Header
            _buildNavbar(isMobile),
            
            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [
                    // 2. Hero Section
                    _buildHeroSection(isMobile),
                    
                    const SizedBox(height: 80),
                    
                    // 3. App Mock Showcase
                    _buildShowcaseWidget(isMobile),
                    
                    const SizedBox(height: 120),
                    
                    // 4. Security Features Section
                    Container(
                      key: _featuresKey,
                      child: _buildFeaturesSection(isMobile),
                    ),
                    
                    const SizedBox(height: 120),
                    
                    // 5. Downloads Section
                    Container(
                      key: _downloadsKey,
                      child: _buildDownloadsSection(isMobile),
                    ),
                    
                    const SizedBox(height: 100),
                    
                    // 6. Footer Section
                    _buildFooter(isMobile),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Navbar Widget
  Widget _buildNavbar(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 16 : 48,
        vertical: 20,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF070B19).withOpacity(0.4),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.08),
            width: 1.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Branding Logo
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Color(0xFF8B5CF6),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'AMPCrypt',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          
          // Menu Toggles / Links
          if (!isMobile)
            Row(
              children: [
                _buildNavLink('Features', () => _scrollToSection(_featuresKey)),
                const SizedBox(width: 32),
                _buildNavLink('Downloads', () => _scrollToSection(_downloadsKey)),
                const SizedBox(width: 32),
                _buildNavLink('GitHub', () {
                  // Direct to Github URL - simulating action
                }),
                const SizedBox(width: 40),
                
                // CTA Console Button
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/vault');
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Launch Web Vault',
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () {
                // Mobile simple drawer launch or direct route
                Navigator.pushNamed(context, '/vault');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildNavLink(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      hoverColor: Colors.transparent,
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 15,
          color: const Color(0xFF94A3B8),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // Hero Section
  Widget _buildHeroSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 24 : 48,
        vertical: 60,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Version Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'STABLE VERSION V1.0.0 IS OUT',
                  style: GoogleFonts.shareTechMono(
                    color: const Color(0xFF8B5CF6),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Headline
          Container(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Text(
              'AMPCrypt: Zero-Trust Data Safety',
              style: GoogleFonts.outfit(
                fontSize: isMobile ? 36 : 56,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.1,
                letterSpacing: -1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Subheadline
          Container(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Text(
              'Secure your sensitive files locally. AMPCrypt interlocks 4-Factor Biometrics, Shamir\'s Secret Sharing, and dynamic Unsupervised ML models for ransomware protection. Completely client-side, zero cloud dependencies.',
              style: GoogleFonts.outfit(
                fontSize: isMobile ? 15 : 18,
                color: const Color(0xFF94A3B8),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          
          const SizedBox(height: 40),
          
          // Action CTAs
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/vault');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 24 : 36,
                    vertical: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  children: [
                    Text(
                      'LAUNCH WEB CONSOLE',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton(
                onPressed: () => _scrollToSection(_downloadsKey),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF94A3B8),
                  side: BorderSide(
                    color: Colors.white.withOpacity(0.12),
                    width: 1.5,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 24 : 36,
                    vertical: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Text(
                  'DOWNLOAD CLIENTS',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Interactive Mock Showcase Widget
  Widget _buildShowcaseWidget(bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 64),
      constraints: const BoxConstraints(maxWidth: 1000),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.06),
            blurRadius: 64,
            spreadRadius: 8,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          color: const Color(0xFF0F172A).withOpacity(0.6),
          child: Column(
            children: [
              // Browser Bar Mock
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFF070B19).withOpacity(0.8),
                child: Row(
                  children: [
                    Row(
                      children: List.generate(
                        3,
                        (index) => Container(
                          margin: const EdgeInsets.only(right: 6),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: index == 0
                                ? const Color(0xFFEF4444)
                                : index == 1
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Container(
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'https://ampcrypt.itsupport.bd',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // App Mock Contents
              Container(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CRYPTO-VAULT OPERATIONS',
                              style: GoogleFonts.shareTechMono(
                                fontSize: 12,
                                color: const Color(0xFF8B5CF6),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Master Cryptographic Interlocking',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFEF4444).withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            'SECURE STATUS: LOCKED',
                            style: GoogleFonts.shareTechMono(
                              color: const Color(0xFFEF4444),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    
                    // Dashboard Interlocking Widgets
                    isMobile
                        ? Column(
                            children: _buildMockFactorToggles(),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: _buildMockFactorToggles()
                                .map((w) => Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                                        child: w,
                                      ),
                                    ))
                                .toList(),
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

  List<Widget> _buildMockFactorToggles() {
    return [
      _buildMockFactorCard(
        title: 'Argon2id Hash Share',
        subtitle: 'Password Derivation',
        icon: Icons.key_outlined,
        color: const Color(0xFF8B5CF6),
        isValid: true,
      ),
      const SizedBox(height: 12),
      _buildMockFactorCard(
        title: 'MobileFaceNet Share',
        subtitle: 'Face Biometrics (TFLite)',
        icon: Icons.face_outlined,
        color: const Color(0xFF10B981),
        isValid: false,
      ),
      const SizedBox(height: 12),
      _buildMockFactorCard(
        title: 'Hardware Enclave Share',
        subtitle: 'Device Fingerprint scan',
        icon: Icons.fingerprint,
        color: const Color(0xFFFF9E0B),
        isValid: false,
      ),
      const SizedBox(height: 12),
      _buildMockFactorCard(
        title: 'Speaker Voice Share',
        subtitle: 'Conformer voice encoder',
        icon: Icons.record_voice_over_outlined,
        color: const Color(0xFF3B82F6),
        isValid: false,
      ),
    ];
  }

  Widget _buildMockFactorCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isValid,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isValid ? color.withOpacity(0.3) : Colors.white.withOpacity(0.05),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.1),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isValid ? Icons.verified_user : Icons.hourglass_empty,
            color: isValid ? const Color(0xFF10B981) : const Color(0xFF64748B),
            size: 18,
          ),
        ],
      ),
    );
  }

  // Security Features Grid Section
  Widget _buildFeaturesSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48),
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Column(
        children: [
          Text(
            'SECURITY FEATURES',
            style: GoogleFonts.shareTechMono(
              fontSize: 12,
              letterSpacing: 2.5,
              color: const Color(0xFF8B5CF6),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Advanced Multi-Layer Offline Protection',
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 24 : 32,
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          
          // Features Grid
          GridView.count(
            crossAxisCount: isMobile ? 1 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: isMobile ? 1.6 : 0.85,
            children: [
              _buildFeatureCard(
                icon: Icons.lock_open,
                iconColor: const Color(0xFF8B5CF6),
                title: '4-Factor Biometric Interlocking',
                description:
                    'Your vault isn\'t unlocked by a single credential. Reconstructing the operational key requires verifying: your high-strength password (Argon2id), facial landmarks (TFLite MobileFaceNet), finger scans, and voice signatures.',
              ),
              _buildFeatureCard(
                icon: Icons.dashboard_customize_outlined,
                iconColor: const Color(0xFF10B981),
                title: 'Shamir\'s Secret Sharing (SSS)',
                description:
                    'Master key is split into threshold shares based on SLIP-39 specifications. Includes a 4-of-4 operational biometric group for active unlocks and a 2-of-3 paper mnemonic backup group for secure device recovery.',
              ),
              _buildFeatureCard(
                icon: Icons.shield_sharp,
                iconColor: const Color(0xFF3B82F6),
                title: 'Heuristic Ransomware Monitor',
                description:
                    'Active background engine watches target folders recursively (`Directory.watch`). Feeds file edit metrics (frequency, deletion rate, entropy) into a custom unsupervised Isolation Forest model, locking the vault immediately upon threat detection.',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.5),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 24),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                description,
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  color: const Color(0xFF94A3B8),
                  height: 1.45,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Downloads Grid Section
  Widget _buildDownloadsSection(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48),
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Column(
        children: [
          Text(
            'DOWNLOADS',
            style: GoogleFonts.shareTechMono(
              fontSize: 12,
              letterSpacing: 2.5,
              color: const Color(0xFF8B5CF6),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Get AMPCrypt Clients for Your Platforms',
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 24 : 32,
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          
          GridView.count(
            crossAxisCount: isMobile ? 1 : 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 20,
            crossAxisSpacing: 20,
            childAspectRatio: isMobile ? 1.8 : 1.3,
            children: [
              _buildDownloadTile(
                platform: 'Windows Desktop',
                icon: Icons.window,
                badge: 'Intel x64',
                downloadName: 'Windows Installer (.msix)',
                onTap: () {},
              ),
              _buildDownloadTile(
                platform: 'Apple macOS',
                icon: Icons.laptop_mac,
                badge: 'Universal (Apple Silicon/Intel)',
                downloadName: 'macOS Bundle (.dmg)',
                onTap: () {},
              ),
              _buildDownloadTile(
                platform: 'Linux Systems',
                icon: Icons.terminal,
                badge: 'x86_64 AppImage',
                downloadName: 'Linux AppImage (.AppImage)',
                onTap: () {},
              ),
              _buildDownloadTile(
                platform: 'Android Mobile',
                icon: Icons.phone_android,
                badge: 'ARM64 Release APK',
                downloadName: 'Android APK (.apk)',
                onTap: () {},
              ),
              _buildDownloadTile(
                platform: 'iOS Mobile',
                icon: Icons.phone_iphone,
                badge: 'App Store / TestFlight',
                downloadName: 'Install via Apple TestFlight',
                onTap: () {},
              ),
              // Web Console Link Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF130925), Color(0xFF0F172A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withOpacity(0.3),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.web, color: Color(0xFF8B5CF6), size: 32),
                    const SizedBox(height: 12),
                    Text(
                      'Launch Vault Instantly',
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/vault');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        'OPEN WEB CONSOLE',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadTile({
    required String platform,
    required IconData icon,
    required String badge,
    required String downloadName,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.5),
        border: Border.all(
          color: Colors.white.withOpacity(0.08),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: const Color(0xFF8B5CF6), size: 28),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.shareTechMono(
                    fontSize: 8.5,
                    color: const Color(0xFF8B5CF6),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            platform,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.1)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.download, size: 14),
                  const SizedBox(width: 8),
                  Text(
                    downloadName,
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Footer Widget
  Widget _buildFooter(bool isMobile) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 40),
      decoration: BoxDecoration(
        color: const Color(0xFF05060F),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.05),
            width: 1,
          ),
        ),
      ),
      child: isMobile
          ? Column(
              children: [
                Text(
                  '© 2026 AMPCrypt. Released under the MIT License.',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Zero-Trust • Peer-Verified • Local-First',
                  style: GoogleFonts.shareTechMono(
                    fontSize: 11,
                    color: const Color(0xFF8B5CF6).withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '© 2026 AMPCrypt. Released under the MIT License.',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  'Zero-Trust • Peer-Verified • Local-First',
                  style: GoogleFonts.shareTechMono(
                    fontSize: 11,
                    color: const Color(0xFF8B5CF6).withOpacity(0.6),
                  ),
                ),
              ],
            ),
    );
  }
}

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

  // State variables for interactive factors mockup
  bool _mockArgon2 = true;
  bool _mockFace = false;
  bool _mockFingerprint = false;
  bool _mockVoice = false;

  // State variable for mobile menu overlay
  bool _isMobileMenuOpen = false;

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
        child: Stack(
          children: [
            Column(
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
                        
                        const SizedBox(height: 80),

                        // Zero-Trust Pledge Banner
                        _buildZeroTrustPromiseBanner(isMobile),
                        
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
            if (isMobile && _isMobileMenuOpen)
              _buildMobileMenuOverlay(),
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
                PopupMenuButton<String>(
                  offset: const Offset(0, 40),
                  color: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5),
                  ),
                  tooltip: 'Features submenu',
                  onSelected: (val) {
                    _scrollToSection(_featuresKey);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Features',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          color: const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        color: Color(0xFF94A3B8),
                        size: 16,
                      ),
                    ],
                  ),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: '4fa',
                      child: Row(
                        children: [
                          Icon(Icons.lock_open, color: const Color(0xFF8B5CF6), size: 18),
                          const SizedBox(width: 12),
                          Text(
                            '4-Factor Biometrics',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'sss',
                      child: Row(
                        children: [
                          Icon(Icons.dashboard_customize_outlined, color: const Color(0xFF10B981), size: 18),
                          const SizedBox(width: 12),
                          Text(
                            'Shamir\'s Secret Sharing',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'ransomware',
                      child: Row(
                        children: [
                          Icon(Icons.shield_sharp, color: const Color(0xFF3B82F6), size: 18),
                          const SizedBox(width: 12),
                          Text(
                            'Ransomware Monitor',
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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
              icon: Icon(
                _isMobileMenuOpen ? Icons.close : Icons.menu,
                color: Colors.white,
              ),
              onPressed: () {
                setState(() {
                  _isMobileMenuOpen = !_isMobileMenuOpen;
                });
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
              'Mathematically uncrackable absolute Zero-Trust file security. If you use AMPCrypt, no one can crack your data without you. Interlocking 4-Factor Biometrics, Shamir\'s Secret Sharing, and local ransomware detection with zero cloud exposures.',
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
    final bool allUnlocked = _mockArgon2 && _mockFace && _mockFingerprint && _mockVoice;
    
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
            color: (allUnlocked ? const Color(0xFF10B981) : const Color(0xFF8B5CF6)).withOpacity(0.06),
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
                padding: EdgeInsets.all(isMobile ? 20 : 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Status Info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
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
                                  fontSize: isMobile ? 16 : 20,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Status Badge
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: allUnlocked
                                ? const Color(0xFF10B981).withOpacity(0.15)
                                : const Color(0xFFEF4444).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: allUnlocked
                                  ? const Color(0xFF10B981).withOpacity(0.5)
                                  : const Color(0xFFEF4444).withOpacity(0.25),
                              width: allUnlocked ? 1.5 : 1.0,
                            ),
                            boxShadow: allUnlocked
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withOpacity(0.2),
                                      blurRadius: 12,
                                    )
                                  ]
                                : [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                allUnlocked ? Icons.lock_open : Icons.lock_outline,
                                color: allUnlocked ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                size: 14,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                allUnlocked ? 'STATUS: UNLOCKED' : 'STATUS: SECURE & LOCKED',
                                style: GoogleFonts.shareTechMono(
                                  color: allUnlocked ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Simulation Instruction Subtext
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        allUnlocked
                            ? '🎉 All factors verified! Cryptographic shares successfully reconstructed.'
                            : '⚡ Interactive Demo: Click the factor cards below to simulate SSS biometric interlocking.',
                        key: ValueKey(allUnlocked),
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: allUnlocked ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                          fontWeight: allUnlocked ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Grid of 4 boxes (2x2 on Desktop, 1x4 on Mobile)
                    GridView.count(
                      crossAxisCount: isMobile ? 1 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: isMobile ? 3.0 : 3.4,
                      children: _buildMockFactorToggles(),
                    ),
                    
                    if (allUnlocked) ...[
                      const SizedBox(height: 24),
                      Center(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 400),
                          builder: (context, value, child) {
                            return Opacity(
                              opacity: value,
                              child: Transform.scale(
                                scale: 0.95 + (value * 0.05),
                                child: child,
                              ),
                            );
                          },
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pushNamed(context, '/vault');
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 8,
                              shadowColor: const Color(0xFF10B981).withOpacity(0.3),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.vpn_key),
                                const SizedBox(width: 10),
                                Text(
                                  'ENTER SECURE WEB VAULT NOW',
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Zero-Trust Pledge Banner Callout
  Widget _buildZeroTrustPromiseBanner(bool isMobile) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 64),
      padding: EdgeInsets.all(isMobile ? 24 : 40),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFF10B981).withOpacity(0.18),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF10B981).withOpacity(0.15),
                ),
                child: const Icon(
                  Icons.lock_person_outlined,
                  color: Color(0xFF10B981),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'THE ZERO-TRUST PLEDGE',
                style: GoogleFonts.shareTechMono(
                  fontSize: 14,
                  letterSpacing: 2.0,
                  color: const Color(0xFF10B981),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'If you use AMPCrypt, no one can crack your data without you.',
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 22 : 28,
              color: Colors.white,
              fontWeight: FontWeight.w900,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'By interlocking your high-entropy password (Argon2id) with local-only face, fingerprint, and voice signatures using mathematical Shamir\'s Secret Sharing thresholds, your master encryption key does not exist anywhere in storage. It is reconstructed dynamically in RAM only when you verify all factors. With zero cloud dependencies, zero external trust, and offline-first execution, it is cryptographically impossible for hackers, developers, or hostiles to access or crack your vault without your explicit, physical authorization.',
            style: GoogleFonts.outfit(
              fontSize: isMobile ? 14 : 16,
              color: const Color(0xFF94A3B8),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMockFactorToggles() {
    return [
      InteractiveFactorCard(
        title: 'Argon2id Hash Share',
        subtitle: 'Password Derivation',
        icon: Icons.key_outlined,
        color: const Color(0xFF8B5CF6),
        isValid: _mockArgon2,
        onTap: () {
          setState(() {
            _mockArgon2 = !_mockArgon2;
          });
        },
      ),
      InteractiveFactorCard(
        title: 'MobileFaceNet Share',
        subtitle: 'Face Biometrics (TFLite)',
        icon: Icons.face_outlined,
        color: const Color(0xFF10B981),
        isValid: _mockFace,
        onTap: () {
          setState(() {
            _mockFace = !_mockFace;
          });
        },
      ),
      InteractiveFactorCard(
        title: 'Hardware Enclave Share',
        subtitle: 'Device Fingerprint scan',
        icon: Icons.fingerprint,
        color: const Color(0xFFFF9E0B),
        isValid: _mockFingerprint,
        onTap: () {
          setState(() {
            _mockFingerprint = !_mockFingerprint;
          });
        },
      ),
      InteractiveFactorCard(
        title: 'Speaker Voice Share',
        subtitle: 'Conformer voice encoder',
        icon: Icons.record_voice_over_outlined,
        color: const Color(0xFF3B82F6),
        isValid: _mockVoice,
        onTap: () {
          setState(() {
            _mockVoice = !_mockVoice;
          });
        },
      ),
    ];
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
                badge: 'Apple/Intel Universal',
                downloadName: 'macOS Bundle (.dmg)',
                onTap: () {},
              ),
              _buildDownloadTile(
                platform: 'Linux Systems',
                icon: Icons.terminal,
                badge: 'x64 AppImage',
                downloadName: 'Linux AppImage (.AppImage)',
                onTap: () {},
              ),
              _buildDownloadTile(
                platform: 'Android Mobile',
                icon: Icons.phone_android,
                badge: 'ARM64 APK',
                downloadName: 'Android APK (.apk)',
                onTap: () {},
              ),
              _buildDownloadTile(
                platform: 'iOS Mobile',
                icon: Icons.phone_iphone,
                badge: 'TestFlight',
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
              const SizedBox(width: 8),
              Flexible(
                child: Container(
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
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
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
                  Flexible(
                    child: Text(
                      downloadName,
                      style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
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

  // Mobile Menu Overlay Widget
  Widget _buildMobileMenuOverlay() {
    return Positioned(
      top: 80, // just below the navbar
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: const Color(0xFF070B19).withOpacity(0.92),
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Text(
                  'NAVIGATION',
                  style: GoogleFonts.shareTechMono(
                    color: const Color(0xFF8B5CF6),
                    fontSize: 12,
                    letterSpacing: 2.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Menu Items
                _buildMobileMenuItem('Features', Icons.extension_outlined, () {
                  setState(() => _isMobileMenuOpen = false);
                  _scrollToSection(_featuresKey);
                }),
                // Mobile Submenu items under Features
                Padding(
                  padding: const EdgeInsets.only(left: 36, top: 4, bottom: 8),
                  child: Column(
                    children: [
                      _buildMobileSubmenuItem('4FA Biometrics', const Color(0xFF8B5CF6), () {
                        setState(() => _isMobileMenuOpen = false);
                        _scrollToSection(_featuresKey);
                      }),
                      _buildMobileSubmenuItem('Shamir\'s SSS', const Color(0xFF10B981), () {
                        setState(() => _isMobileMenuOpen = false);
                        _scrollToSection(_featuresKey);
                      }),
                      _buildMobileSubmenuItem('Ransomware Shield', const Color(0xFF3B82F6), () {
                        setState(() => _isMobileMenuOpen = false);
                        _scrollToSection(_featuresKey);
                      }),
                    ],
                  ),
                ),
                
                _buildMobileMenuItem('Downloads', Icons.download_outlined, () {
                  setState(() => _isMobileMenuOpen = false);
                  _scrollToSection(_downloadsKey);
                }),
                _buildMobileMenuItem('GitHub Repository', Icons.code_outlined, () {
                  setState(() => _isMobileMenuOpen = false);
                }),
                
                const Spacer(),
                
                // Launch button at the bottom of the mobile drawer
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() => _isMobileMenuOpen = false);
                      Navigator.pushNamed(context, '/vault');
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 8,
                      shadowColor: const Color(0xFF8B5CF6).withOpacity(0.3),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.vpn_key_outlined, size: 20),
                        const SizedBox(width: 12),
                        Text(
                          'LAUNCH WEB CONSOLE',
                          style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileMenuItem(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF94A3B8), size: 20),
            const SizedBox(width: 16),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right, color: Color(0xFF475569), size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSubmenuItem(String label, Color dotColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
            ),
            const SizedBox(width: 16),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 14,
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom Interactive Factor Card with Hover and State Animations
class InteractiveFactorCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isValid;
  final VoidCallback onTap;

  const InteractiveFactorCard({
    key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isValid,
    required this.onTap,
  }) : super(key: key);

  @override
  State<InteractiveFactorCard> createState() => _InteractiveFactorCardState();
}

class _InteractiveFactorCardState extends State<InteractiveFactorCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final borderGlowColor = widget.isValid 
        ? widget.color.withOpacity(_isHovered ? 0.6 : 0.3)
        : (_isHovered ? Colors.white.withOpacity(0.15) : Colors.white.withOpacity(0.05));

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.isValid 
                  ? widget.color.withOpacity(0.08)
                  : const Color(0xFF1E293B).withOpacity(0.4),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: borderGlowColor,
                width: widget.isValid ? 1.5 : 1.0,
              ),
              boxShadow: _isHovered || widget.isValid
                  ? [
                      BoxShadow(
                        color: widget.isValid 
                            ? widget.color.withOpacity(0.15)
                            : Colors.white.withOpacity(0.02),
                        blurRadius: _isHovered ? 16 : 8,
                        spreadRadius: _isHovered ? 2 : 0,
                      )
                    ]
                  : [],
            ),
            child: Row(
              children: [
                // Icon wrapper with pulse decoration
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isValid 
                        ? widget.color.withOpacity(0.2)
                        : Colors.white.withOpacity(0.05),
                    boxShadow: widget.isValid
                        ? [
                            BoxShadow(
                              color: widget.color.withOpacity(0.3),
                              blurRadius: 8,
                            )
                          ]
                        : [],
                  ),
                  child: Icon(
                    widget.icon, 
                    color: widget.isValid ? widget.color : const Color(0xFF64748B), 
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                // Indicator status check / lock
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isValid 
                        ? const Color(0xFF10B981).withOpacity(0.15)
                        : Colors.white.withOpacity(0.03),
                  ),
                  child: Icon(
                    widget.isValid ? Icons.check : Icons.lock_outline,
                    color: widget.isValid ? const Color(0xFF10B981) : const Color(0xFF475569),
                    size: 16,
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

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import '../../core/app_info.dart';
import '../../core/theme/app_colors.dart';

/// Redesigned Ice-Style Desktop & Mobile Splash Screen with adaptive Theme support.
/// Features a horizontal dual-panel layout on desktop screens with system diagnostic
/// milestone cards, frosted glassmorphism, glacial aurora ambient orbs, and particle dust.
class SplashView extends StatefulWidget {
  final bool isLoading;
  final String loadingText;
  final bool showProgress;
  final int maxDisplayTime;

  const SplashView({
    super.key,
    this.isLoading = true,
    this.loadingText = 'Loading RentManager...',
    this.showProgress = false,
    this.maxDisplayTime = 8000,
  });

  @override
  State<SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<SplashView>
    with TickerProviderStateMixin {
  late final AnimationController _ambientController;
  late final AnimationController _entranceController;
  late final AnimationController _sparkleController;

  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _slideAnimation;

  // Pre-generate static seed values for ice crystal particles
  late final List<_IceParticle> _particles;

  @override
  void initState() {
    super.initState();

    // 1. Ambient breathing / particle drift controller (slow continuous loop)
    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    // 2. Staggered entrance animation for logo, text, and loading bar
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    );

    _slideAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic),
    );

    // 3. Subtle periodic sparkle on the ice badge
    _sparkleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    // 4. Generate 28 organic ice crystal particles
    final random = math.Random(42);
    _particles = List.generate(28, (index) {
      return _IceParticle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: 1.5 + random.nextDouble() * 3.5,
        speed: 0.15 + random.nextDouble() * 0.45,
        swayAmplitude: 0.02 + random.nextDouble() * 0.05,
        swayPhase: random.nextDouble() * 2 * math.pi,
        opacity: 0.25 + random.nextDouble() * 0.55,
        isHexagon: index % 3 == 0,
      );
    });

    _entranceController.forward();
  }

  @override
  void dispose() {
    _ambientController.dispose();
    _entranceController.dispose();
    _sparkleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determine theme mode dynamically based on context brightness
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-driven Ice Palette
    final bgGradientColors = isDark
        ? const [
            Color(0xFF041017),
            Color(0xFF081C26),
            Color(0xFF0B2533),
            Color(0xFF06151E),
          ]
        : const [
            Color(0xFFF3F9FD),
            Color(0xFFE4F1FA),
            Color(0xFFD6EAF8),
            Color(0xFFEBF5FB),
          ];

    final orb1Color = isDark
        ? const Color(0xFF0284C7).withValues(alpha: 0.35)
        : const Color(0xFF7DD3FC).withValues(alpha: 0.45);

    final orb2Color = isDark
        ? const Color(0xFF0D9488).withValues(alpha: 0.28)
        : const Color(0xFF99F6E4).withValues(alpha: 0.40);

    final orb3Color = isDark
        ? const Color(0xFF38BDF8).withValues(alpha: 0.22)
        : const Color(0xFFBAE6FD).withValues(alpha: 0.50);

    final glassFillColor = isDark
        ? const Color(0xFF0D2533).withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.75);

    final glassBorderColorTop = isDark
        ? Colors.white.withValues(alpha: 0.38)
        : Colors.white.withValues(alpha: 0.95);

    final glassBorderColorBottom = isDark
        ? const Color(0xFF38BDF8).withValues(alpha: 0.15)
        : const Color(0xFF0284C7).withValues(alpha: 0.20);

    final titleGradient = isDark
        ? const [
            Color(0xFFFFFFFF),
            Color(0xFFE0F2FE),
            Color(0xFF7DD3FC),
          ]
        : const [
            Color(0xFF0A2540),
            Color(0xFF0369A1),
            Color(0xFF0284C7),
          ];

    final subtitleColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF475569);

    final badgeHaloColor = isDark
        ? const Color(0xFF38BDF8).withValues(alpha: 0.25)
        : const Color(0xFF0284C7).withValues(alpha: 0.15);

    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFCFE4F3);

    final progressGradient = isDark
        ? const [Color(0xFF38BDF8), Color(0xFF4ADE80)]
        : const [Color(0xFF0284C7), Color(0xFF10B981)];

    final statusTextColor = isDark
        ? const Color(0xFF7DD3FC)
        : const Color(0xFF0369A1);

    final versionTextColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    final particleTint = isDark
        ? const Color(0xFFBAE6FD)
        : const Color(0xFF0284C7);

    return Scaffold(
      body: Stack(
        children: [
          // 1. Deep Glacial Gradient Background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: bgGradientColors,
                  stops: const [0.0, 0.4, 0.75, 1.0],
                ),
              ),
            ),
          ),

          // 2. Animated Aurora Ambient Ice Orbs
          AnimatedBuilder(
            animation: _ambientController,
            builder: (context, _) {
              final t = _ambientController.value * 2 * math.pi;
              final sinT = math.sin(t);
              final cosT = math.cos(t);

              return Stack(
                children: [
                  // Top-left Glacial Orb
                  Positioned(
                    top: -60 + sinT * 25,
                    left: -40 + cosT * 20,
                    child: _buildBlurOrb(
                      size: 320,
                      color: orb1Color,
                    ),
                  ),
                  // Center-right Mint Ice Orb
                  Positioned(
                    top: MediaQuery.of(context).size.height * 0.35 + cosT * 30,
                    right: -70 + sinT * 25,
                    child: _buildBlurOrb(
                      size: 300,
                      color: orb2Color,
                    ),
                  ),
                  // Bottom-left Cyan Orb
                  Positioned(
                    bottom: -80 + sinT * 30,
                    left: 20 + cosT * 25,
                    child: _buildBlurOrb(
                      size: 340,
                      color: orb3Color,
                    ),
                  ),
                ],
              );
            },
          ),

          // 3. Floating Ice Crystal Dust & Hexagon Snowflakes
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ambientController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _IceParticlesPainter(
                    particles: _particles,
                    progress: _ambientController.value,
                    particleColor: particleTint,
                  ),
                );
              },
            ),
          ),

          // 4. Responsive Master Slate (Desktop Dual-Panel or Mobile Stack)
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 840) {
                  return _buildDesktopLayout(
                    context: context,
                    isDark: isDark,
                    glassFillColor: glassFillColor,
                    glassBorderColorTop: glassBorderColorTop,
                    glassBorderColorBottom: glassBorderColorBottom,
                    titleGradient: titleGradient,
                    subtitleColor: subtitleColor,
                    badgeHaloColor: badgeHaloColor,
                    trackColor: trackColor,
                    progressGradient: progressGradient,
                    statusTextColor: statusTextColor,
                    versionTextColor: versionTextColor,
                  );
                }
                return _buildMobileLayout(
                  context: context,
                  isDark: isDark,
                  glassFillColor: glassFillColor,
                  glassBorderColorTop: glassBorderColorTop,
                  glassBorderColorBottom: glassBorderColorBottom,
                  titleGradient: titleGradient,
                  subtitleColor: subtitleColor,
                  badgeHaloColor: badgeHaloColor,
                  trackColor: trackColor,
                  progressGradient: progressGradient,
                  statusTextColor: statusTextColor,
                  versionTextColor: versionTextColor,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // DESKTOP WIDESCREEN DUAL-PANEL LAYOUT (WIDTH >= 840px)
  // ===========================================================================

  Widget _buildDesktopLayout({
    required BuildContext context,
    required bool isDark,
    required Color glassFillColor,
    required Color glassBorderColorTop,
    required Color glassBorderColorBottom,
    required List<Color> titleGradient,
    required Color subtitleColor,
    required Color badgeHaloColor,
    required Color trackColor,
    required List<Color> progressGradient,
    required Color statusTextColor,
    required Color versionTextColor,
  }) {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 820),
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.45)
                      : const Color(0xFF0369A1).withValues(alpha: 0.12),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: badgeHaloColor,
                  blurRadius: 48,
                  spreadRadius: -10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: glassFillColor,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      width: 1.2,
                      color: Colors.transparent,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        glassBorderColorTop.withValues(alpha: 0.45),
                        glassBorderColorBottom.withValues(alpha: 0.15),
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      // Left Hero Showcase Panel
                      Container(
                        width: 330,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 24),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF07151D).withValues(alpha: 0.45)
                              : const Color(0xFFE0F2FE).withValues(alpha: 0.35),
                          border: Border(
                            right: BorderSide(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : const Color(0x14000000),
                            ),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Frost Edition Pill
                            _buildFrostPill(isDark: isDark),

                            const SizedBox(height: 18),

                            // Animated Ice Emblem
                            _buildIceEmblem(
                              isDark: isDark,
                              haloColor: badgeHaloColor,
                            ),

                            const SizedBox(height: 16),

                            // App Title with Ice Shader
                            ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) => LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: titleGradient,
                              ).createShader(bounds),
                              child: const Text(
                                'RentManager',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ),

                            const SizedBox(height: 6),

                            // Tagline
                            Text(
                              'Property Management Made Simple',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: subtitleColor,
                                letterSpacing: 0.3,
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Security tag
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Ionicons.shieldCheckmarkOutline,
                                  size: 13,
                                  color: versionTextColor,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Encrypted & Protected • v$kAppVersion',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: versionTextColor,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Right Diagnostics & System Activity Panel
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const ClampingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 26, vertical: 22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Top Initialization Header
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'DESKTOP WORKSPACE INITIALIZATION',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.1,
                                        color: statusTextColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _buildPulseBadge(isDark),
                                ],
                              ),

                              const SizedBox(height: 14),

                              // System Milestone Cards
                              _buildMilestoneTile(
                                icon: Ionicons.serverOutline,
                                title: 'Local-First Encrypted Database',
                                subtitle: 'SQLite storage & cache verified',
                                isComplete: true,
                                isDark: isDark,
                              ),
                              _buildMilestoneTile(
                                icon: Ionicons.businessOutline,
                                title: 'Property & Lease Engine',
                                subtitle: 'Tenants, units & records active',
                                isComplete: true,
                                isDark: isDark,
                              ),
                              _buildMilestoneTile(
                                icon: Ionicons.hardwareChipOutline,
                                title: 'Metal Graphics Pipeline',
                                subtitle: 'Impeller accelerated rendering initialized',
                                isComplete: false,
                                isDark: isDark,
                              ),

                              const SizedBox(height: 14),

                              // Frosted Progress Bar
                              _buildFrostedProgressBar(
                                trackColor: trackColor,
                                progressGradient: progressGradient,
                              ),

                              const SizedBox(height: 12),

                              // Loading Status Row
                              _buildStatusRow(
                                statusText: widget.loadingText,
                                textColor: statusTextColor,
                                isDark: isDark,
                              ),

                              const SizedBox(height: 14),

                              // Bottom System Badges
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  _buildSysTag('Native Desktop', Ionicons.desktopOutline, isDark),
                                  _buildSysTag('Hardware Accelerated', Ionicons.flashOutline, isDark),
                                  _buildSysTag('Offline Privacy', Ionicons.lockClosedOutline, isDark),
                                ],
                              ),
                            ],
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
    );
  }

  // ===========================================================================
  // MOBILE VERTICAL SLATE LAYOUT (WIDTH < 840px)
  // ===========================================================================

  Widget _buildMobileLayout({
    required BuildContext context,
    required bool isDark,
    required Color glassFillColor,
    required Color glassBorderColorTop,
    required Color glassBorderColorBottom,
    required List<Color> titleGradient,
    required Color subtitleColor,
    required Color badgeHaloColor,
    required Color trackColor,
    required List<Color> progressGradient,
    required Color statusTextColor,
    required Color versionTextColor,
  }) {
    return Center(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A. Animated Ice Emblem
            ScaleTransition(
              scale: _scaleAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: _buildIceEmblem(
                  isDark: isDark,
                  haloColor: badgeHaloColor,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // B. Frosted Glass Slate Card
            FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(_slideAnimation),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 420),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.35)
                            : const Color(0xFF0369A1).withValues(alpha: 0.08),
                        blurRadius: 30,
                        offset: const Offset(0, 14),
                      ),
                      BoxShadow(
                        color: badgeHaloColor,
                        blurRadius: 40,
                        spreadRadius: -10,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 26,
                          vertical: 30,
                        ),
                        decoration: BoxDecoration(
                          color: glassFillColor,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            width: 1.5,
                            color: Colors.transparent,
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              glassBorderColorTop.withValues(alpha: 0.45),
                              glassBorderColorBottom.withValues(alpha: 0.15),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Frost Edition Pill
                            _buildFrostPill(isDark: isDark),

                            const SizedBox(height: 18),

                            // App Title with Ice Shader
                            ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (bounds) => LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: titleGradient,
                              ).createShader(bounds),
                              child: const Text(
                                'RentManager',
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Tagline
                            Text(
                              'Property Management Made Simple',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: subtitleColor,
                                letterSpacing: 0.4,
                              ),
                            ),

                            const SizedBox(height: 30),

                            // C. Frosted Progress Channel
                            _buildFrostedProgressBar(
                              trackColor: trackColor,
                              progressGradient: progressGradient,
                            ),

                            const SizedBox(height: 18),

                            // Loading Status Row
                            _buildStatusRow(
                              statusText: widget.loadingText,
                              textColor: statusTextColor,
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 36),

            // D. Bottom Security & Version Badge
            FadeTransition(
              opacity: _fadeAnimation,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Ionicons.shieldCheckmarkOutline,
                    size: 14,
                    color: versionTextColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Encrypted & Protected • v$kAppVersion',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: versionTextColor,
                      letterSpacing: 0.3,
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

  // ===========================================================================
  // SUB-WIDGET BUILDERS & HELPERS
  // ===========================================================================

  Widget _buildMilestoneTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isComplete,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0x14000000),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isComplete
                  ? const Color(0xFF10B981).withValues(alpha: 0.16)
                  : const Color(0xFF38BDF8).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 15,
              color: isComplete
                  ? const Color(0xFF10B981)
                  : const Color(0xFF38BDF8),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.heading,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          if (isComplete)
            const Icon(Ionicons.checkmarkCircle,
                size: 15, color: Color(0xFF10B981))
          else
            RotationTransition(
              turns: _ambientController,
              child: const Icon(Ionicons.syncOutline,
                  size: 14, color: Color(0xFF38BDF8)),
            ),
        ],
      ),
    );
  }

  Widget _buildPulseBadge(bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Color(0xFF10B981),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0xFF10B981),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'READY',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
          ),
        ),
      ],
    );
  }

  Widget _buildSysTag(String label, IconData icon, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFF0284C7).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : const Color(0xFF0284C7).withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 11,
              color: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0369A1)),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1),
            ),
          ),
        ],
      ),
    );
  }

  /// Large ambient blurred light orb for the background
  Widget _buildBlurOrb({required double size, required Color color}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color,
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.2, 1.0],
        ),
      ),
    );
  }

  /// Crystalline Frosted Ice Badge with Home icon and glint effect
  Widget _buildIceEmblem({required bool isDark, required Color haloColor}) {
    return AnimatedBuilder(
      animation: _sparkleController,
      builder: (context, _) {
        final sparkle = _sparkleController.value;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer breathing frost halo
            Container(
              width: 124,
              height: 124,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: haloColor.withValues(
                      alpha: haloColor.a * (0.8 + 0.4 * sparkle),
                    ),
                    blurRadius: 36 + 10 * sparkle,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),

            // Frosted Glass Hex-Squircle Tile
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          const Color(0xFF1E3A4C).withValues(alpha: 0.65),
                          const Color(0xFF0F2633).withValues(alpha: 0.85),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.90),
                          const Color(0xFFE0F2FE).withValues(alpha: 0.75),
                        ],
                ),
                border: Border.all(
                  width: 2,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.35 + 0.2 * sparkle)
                      : Colors.white,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.4)
                        : const Color(0xFF0284C7).withValues(alpha: 0.15),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Diagonal specular ice reflection highlight
                      Positioned(
                        top: -20,
                        left: -20,
                        width: 70,
                        height: 70,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Colors.white.withValues(alpha: isDark ? 0.4 : 0.7),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Center Icon with Ice/Mint Gradient
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: isDark
                              ? const [
                                  Color(0xFF67E8F9),
                                  Color(0xFF38BDF8),
                                  Color(0xFF4CAF50),
                                ]
                              : const [
                                  Color(0xFF0284C7),
                                  Color(0xFF0EA5E9),
                                  Color(0xFF2E7D32),
                                ],
                        ).createShader(bounds),
                        child: const Icon(
                          Ionicons.business,
                          size: 52,
                        ),
                      ),

                      // Corner glint / sparkle star
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Transform.rotate(
                          angle: sparkle * math.pi,
                          child: Icon(
                            Ionicons.sparkles,
                            size: 14,
                            color: Colors.white.withValues(
                              alpha: 0.4 + 0.6 * sparkle,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Elegant top pill chip with ice crystal indicator
  Widget _buildFrostPill({required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.07)
            : const Color(0xFF0284C7).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.15)
              : const Color(0xFF0284C7).withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Ionicons.snowOutline,
            size: 13,
            color: isDark ? const Color(0xFF7DD3FC) : const Color(0xFF0284C7),
          ),
          const SizedBox(width: 6),
          Text(
            'PROPERTY SUITE',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: isDark ? const Color(0xFFBAE6FD) : const Color(0xFF0369A1),
            ),
          ),
        ],
      ),
    );
  }

  /// Sleek frosted track housing the LinearProgressIndicator
  Widget _buildFrostedProgressBar({
    required Color trackColor,
    required List<Color> progressGradient,
  }) {
    return Container(
      height: 6,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: trackColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(progressGradient[0]),
        ),
      ),
    );
  }

  /// Loading status row with rotating ice-sync spinner and label
  Widget _buildStatusRow({
    required String statusText,
    required Color textColor,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        RotationTransition(
          turns: _ambientController,
          child: Icon(
            Ionicons.syncOutline,
            size: 15,
            color: textColor,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            statusText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Helper model for animated ice particles
class _IceParticle {
  final double x;
  final double y;
  final double size;
  final double speed;
  final double swayAmplitude;
  final double swayPhase;
  final double opacity;
  final bool isHexagon;

  const _IceParticle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.swayAmplitude,
    required this.swayPhase,
    required this.opacity,
    required this.isHexagon,
  });
}

/// Custom painter for ice crystal dust and subtle floating ice shards
class _IceParticlesPainter extends CustomPainter {
  final List<_IceParticle> particles;
  final double progress; // 0.0 to 1.0
  final Color particleColor;

  _IceParticlesPainter({
    required this.particles,
    required this.progress,
    required this.particleColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      // Calculate continuous drifting vertical position (moving upwards)
      final currentY = (p.y - (progress * p.speed)) % 1.0;
      final posY = currentY * size.height;

      // Add gentle horizontal oscillation (sway)
      final sway = math.sin((progress * 2 * math.pi) + p.swayPhase) * p.swayAmplitude;
      final posX = ((p.x + sway) % 1.0) * size.width;

      paint.color = particleColor.withValues(alpha: p.opacity);

      if (p.isHexagon) {
        // Draw delicate hexagonal crystal / diamond
        _drawDiamond(canvas, Offset(posX, posY), p.size, paint);
      } else {
        // Draw soft circular frost particle
        canvas.drawCircle(Offset(posX, posY), p.size * 0.5, paint);
      }
    }
  }

  void _drawDiamond(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.7, center.dy)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * 0.7, center.dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _IceParticlesPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.particleColor != particleColor;
  }
}
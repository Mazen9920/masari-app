import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _logoController;
  late AnimationController _taglineController;
  late AnimationController _badgeController;
  late AnimationController _pulseController;
  late AnimationController _progressController;
  late AnimationController _floatController;

  // Animations
  late Animation<double> _logoFade;
  late Animation<Offset> _logoSlide;
  late Animation<double> _taglineFade;
  late Animation<double> _badgeFade;
  late Animation<double> _pulseAnim;
  late Animation<double> _progressAnim;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();

    // Set status bar to light (white icons on dark background)
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

    // ─── Logo animation (fade in + slide up) ───
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _logoFade = CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOut,
    );
    _logoSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.easeOutCubic,
    ));

    // ─── Tagline animation (delayed fade in) ───
    _taglineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _taglineFade = CurvedAnimation(
      parent: _taglineController,
      curve: Curves.easeOut,
    );

    // ─── Badge animation (delayed fade in) ───
    _badgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _badgeFade = CurvedAnimation(
      parent: _badgeController,
      curve: Curves.easeOut,
    );

    // ─── Accent dot pulse (infinite) ───
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // ─── Progress bar ───
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _progressAnim = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOutCubic,
    );

    // ─── Floating animation for logo group ───
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _floatAnim = Tween<double>(begin: -3, end: 3).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    // ─── Sequence the animations ───
    _startAnimations();
  }

  Future<void> _startAnimations() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();
    _pulseController.repeat(reverse: true);
    _floatController.repeat(reverse: true);

    await Future.delayed(const Duration(milliseconds: 500));
    _taglineController.forward();
    _progressController.forward();

    await Future.delayed(const Duration(milliseconds: 400));
    _badgeController.forward();

    // Navigate to onboarding after splash completes
    await Future.delayed(const Duration(milliseconds: 2200));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const OnboardingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _taglineController.dispose();
    _badgeController.dispose();
    _pulseController.dispose();
    _progressController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: AppColors.splashGradient,
        ),
        child: Stack(
          children: [
            // ─── Background decorative blobs ───
            _buildBackgroundBlobs(),

            // ─── Main content ───
            SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),

                  // ─── Logo + Tagline (centered) ───
                  AnimatedBuilder(
                    animation: _floatAnim,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _floatAnim.value),
                        child: child,
                      );
                    },
                    child: _buildLogoSection(),
                  ),

                  const Spacer(flex: 2),

                  // ─── Powered by AI badge ───
                  _buildAIBadge(),

                  const SizedBox(height: 24),

                  // ─── Progress bar ───
                  _buildProgressBar(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundBlobs() {
    return Stack(
      children: [
        // Top-right blob
        Positioned(
          top: -80,
          right: -60,
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.secondaryBlue.withOpacity(0.15),
            ),
          ),
        ),
        // Bottom-left blob
        Positioned(
          bottom: -100,
          left: -80,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryNavy.withOpacity(0.3),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogoSection() {
    return SlideTransition(
      position: _logoSlide,
      child: FadeTransition(
        opacity: _logoFade,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Logo text with accent dot
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Masari',
                  style: AppTypography.displayLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(width: 4),
                // Pulsing accent dot
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: AnimatedBuilder(
                    animation: _pulseAnim,
                    builder: (context, child) {
                      return Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.accentOrange,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.accentOrange
                                  .withOpacity(_pulseAnim.value * 0.6),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Tagline
            FadeTransition(
              opacity: _taglineFade,
              child: Text(
                'Your Business, Simplified',
                style: AppTypography.bodyLarge.copyWith(
                  color: Colors.white.withOpacity(0.8),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIBadge() {
    return FadeTransition(
      opacity: _badgeFade,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: AppRadius.pillRadius,
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentOrange.withOpacity(0.1),
              blurRadius: 20,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 16,
              color: AppColors.accentOrange,
            ),
            const SizedBox(width: 8),
            Text(
              'POWERED BY AI',
              style: AppTypography.captionSmall.copyWith(
                color: Colors.white.withOpacity(0.9),
                letterSpacing: 2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 80),
      child: AnimatedBuilder(
        animation: _progressAnim,
        builder: (context, child) {
          return Container(
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              color: Colors.white.withOpacity(0.15),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _progressAnim.value,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: AppColors.accentOrange,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

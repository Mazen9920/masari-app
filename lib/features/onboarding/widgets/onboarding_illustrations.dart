import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';

// ═══════════════════════════════════════════════════════════
// ILLUSTRATION 1: Track Effortlessly
// A phone with dashboard + floating income card
// ═══════════════════════════════════════════════════════════

class TrackIllustration extends StatefulWidget {
  const TrackIllustration({super.key});

  @override
  State<TrackIllustration> createState() => _TrackIllustrationState();
}

class _TrackIllustrationState extends State<TrackIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 340,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background glow
          Positioned.fill(
            child: Center(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accentOrange.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Phone mockup with dashboard
          _buildPhoneMockup(),

          // Floating income card (tilted, top-right)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final offset = math.sin(_controller.value * math.pi) * 4;
              return Positioned(
                top: 30,
                right: 20,
                child: Transform.translate(
                  offset: Offset(0, offset),
                  child: Transform.rotate(
                    angle: -0.08,
                    child: child,
                  ),
                ),
              );
            },
            child: _buildFloatingIncomeCard(),
          ),

          // Floating expense badge (bottom-left)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final offset = math.cos(_controller.value * math.pi) * 3;
              return Positioned(
                bottom: 50,
                left: 24,
                child: Transform.translate(
                  offset: Offset(0, offset),
                  child: child,
                ),
              );
            },
            child: _buildFloatingExpenseBadge(),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneMockup() {
    return Container(
      width: 180,
      height: 300,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.borderLight, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Status bar dot
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            // Mini greeting
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 80,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Revenue card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: AppColors.splashGradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 40, height: 4, color: Colors.white24),
                  const SizedBox(height: 6),
                  Text(
                    'EGP 45,200',
                    style: AppTypography.labelMedium.copyWith(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Mini bar chart
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _miniBar(0.4, AppColors.secondaryBlue.withOpacity(0.4)),
                _miniBar(0.6, AppColors.secondaryBlue.withOpacity(0.5)),
                _miniBar(0.45, AppColors.secondaryBlue.withOpacity(0.4)),
                _miniBar(0.7, AppColors.secondaryBlue.withOpacity(0.6)),
                _miniBar(0.55, AppColors.secondaryBlue.withOpacity(0.5)),
                _miniBar(0.85, AppColors.secondaryBlue),
              ],
            ),
            const Spacer(),
            // Mini transactions
            ...[0.7, 0.5, 0.6].map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.textTertiary.withOpacity(0.3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 60 * w, height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _miniBar(double heightFactor, Color color) {
    return Container(
      width: 14,
      height: 60 * heightFactor,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildFloatingIncomeCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.arrow_upward_rounded,
              color: AppColors.success,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Income',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 0,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '+EGP 4,250',
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingExpenseBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentOrange,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Auto-categorized',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.check_circle, size: 14, color: AppColors.success),
        ],
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════
// ILLUSTRATION 2: AI Does the Hard Work
// Messy data → AI processing node → Clean organized data
// ═══════════════════════════════════════════════════════════

class AIInsightIllustration extends StatefulWidget {
  const AIInsightIllustration({super.key});

  @override
  State<AIInsightIllustration> createState() => _AIInsightIllustrationState();
}

class _AIInsightIllustrationState extends State<AIInsightIllustration>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 360,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Subtle dot grid pattern
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: CustomPaint(
                  painter: _DotGridPainter(
                    color: AppColors.accentOrange.withOpacity(0.04),
                  ),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  // Main visual: messy → AI → clean
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Messy data (left)
                        _buildMessyData(),

                        // Connecting dashed line
                        _buildConnector(isLeft: true),

                        // AI Processing node (center)
                        _buildAINode(),

                        // Connecting dashed line
                        _buildConnector(isLeft: false),

                        // Clean data (right)
                        _buildCleanData(),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // AI quote bubble
                  _buildQuoteBubble(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessyData() {
    return Opacity(
      opacity: 0.5,
      child: Transform.rotate(
        angle: -0.08,
        child: SizedBox(
          width: 65,
          height: 90,
          child: Column(
            children: [
              Expanded(
                child: CustomPaint(
                  size: const Size(65, 60),
                  painter: _MessyChartPainter(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Unsorted',
                style: AppTypography.captionSmall.copyWith(
                  fontSize: 8,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnector({required bool isLeft}) {
    return SizedBox(
      width: 24,
      child: CustomPaint(
        size: const Size(24, 2),
        painter: _DashedLinePainter(
          color: isLeft
              ? AppColors.textTertiary.withOpacity(0.3)
              : AppColors.accentOrange.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildAINode() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * 0.05);
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentOrange.withOpacity(0.35),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_awesome,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  Widget _buildCleanData() {
    return Transform.rotate(
      angle: 0.05,
      child: Container(
        width: 75,
        height: 100,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _cleanBar(0.35, AppColors.accentOrange.withOpacity(0.4)),
                  _cleanBar(0.6, AppColors.accentOrange.withOpacity(0.6)),
                  _cleanBar(0.45, AppColors.accentOrange.withOpacity(0.5)),
                  _cleanBar(0.85, AppColors.accentOrange),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 2,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
            // "Optimized" badge sits on the stack
          ],
        ),
      ),
    );
  }

  Widget _cleanBar(double factor, Color color) {
    return Container(
      width: 10,
      height: 50 * factor,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  Widget _buildQuoteBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.success,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              '"Your cash flow looks healthier this month."',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════
// ILLUSTRATION 3: Grow With Confidence
// Phone with chart + rocket + floating coins
// ═══════════════════════════════════════════════════════════

class GrowIllustration extends StatefulWidget {
  const GrowIllustration({super.key});

  @override
  State<GrowIllustration> createState() => _GrowIllustrationState();
}

class _GrowIllustrationState extends State<GrowIllustration>
    with TickerProviderStateMixin {
  late AnimationController _floatController;
  late AnimationController _coin1Controller;
  late AnimationController _coin2Controller;
  late AnimationController _coin3Controller;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _coin1Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _coin2Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat(reverse: true);

    _coin3Controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    _coin1Controller.dispose();
    _coin2Controller.dispose();
    _coin3Controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 360,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background radial glow
          Center(
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.accentOrange.withOpacity(0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Phone with growth chart
          _buildPhoneWithChart(),

          // Rocket
          AnimatedBuilder(
            animation: _floatController,
            builder: (context, child) {
              final y = math.sin(_floatController.value * math.pi) * 6;
              return Positioned(
                top: 20 + y,
                child: child!,
              );
            },
            child: _buildRocket(),
          ),

          // Floating coins
          _buildCoin(_coin1Controller, 60, 50, 38),
          _buildCoin(_coin2Controller, null, 80, 32, right: 40),
          _buildCoin(_coin3Controller, 30, null, 26, right: 70),
        ],
      ),
    );
  }

  Widget _buildPhoneWithChart() {
    return Container(
      width: 170,
      height: 270,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Notch
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Trending icon
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.trending_up_rounded,
                color: AppColors.accentOrange,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),

            // Skeleton text lines
            Container(
              width: 100, height: 5,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 70, height: 5,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),

            // Growth chart bars
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _growthBar(0.25, 0.3),
                  _growthBar(0.4, 0.5),
                  _growthBar(0.35, 0.4),
                  _growthBar(0.55, 0.7),
                  _growthBar(0.75, 1.0),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _growthBar(double factor, double opacity) {
    final isLast = opacity == 1.0;
    return Container(
      width: 16,
      height: 80 * factor,
      decoration: BoxDecoration(
        color: AppColors.accentOrange.withOpacity(opacity),
        borderRadius: BorderRadius.circular(5),
        boxShadow: isLast ? [
          BoxShadow(
            color: AppColors.accentOrange.withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
    );
  }

  Widget _buildRocket() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rocket emoji (universal, no external dependencies)
        const Text('🚀', style: TextStyle(fontSize: 48)),
        // Trail
        Container(
          width: 3,
          height: 20,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.accentOrange.withOpacity(0.6),
                AppColors.accentOrange.withOpacity(0),
              ],
            ),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  Widget _buildCoin(
    AnimationController controller,
    double? top,
    double? bottom,
    double size, {
    double? left,
    double? right,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final y = math.sin(controller.value * math.pi) * 8;
        return Positioned(
          top: top != null ? top + y : null,
          bottom: bottom != null ? bottom - y : null,
          left: left,
          right: right,
          child: child!,
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          ),
          border: Border.all(
            color: const Color(0xFFE6A817),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFFD700).withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            'E£',
            style: TextStyle(
              color: const Color(0xFF8B6914),
              fontWeight: FontWeight.w800,
              fontSize: size * 0.3,
            ),
          ),
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════
// CUSTOM PAINTERS
// ═══════════════════════════════════════════════════════════

class _DotGridPainter extends CustomPainter {
  final Color color;
  _DotGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MessyChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textTertiary.withOpacity(0.4)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height * 0.8);
    path.lineTo(size.width * 0.15, size.height * 0.3);
    path.lineTo(size.width * 0.35, size.height * 0.7);
    path.lineTo(size.width * 0.55, size.height * 0.2);
    path.lineTo(size.width * 0.75, size.height * 0.6);
    path.lineTo(size.width, size.height * 0.1);

    canvas.drawPath(path, paint);

    // Red dots for "errors"
    final dotPaint = Paint()..color = AppColors.danger.withOpacity(0.5);
    canvas.drawCircle(Offset(size.width * 0.2, size.height * 0.2), 2, dotPaint);
    canvas.drawCircle(Offset(size.width * 0.7, size.height * 0.5), 2, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    const dashWidth = 4.0;
    const dashGap = 3.0;
    double x = 0;
    final y = size.height / 2;

    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../cash_flow/providers/scheduled_transactions_provider.dart';
import '../cash_flow/screens/scheduled_transactions_screen.dart';
import '../cash_flow/widgets/add_recurring_sheet.dart';
import '../../features/ai/ai_chat_screen.dart';

class CashFlowScreen extends ConsumerStatefulWidget {
  const CashFlowScreen({super.key});

  @override
  ConsumerState<CashFlowScreen> createState() => _CashFlowScreenState();
}

class _CashFlowScreenState extends ConsumerState<CashFlowScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider);
    final fmt = NumberFormat('#,##0', 'en');
    
    // Calculate Money In / Out for current month
    final now = _selectedDate;
    final monthTransactions = transactions.where((t) => 
      t.dateTime.year == now.year && t.dateTime.month == now.month
    ).toList();

    final double moneyIn = monthTransactions
        .where((t) => t.isIncome)
        .fold(0.0, (sum, t) => sum + t.amount.abs());

    final double moneyOut = monthTransactions
        .where((t) => !t.isIncome)
        .fold(0.0, (sum, t) => sum + t.amount.abs());

    // Mock Cash Balance (ideally this comes from Accounts provider)
    final double currentCashBalance = 67350.0; 

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: Stack(
        children: [
          SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 150), // Increase padding
            child: Column(
              children: [
                const SizedBox(height: 24),
                _buildDateSelector(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      _buildHeroCard(currentCashBalance, fmt),
                      const SizedBox(height: 16),
                      _buildAlertBanner(),
                      const SizedBox(height: 16),
                      _buildAIForecastCard(),
                      const SizedBox(height: 16),
                      _buildKPICards(moneyIn, moneyOut, fmt),
                      const SizedBox(height: 16),
                      _buildChartSection(),
                      const SizedBox(height: 16),
                      _buildComingUpSection(fmt),
                      const SizedBox(height: 24),
                      _buildShareButton(),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Manually Positioned FAB above Nav Bar
          // Assuming approx 80-90px for bottom nav + safe area
          Positioned(
            right: 16,
            bottom: 100, 
            child: _buildAskAIButton()
                .animate()
                .scale(duration: 400.ms, curve: Curves.easeOutBack),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  WIDGETS
  // ═══════════════════════════════════════════════════════



  Widget _buildDateSelector() {
    return Center(
      child: GestureDetector(
        onTap: () async {
          HapticFeedback.lightImpact();
          // Simple month picker or date picker
          final picked = await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: AppColors.primaryNavy,
                    onPrimary: Colors.white,
                    onSurface: AppColors.textPrimary,
                  ),
                ),
                child: child!,
              );
            },
          );
          if (picked != null) {
            setState(() => _selectedDate = picked);
          }
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(50),
            border: Border.all(color: AppColors.borderLight),
            boxShadow: [
               BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(_selectedDate),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(double balance, NumberFormat fmt) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Cash Balance',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'EGP ${fmt.format(balance)}',
                style: AppTypography.h1.copyWith(fontSize: 32, letterSpacing: -1),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDCFCE7), // Green-100
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.trending_up, size: 14, color: Color(0xFF15803D)),
                        const SizedBox(width: 4),
                        const Text(
                          '12%',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'vs last month',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          // Decorative Sparkline Background (Abstract SVG replacement)
          Positioned(
            right: -24,
            bottom: -24,
            child: Opacity(
              opacity: 0.5,
              child: SvgSparklinePlaceholder(width: 140, height: 80),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildAlertBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB), // Yellow-50
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFEF3C7)), // Yellow-100
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Low Cash Alert',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF92400E), // Yellow-800
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Potential dip expected in week 3 due to upcoming office rent payment.',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFFB45309).withValues(alpha: 0.8), // Yellow-700
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 100.ms);
  }

  Widget _buildAIForecastCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentOrange.withValues(alpha: 0.2), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Blur Glow Effect placeholder
          Positioned(
            right: -20,
            top: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.accentOrange.withValues(alpha: 0.2), blurRadius: 40)],
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accentOrange.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.auto_awesome, color: AppColors.accentOrange, size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'AI Forecast',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.5,
                    fontFamily: 'Inter',
                  ),
                  children: [
                    const TextSpan(text: 'Based on your pending invoices, you should reach a healthy '),
                    TextSpan(
                      text: 'EGP 52,000',
                      style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    const TextSpan(text: ' by the end of March.'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms);
  }

  Widget _buildKPICards(double moneyIn, double moneyOut, NumberFormat fmt) {
    return Row(
      children: [
        Expanded(
          child: _buildKPICard(
            label: 'Money In',
            amount: moneyIn,
            color: const Color(0xFF22C55E), // Green-500
            fmt: fmt,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKPICard(
            label: 'Money Out',
            amount: moneyOut,
            color: const Color(0xFFF87171), // Red-400
            fmt: fmt,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 300.ms);
  }

  Widget _buildKPICard({
    required String label,
    required double amount,
    required Color color,
    required NumberFormat fmt,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'EGP ${fmt.format(amount)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cash Movement',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildChartToggle('Wk', true),
                    _buildChartToggle('Mo', false),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Placeholder for the "Abstract Chart"
          SizedBox(
            height: 120,
            width: double.infinity,
            child: CustomPaint(
              painter: AbstractChartPainter(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Feb 1', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
              Text('Feb 8', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
              Text('Feb 15', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
              Text('Feb 22', style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 400.ms);
  }

  Widget _buildComingUpSection(NumberFormat fmt) {
    final scheduled = ref.watch(scheduledTransactionsProvider);
    // Sort by next due date
    final sorted = List.of(scheduled)..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
    // Take top 3
    final upcoming = sorted.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Coming Up',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ScheduledTransactionsScreen()),
                  );
                },
                child: Text(
                  'Manage',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (upcoming.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Column(
              children: [
                Icon(Icons.calendar_today_rounded, color: AppColors.textTertiary, size: 32),
                const SizedBox(height: 8),
                Text(
                  'No upcoming payments',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                ),
              ],
            ),
          )
        else
          ...upcoming.map((t) {
            // Calculate progress (mock logic for now: days passed / 30)
            // Real logic requires "last paid date"
            final daysUntil = t.nextDueDate.difference(DateTime.now()).inDays;
            final progress = (30 - daysUntil).clamp(0, 30) / 30.0;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildUpcomingItem(
                title: t.title,
                subtitle: 'Due ${DateFormat('MMM d').format(t.nextDueDate)}',
                amount: t.amount,
                color: t.isIncome ? Colors.green : Colors.orange,
                icon: t.isIncome ? Icons.monetization_on_rounded : Icons.payment_rounded,
                progress: t.isActive ? progress : 0, 
                progressColor: t.isIncome ? Colors.green : Colors.orange,
                fmt: fmt,
                isIncome: t.isIncome,
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => AddRecurringSheet(transaction: t),
                  );
                },
              ),
            );
          }),
      ],
    ).animate().fadeIn(duration: 400.ms, delay: 500.ms);
  }

  Widget _buildUpcomingItem({
    required String title,
    required String subtitle,
    required double amount,
    required Color color,
    required IconData icon,
    required double progress, // 0 to 1
    required Color progressColor,
    required NumberFormat fmt,
    bool isIncome = false,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
           BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isIncome ? '+' : ''} EGP ${fmt.format(amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isIncome ? const Color(0xFF16A34A) : AppColors.textPrimary, // Green-600 or Black
                ),
              ),
              if (!isIncome) ...[
                const SizedBox(height: 6),
                Container(
                  width: 60,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      decoration: BoxDecoration(
                        color: progressColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                 const SizedBox(height: 6),
                 Text(
                   'Invoiced',
                   style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
                 )
              ]
            ],
          ),
        ],
      ),
    ),
  );
}

  Widget _buildShareButton() {
    return TextButton.icon(
      onPressed: () {
        HapticFeedback.lightImpact();
      },
      icon: const Icon(Icons.ios_share_rounded, size: 18),
      label: const Text('Share Summary'),
      style: TextButton.styleFrom(
        foregroundColor: AppColors.textTertiary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildAskAIButton() {
    return FloatingActionButton.extended(
      onPressed: () {
        HapticFeedback.lightImpact();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AiChatScreen(contextType: 'CashFlow'),
          ),
        );
      },
      backgroundColor: AppColors.accentOrange,
      icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
      label: const Text('Ask AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      extendedPadding: const EdgeInsets.symmetric(horizontal: 16),
    );
  }
  Widget _buildChartToggle(String label, bool isActive) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        // Toggle logic here (state update)
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                  )
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  PAINTERS
// ═══════════════════════════════════════════════════════

class SvgSparklinePlaceholder extends StatelessWidget {
  final double width;
  final double height;

  const SvgSparklinePlaceholder({super.key, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF60A5FA).withValues(alpha: 0.2) // Blue-400
      ..strokeWidth = 2
      ..style = PaintingStyle.fill;
      
    final path = Path();
    path.moveTo(0, size.height * 0.8);
    path.quadraticBezierTo(size.width * 0.2, size.height * 0.7, size.width * 0.4, size.height * 0.6);
    path.quadraticBezierTo(size.width * 0.8, size.height * 0.4, size.width, size.height * 0.2);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class AbstractChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path();
    path.moveTo(0, h * 0.8);
    path.cubicTo(w * 0.2, h * 0.9, w * 0.2, h * 0.4, w * 0.4, h * 0.5);
    path.cubicTo(w * 0.6, h * 0.6, w * 0.6, h * 0.2, w * 0.8, h * 0.3);
    path.lineTo(w, h * 0.1);
    
    // Gradient fill
    final fillPath = Path.from(path);
    fillPath.lineTo(w, h);
    fillPath.lineTo(0, h);
    fillPath.close();

    final paintFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.accentOrange.withValues(alpha: 0.2),
          AppColors.accentOrange.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, paintFill);

    // Stroke
    final paintStroke = Paint()
      ..color = AppColors.accentOrange
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paintStroke);

    // Points
    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final pointBorder = Paint()
      ..color = AppColors.accentOrange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final p1 = Offset(w * 0.4, h * 0.5);
    final p2 = Offset(w * 0.8, h * 0.3);

    canvas.drawCircle(p1, 3, pointPaint);
    canvas.drawCircle(p1, 3, pointBorder);

    canvas.drawCircle(p2, 3, pointPaint);
    canvas.drawCircle(p2, 3, pointBorder);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

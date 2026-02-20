import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';

class ReportPreviewScreen extends StatelessWidget {
  const ReportPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.9),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text(
          'Report Preview: Feb 2026',
          style: AppTypography.h3.copyWith(color: AppColors.primaryNavy, fontSize: 16),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report downloaded to device')));
            },
            icon: const Icon(Icons.download_outlined, color: AppColors.primaryNavy),
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share options opening...')));
            },
            icon: const Icon(Icons.share_outlined, color: AppColors.primaryNavy),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        physics: const BouncingScrollPhysics(),
        child: Center(
          child: Transform.scale(
            scale: 0.98,
            alignment: Alignment.topCenter,
            child: _buildReportDocument(context),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomActionBar(context),
    );
  }

  Widget _buildBottomActionBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      // Use SafeArea in case we have bottom notch
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report shared via WhatsApp')));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                elevation: 8,
                shadowColor: const Color(0xFF25D366).withValues(alpha: 0.3),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
              ),
              icon: const Icon(Icons.chat_rounded, size: 20),
              label: const Text('Share via WhatsApp', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share options opening...')));
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade500,
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
              ),
              child: const Text('Other Share Options', style: TextStyle(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportDocument(BuildContext context) {
    return Container(
      width: 360,
      constraints: const BoxConstraints(minHeight: 500),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: -2,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryNavy,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('M', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TechStyle Egypt', style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('FEBRUARY 2026 REPORT', style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w500, fontSize: 9, letterSpacing: 0.5)),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Generated', style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 12)),
                  Text('01 Mar 2026', style: TextStyle(color: Colors.grey.shade400, fontSize: 9)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: Colors.grey.shade100, height: 1),
          const SizedBox(height: 16),

          // KPIs
          Row(
            children: [
              Expanded(child: _buildKPICard('Net Profit', 'EGP 42k', '+12%', true, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildKPICard('Revenue', 'EGP 128k', 'vs 114k last mo.', null, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildKPICard('Expenses', 'EGP 86k', '-2%', false, Colors.red)),
            ],
          ),
          const SizedBox(height: 24),

          // Cashflow Trend
          Text('CASHFLOW TREND', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.shade100, height: 1),
          const SizedBox(height: 8),
          Container(
            height: 96, // h-24 -> 96px
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                      gradient: LinearGradient(
                        colors: [AppColors.primaryNavy.withValues(alpha: 0.05), Colors.transparent],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                   child: CustomPaint(
                     painter: _MockChartPainter(),
                   ),
                ),
                Positioned(
                  bottom: -2, left: 0, right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('W1', style: TextStyle(fontSize: 7, color: Colors.grey)),
                      Text('W2', style: TextStyle(fontSize: 7, color: Colors.grey)),
                      Text('W3', style: TextStyle(fontSize: 7, color: Colors.grey)),
                      Text('W4', style: TextStyle(fontSize: 7, color: Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Top Expenses
          Text('TOP EXPENSES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade800, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Divider(color: Colors.grey.shade100, height: 1),
          const SizedBox(height: 8),
          _buildExpenseRow('Salaries', 0.65, AppColors.primaryNavy),
          const SizedBox(height: 8),
          _buildExpenseRow('Rent', 0.20, AppColors.accentOrange),
          const SizedBox(height: 8),
          _buildExpenseRow('Marketing', 0.10, Colors.teal.shade500),
          const SizedBox(height: 8),
          _buildExpenseRow('Software', 0.05, Colors.purple.shade500),
          const SizedBox(height: 24),

          // AI Analysis
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.indigo.shade50, Colors.purple.shade50],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.shade100),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white, 
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1)),
                    ]
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: Colors.indigo.shade600, size: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI Analysis', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo.shade900)),
                      const SizedBox(height: 2),
                      Text(
                        'Revenue grew by 12% vs January. Salaries remain your largest outflow, consider reviewing contract renewals.',
                        style: TextStyle(fontSize: 9, color: Colors.indigo.shade800.withValues(alpha: 0.8), height: 1.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
          Divider(color: Colors.grey.shade100, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Powered by Masari', style: TextStyle(fontSize: 8, color: Colors.grey.shade400)),
              Text('Page 1 of 1', style: TextStyle(fontSize: 8, color: Colors.grey.shade400)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKPICard(String label, String value, String subtitle, bool? isUp, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: color.shade700)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade700)),
          const SizedBox(height: 2),
          Row(
            children: [
              if (isUp != null)
                Icon(isUp ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 10, color: color.shade600),
              if (isUp != null)
                const SizedBox(width: 2),
              Expanded(
                child: Text(
                  subtitle, 
                  style: TextStyle(fontSize: 8, color: color.shade600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExpenseRow(String label, double percent, Color color) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.grey.shade600))),
        Expanded(
          child: Container(
            height: 8,
            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: percent,
              child: Container(
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
        ),
        SizedBox(width: 40, child: Text('${(percent * 100).toInt()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black87))),
      ],
    );
  }
}

class _MockChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = AppColors.primaryNavy.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = AppColors.primaryNavy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    
    // Scale functions based on SVG viewBox 0 0 100 50
    double scaleX(double x) => (x / 100) * size.width;
    double scaleY(double y) => (y / 50) * size.height;

    // Points from the SVG path
    final points = [
      Offset(scaleX(0), scaleY(45)),
      Offset(scaleX(10), scaleY(40)),
      Offset(scaleX(20), scaleY(42)),
      Offset(scaleX(30), scaleY(35)),
      Offset(scaleX(40), scaleY(38)),
      Offset(scaleX(50), scaleY(25)),
      Offset(scaleX(60), scaleY(30)),
      Offset(scaleX(70), scaleY(20)),
      Offset(scaleX(80), scaleY(22)),
      Offset(scaleX(90), scaleY(10)),
      Offset(scaleX(100), scaleY(15)),
    ];

    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
    }
    
    // Fill path (add bottom corners and close)
    final fillPath = Path.from(path);
    fillPath.lineTo(scaleX(100), scaleY(50));
    fillPath.lineTo(scaleX(0), scaleY(50));
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

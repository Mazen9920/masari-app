import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text('Help Center', style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Search
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
              ),
              child: const TextField(
                decoration: InputDecoration(
                  hintText: 'Search for help...',
                  hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textTertiary),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // Quick Help Categories
            _sectionTitle('QUICK HELP'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildQuickHelpCard(context, Icons.play_circle_outline_rounded, 'Getting\nStarted', const Color(0xFF3B82F6))),
                const SizedBox(width: 12),
                Expanded(child: _buildQuickHelpCard(context, Icons.receipt_long_rounded, 'Transactions\nHelp', const Color(0xFF22C55E))),
                const SizedBox(width: 12),
                Expanded(child: _buildQuickHelpCard(context, Icons.bar_chart_rounded, 'Reports\nGuide', const Color(0xFF8B5CF6))),
              ],
            ),
            const SizedBox(height: 28),
            // FAQ
            _sectionTitle('FREQUENTLY ASKED'),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
              ),
              child: Column(
                children: [
                  _buildFAQItem('How do I add a new transaction?', 'Tap the + button at the bottom of the screen to add income or expense transactions.'),
                  _faqDivider(),
                  _buildFAQItem('How do I export my reports?', 'Go to Reports > Tap the share icon in the top right to access the Export & Share center.'),
                  _faqDivider(),
                  _buildFAQItem('How do I manage my inventory?', 'Navigate to the Manage tab > Inventory to view, add, and track your products and materials.'),
                  _faqDivider(),
                  _buildFAQItem('How do I set up recurring transactions?', 'Go to Cash Flow > Coming Up section > Tap "Manage" to add scheduled transactions.'),
                  _faqDivider(),
                  _buildFAQItem('Can I change my currency?', 'Yes! Go to Profile > Currency & Language to change your default currency.'),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Contact Support
            _sectionTitle('NEED MORE HELP?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primaryNavy, AppColors.secondaryBlue],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: AppColors.primaryNavy.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Contact Support', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('We\'re here to help 24/7', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Chat', style: TextStyle(color: AppColors.primaryNavy, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text, style: AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 11,
      )),
    );
  }

  Widget _buildQuickHelpCard(BuildContext context, IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () => HapticFeedback.lightImpact(),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4)],
        ),
        child: Column(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 10),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3)),
          ],
        ),
      ),
    );
  }

  Widget _faqDivider() => Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5));

  Widget _buildFAQItem(String question, String answer) {
    return Theme(
      data: ThemeData(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(question, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        iconColor: AppColors.textTertiary,
        collapsedIconColor: AppColors.textTertiary,
        children: [
          Text(answer, style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
        title: Text('About Masari', style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Logo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: AppColors.navyGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primaryNavy.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Center(
                child: Text('M', style: TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Masari', style: AppTypography.h1.copyWith(color: AppColors.primaryNavy)),
            const SizedBox(height: 4),
            Text(
              'Smart Financial Management',
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Text(
                'Version 1.0.0 (Build 42)',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 32),
            // Links
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
              ),
              child: Column(
                children: [
                  _buildLink(icon: Icons.description_outlined, title: 'Terms of Service', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening Terms of Service...')));
                  }),
                  _divider(),
                  _buildLink(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Opening Privacy Policy...')));
                  }),
                  _divider(),
                  _buildLink(icon: Icons.gavel_rounded, title: 'Open Source Licenses', onTap: () {
                    showLicensePage(
                      context: context,
                      applicationName: 'Masari',
                      applicationVersion: '1.0.0',
                    );
                  }),
                  _divider(),
                  _buildLink(icon: Icons.star_outline_rounded, title: 'Rate the App', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thank you! Opening app store...')));
                  }),
                  _divider(),
                  _buildLink(icon: Icons.share_outlined, title: 'Share Masari', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share link copied to clipboard!')));
                  }),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Footer
            Text(
              'Made with ❤️ in Egypt',
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              '© 2026 Masari. All rights reserved.',
              style: TextStyle(fontSize: 11, color: AppColors.textTertiary.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5), indent: 56);

  Widget _buildLink({required IconData icon, required String title, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

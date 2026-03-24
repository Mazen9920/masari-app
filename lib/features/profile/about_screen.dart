import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

const _kPrivacyUrl = 'https://masari.app/privacy.html';
const _kTermsUrl = 'https://masari.app/terms.html';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.safePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text(l10n.aboutTitle, style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
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
            Text(l10n.appName, style: AppTypography.h1.copyWith(color: AppColors.primaryNavy)),
            const SizedBox(height: 4),
            Text(
              l10n.aboutTagline,
              style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.hasData
                    ? l10n.aboutVersion(snapshot.data!.version, snapshot.data!.buildNumber)
                    : l10n.loading;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Text(
                    version,
                    style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontWeight: FontWeight.w600),
                  ),
                );
              },
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
                  _buildLink(icon: Icons.description_outlined, title: l10n.aboutTermsOfService, onTap: () {
                    launchUrl(Uri.parse(_kTermsUrl), mode: LaunchMode.externalApplication);
                  }),
                  _divider(),
                  _buildLink(icon: Icons.privacy_tip_outlined, title: l10n.aboutPrivacyPolicy, onTap: () {
                    launchUrl(Uri.parse(_kPrivacyUrl), mode: LaunchMode.externalApplication);
                  }),
                  _divider(),
                  _buildLink(icon: Icons.gavel_rounded, title: l10n.aboutOpenSourceLicenses, onTap: () async {
                    final info = await PackageInfo.fromPlatform();
                    if (!context.mounted) return;
                    showLicensePage(
                      context: context,
                      applicationName: l10n.appName,
                      applicationVersion: info.version,
                    );
                  }),
                  _divider(),
                  _buildLink(icon: Icons.star_outline_rounded, title: l10n.aboutRateApp, onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.aboutRateThankYou)));
                  }),
                  _divider(),
                  _buildLink(icon: Icons.share_outlined, title: l10n.aboutShareMasari, onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.aboutShareCopied)));
                  }),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Footer
            Text(
              l10n.aboutMadeIn,
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.aboutCopyright,
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

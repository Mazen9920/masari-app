import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/navigation/app_router.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class DataBackupScreen extends ConsumerStatefulWidget {
  const DataBackupScreen({super.key});

  @override
  ConsumerState<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends ConsumerState<DataBackupScreen> {
  bool _autoBackup = true;

  @override
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
        title: Text(l10n.dataBackupTitle, style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Backup Status Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                    const Color(0xFF0EA5E9).withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF0EA5E9).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.cloud_done_outlined, color: Color(0xFF0EA5E9), size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.dataBackupLastBackup, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(l10n.dataBackupNoBackups, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(l10n.comingSoon, style: TextStyle(fontSize: 12, color: AppColors.textTertiary, fontStyle: FontStyle.italic)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _sectionTitle(l10n.dataBackupSectionBackup),
            const SizedBox(height: 10),
            _buildCard([
              _buildToggleRow(
                icon: Icons.sync_rounded,
                iconColor: const Color(0xFF22C55E),
                title: l10n.dataBackupAutoBackup,
                subtitle: l10n.dataBackupAutoSubtitle,
                value: _autoBackup,
                onChanged: (v) => setState(() => _autoBackup = v),
              ),
              _divider(),
              _buildActionRow(
                icon: Icons.cloud_upload_outlined,
                iconColor: const Color(0xFF3B82F6),
                title: l10n.dataBackupNow,
                subtitle: l10n.comingSoon,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.dataBackupComingSoon)),
                  );
                },
              ),
              _divider(),
              _buildActionRow(
                icon: Icons.cloud_download_outlined,
                iconColor: const Color(0xFF8B5CF6),
                title: l10n.dataBackupRestore,
                subtitle: l10n.comingSoon,
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      title: Text(l10n.dataBackupRestore, style: AppTypography.h3),
                      content: Text(l10n.dataBackupRestoreMessage),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.dataBackupRestored)));
                          },
                          child: Text(l10n.restore),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ]),
            const SizedBox(height: 24),
            _sectionTitle(l10n.dataBackupSectionExport),
            const SizedBox(height: 10),
            _buildCard([
              _buildActionRow(
                icon: Icons.download_rounded,
                iconColor: const Color(0xFFF59E0B),
                title: l10n.dataBackupExportAll,
                subtitle: l10n.comingSoon,
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.dataBackupExportComingSoon)));
                },
              ),
            ]),
            const SizedBox(height: 24),
            _sectionTitle(l10n.dataBackupSectionDanger),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
              ),
              child: _buildActionRow(
                icon: Icons.delete_forever_rounded,
                iconColor: AppColors.danger,
                title: l10n.dataBackupDeleteAll,
                subtitle: l10n.dataBackupDeleteSubtitle,
                onTap: () => _showDeleteAccountDialog(context, l10n),
                isDestructive: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog(BuildContext context, AppLocalizations l10n) async {
    final emailController = TextEditingController();
    final userEmail = ref.read(authProvider).user?.email ?? '';
    bool isDeleting = false;
    String? errorText;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l10n.dataBackupDeleteAll,
                    style: AppTypography.h3.copyWith(color: AppColors.danger)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.dataBackupDeleteMessage,
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
              const SizedBox(height: 20),
              Text(l10n.dataBackupConfirmEmail,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              TextField(
                controller: emailController,
                enabled: !isDeleting,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: l10n.dataBackupConfirmEmailHint,
                  errorText: errorText,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              if (isDeleting) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger),
                    ),
                    const SizedBox(width: 12),
                    Text(l10n.dataBackupDeleting,
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: isDeleting
                  ? null
                  : () async {
                      final enteredEmail = emailController.text.trim();
                      if (enteredEmail.toLowerCase() != userEmail.toLowerCase()) {
                        setDialogState(() => errorText = l10n.dataBackupEmailMismatch);
                        return;
                      }
                      setDialogState(() {
                        isDeleting = true;
                        errorText = null;
                      });

                      try {
                        final callable = FirebaseFunctions.instance.httpsCallable('deleteUserData');
                        await callable.call({'confirmEmail': enteredEmail});

                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);

                        // Sign out locally and navigate to login
                        await ref.read(authProvider.notifier).signOut();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.dataBackupDeleteSuccess),
                            backgroundColor: AppColors.success,
                          ),
                        );
                        context.go(AppRoutes.login);
                      } catch (e) {
                        if (!ctx.mounted) return;
                        setDialogState(() {
                          isDeleting = false;
                          errorText = l10n.dataBackupDeleteFailed;
                        });
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: Text(l10n.dataBackupDeleteEverything),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(text, style: AppTypography.captionSmall.copyWith(
        color: AppColors.textTertiary, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontSize: 11,
      )),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8)],
      ),
      child: Column(children: children),
    );
  }

  Widget _divider() => Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5), indent: 68);

  Widget _buildToggleRow({
    required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required bool value, required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: iconColor, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ])),
          Switch(value: value, onChanged: (v) { HapticFeedback.lightImpact(); onChanged(v); },
            activeThumbColor: AppColors.accentOrange, activeTrackColor: AppColors.accentOrange.withValues(alpha: 0.3),
            inactiveThumbColor: Colors.white, inactiveTrackColor: const Color(0xFFCBD5E1)),
        ],
      ),
    );
  }

  Widget _buildActionRow({
    required IconData icon, required Color iconColor,
    required String title, required String subtitle,
    required VoidCallback onTap, bool isDestructive = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: iconColor, size: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDestructive ? AppColors.danger : AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ])),
              Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

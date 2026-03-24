import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

class CurrencyLanguageScreen extends ConsumerWidget {
  const CurrencyLanguageScreen({super.key});

  static const _currencies = [
    {'code': 'EGP', 'name': 'Egyptian Pound', 'symbol': 'E£'},
    {'code': 'USD', 'name': 'US Dollar',       'symbol': '\$'},
    {'code': 'EUR', 'name': 'Euro',             'symbol': '€'},
    {'code': 'SAR', 'name': 'Saudi Riyal',      'symbol': '﷼'},
    {'code': 'AED', 'name': 'UAE Dirham',       'symbol': 'د.إ'},
    {'code': 'GBP', 'name': 'British Pound',    'symbol': '£'},
  ];

  static const _languages = ['English', 'العربية'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(appSettingsProvider);
    final notifier = ref.read(appSettingsProvider.notifier);
    final selectedCurrency = settings.currency;
    final selectedLanguage = settings.language;
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => context.safePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primaryNavy),
        ),
        title: Text(l10n.currencyLanguageTitle, style: AppTypography.h3.copyWith(color: AppColors.primaryNavy)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Currency Section
            _sectionTitle(l10n.currencySection),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8),
                ],
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _currencies.length; i++) ...[
                    _buildCurrencyTile(
                      _currencies[i],                      localizedName: _localizedCurrencyName(l10n, _currencies[i]['code']!),                      isSelected: selectedCurrency == _currencies[i]['code'],
                      onTap: () async {
                        final code = _currencies[i]['code']!;
                        if (selectedCurrency == code) return;
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(l10n.currencyChangeTitle),
                            content: Text(
                              l10n.currencyChangeMessage(code),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: Text(l10n.cancel),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: Text(l10n.currencyChangeBtn),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) {
                          HapticFeedback.lightImpact();
                          notifier.setCurrency(code);
                        }
                      },
                    ),
                    if (i < _currencies.length - 1)
                      Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5), indent: 56),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),
            // Language Section
            _sectionTitle(l10n.languageSection),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8),
                ],
              ),
              child: Column(
                children: [
                  for (int i = 0; i < _languages.length; i++) ...[
                    _buildLanguageTile(
                      _languages[i],
                      isSelected: selectedLanguage == _languages[i],
                      onTap: () {
                        HapticFeedback.lightImpact();
                        notifier.setLanguage(_languages[i]);
                      },
                    ),
                    if (i < _languages.length - 1)
                      Divider(height: 1, color: AppColors.borderLight.withValues(alpha: 0.5), indent: 56),
                  ],
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
      child: Text(
        text,
        style: AppTypography.captionSmall.copyWith(
          color: AppColors.textTertiary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          fontSize: 11,
        ),
      ),
    );
  }

  String _localizedCurrencyName(AppLocalizations l10n, String code) => switch (code) {
    'EGP' => l10n.currencyEgp,
    'USD' => l10n.currencyUsd,
    'EUR' => l10n.currencyEur,
    'SAR' => l10n.currencySar,
    'AED' => l10n.currencyAed,
    'GBP' => l10n.currencyGbp,
    _ => code,
  };

  Widget _buildCurrencyTile(
    Map<String, String> currency, {
    required String localizedName,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryNavy.withValues(alpha: 0.1) : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  currency['symbol']!,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? AppColors.primaryNavy : AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currency['code']!,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? AppColors.primaryNavy : AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      localizedName,
                      style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryNavy,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile(
    String language, {
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primaryNavy.withValues(alpha: 0.1) : AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.translate_rounded,
                  size: 18,
                  color: isSelected ? AppColors.primaryNavy : AppColors.textTertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  language,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? AppColors.primaryNavy : AppColors.textPrimary,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: AppColors.primaryNavy,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

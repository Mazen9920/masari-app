import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/navigation/app_router.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/form_components.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _agreedToTerms = false;
  bool _isLoading = false;
  String _selectedCountryCode = '+20';

  final List<Map<String, String>> _countryCodes = [
    {'code': '+20', 'flag': '🇪🇬', 'key': 'egypt'},
    {'code': '+966', 'flag': '🇸🇦', 'key': 'saudiArabia'},
    {'code': '+971', 'flag': '🇦🇪', 'key': 'uae'},
    {'code': '+965', 'flag': '🇰🇼', 'key': 'kuwait'},
    {'code': '+973', 'flag': '🇧🇭', 'key': 'bahrain'},
    {'code': '+974', 'flag': '🇶🇦', 'key': 'qatar'},
    {'code': '+968', 'flag': '🇴🇲', 'key': 'oman'},
    {'code': '+962', 'flag': '🇯🇴', 'key': 'jordan'},
    {'code': '+1', 'flag': '🇺🇸', 'key': 'us'},
    {'code': '+44', 'flag': '🇬🇧', 'key': 'uk'},
  ];

  String _localizedCountryName(AppLocalizations l10n, String key) {
    switch (key) {
      case 'egypt': return l10n.countryEgypt;
      case 'saudiArabia': return l10n.countrySaudiArabia;
      case 'uae': return l10n.countryUAE;
      case 'kuwait': return l10n.countryKuwait;
      case 'bahrain': return l10n.countryBahrain;
      case 'qatar': return l10n.countryQatar;
      case 'oman': return l10n.countryOman;
      case 'jordan': return l10n.countryJordan;
      case 'us': return l10n.countryUS;
      case 'uk': return l10n.countryUK;
      default: return key;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onSignUp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.agreeToTermsError,
            style: AppTypography.bodySmall.copyWith(color: Colors.white),
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardRadius,
          ),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await ref.read(authProvider.notifier).signUp(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      phone: '$_selectedCountryCode${_phoneController.text.trim()}',
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      // Save user data to legacy provider for setup screens
      ref.read(userProvider.notifier).setUser(
        _nameController.text.trim(),
        _emailController.text.trim(),
      );
      context.go(AppRoutes.setupStep1);
    } else {
      final error = ref.read(authProvider).error ?? AppLocalizations.of(context)!.signUpFailed;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _onGoogleSignUp() async {
    setState(() => _isLoading = true);
    final success = await ref.read(authProvider.notifier).signInWithGoogle();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.go(AppRoutes.home);
    } else {
      final error = ref.read(authProvider).error ?? AppLocalizations.of(context)!.googleSignInFailed;
      if (error.contains('cancelled')) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _onAppleSignUp() async {
    setState(() => _isLoading = true);
    final success = await ref.read(authProvider.notifier).signInWithApple();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.go(AppRoutes.home);
    } else {
      final error = ref.read(authProvider).error ?? AppLocalizations.of(context)!.appleSignInFailed;
      if (error.contains('cancelled')) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _navigateToLogin() {
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenHorizontal,
          ),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildHeader(),
              const SizedBox(height: 32),
              _buildForm(),
              const SizedBox(height: 20),
              _buildTermsCheckbox(),
              const SizedBox(height: 24),
              RevvoPrimaryButton(
                text: _isLoading ? AppLocalizations.of(context)!.creatingAccount : AppLocalizations.of(context)!.signUp,
                icon: Icons.arrow_forward_rounded,
                onPressed: _isLoading ? null : _onSignUp,
              ),
              const SizedBox(height: 28),
              SocialLoginButtons(
                onGoogleTap: _isLoading ? null : _onGoogleSignUp,
                onAppleTap: _isLoading ? null : _onAppleSignUp,
              ),
              const SizedBox(height: 32),
              _buildFooterLink(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.accentOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.account_balance_wallet_outlined,
            color: AppColors.accentOrange,
            size: 28,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context)!.createYourAccount,
          style: AppTypography.h1.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          AppLocalizations.of(context)!.signUpSubtitle,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          RevvoTextField(
            label: AppLocalizations.of(context)!.fullName,
            icon: Icons.person_outline_rounded,
            controller: _nameController,
            keyboardType: TextInputType.name,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return AppLocalizations.of(context)!.pleaseEnterName;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          RevvoTextField(
            label: AppLocalizations.of(context)!.workEmail,
            icon: Icons.email_outlined,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || !value.contains('@')) {
                return AppLocalizations.of(context)!.pleaseEnterValidEmail;
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Phone with country code
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 100,
                child: _buildCountryCodeSelector(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: RevvoTextField(
                  label: AppLocalizations.of(context)!.phoneNumber,
                  icon: Icons.phone_iphone_rounded,
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          RevvoTextField(
            label: AppLocalizations.of(context)!.password,
            icon: Icons.lock_outline_rounded,
            controller: _passwordController,
            obscureText: true,
            validator: (value) {
              if (value == null || value.length < 6) {
                return AppLocalizations.of(context)!.passwordMinLength;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCountryCodeSelector() {
    final selected = _countryCodes.firstWhere(
      (c) => c['code'] == _selectedCountryCode,
    );
    return GestureDetector(
      onTap: () => _showCountryPicker(),
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.surfaceLight,
          borderRadius: AppRadius.cardRadius,
          border: Border.all(color: AppColors.borderLight),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              selected['flag']!,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(width: 4),
            Text(
              selected['code']!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 16,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceLight,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.selectCountry,
                  style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _countryCodes.map((country) {
                      final isSelected = country['code'] == _selectedCountryCode;
                      return ListTile(
                        leading: Text(country['flag']!, style: const TextStyle(fontSize: 24)),
                        title: Text(
                          '${_localizedCountryName(AppLocalizations.of(context)!, country['key']!)} (${country['code']})',
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: AppColors.accentOrange, size: 22)
                            : null,
                        onTap: () {
                          setState(() => _selectedCountryCode = country['code']!);
                          Navigator.pop(context);
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTermsCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
            activeColor: AppColors.accentOrange,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            side: const BorderSide(color: AppColors.borderLight, width: 1.5),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              children: [
                TextSpan(text: AppLocalizations.of(context)!.iAgreeTo),
                TextSpan(
                  text: AppLocalizations.of(context)!.termsOfService,
                  style: const TextStyle(
                    color: AppColors.accentOrange,
                    fontWeight: FontWeight.w600,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = () {
                    launchUrl(Uri.parse('https://revvo-app.com/terms'), mode: LaunchMode.externalApplication);
                  },
                ),
                TextSpan(text: AppLocalizations.of(context)!.andWord),
                TextSpan(
                  text: AppLocalizations.of(context)!.privacyPolicy,
                  style: const TextStyle(
                    color: AppColors.accentOrange,
                    fontWeight: FontWeight.w600,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = () {
                    launchUrl(Uri.parse('https://revvo-app.com/privacy'), mode: LaunchMode.externalApplication);
                  },
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterLink() {
    return RichText(
      text: TextSpan(
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        children: [
          TextSpan(text: AppLocalizations.of(context)!.alreadyHaveAccount),
          TextSpan(
            text: AppLocalizations.of(context)!.logIn,
            style: const TextStyle(
              color: AppColors.secondaryBlue,
              fontWeight: FontWeight.w700,
            ),
            recognizer: TapGestureRecognizer()..onTap = _navigateToLogin,
          ),
        ],
      ),
    );
  }
}

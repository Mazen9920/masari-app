import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/navigation/app_router.dart';
import '../../core/providers/auth_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../core/providers/repository_providers.dart';
import 'widgets/form_components.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLogin() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);

    final success = await ref.read(authProvider.notifier).signIn(
      email: _emailController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      context.go(AppRoutes.home);
    } else {
      final error = ref.read(authProvider).error ?? AppLocalizations.of(context)!.loginFailed;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  void _onGoogleSignIn() async {
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

  void _onAppleSignIn() async {
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

  void _navigateToSignUp() {
    context.go(AppRoutes.signup);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenHorizontal,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                _buildHeader(),
                const SizedBox(height: 40),
                _buildForm(),
                const SizedBox(height: 12),
                _buildForgotPassword(),
                const SizedBox(height: 28),
                RevvoPrimaryButton(
                  text: _isLoading ? AppLocalizations.of(context)!.loggingIn : AppLocalizations.of(context)!.logIn,
                  icon: Icons.arrow_forward_rounded,
                  onPressed: _isLoading ? null : _onLogin,
                ),
                const SizedBox(height: 32),
                SocialLoginButtons(
                  onGoogleTap: _isLoading ? null : _onGoogleSignIn,
                  onAppleTap: _isLoading ? null : _onAppleSignIn,
                ),
                const SizedBox(height: 40),
                _buildFooterLink(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Logo icon — chart line (matching Stitch design)
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.accentOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.accentOrange.withValues(alpha: 0.2),
            ),
          ),
          child: const Icon(
            Icons.show_chart_rounded,
            color: AppColors.accentOrange,
            size: 32,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          AppLocalizations.of(context)!.welcomeBack,
          style: AppTypography.h1.copyWith(
            color: AppColors.textPrimary,
            fontSize: 30,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context)!.logInSubtitle,
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textSecondary,
          ),
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
            label: AppLocalizations.of(context)!.emailAddress,
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
          RevvoTextField(
            label: AppLocalizations.of(context)!.password,
            icon: Icons.lock_outline_rounded,
            controller: _passwordController,
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return AppLocalizations.of(context)!.pleaseEnterPassword;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildForgotPassword() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () async {
          final email = _emailController.text.trim();
          if (email.isEmpty || !email.contains('@')) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.enterEmailFirst),
            ));
            return;
          }
          // Access the repo through the notifier's mechanism
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(AppLocalizations.of(context)!.sendingResetLink),
          ));
          // We'll call signIn's repo via the provider pattern
          // For now, use the auth repository directly through the provider
          try {
            final authRepo = ref.read(authRepositoryProvider);
            final result = await authRepo.resetPassword(email: email);
            if (!mounted) return;
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(result.isSuccess
                  ? AppLocalizations.of(context)!.resetLinkSent(email)
                  : result.error ?? AppLocalizations.of(context)!.failedToSendResetLink),
              backgroundColor: result.isSuccess ? AppColors.primaryNavy : AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(AppLocalizations.of(context)!.failedToSendResetLink),
              backgroundColor: AppColors.danger,
            ));
          }
        },
        child: Text(
          AppLocalizations.of(context)!.forgotPassword,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.secondaryBlue,
          ),
        ),
      ),
    );
  }

  Widget _buildFooterLink() {
    return RichText(
      text: TextSpan(
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary,
        ),
        children: [
          TextSpan(text: AppLocalizations.of(context)!.dontHaveAccount),
          TextSpan(
            text: AppLocalizations.of(context)!.signUp,
            style: const TextStyle(
              color: AppColors.secondaryBlue,
              fontWeight: FontWeight.w700,
            ),
            recognizer: TapGestureRecognizer()..onTap = _navigateToSignUp,
          ),
        ],
      ),
    );
  }
}

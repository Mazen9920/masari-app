import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/navigation/app_router.dart';
import '../../core/providers/auth_provider.dart';
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
      final error = ref.read(authProvider).error ?? 'Login failed';
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
      final error = ref.read(authProvider).error ?? 'Google sign-in failed';
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
      final error = ref.read(authProvider).error ?? 'Apple sign-in failed';
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
                MasariPrimaryButton(
                  text: _isLoading ? 'Logging in…' : 'Log In',
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
          'Welcome Back',
          style: AppTypography.h1.copyWith(
            color: AppColors.textPrimary,
            fontSize: 30,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Log in to manage your finances.',
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
          MasariTextField(
            label: 'Email Address',
            icon: Icons.email_outlined,
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || !value.contains('@')) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          MasariTextField(
            label: 'Password',
            icon: Icons.lock_outline_rounded,
            controller: _passwordController,
            obscureText: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Please enter your email address first'),
            ));
            return;
          }
          // Access the repo through the notifier's mechanism
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sending password reset link…'),
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
                  ? 'Password reset link sent to $email'
                  : result.error ?? 'Failed to send reset link'),
              backgroundColor: result.isSuccess ? AppColors.primaryNavy : AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ));
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to send reset link: $e'),
              backgroundColor: AppColors.danger,
            ));
          }
        },
        child: Text(
          'Forgot Password?',
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
          const TextSpan(text: "Don't have an account? "),
          TextSpan(
            text: 'Sign Up',
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

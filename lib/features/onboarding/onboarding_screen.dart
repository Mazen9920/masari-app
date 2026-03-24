import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/navigation/app_router.dart';
import '../../l10n/app_localizations.dart';
import 'widgets/onboarding_page.dart';
import 'widgets/onboarding_illustrations.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  late AnimationController _buttonAnimController;
  late Animation<double> _buttonScale;

  List<OnboardingPageData> _pages(AppLocalizations l10n) => [
    OnboardingPageData(
      title: l10n.onboardingTitle1,
      highlightWord: l10n.onboardingHighlight1,
      subtitle: l10n.onboardingSubtitle1,
      illustration: const TrackIllustration(),
    ),
    OnboardingPageData(
      title: l10n.onboardingTitle2,
      highlightWord: l10n.onboardingHighlight2,
      subtitle: l10n.onboardingSubtitle2,
      illustration: const AIInsightIllustration(),
    ),
    OnboardingPageData(
      title: l10n.onboardingTitle3,
      highlightWord: l10n.onboardingHighlight3,
      subtitle: l10n.onboardingSubtitle3,
      illustration: const GrowIllustration(),
    ),
  ];

  bool get _isLastPage => _currentPage == 2;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    _buttonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _buttonScale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _buttonAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _buttonAnimController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
  }

  void _nextPage() {
    if (_isLastPage) {
      _navigateToAuth();
    } else {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _skip() {
    _navigateToAuth();
  }

  void _navigateToAuth() {
    context.go(AppRoutes.signup);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            // ─── Top bar with Skip button ───
            _buildTopBar(),

            // ─── Page content ───
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: 3,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  final l10n = AppLocalizations.of(context)!;
                  return OnboardingPage(data: _pages(l10n)[index]);
                },
              ),
            ),

            // ─── Bottom section: indicators + button ───
            _buildBottomSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenHorizontal,
        vertical: 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Skip button (hidden on last page)
          AnimatedOpacity(
            opacity: _isLastPage ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: GestureDetector(
              onTap: _isLastPage ? null : _skip,
              child: Text(
                AppLocalizations.of(context)!.onboardingSkip,
                style: AppTypography.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenHorizontal,
        16,
        AppSpacing.screenHorizontal,
        24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ─── Page indicators ───
          _buildPageIndicators(),

          const SizedBox(height: 28),

          // ─── Primary action button ───
          _buildPrimaryButton(),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPageIndicators() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        final isActive = index == _currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 28 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: isActive
                ? AppColors.accentOrange
                : AppColors.textTertiary.withValues(alpha: 0.3),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppColors.accentOrange.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }

  Widget _buildPrimaryButton() {
    return GestureDetector(
      onTapDown: (_) => _buttonAnimController.forward(),
      onTapUp: (_) {
        _buttonAnimController.reverse();
        _nextPage();
      },
      onTapCancel: () => _buttonAnimController.reverse(),
      child: AnimatedBuilder(
        animation: _buttonScale,
        builder: (context, child) {
          return Transform.scale(scale: _buttonScale.value, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.accentOrange,
            borderRadius: AppRadius.buttonRadius,
            boxShadow: AppColors.accentShadow,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Button text changes on last page
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _isLastPage ? AppLocalizations.of(context)!.getStarted : AppLocalizations.of(context)!.onboardingNext,
                  key: ValueKey(_isLastPage),
                  style: AppTypography.labelLarge.copyWith(
                    color: Colors.white,
                    fontSize: 17,
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Arrow or sparkle icon
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  _isLastPage
                      ? Icons.auto_awesome_rounded
                      : Icons.arrow_forward_rounded,
                  key: ValueKey(_isLastPage ? 'sparkle' : 'arrow'),
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

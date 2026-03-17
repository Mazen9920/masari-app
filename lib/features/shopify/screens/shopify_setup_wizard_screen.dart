import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/navigation/app_router.dart';
import '../../../core/providers/app_settings_provider.dart';
import '../../../core/services/shopify_sync_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../providers/shopify_connection_provider.dart';
import '../providers/shopify_sync_provider.dart';
import '../../../shared/utils/safe_pop.dart';

/// Multi-step wizard for first-time Shopify integration setup.
///
/// Steps:
/// 1. Enter store domain
/// 2. OAuth authorization (opens browser)
/// 3. Select Shopify location
/// 4. Product & inventory sync
/// 5. Confirmation & start syncing
class ShopifySetupWizardScreen extends ConsumerStatefulWidget {
  const ShopifySetupWizardScreen({super.key});

  @override
  ConsumerState<ShopifySetupWizardScreen> createState() =>
      _ShopifySetupWizardScreenState();
}

class _ShopifySetupWizardScreenState
    extends ConsumerState<ShopifySetupWizardScreen>
    with WidgetsBindingObserver {
  int _currentStep = 0;
  final _pageController = PageController();

  // Step 1: Store domain
  final _domainController = TextEditingController();
  String? _domainError;
  bool _connecting = false;

  // Step 2: OAuth
  bool _waitingForOAuth = false;
  bool _oauthCompleted = false;
  bool _checkingOAuth = false;
  String? _oauthCheckError;

  // Step 3: Location
  List<Map<String, dynamic>> _locations = [];
  bool _loadingLocations = false;
  String? _locationsError;
  String? _selectedLocationId;
  String? _selectedLocationName;

  // Step 4: Product & inventory sync
  bool _syncingProducts = false;
  bool _productSyncDone = false;
  int _productsSynced = 0;
  String? _productSyncError;

  // Step 5: Final
  bool _isFinishing = false;

  DateTime? _lastAutoRefreshAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _domainController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted || !_waitingForOAuth) return;

    final now = DateTime.now();
    final last = _lastAutoRefreshAt;
    if (last != null && now.difference(last).inSeconds < 2) return;
    _lastAutoRefreshAt = now;
    _checkOAuthCompletion();
  }

  Future<void> _checkOAuthCompletion() async {
    if (_checkingOAuth) return;
    setState(() {
      _checkingOAuth = true;
      _oauthCheckError = null;
    });
    HapticFeedback.lightImpact();

    // Small delay to allow Firestore propagation after OAuth callback
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;

    await ref.read(shopifyConnectionProvider.notifier).refresh();
    if (!mounted) return;

    final conn = ref.read(shopifyConnectionProvider).value;
    if (conn != null && conn.isActive) {
      setState(() {
        _checkingOAuth = false;
        _waitingForOAuth = false;
        _oauthCompleted = true;
        _oauthCheckError = null;
      });
      // Defer navigation to avoid triggering during build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _goToStep(2); // Proceed to location selection
        _fetchLocations();
      });
    } else {
      setState(() {
        _checkingOAuth = false;
        _oauthCheckError =
            'Authorization not detected yet.\n'
            'Make sure you approved the app on Shopify,\n'
            'then tap the button again.';
      });
    }
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildProgressBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStep1StoreDomain(),
                  _buildStep2OAuth(),
                  _buildStep3Location(),
                  _buildStep4ProductSync(),
                  _buildStep5Confirmation(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (_currentStep > 0 && !_oauthCompleted) {
                _goToStep(_currentStep - 1);
              } else {
                _showExitConfirmation();
              }
            },
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: AppColors.primaryNavy,
          ),
          const Spacer(),
          Text(
            'Shopify Setup',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          Text(
            'Step ${_currentStep + 1}/5',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: List.generate(5, (i) {
          final isCompleted = i < _currentStep;
          final isCurrent = i == _currentStep;
          return Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 4 ? 4 : 0),
              decoration: BoxDecoration(
                color: isCompleted
                    ? AppColors.shopifyPurple
                    : isCurrent
                        ? AppColors.shopifyPurple.withValues(alpha: 0.4)
                        : AppColors.borderLight,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Exit Setup?'),
        content: Text(
          _oauthCompleted
              ? 'Your Shopify connection is active. You can finish setup later from the Manage screen.'
              : 'Your setup is not complete. You can restart anytime from the Manage screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Continue Setup'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) context.safePop();
              });
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.textSecondary),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  // ── Step 1: Store Domain ─────────────────────────────────

  Widget _buildStep1StoreDomain() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hero
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.shopifyPurple, Color(0xFF5B21B6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color:
                        AppColors.shopifyPurple.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.store_rounded, size: 36, color: Colors.white),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Connect Your Shopify Store',
              style: AppTypography.h2.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Enter your Shopify store domain to get started.\nThis is a one-time setup.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Domain input
          Text(
            'SHOP DOMAIN',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _domainError != null
                    ? AppColors.danger.withValues(alpha: 0.5)
                    : AppColors.borderLight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _domainController,
                    decoration: InputDecoration(
                      hintText: 'your-store',
                      hintStyle: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textTertiary,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _onConnectDomain(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Text(
                    '.myshopify.com',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_domainError != null) ...[
            const SizedBox(height: 8),
            Text(_domainError!, style: AppTypography.bodySmall.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: 24),

          // Connect button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _connecting ? null : _onConnectDomain,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.shopifyPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: AppColors.shopifyPurple.withValues(alpha: 0.3),
              ),
              child: _connecting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.link_rounded, size: 20),
                        const SizedBox(width: 8),
                        Text('Connect to Shopify', style: AppTypography.labelLarge.copyWith(
                          color: Colors.white, fontWeight: FontWeight.w700,
                        )),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 32),

          // Info cards
          _InfoCard(
            icon: Icons.security_rounded,
            title: 'Secure OAuth Connection',
            description: 'We never see your Shopify password. Authorization uses industry-standard OAuth 2.0.',
          ),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.sync_rounded,
            title: 'Always-On Sync',
            description: 'After setup, Shopify orders automatically sync to Masari in real-time via webhooks.',
          ),
          const SizedBox(height: 10),
          _InfoCard(
            icon: Icons.link_off_rounded,
            title: 'Disconnect Anytime',
            description: 'You can disconnect your Shopify store at any time from the settings.',
          ),
          const SizedBox(height: 16),

          // ── Privacy / Data disclosure notice ─────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F5FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.shopifyPurple.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.privacy_tip_outlined,
                      size: 16,
                      color: AppColors.shopifyPurple,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Data Masari Will Access',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.shopifyPurple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _DataBullet('Orders — customer name, email, phone, shipping address, items, and totals. Stored in your private Masari account to populate your sales ledger.'),
                _DataBullet('Inventory — product titles, variants, and stock levels. Used to keep your Masari inventory in sync with Shopify.'),
                _DataBullet('This data is never shared with third parties or used for marketing. It is accessible only by you and deleted when you delete your account.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onConnectDomain() async {
    final domain = _domainController.text.trim().toLowerCase();
    if (domain.isEmpty) {
      setState(() => _domainError = 'Please enter your Shopify store name');
      return;
    }
    final cleanDomain = domain
        .replaceAll('https://', '')
        .replaceAll('http://', '')
        .replaceAll('.myshopify.com', '')
        .replaceAll('/', '');
    if (cleanDomain.isEmpty || cleanDomain.contains(' ')) {
      setState(() => _domainError = 'Invalid store name');
      return;
    }

    setState(() { _connecting = true; _domainError = null; });
    HapticFeedback.mediumImpact();

    // Ensure Firestore has the current tier (CF reads it for access check)
    final tier = ref.read(appSettingsProvider).tier;
    if (tier.hasShopifyAccess) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .set({'subscription_tier': tier.name}, SetOptions(merge: true));
        } catch (_) {}
      }
    }

    final shopDomain = '$cleanDomain.myshopify.com';
    final result = await ref.read(shopifyConnectionProvider.notifier).connect(shopDomain);

    if (!mounted) return;

    if (result.isSuccess) {
      setState(() {
        _connecting = false;
        _waitingForOAuth = true;
      });
      _goToStep(1); // Go to OAuth waiting step
    } else {
      setState(() {
        _connecting = false;
        _domainError = result.error ?? 'Connection failed';
      });
    }
  }

  // ── Step 2: OAuth Authorization ──────────────────────────

  Widget _buildStep2OAuth() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
      child: Column(
        children: [
          // OAuth animation
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.shopifyPurple.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: _oauthCompleted
                ? const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 56)
                : const Icon(Icons.open_in_browser_rounded,
                    color: AppColors.shopifyPurple, size: 48),
          ),
          const SizedBox(height: 24),
          Text(
            _oauthCompleted ? 'Connected!' : 'Authorizing…',
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _oauthCompleted
                ? 'Your Shopify store is now connected to Masari.'
                : 'Complete the authorization in your browser.\nWhen done, come back here.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          if (!_oauthCompleted) ...[
            // Manual "I've authorized" button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _checkingOAuth ? null : _checkOAuthCompletion,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.shopifyPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _checkingOAuth
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white,
                        ),
                      )
                    : const Text("I've Authorized in Browser",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            // Error message when check fails
            if (_oauthCheckError != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.danger.withValues(alpha: 0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline_rounded,
                        color: AppColors.danger, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _oauthCheckError!,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _goToStep(0),
              icon: Icon(Icons.arrow_back_rounded,
                  size: 16, color: AppColors.textTertiary),
              label: Text('Change Store',
                  style: TextStyle(color: AppColors.textTertiary)),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  _goToStep(2);
                  _fetchLocations();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.shopifyPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Continue Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Step 3: Location Selection ───────────────────────────

  Future<void> _fetchLocations() async {
    setState(() { _loadingLocations = true; _locationsError = null; });
    try {
      final apiService = ref.read(shopifyApiServiceProvider);
      final result = await apiService.fetchLocations();
      if (!mounted) return;

      if (result.isSuccess && result.data != null) {
        final locs = result.data!;
        setState(() {
          _locations = locs;
          _loadingLocations = false;
          _locationsError = null;
          // Auto-select primary or first location
          final primary = locs.where((l) => l['primary'] == true).toList();
          if (primary.isNotEmpty) {
            _selectedLocationId = primary.first['id']?.toString();
            _selectedLocationName = primary.first['name']?.toString();
          } else if (locs.isNotEmpty) {
            _selectedLocationId = locs.first['id']?.toString();
            _selectedLocationName = locs.first['name']?.toString();
          }
        });
      } else {
        setState(() {
          _loadingLocations = false;
          _locationsError = result.error ?? 'Failed to fetch locations';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingLocations = false;
        _locationsError = 'Error fetching locations: $e';
      });
    }
  }

  Widget _buildStep3Location() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.shopifyPurple.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_on_rounded,
                  color: AppColors.shopifyPurple, size: 36),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Select Your Location',
              style: AppTypography.h2.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Masari will sync inventory with this Shopify location.\nIf you have multiple locations, pick your primary one.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary, height: 1.5),
            ),
          ),
          const SizedBox(height: 28),

          if (_locationsError != null) ...[            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.dangerLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _locationsError!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_loadingLocations) ...[
            const Center(
              child: CircularProgressIndicator(
                color: AppColors.shopifyPurple)),
          ] else if (_locations.isEmpty) ...[
            _buildLocationEmptyState(),
          ] else ...[
            ..._locations.map((loc) {
              final locId = loc['id']?.toString() ?? '';
              final locName = loc['name']?.toString() ?? 'Unknown';
              final isPrimary = loc['primary'] == true;
              final isSelected = _selectedLocationId == locId;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => setState(() {
                    _selectedLocationId = locId;
                    _selectedLocationName = locName;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.shopifyPurple.withValues(alpha: 0.05)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? AppColors.shopifyPurple
                            : AppColors.borderLight,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                          color: isSelected
                              ? AppColors.shopifyPurple
                              : AppColors.textTertiary,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(locName, style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 15,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              )),
                              if (isPrimary)
                                Text('Primary location', style: TextStyle(
                                  color: AppColors.shopifyPurple,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selectedLocationId != null ? () => _saveLocationAndProceed() : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.shopifyPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationEmptyState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.textTertiary, size: 32),
          const SizedBox(height: 8),
          Text('No locations found', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Make sure your Shopify store has at least one active location.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _fetchLocations,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLocationAndProceed() async {
    await ref.read(shopifyConnectionProvider.notifier).updateSettings(
      shopifyLocationId: _selectedLocationId,
      shopifyLocationName: _selectedLocationName,
      syncOrdersEnabled: true,
      syncInventoryEnabled: true,
      inventorySyncDirection: 'shopify_to_masari',
      inventorySyncMode: 'always',
    );
    _goToStep(3);
  }

  // ── Step 4: Product & Inventory Sync ─────────────────────────

  Widget _buildStep4ProductSync() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.shopifyPurple.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: _syncingProducts
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: AppColors.shopifyPurple,
                      ),
                    )
                  : Icon(
                      _productSyncDone
                          ? Icons.check_circle_rounded
                          : Icons.inventory_2_outlined,
                      color: AppColors.shopifyPurple,
                      size: 36,
                    ),
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              _productSyncDone
                  ? 'Products & Inventory Synced!'
                  : 'Sync Products & Inventory',
              style: AppTypography.h2.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _syncingProducts
                  ? 'Importing your Shopify products and inventory levels into Masari…'
                  : _productSyncDone
                      ? '$_productsSynced product(s) imported with current inventory levels.'
                      : 'We\'ll import your products and their current inventory levels from Shopify.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ),

          if (_productSyncError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _productSyncError!,
                      style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_productSyncDone) ...[
            const SizedBox(height: 24),
            // Cost guidance banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: const Color(0xFFFDBA74).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline_rounded,
                          color: const Color(0xFFF59E0B), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Set Product Costs',
                        style: TextStyle(
                          color: const Color(0xFF92400E),
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'For accurate profit tracking, set the cost price for '
                    'each product in your inventory.\n\n'
                    'You can import historical orders anytime from '
                    'Shopify Settings → Re-import Historical Orders.',
                    style: TextStyle(
                      color: const Color(0xFF92400E).withValues(alpha: 0.85),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),

          if (!_syncingProducts && !_productSyncDone) ...[
            // Start sync button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _startProductSync,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.shopifyPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync_rounded, size: 20),
                    SizedBox(width: 8),
                    Text('Sync Products & Inventory',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ],

          if (_productSyncError != null && !_syncingProducts) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _startProductSync,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  side: BorderSide(color: AppColors.shopifyPurple),
                ),
                child: const Text('Retry',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],

          if (_productSyncDone) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _goToStep(4),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.shopifyPurple,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Continue',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _startProductSync() async {
    setState(() {
      _syncingProducts = true;
      _productSyncError = null;
    });

    try {
      final count =
          await ref.read(shopifySyncProvider.notifier).syncProducts();
      if (!mounted) return;
      if (count >= 0) {
        setState(() {
          _syncingProducts = false;
          _productSyncDone = true;
          _productsSynced = count;
        });
      } else {
        setState(() {
          _syncingProducts = false;
          _productSyncError = 'Failed to sync products. Please try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _syncingProducts = false;
        _productSyncError = 'Error syncing products: $e';
      });
    }
  }

  // ── Step 5: Confirmation ─────────────────────────────────

  Widget _buildStep5Confirmation() {
    final conn = ref.watch(shopifyConnectionProvider).value;
    final shopName = conn?.shopName ?? _domainController.text;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      child: Column(
        children: [
          // Success icon
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.shopifyPurple, Color(0xFF5B21B6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.shopifyPurple.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, size: 44, color: Colors.white),
          ),
          const SizedBox(height: 24),
          Text(
            'Ready to Sync!',
            style: AppTypography.h2.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            "Here's a summary of your setup:",
            style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 28),

          // Summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borderLight),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
              ],
            ),
            child: Column(
              children: [
                _SummaryRow(icon: Icons.store_rounded, label: 'Store', value: shopName),
                const Divider(height: 24),
                _SummaryRow(icon: Icons.location_on_rounded, label: 'Location', value: _selectedLocationName ?? 'Default'),
                const Divider(height: 24),
                _SummaryRow(icon: Icons.sync_rounded, label: 'Order Sync', value: 'Always on (real-time)'),
                const Divider(height: 24),
                _SummaryRow(icon: Icons.inventory_2_outlined, label: 'Products Synced', value: '$_productsSynced product(s)'),
                const Divider(height: 24),
                _SummaryRow(icon: Icons.inventory_2_outlined, label: 'Inventory Sync', value: 'Always on'),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Start button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _isFinishing ? null : _onFinishSetup,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.shopifyPurple,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 56),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: AppColors.shopifyPurple.withValues(alpha: 0.3),
              ),
              child: _isFinishing
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.rocket_launch_rounded, size: 20),
                        SizedBox(width: 8),
                        Text('Start Syncing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onFinishSetup() async {
    setState(() => _isFinishing = true);
    HapticFeedback.mediumImpact();

    // Mark setup as completed in Firestore
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('shopify_connections')
            .doc(uid)
            .update({
          'setup_completed': true,
          'setup_completed_at': FieldValue.serverTimestamp(),
        });
      } catch (_) {
        // Best-effort; connection is already active
      }
    }

    if (!mounted) return;
    setState(() => _isFinishing = false);

    // Navigate to Shopify settings screen
    if (context.mounted) {
      context.go(AppRoutes.shopify);
    }
  }
}

// ── Helper widgets ─────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.shopifyPurple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.shopifyPurple, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(description, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataBullet extends StatelessWidget {
  final String text;
  const _DataBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 5, color: AppColors.shopifyPurple),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.shopifyPurple, size: 20),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: AppColors.textTertiary, fontSize: 13, fontWeight: FontWeight.w500)),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/app_localizations.dart';

/// Modal bottom sheet that loads a pre-fetched Paymob iframe URL in a WebView.
///
/// Call [show] to fetch the payment URL and display the sheet.
/// Returns `true` on success, `false` on cancel, `null` on error.
class PaymobCheckoutSheet extends StatefulWidget {
  const PaymobCheckoutSheet._({required this.iframeUrl});

  final String iframeUrl;

  /// Calls the CF to get the iframe URL, then opens the sheet.
  /// Shows a loading overlay on the calling screen while the CF runs.
  static Future<bool?> show(
    BuildContext context, {
    required String plan,
  }) async {
    // Show a blocking loading dialog while the CF runs.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.accentOrange),
                const SizedBox(height: 16),
                Text(
                  AppLocalizations.of(context)!.paymobProcessing,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    decoration: TextDecoration.none,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      if (kDebugMode) debugPrint('[PaymobSheet] Calling createPaymentIntent for $plan');
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        'createPaymentIntent',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 120)),
      );
      final result = await callable.call<Map<String, dynamic>>({'plan': plan});
      final iframeUrl = (result.data['iframe_url'] as String?)?.trim();
      if (kDebugMode) debugPrint('[PaymobSheet] Got URL: $iframeUrl');

      if (!context.mounted) return null;
      Navigator.of(context).pop(); // dismiss loading dialog

      if (iframeUrl == null || iframeUrl.isEmpty) {
        throw Exception('No iframe URL returned');
      }

      // Now open the sheet with the URL ready.
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => PaymobCheckoutSheet._(iframeUrl: iframeUrl),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[PaymobSheet] Error: $e');
      if (context.mounted) {
        Navigator.of(context).pop(); // dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.paymobPaymentFailed,
            ),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return null;
    }
  }

  @override
  State<PaymobCheckoutSheet> createState() => _PaymobCheckoutSheetState();
}

class _PaymobCheckoutSheetState extends State<PaymobCheckoutSheet> {
  late final WebViewController _controller;
  bool _pageLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: _onNavigation,
        onPageStarted: (url) {
          if (kDebugMode) debugPrint('[PaymobSheet] Page started: $url');
        },
        onPageFinished: (url) {
          if (kDebugMode) debugPrint('[PaymobSheet] Page finished: $url');
          if (mounted) setState(() => _pageLoading = false);
        },
        onWebResourceError: (error) {
          if (kDebugMode) debugPrint('[PaymobSheet] WebView error: ${error.description}');
        },
      ))
      ..loadRequest(Uri.parse(widget.iframeUrl));
  }

  NavigationDecision _onNavigation(NavigationRequest request) {
    if (kDebugMode) debugPrint('[PaymobSheet] Navigation: ${request.url}');
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.navigate;

    final success = uri.queryParameters['success'];
    if (success != null) {
      if (mounted) {
        Navigator.of(context).pop(success == 'true');
      }
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(
        children: [
          // ── Handle bar + close ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),

          // ── Disclaimer ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              AppLocalizations.of(context)!.subscriptionTermsNotice(
                AppLocalizations.of(context)!.termsOfService,
                AppLocalizations.of(context)!.privacyPolicy,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
            ),
          ),

          // ── WebView ──
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_pageLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentOrange,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

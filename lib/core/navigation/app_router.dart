import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

// ── Feature screens ──
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/setup/business_setup_step1.dart';
import '../../features/setup/business_setup_step2.dart';
import '../../features/setup/business_setup_step3.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/transactions/transactions_list_screen.dart';
import '../../features/transactions/add_transaction_screen.dart';
import '../../features/manage/manage_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/inventory/inventory_list_screen.dart';
import '../../features/inventory/product_detail_screen.dart';
import '../../features/suppliers/suppliers_overview_screen.dart';
import '../../features/suppliers/supplier_detail_screen.dart';
import '../../features/categories/categories_list_screen.dart';
import '../../features/categories/category_detail_screen.dart';
import '../../features/transactions/transaction_detail_screen.dart';
import '../../features/transactions/edit_transaction_screen.dart';
import '../../features/inventory/edit_product_screen.dart';
import '../../features/suppliers/edit_supplier_screen.dart';
import '../../features/suppliers/edit_payment_screen.dart';
import '../../features/suppliers/record_purchase_screen.dart';
import '../../features/suppliers/record_payment_screen.dart';
import '../../features/suppliers/payment_detail_screen.dart';
import '../../features/suppliers/purchase_detail_screen.dart';
import '../../features/categories/edit_category_screen.dart';
import '../../features/inventory/add_product_screen.dart';
import '../../features/inventory/add_material_screen.dart';
import '../../features/suppliers/add_supplier_screen.dart';
import '../../features/manage/hub_settings_screen.dart';
import '../../features/reports/export_share_screen.dart';
import '../../features/categories/manage_categories_screen.dart';
import '../../features/categories/budgets_overview_screen.dart';

// Remaining Profile & Config Screens:
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/business_info_screen.dart';
import '../../features/profile/currency_language_screen.dart';
import '../../features/profile/manage_subscription_screen.dart';
import '../../features/profile/billing_management_screen.dart';
import '../../features/profile/notification_preferences_screen.dart';
import '../../features/profile/security_screen.dart';
import '../../features/profile/data_backup_screen.dart';
import '../../features/profile/help_center_screen.dart';
import '../../features/profile/about_screen.dart';
import '../../features/suppliers/payments_summary_screen.dart';
import '../../features/suppliers/purchases_summary_screen.dart';
import '../../features/suppliers/received_goods_summary_screen.dart';
import '../../features/inventory/inventory_settings_screen.dart';
import '../../features/manage/pinned_actions_screen.dart';
import '../../features/ai/ai_chat_screen.dart';
import '../../features/cash_flow/screens/scheduled_transactions_screen.dart';
import '../../features/sales/sales_list_screen.dart';
import '../../features/sales/sale_detail_screen.dart';
import '../../features/sales/record_sale_screen.dart';
import '../../features/inventory/receive_goods_screen.dart';
import '../../features/inventory/missing_cost_screen.dart';
import '../../features/inventory/breakdown_screen.dart';
import '../../features/suppliers/receipt_detail_screen.dart';
import '../../features/suppliers/edit_receipt_screen.dart';
import '../../features/shopify/screens/shopify_connect_screen.dart';
import '../../features/shopify/screens/shopify_setup_wizard_screen.dart';
import '../../features/shopify/screens/shopify_product_mapping_screen.dart';
import '../../features/shopify/screens/shopify_import_screen.dart';
import '../../features/shopify/screens/shopify_inventory_sync_screen.dart';
import '../../features/shopify/screens/shopify_sync_history_screen.dart';
import '../../features/bosta/screens/bosta_connect_screen.dart';
import '../../features/bosta/screens/bosta_shipments_screen.dart';
import '../../features/bosta/screens/bosta_audit_screen.dart';
import '../../features/bosta/screens/bosta_shipment_detail_screen.dart';
import '../../shared/models/bosta_shipment_model.dart';
import '../../shared/models/sale_model.dart';
import '../../shared/models/goods_receipt_model.dart';
import '../../shared/widgets/feature_gate.dart';
import '../../shared/widgets/transaction_type_picker.dart';
import '../providers/app_settings_provider.dart';
import '../../l10n/app_localizations.dart';

/// Route path constants.
abstract class AppRoutes {
  // Auth & onboarding
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const signup = '/signup';
  static const setupStep1 = '/setup/step1';
  static const setupStep2 = '/setup/step2';
  static const setupStep3 = '/setup/step3';

  // Main shell tabs
  static const home = '/home';
  static const reports = '/reports';
  static const transactions = '/transactions';
  static const manage = '/manage';

  // Overlays & detail screens
  static const addTransaction = '/add-transaction';
  static const notifications = '/notifications';
  static const profile = '/profile';
  
  // Hub sub-screens
  static const inventory = '/manage/inventory';
  static const suppliers = '/manage/suppliers';
  static const categories = '/manage/categories';

  // Detail & Action screens
  static const transactionDetail = '/transactions/detail';
  static const productDetail = '/inventory/detail';
  static const breakdown = '/inventory/breakdown';
  static const missingCosts = '/inventory/missing-costs';
  static const supplierDetail = '/suppliers/detail';
  static const categoryDetail = '/categories/detail';
  static const scheduledTransactions = '/reports/scheduled_transactions';

  // Shopify
  static const shopify = '/manage/shopify';
  static const shopifySetupWizard = '/manage/shopify/setup';
  static const shopifyProductMappings = '/manage/shopify/products';
  static const shopifyImport = '/manage/shopify/import';
  static const shopifyInventorySync = '/manage/shopify/inventory';
  static const shopifySyncHistory = '/manage/shopify/history';

  // Bosta
  static const bosta = '/manage/bosta';
  static const bostaShipments = '/manage/bosta/shipments';
  static const bostaShipmentDetail = '/manage/bosta/shipments/detail';
  static const bostaAudit = '/manage/bosta/audit';
}

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Creates the app router with auth-aware redirects.
GoRouter createAppRouter(Ref ref, RouterNotifier notifier) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: notifier,
    debugLogDiagnostics: false,

    // ── Auth redirect ──────────────────────────────
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isAuth = authState.isAuthenticated;
      final currentPath = state.uri.path;

      // Public routes that don't require auth (and where auth users shouldn't be)
      const publicRoutes = [
        AppRoutes.splash,
        AppRoutes.onboarding,
        AppRoutes.login,
        AppRoutes.signup,
      ];

      final isPublicRoute = publicRoutes.contains(currentPath);

      // If NOT authenticated and trying to access a private route (or setup route), redirect to login
      if (!isAuth && !isPublicRoute && currentPath != AppRoutes.splash) {
        return AppRoutes.login;
      }

      // If authenticated and on a public auth route (like login/signup), go home.
      // (We intentionally do NOT redirect them if they are on a setup route)
      if (isAuth && isPublicRoute && currentPath != AppRoutes.splash) {
        return AppRoutes.home;
      }

      // Allow navigation to proceed naturally
      return null;
    },

    // ── Routes ─────────────────────────────────────
    routes: [
      // Splash screen
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // Onboarding
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),

      // Auth
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        name: 'SignUpScreen',
        builder: (context, state) => const SignUpScreen(),
      ),

      // Business setup
      GoRoute(
        path: AppRoutes.setupStep1,
        builder: (context, state) => const BusinessSetupStep1(),
      ),
      GoRoute(
        path: AppRoutes.setupStep2,
        builder: (context, state) => const BusinessSetupStep2(),
      ),
      GoRoute(
        path: AppRoutes.setupStep3,
        builder: (context, state) => const BusinessSetupStep3(),
      ),

      // ── Main Shell (bottom nav) ──────────────────
      ShellRoute(
        builder: (context, state, child) {
          return ScaffoldWithNavBar(child: child);
        },
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.reports,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ReportsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.transactions,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: TransactionsListScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.manage,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ManageScreen(),
            ),
          ),
        ],
      ),

      // Overlays (pushed on top of shell)
      GoRoute(
        path: AppRoutes.addTransaction,
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;
          final isExpense = args?['isExpense'] as bool? ?? true;
          final hideToggle = args?['hideToggle'] as bool? ?? false;
          return CustomTransitionPage(
            child: AddTransactionScreen(
              initialIsExpense: isExpense,
              hideToggle: hideToggle,
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              );
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        name: 'ScheduledTransactionsScreen',
        path: AppRoutes.scheduledTransactions,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.recurringTransactions,
          appBarTitle: AppLocalizations.of(context)!.scheduledTransactions,
          child: const ScheduledTransactionsScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        name: 'InventoryListScreen',
        path: AppRoutes.inventory,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const InventoryListScreen(),
      ),
      GoRoute(
        path: AppRoutes.suppliers,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.supplierManagement,
          appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
          child: const SuppliersOverviewScreen(),
        ),
      ),
      GoRoute(
        name: 'TransactionDetailScreen',
        path: AppRoutes.transactionDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return TransactionDetailScreen(transaction: args['transaction']);
        },
      ),
      GoRoute(
        name: 'ProductDetailScreen',
        path: AppRoutes.productDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return ProductDetailScreen(productId: args['productId'] ?? args['product']?.id ?? '');
        },
      ),
      GoRoute(
        name: 'SupplierDetailScreen',
        path: AppRoutes.supplierDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: SupplierDetailScreen(supplier: args['supplier']),
          );
        },
      ),
      GoRoute(
        name: 'CategoryDetailScreen',
        path: AppRoutes.categoryDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return CategoryDetailScreen(
            category: args['category'],
            month: args['month'] as DateTime?,
          );
        },
      ),
      GoRoute(
        name: 'EditTransactionScreen',
        path: '/transactions/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return EditTransactionScreen(transaction: args['transaction']);
        },
      ),
      GoRoute(
        name: 'EditProductScreen',
        path: '/inventory/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return EditProductScreen(productId: args['productId']);
        },
      ),
      GoRoute(
        name: 'MissingCostScreen',
        path: AppRoutes.missingCosts,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const MissingCostScreen(),
      ),
      GoRoute(
        name: 'BreakdownScreen',
        path: AppRoutes.breakdown,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return BreakdownScreen(productId: args['productId'] as String);
        },
      ),
      GoRoute(
        name: 'EditSupplierScreen',
        path: '/suppliers/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: EditSupplierScreen(supplier: args['supplier']),
          );
        },
      ),
      GoRoute(
        name: 'EditPaymentScreen',
        path: '/suppliers/payment/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: EditPaymentScreen(
              payment: args['payment'],
              supplierId: args['supplierId'],
            ),
          );
        },
      ),
      GoRoute(
        name: 'RecordPurchaseScreen',
        path: '/suppliers/purchase/record',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: RecordPurchaseScreen(
                preselectedSupplierId: args['preselectedSupplierId'],
              purchaseToEdit: args['purchaseToEdit'],
            ),
          );
        },
      ),
      GoRoute(
        name: 'RecordPaymentScreen',
        path: '/suppliers/payment/record',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: RecordPaymentScreen(
              preselectedSupplierId: args['preselectedSupplierId'],
              preselectedPurchaseId: args['preselectedPurchaseId'],
            ),
          );
        },
      ),
      GoRoute(
        name: 'EditCategoryScreen',
        path: '/categories/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return EditCategoryScreen(category: args['category']);
        },
      ),
      GoRoute(
        name: 'TransactionsListScreen',
        path: '/transactions/filtered',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return TransactionsListScreen(
            showBackButton: args['showBackButton'] ?? true,
            pageTitle: args['pageTitle'] ?? AppLocalizations.of(context)!.transactions,
            initialFilter: args['initialFilter'],
          );
        },
      ),
      GoRoute(
        name: 'PaymentDetailScreen',
        path: '/suppliers/payment/detail',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: PaymentDetailScreen(payment: args['payment'], supplier: args['supplier']),
          );
        },
      ),
      GoRoute(
        name: 'PurchaseDetailScreen',
        path: '/suppliers/purchase/detail',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: PurchaseDetailScreen(supplier: args['supplier'], purchase: args['purchase']),
          );
        },
      ),
      GoRoute(
        name: 'ReceiptDetailScreen',
        path: '/suppliers/receipt/detail',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          final receipt = args['receipt'];
          if (receipt is! GoodsReceipt) {
            return Scaffold(body: Center(child: Text(AppLocalizations.of(context)!.receiptNotFound)));
          }
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: ReceiptDetailScreen(receipt: receipt),
          );
        },
      ),
      GoRoute(
        name: 'EditReceiptScreen',
        path: '/suppliers/receipt/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          final receipt = args['receipt'];
          if (receipt is! GoodsReceipt) {
            return Scaffold(body: Center(child: Text(AppLocalizations.of(context)!.receiptNotFound)));
          }
          return FeatureGateScreen(
            feature: GrowthFeature.supplierManagement,
            appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
            child: EditReceiptScreen(receipt: receipt),
          );
        },
      ),
      GoRoute(
        name: 'AddProductScreen',
        path: '/inventory/add',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AddProductScreen(),
      ),
      GoRoute(
        name: 'AddMaterialScreen',
        path: '/inventory/add-material',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.rawMaterials,
          appBarTitle: AppLocalizations.of(context)!.addMaterial,
          child: const AddMaterialScreen(),
        ),
      ),
      GoRoute(
        name: 'AddSupplierScreen',
        path: '/suppliers/add',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.supplierManagement,
          appBarTitle: AppLocalizations.of(context)!.suppliersTitle,
          child: const AddSupplierScreen(),
        ),
      ),
      GoRoute(
        name: 'HubSettingsScreen',
        path: '/manage/settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.hubSettings,
          appBarTitle: AppLocalizations.of(context)!.hubSettings,
          child: const HubSettingsScreen(),
        ),
      ),
      GoRoute(
        name: 'ExportShareScreen',
        path: '/reports/export',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.exportReports,
          appBarTitle: AppLocalizations.of(context)!.exportAndShare,
          child: const ExportShareScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.categories,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CategoriesListScreen(),
      ),
      GoRoute(
        name: 'ManageCategoriesScreen',
        path: '/categories/manage',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ManageCategoriesScreen(),
      ),
      GoRoute(
        name: 'BudgetsOverviewScreen',
        path: '/categories/budgets',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.budgetLimits,
          appBarTitle: AppLocalizations.of(context)!.budgetsTitle,
          child: const BudgetsOverviewScreen(),
        ),
      ),
      GoRoute(
        name: 'EditProfileScreen',
        path: '/profile/edit',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        name: 'BusinessInfoScreen',
        path: '/profile/business-info',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const BusinessInfoScreen(),
      ),
      GoRoute(
        name: 'CurrencyLanguageScreen',
        path: '/profile/currency-language',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CurrencyLanguageScreen(),
      ),
      GoRoute(
        name: 'ManageSubscriptionScreen',
        path: '/profile/subscription',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ManageSubscriptionScreen(),
      ),
      GoRoute(
        name: 'BillingManagementScreen',
        path: '/profile/billing',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const BillingManagementScreen(),
      ),
      GoRoute(
        name: 'NotificationPreferencesScreen',
        path: '/profile/notification-prefs',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationPreferencesScreen(),
      ),
      GoRoute(
        name: 'SecurityScreen',
        path: '/profile/security',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SecurityScreen(),
      ),
      GoRoute(
        name: 'DataBackupScreen',
        path: '/profile/backup',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const DataBackupScreen(),
      ),
      GoRoute(
        name: 'HelpCenterScreen',
        path: '/profile/help',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const HelpCenterScreen(),
      ),
      GoRoute(
        name: 'AboutScreen',
        path: '/profile/about',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const AboutScreen(),
      ),
      GoRoute(
        name: 'PaymentsSummaryScreen',
        path: '/suppliers/payments',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.paymentsSummary,
          appBarTitle: AppLocalizations.of(context)!.paymentsDashboardTitle,
          child: const PaymentsSummaryScreen(),
        ),
      ),
      GoRoute(
        name: 'PurchasesSummaryScreen',
        path: '/suppliers/purchases',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.purchasesSummary,
          appBarTitle: AppLocalizations.of(context)!.purchasesDashboardTitle,
          child: const PurchasesSummaryScreen(),
        ),
      ),
      GoRoute(
        name: 'ReceivedGoodsSummaryScreen',
        path: '/suppliers/received-goods',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.goodsReceiving,
          appBarTitle: AppLocalizations.of(context)!.receivedGoods,
          child: const ReceivedGoodsSummaryScreen(),
        ),
      ),
      GoRoute(
        name: 'InventorySettingsScreen',
        path: '/inventory/settings',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.inventorySettings,
          appBarTitle: AppLocalizations.of(context)!.inventorySettings,
          child: const InventorySettingsScreen(),
        ),
      ),
      GoRoute(
        name: 'PinnedActionsScreen',
        path: '/manage/pinned',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.hubSettings,
          appBarTitle: AppLocalizations.of(context)!.pinnedActions,
          child: const PinnedActionsScreen(),
        ),
      ),
      GoRoute(
        name: 'AiChatScreen',
        path: '/ai',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
           final args = state.extra as Map<String, dynamic>? ?? {};
           return FeatureGateScreen(
             feature: GrowthFeature.aiChat,
             appBarTitle: AppLocalizations.of(context)!.aiInsightsTitle,
             child: AiChatScreen(contextType: args['contextType']),
           );
        },
      ),
      // ── Sales (Growth) ────────────────────────────────────
      GoRoute(
        name: 'SalesListScreen',
        path: '/sales',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.salesSystem,
          appBarTitle: AppLocalizations.of(context)!.salesTitle,
          child: const SalesListScreen(),
        ),
      ),
      GoRoute(
        name: 'SaleDetailScreen',
        path: '/sales/detail',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.salesSystem,
            appBarTitle: AppLocalizations.of(context)!.salesTitle,
            child: SaleDetailScreen(sale: args['sale']),
          );
        },
      ),
      GoRoute(
        name: 'RecordSaleScreen',
        path: '/sales/record',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>?;
          return FeatureGateScreen(
            feature: GrowthFeature.salesSystem,
            appBarTitle: AppLocalizations.of(context)!.salesTitle,
            child: RecordSaleScreen(
              existingSale: args?['sale'] as Sale?,
            ),
          );
        },
      ),
      GoRoute(
        name: 'ReceiveGoodsScreen',
        path: '/inventory/receive',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final args = state.extra as Map<String, dynamic>? ?? {};
          return FeatureGateScreen(
            feature: GrowthFeature.goodsReceiving,
            appBarTitle: AppLocalizations.of(context)!.receiveGoods,
            child: ReceiveGoodsScreen(
              preselectedSupplierId: args['preselectedSupplierId'] as String?,
              preselectedPurchaseId: args['preselectedPurchaseId'] as String?,
            ),
          );
        },
      ),
      // ── Shopify (Growth) ──────────────────────────────────
      GoRoute(
        name: 'ShopifyConnectScreen',
        path: AppRoutes.shopify,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.shopifyIntegration,
          appBarTitle: AppLocalizations.of(context)!.shopifyTitle,
          child: const ShopifyConnectScreen(),
        ),
      ),
      GoRoute(
        name: 'ShopifySetupWizard',
        path: AppRoutes.shopifySetupWizard,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.shopifyIntegration,
          appBarTitle: AppLocalizations.of(context)!.shopifySetup,
          child: const ShopifySetupWizardScreen(),
        ),
      ),
      GoRoute(
        name: 'ShopifyProductMappingScreen',
        path: AppRoutes.shopifyProductMappings,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.shopifyIntegration,
          appBarTitle: AppLocalizations.of(context)!.productMappingsTitle,
          child: const ShopifyProductMappingScreen(),
        ),
      ),
      GoRoute(
        name: 'ShopifyImportScreen',
        path: AppRoutes.shopifyImport,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.shopifyIntegration,
          appBarTitle: AppLocalizations.of(context)!.importOrders,
          child: const ShopifyImportScreen(),
        ),
      ),
      GoRoute(
        name: 'ShopifyInventorySyncScreen',
        path: AppRoutes.shopifyInventorySync,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.shopifyIntegration,
          appBarTitle: AppLocalizations.of(context)!.inventorySyncLabel,
          child: const ShopifyInventorySyncScreen(),
        ),
      ),
      GoRoute(
        name: 'ShopifySyncHistoryScreen',
        path: AppRoutes.shopifySyncHistory,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.shopifyIntegration,
          appBarTitle: AppLocalizations.of(context)!.syncHistoryTitle,
          child: const ShopifySyncHistoryScreen(),
        ),
      ),

      // ── Bosta ──────────────────────────────────────────
      GoRoute(
        name: 'BostaConnectScreen',
        path: AppRoutes.bosta,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.bostaIntegration,
          appBarTitle: AppLocalizations.of(context)!.bostaTitle,
          child: const BostaConnectScreen(),
        ),
      ),
      GoRoute(
        name: 'BostaShipmentsScreen',
        path: AppRoutes.bostaShipments,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => FeatureGateScreen(
          feature: GrowthFeature.bostaIntegration,
          appBarTitle: AppLocalizations.of(context)!.bostaShipmentsTitle,
          child: const BostaShipmentsScreen(),
        ),
      ),
      GoRoute(
        name: 'BostaShipmentDetailScreen',
        path: AppRoutes.bostaShipmentDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return BostaShipmentDetailScreen(
            shipment: extra['shipment'] as BostaShipment,
          );
        },
      ),
      GoRoute(
        name: 'BostaAuditScreen',
        path: AppRoutes.bostaAudit,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const BostaAuditScreen(),
      ),
    ],
  );
}

/// Riverpod provider for the router.
final routerProvider = Provider<GoRouter>((ref) {
  final notifier = RouterNotifier(ref);
  return createAppRouter(ref, notifier);
});

/// A notifier that triggers a router redirect whenever auth state changes.
class RouterNotifier extends ChangeNotifier {
  final Ref _ref;
  RouterNotifier(this._ref) {
    _ref.listen<AuthState>(authProvider, (_, _) {
      notifyListeners();
    });
  }
}

// ═══════════════════════════════════════════════════════════
// SCAFFOLD WITH NAV BAR — replaces MainShell's IndexedStack
// ═══════════════════════════════════════════════════════════

class ScaffoldWithNavBar extends StatelessWidget {
  final Widget child;

  const ScaffoldWithNavBar({super.key, required this.child});

  static int _locationToIndex(String location) {
    if (location.startsWith(AppRoutes.home)) return 0;
    if (location.startsWith(AppRoutes.transactions)) return 1;
    if (location.startsWith(AppRoutes.reports)) return 3;
    if (location.startsWith(AppRoutes.manage)) return 4;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final currentIndex = _locationToIndex(location);

    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: _FloatingNavBar(
        currentIndex: currentIndex,
        onFabTap: () => _onFabTap(context),
        onTabTap: (route) => context.go(route),
      ),
    );
  }

  void _onFabTap(BuildContext context) async {
    final type = await showTransactionTypePicker(context);
    if (type == null || !context.mounted) return;
    switch (type) {
      case TransactionType.sale:
        context.push('/sales/record');
      case TransactionType.expense:
        context.push(AppRoutes.addTransaction,
            extra: {'isExpense': true, 'hideToggle': true});
      case TransactionType.otherIncome:
        context.push(AppRoutes.addTransaction,
            extra: {'isExpense': false, 'hideToggle': true});
    }
  }
}

/// Modern floating bottom nav bar with center FAB.
class _FloatingNavBar extends StatelessWidget {
  final int currentIndex;
  final VoidCallback onFabTap;
  final ValueChanged<String> onTabTap;

  const _FloatingNavBar({
    required this.currentIndex,
    required this.onFabTap,
    required this.onTabTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B4F72).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 4),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              // Left tabs
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _NavTab(
                      icon: Icons.home_rounded,
                      label: l10n.home,
                      isSelected: currentIndex == 0,
                      onTap: () => onTabTap(AppRoutes.home),
                    ),
                    _NavTab(
                      icon: Icons.receipt_long_rounded,
                      label: l10n.transactions,
                      isSelected: currentIndex == 1,
                      onTap: () => onTabTap(AppRoutes.transactions),
                    ),
                  ],
                ),
              ),

              // Center FAB
              GestureDetector(
                onTap: onFabTap,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFF8C42), Color(0xFFE67E22)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(0xFFE67E22).withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add_rounded,
                      color: Colors.white, size: 26),
                ),
              ),

              // Right tabs
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _NavTab(
                      icon: Icons.pie_chart_rounded,
                      label: l10n.reports,
                      isSelected: currentIndex == 3,
                      onTap: () => onTabTap(AppRoutes.reports),
                    ),
                    _NavTab(
                      icon: Icons.grid_view_rounded,
                      label: l10n.manage,
                      isSelected: currentIndex == 4,
                      onTap: () => onTabTap(AppRoutes.manage),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Single nav tab with active pill indicator.
class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  static const _active = Color(0xFF1B4F72);
  static const _inactive = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label tab',
      button: true,
      selected: isSelected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Active pill indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                width: isSelected ? 32 : 0,
                height: 3,
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: isSelected ? _active : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(
                icon,
                size: 22,
                color: isSelected ? _active : _inactive,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  color: isSelected ? _active : _inactive,
                  letterSpacing: isSelected ? 0.2 : 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

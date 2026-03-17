import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'Masari App'**
  String get appTitle;

  /// No description provided for @greetingMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning,'**
  String get greetingMorning;

  /// No description provided for @greetingAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon,'**
  String get greetingAfternoon;

  /// No description provided for @greetingEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening,'**
  String get greetingEvening;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @transactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactions;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @revenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get revenue;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @netProfit.
  ///
  /// In en, this message translates to:
  /// **'Net Profit'**
  String get netProfit;

  /// No description provided for @grossProfit.
  ///
  /// In en, this message translates to:
  /// **'Gross Profit'**
  String get grossProfit;

  /// No description provided for @costOfSales.
  ///
  /// In en, this message translates to:
  /// **'Cost of Sales'**
  String get costOfSales;

  /// No description provided for @costOfGoodsSold.
  ///
  /// In en, this message translates to:
  /// **'Cost of Goods Sold'**
  String get costOfGoodsSold;

  /// No description provided for @operatingExpenses.
  ///
  /// In en, this message translates to:
  /// **'Operating Expenses'**
  String get operatingExpenses;

  /// No description provided for @operatingExp.
  ///
  /// In en, this message translates to:
  /// **'Operating Exp'**
  String get operatingExp;

  /// No description provided for @incomeStatement.
  ///
  /// In en, this message translates to:
  /// **'Income Statement'**
  String get incomeStatement;

  /// No description provided for @revenueSources.
  ///
  /// In en, this message translates to:
  /// **'Revenue Sources'**
  String get revenueSources;

  /// No description provided for @totalAssets.
  ///
  /// In en, this message translates to:
  /// **'Total Assets'**
  String get totalAssets;

  /// No description provided for @totalLiabilities.
  ///
  /// In en, this message translates to:
  /// **'Total Liabilities'**
  String get totalLiabilities;

  /// No description provided for @ownersEquity.
  ///
  /// In en, this message translates to:
  /// **'Owner\'s Equity'**
  String get ownersEquity;

  /// No description provided for @netWorth.
  ///
  /// In en, this message translates to:
  /// **'Net Worth'**
  String get netWorth;

  /// No description provided for @balanceSheet.
  ///
  /// In en, this message translates to:
  /// **'Balance Sheet'**
  String get balanceSheet;

  /// No description provided for @whatYouOwn.
  ///
  /// In en, this message translates to:
  /// **'What You Own'**
  String get whatYouOwn;

  /// No description provided for @whatYouOwe.
  ///
  /// In en, this message translates to:
  /// **'What You Owe'**
  String get whatYouOwe;

  /// No description provided for @lessTotalLiabilities.
  ///
  /// In en, this message translates to:
  /// **'Less: Total Liabilities'**
  String get lessTotalLiabilities;

  /// No description provided for @accountingEquationBalanced.
  ///
  /// In en, this message translates to:
  /// **'Assets = Liabilities + Equity  ✓'**
  String get accountingEquationBalanced;

  /// No description provided for @accountingEquationUnbalanced.
  ///
  /// In en, this message translates to:
  /// **'Assets ≠ Liabilities + Equity  ✗'**
  String get accountingEquationUnbalanced;

  /// No description provided for @currentPeriodNetIncome.
  ///
  /// In en, this message translates to:
  /// **'Current Period Net Income'**
  String get currentPeriodNetIncome;

  /// No description provided for @assets.
  ///
  /// In en, this message translates to:
  /// **'Assets'**
  String get assets;

  /// No description provided for @liabilities.
  ///
  /// In en, this message translates to:
  /// **'Liabilities'**
  String get liabilities;

  /// No description provided for @distribution.
  ///
  /// In en, this message translates to:
  /// **'Distribution'**
  String get distribution;

  /// No description provided for @netWorthTrend.
  ///
  /// In en, this message translates to:
  /// **'NET WORTH TREND'**
  String get netWorthTrend;

  /// No description provided for @netEquityPosition.
  ///
  /// In en, this message translates to:
  /// **'NET EQUITY POSITION'**
  String get netEquityPosition;

  /// No description provided for @bankAccounts.
  ///
  /// In en, this message translates to:
  /// **'Cash & Bank'**
  String get bankAccounts;

  /// No description provided for @cashOnHand.
  ///
  /// In en, this message translates to:
  /// **'Cash Adjustment'**
  String get cashOnHand;

  /// No description provided for @inventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventory;

  /// No description provided for @otherReceivables.
  ///
  /// In en, this message translates to:
  /// **'Other Receivables'**
  String get otherReceivables;

  /// No description provided for @salesReceivables.
  ///
  /// In en, this message translates to:
  /// **'Accounts Receivable'**
  String get salesReceivables;

  /// No description provided for @supplierPrepayments.
  ///
  /// In en, this message translates to:
  /// **'Supplier Prepayments'**
  String get supplierPrepayments;

  /// No description provided for @supplierPayable.
  ///
  /// In en, this message translates to:
  /// **'Supplier Payable'**
  String get supplierPayable;

  /// No description provided for @loans.
  ///
  /// In en, this message translates to:
  /// **'Loans'**
  String get loans;

  /// No description provided for @unpaidSalaries.
  ///
  /// In en, this message translates to:
  /// **'Unpaid Salaries'**
  String get unpaidSalaries;

  /// No description provided for @openingCashBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening Cash Balance'**
  String get openingCashBalance;

  /// No description provided for @currentCashBalance.
  ///
  /// In en, this message translates to:
  /// **'Current Cash Balance'**
  String get currentCashBalance;

  /// No description provided for @cashFlow.
  ///
  /// In en, this message translates to:
  /// **'Cash Flow'**
  String get cashFlow;

  /// No description provided for @cashMovement.
  ///
  /// In en, this message translates to:
  /// **'Cash Movement'**
  String get cashMovement;

  /// No description provided for @moneyIn.
  ///
  /// In en, this message translates to:
  /// **'Money In'**
  String get moneyIn;

  /// No description provided for @moneyOut.
  ///
  /// In en, this message translates to:
  /// **'Money Out'**
  String get moneyOut;

  /// No description provided for @lowCashAlert.
  ///
  /// In en, this message translates to:
  /// **'Low Cash Alert'**
  String get lowCashAlert;

  /// No description provided for @aiForecastComingSoon.
  ///
  /// In en, this message translates to:
  /// **'AI Forecast (Coming Soon)'**
  String get aiForecastComingSoon;

  /// No description provided for @monthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthly;

  /// No description provided for @yearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly'**
  String get yearly;

  /// No description provided for @noActivityYet.
  ///
  /// In en, this message translates to:
  /// **'No activity yet'**
  String get noActivityYet;

  /// No description provided for @breakingEven.
  ///
  /// In en, this message translates to:
  /// **'Breaking even'**
  String get breakingEven;

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoon;

  /// No description provided for @askAiSoon.
  ///
  /// In en, this message translates to:
  /// **'Ask AI (Soon)'**
  String get askAiSoon;

  /// No description provided for @aiInsightsComingSoon.
  ///
  /// In en, this message translates to:
  /// **'AI Insights — coming soon!'**
  String get aiInsightsComingSoon;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get somethingWentWrong;

  /// No description provided for @orderDetails.
  ///
  /// In en, this message translates to:
  /// **'Order Details'**
  String get orderDetails;

  /// No description provided for @editOrder.
  ///
  /// In en, this message translates to:
  /// **'Edit Order'**
  String get editOrder;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get cancelOrder;

  /// No description provided for @orderStatus.
  ///
  /// In en, this message translates to:
  /// **'Order Status'**
  String get orderStatus;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmed;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @paid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// No description provided for @partial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get partial;

  /// No description provided for @unpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get unpaid;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @tax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get tax;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @cogs.
  ///
  /// In en, this message translates to:
  /// **'COGS'**
  String get cogs;

  /// No description provided for @outstanding.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get outstanding;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @amountPaid.
  ///
  /// In en, this message translates to:
  /// **'Amount Paid'**
  String get amountPaid;

  /// No description provided for @shipping.
  ///
  /// In en, this message translates to:
  /// **'Shipping'**
  String get shipping;

  /// No description provided for @shippingCost.
  ///
  /// In en, this message translates to:
  /// **'Shipping Cost'**
  String get shippingCost;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @tracking.
  ///
  /// In en, this message translates to:
  /// **'Tracking'**
  String get tracking;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @vsLastMonth.
  ///
  /// In en, this message translates to:
  /// **'vs last mo'**
  String get vsLastMonth;

  /// No description provided for @sixMonthTrend.
  ///
  /// In en, this message translates to:
  /// **'6-Month Trend'**
  String get sixMonthTrend;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @walkInCustomer.
  ///
  /// In en, this message translates to:
  /// **'Walk-in Customer'**
  String get walkInCustomer;

  /// No description provided for @downloadReport.
  ///
  /// In en, this message translates to:
  /// **'Download Report'**
  String get downloadReport;

  /// No description provided for @viewFullAnalysis.
  ///
  /// In en, this message translates to:
  /// **'View Full Analysis'**
  String get viewFullAnalysis;

  /// No description provided for @noUpcomingPayments.
  ///
  /// In en, this message translates to:
  /// **'No upcoming payments'**
  String get noUpcomingPayments;

  /// No description provided for @comingUp.
  ///
  /// In en, this message translates to:
  /// **'Coming Up'**
  String get comingUp;

  /// No description provided for @invoiced.
  ///
  /// In en, this message translates to:
  /// **'Invoiced'**
  String get invoiced;

  /// No description provided for @saleAction.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get saleAction;

  /// No description provided for @expense.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expense;

  /// No description provided for @product.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get product;

  /// No description provided for @importAction.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importAction;

  /// No description provided for @profitMargins.
  ///
  /// In en, this message translates to:
  /// **'Profit Margins'**
  String get profitMargins;

  /// No description provided for @grossMargin.
  ///
  /// In en, this message translates to:
  /// **'Gross Margin'**
  String get grossMargin;

  /// No description provided for @netMargin.
  ///
  /// In en, this message translates to:
  /// **'Net Margin'**
  String get netMargin;

  /// No description provided for @cogsRatio.
  ///
  /// In en, this message translates to:
  /// **'COGS Ratio'**
  String get cogsRatio;

  /// No description provided for @topProducts.
  ///
  /// In en, this message translates to:
  /// **'Top Products'**
  String get topProducts;

  /// No description provided for @viewAll.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAll;

  /// No description provided for @inventoryValuation.
  ///
  /// In en, this message translates to:
  /// **'Inventory Valuation'**
  String get inventoryValuation;

  /// No description provided for @costValue.
  ///
  /// In en, this message translates to:
  /// **'Cost Value'**
  String get costValue;

  /// No description provided for @retailValue.
  ///
  /// In en, this message translates to:
  /// **'Retail Value'**
  String get retailValue;

  /// No description provided for @potentialProfit.
  ///
  /// In en, this message translates to:
  /// **'Potential Profit'**
  String get potentialProfit;

  /// No description provided for @totalSkus.
  ///
  /// In en, this message translates to:
  /// **'Total SKUs'**
  String get totalSkus;

  /// No description provided for @lowStockAlerts.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alerts'**
  String get lowStockAlerts;

  /// No description provided for @outOfStockStatus.
  ///
  /// In en, this message translates to:
  /// **'Out of Stock'**
  String get outOfStockStatus;

  /// No description provided for @receivable.
  ///
  /// In en, this message translates to:
  /// **'Receivable'**
  String get receivable;

  /// No description provided for @payable.
  ///
  /// In en, this message translates to:
  /// **'Payable'**
  String get payable;

  /// No description provided for @enterMaterialNameFirst.
  ///
  /// In en, this message translates to:
  /// **'Enter material name first'**
  String get enterMaterialNameFirst;

  /// No description provided for @rawMaterial.
  ///
  /// In en, this message translates to:
  /// **'Raw Material'**
  String get rawMaterial;

  /// No description provided for @materialName.
  ///
  /// In en, this message translates to:
  /// **'Material Name'**
  String get materialName;

  /// No description provided for @egCottonFabric.
  ///
  /// In en, this message translates to:
  /// **'e.g. Cotton Fabric'**
  String get egCottonFabric;

  /// No description provided for @skuRefCode.
  ///
  /// In en, this message translates to:
  /// **'SKU / Ref Code'**
  String get skuRefCode;

  /// No description provided for @categoryOptional.
  ///
  /// In en, this message translates to:
  /// **'Category (Optional)'**
  String get categoryOptional;

  /// No description provided for @egFabricChemicals.
  ///
  /// In en, this message translates to:
  /// **'e.g. Fabric, Chemicals'**
  String get egFabricChemicals;

  /// No description provided for @supplierOptional.
  ///
  /// In en, this message translates to:
  /// **'Supplier (Optional)'**
  String get supplierOptional;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @typeSupplierName.
  ///
  /// In en, this message translates to:
  /// **'Type supplier name'**
  String get typeSupplierName;

  /// No description provided for @noSuppliersYet.
  ///
  /// In en, this message translates to:
  /// **'No suppliers yet'**
  String get noSuppliersYet;

  /// No description provided for @costPricePerUnit.
  ///
  /// In en, this message translates to:
  /// **'Cost Price per Unit'**
  String get costPricePerUnit;

  /// No description provided for @unitOfMeasure.
  ///
  /// In en, this message translates to:
  /// **'Unit of Measure'**
  String get unitOfMeasure;

  /// No description provided for @startingStock.
  ///
  /// In en, this message translates to:
  /// **'Starting Stock'**
  String get startingStock;

  /// No description provided for @reorderPoint.
  ///
  /// In en, this message translates to:
  /// **'Reorder Point'**
  String get reorderPoint;

  /// No description provided for @materialProperties.
  ///
  /// In en, this message translates to:
  /// **'Material Properties'**
  String get materialProperties;

  /// No description provided for @baseType.
  ///
  /// In en, this message translates to:
  /// **'Base Type'**
  String get baseType;

  /// No description provided for @wasteScrapPercentage.
  ///
  /// In en, this message translates to:
  /// **'Waste / Scrap %'**
  String get wasteScrapPercentage;

  /// No description provided for @storageLocation.
  ///
  /// In en, this message translates to:
  /// **'Storage Location'**
  String get storageLocation;

  /// No description provided for @egWarehouseShelf.
  ///
  /// In en, this message translates to:
  /// **'e.g. Warehouse A, Shelf 3'**
  String get egWarehouseShelf;

  /// No description provided for @anyExtraNotes.
  ///
  /// In en, this message translates to:
  /// **'Any extra notes'**
  String get anyExtraNotes;

  /// No description provided for @noCostRecorded.
  ///
  /// In en, this message translates to:
  /// **'No cost recorded'**
  String get noCostRecorded;

  /// No description provided for @costForAllVariants.
  ///
  /// In en, this message translates to:
  /// **'Cost for all variants'**
  String get costForAllVariants;

  /// No description provided for @enterValidQuantity.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid quantity'**
  String get enterValidQuantity;

  /// No description provided for @breakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get breakdown;

  /// No description provided for @noBreakdownRecipeFound.
  ///
  /// In en, this message translates to:
  /// **'No breakdown recipe found'**
  String get noBreakdownRecipeFound;

  /// No description provided for @sourceVariantNotFound.
  ///
  /// In en, this message translates to:
  /// **'Source variant not found'**
  String get sourceVariantNotFound;

  /// No description provided for @quantityToBreakDown.
  ///
  /// In en, this message translates to:
  /// **'Quantity to break down'**
  String get quantityToBreakDown;

  /// No description provided for @pullFromShopify.
  ///
  /// In en, this message translates to:
  /// **'Pull from Shopify'**
  String get pullFromShopify;

  /// No description provided for @pushToShopify.
  ///
  /// In en, this message translates to:
  /// **'Push to Shopify'**
  String get pushToShopify;

  /// No description provided for @fetchPreview.
  ///
  /// In en, this message translates to:
  /// **'Fetch Preview'**
  String get fetchPreview;

  /// No description provided for @selectProductsToPreview.
  ///
  /// In en, this message translates to:
  /// **'Select products to preview'**
  String get selectProductsToPreview;

  /// No description provided for @dateRangeSection.
  ///
  /// In en, this message translates to:
  /// **'Date Range'**
  String get dateRangeSection;

  /// No description provided for @from.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get from;

  /// No description provided for @to.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get to;

  /// No description provided for @importOrders.
  ///
  /// In en, this message translates to:
  /// **'Import Orders'**
  String get importOrders;

  /// No description provided for @importComplete.
  ///
  /// In en, this message translates to:
  /// **'Import Complete'**
  String get importComplete;

  /// No description provided for @connectionError.
  ///
  /// In en, this message translates to:
  /// **'Connection Error'**
  String get connectionError;

  /// No description provided for @shopifyOrder.
  ///
  /// In en, this message translates to:
  /// **'Shopify Order'**
  String get shopifyOrder;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @clearAllLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear All Logs'**
  String get clearAllLogs;

  /// No description provided for @clearSyncHistory.
  ///
  /// In en, this message translates to:
  /// **'Clear Sync History'**
  String get clearSyncHistory;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @errorCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Error copied to clipboard'**
  String get errorCopiedToClipboard;

  /// No description provided for @editReceipt.
  ///
  /// In en, this message translates to:
  /// **'Edit Receipt'**
  String get editReceipt;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @received.
  ///
  /// In en, this message translates to:
  /// **'Received'**
  String get received;

  /// No description provided for @unitCost.
  ///
  /// In en, this message translates to:
  /// **'Unit Cost'**
  String get unitCost;

  /// No description provided for @deliveryNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Delivery notes (optional)'**
  String get deliveryNotesOptional;

  /// No description provided for @receiptUpdated.
  ///
  /// In en, this message translates to:
  /// **'Receipt updated'**
  String get receiptUpdated;

  /// No description provided for @purchasesWithReceipts.
  ///
  /// In en, this message translates to:
  /// **'Purchases with Receipts'**
  String get purchasesWithReceipts;

  /// No description provided for @unlinkedReceipts.
  ///
  /// In en, this message translates to:
  /// **'Unlinked Receipts'**
  String get unlinkedReceipts;

  /// No description provided for @awaitingReceipt.
  ///
  /// In en, this message translates to:
  /// **'Awaiting Receipt'**
  String get awaitingReceipt;

  /// No description provided for @noReceivedGoodsYet.
  ///
  /// In en, this message translates to:
  /// **'No received goods yet'**
  String get noReceivedGoodsYet;

  /// No description provided for @recordGoodsReceiptHelp.
  ///
  /// In en, this message translates to:
  /// **'Record goods received from suppliers to track inventory and costs.'**
  String get recordGoodsReceiptHelp;

  /// No description provided for @receiveGoods.
  ///
  /// In en, this message translates to:
  /// **'Receive Goods'**
  String get receiveGoods;

  /// No description provided for @receivedGoods.
  ///
  /// In en, this message translates to:
  /// **'Received Goods'**
  String get receivedGoods;

  /// No description provided for @totalReceivedValue.
  ///
  /// In en, this message translates to:
  /// **'Total Received Value'**
  String get totalReceivedValue;

  /// No description provided for @viewDetails.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetails;

  /// No description provided for @categorizeTransactions.
  ///
  /// In en, this message translates to:
  /// **'Categorize Transactions'**
  String get categorizeTransactions;

  /// No description provided for @setCategory.
  ///
  /// In en, this message translates to:
  /// **'Set Category'**
  String get setCategory;

  /// No description provided for @takePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// No description provided for @chooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get chooseFromGallery;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @recordSaleOrder.
  ///
  /// In en, this message translates to:
  /// **'Record Sale Order'**
  String get recordSaleOrder;

  /// No description provided for @recordPaymentOut.
  ///
  /// In en, this message translates to:
  /// **'Record Payment Out'**
  String get recordPaymentOut;

  /// No description provided for @otherIncome.
  ///
  /// In en, this message translates to:
  /// **'Other Income'**
  String get otherIncome;

  /// No description provided for @recordOtherIncome.
  ///
  /// In en, this message translates to:
  /// **'Record Other Income'**
  String get recordOtherIncome;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes'**
  String get discardChanges;

  /// No description provided for @keepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep Editing'**
  String get keepEditing;

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @trackProfitability.
  ///
  /// In en, this message translates to:
  /// **'Track profitability'**
  String get trackProfitability;

  /// No description provided for @controlCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Control cash flow'**
  String get controlCashFlow;

  /// No description provided for @growMyBusiness.
  ///
  /// In en, this message translates to:
  /// **'Grow my business'**
  String get growMyBusiness;

  /// No description provided for @createFinancialReports.
  ///
  /// In en, this message translates to:
  /// **'Create financial reports'**
  String get createFinancialReports;

  /// No description provided for @plYouEarned.
  ///
  /// In en, this message translates to:
  /// **'You earned {currency} {amount}!'**
  String plYouEarned(String currency, String amount);

  /// No description provided for @plProfitMarginBody.
  ///
  /// In en, this message translates to:
  /// **'Your profit margin is {margin}%. Keep tracking expenses to maintain momentum.'**
  String plProfitMarginBody(String margin);

  /// No description provided for @plBreakingEvenBody.
  ///
  /// In en, this message translates to:
  /// **'Your income exactly covers your expenses. Look for ways to increase revenue or reduce costs.'**
  String get plBreakingEvenBody;

  /// No description provided for @plYouLost.
  ///
  /// In en, this message translates to:
  /// **'You lost {currency} {amount}'**
  String plYouLost(String currency, String amount);

  /// No description provided for @plLossBody.
  ///
  /// In en, this message translates to:
  /// **'Your expenses exceeded your income this period. Review your spending to find areas to cut back.'**
  String get plLossBody;

  /// No description provided for @plUpVsPrevious.
  ///
  /// In en, this message translates to:
  /// **'↑ {pct}% vs previous period'**
  String plUpVsPrevious(String pct);

  /// No description provided for @plDownVsPrevious.
  ///
  /// In en, this message translates to:
  /// **'↓ {pct}% vs previous period'**
  String plDownVsPrevious(String pct);

  /// No description provided for @noActivityInPreviousPeriod.
  ///
  /// In en, this message translates to:
  /// **'No activity in previous period'**
  String get noActivityInPreviousPeriod;

  /// No description provided for @failedToLoadTransactions.
  ///
  /// In en, this message translates to:
  /// **'Failed to load transactions'**
  String get failedToLoadTransactions;

  /// No description provided for @pullDownToRetry.
  ///
  /// In en, this message translates to:
  /// **'Pull down to retry.'**
  String get pullDownToRetry;

  /// No description provided for @noActivityForThisPeriod.
  ///
  /// In en, this message translates to:
  /// **'No activity for this period'**
  String get noActivityForThisPeriod;

  /// No description provided for @recordSaleOrExpense.
  ///
  /// In en, this message translates to:
  /// **'Record a sale or expense to see your\nprofit & loss report come to life.'**
  String get recordSaleOrExpense;

  /// No description provided for @addTransaction.
  ///
  /// In en, this message translates to:
  /// **'Add Transaction'**
  String get addTransaction;

  /// No description provided for @openingCashHelpText.
  ///
  /// In en, this message translates to:
  /// **'How much cash did you start with before using Masari?'**
  String get openingCashHelpText;

  /// No description provided for @tapToSetStartingCash.
  ///
  /// In en, this message translates to:
  /// **'Tap to set your starting cash'**
  String get tapToSetStartingCash;

  /// No description provided for @openingCashDialogDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter the cash you had before you started tracking transactions in Masari.'**
  String get openingCashDialogDesc;

  /// No description provided for @lowCashAlertBody.
  ///
  /// In en, this message translates to:
  /// **'Your current balance is critically low. Consider reviewing upcoming expenses to avoid a negative balance.'**
  String get lowCashAlertBody;

  /// No description provided for @forecastPositive.
  ///
  /// In en, this message translates to:
  /// **'Based on your recent transaction patterns, you should reach a healthy {currency} {amount} by the end of the month.'**
  String forecastPositive(String currency, String amount);

  /// No description provided for @forecastNegative.
  ///
  /// In en, this message translates to:
  /// **'Based on your recent spending, your balance may dip to {currency} {amount} by month-end. Consider cutting back on expenses.'**
  String forecastNegative(String currency, String amount);

  /// No description provided for @vsLastMonthLabel.
  ///
  /// In en, this message translates to:
  /// **'vs last month'**
  String get vsLastMonthLabel;

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueToday;

  /// No description provided for @dueTomorrow.
  ///
  /// In en, this message translates to:
  /// **'Due tomorrow'**
  String get dueTomorrow;

  /// No description provided for @dueInDays.
  ///
  /// In en, this message translates to:
  /// **'Due in {days} days'**
  String dueInDays(int days);

  /// No description provided for @addLastMonthTrend.
  ///
  /// In en, this message translates to:
  /// **'Add last month\'s data to see trend'**
  String get addLastMonthTrend;

  /// No description provided for @shareReport.
  ///
  /// In en, this message translates to:
  /// **'Share Report'**
  String get shareReport;

  /// No description provided for @pnlStatement.
  ///
  /// In en, this message translates to:
  /// **'Profit & Loss Statement'**
  String get pnlStatement;

  /// No description provided for @totalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Revenue'**
  String get totalRevenue;

  /// No description provided for @salesRevenue.
  ///
  /// In en, this message translates to:
  /// **'Sales Revenue'**
  String get salesRevenue;

  /// No description provided for @cashFlowStatement.
  ///
  /// In en, this message translates to:
  /// **'Cash Flow Statement'**
  String get cashFlowStatement;

  /// No description provided for @totalInflow.
  ///
  /// In en, this message translates to:
  /// **'Total Inflow'**
  String get totalInflow;

  /// No description provided for @totalOutflow.
  ///
  /// In en, this message translates to:
  /// **'Total Outflow'**
  String get totalOutflow;

  /// No description provided for @netCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Net Cash Flow'**
  String get netCashFlow;

  /// No description provided for @cashInflows.
  ///
  /// In en, this message translates to:
  /// **'Cash Inflows'**
  String get cashInflows;

  /// No description provided for @cashOutflows.
  ///
  /// In en, this message translates to:
  /// **'Cash Outflows'**
  String get cashOutflows;

  /// No description provided for @openingBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening Balance'**
  String get openingBalance;

  /// No description provided for @closingBalance.
  ///
  /// In en, this message translates to:
  /// **'Closing Balance'**
  String get closingBalance;

  /// No description provided for @totalCashInflow.
  ///
  /// In en, this message translates to:
  /// **'Total Cash Inflow'**
  String get totalCashInflow;

  /// No description provided for @totalCashOutflow.
  ///
  /// In en, this message translates to:
  /// **'Total Cash Outflow'**
  String get totalCashOutflow;

  /// No description provided for @monthlyFinancialReport.
  ///
  /// In en, this message translates to:
  /// **'Monthly Financial Report'**
  String get monthlyFinancialReport;

  /// No description provided for @profitAndLoss.
  ///
  /// In en, this message translates to:
  /// **'Profit & Loss'**
  String get profitAndLoss;

  /// No description provided for @cashInflowLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash Inflow'**
  String get cashInflowLabel;

  /// No description provided for @cashOutflowLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash Outflow'**
  String get cashOutflowLabel;

  /// No description provided for @salesOverview.
  ///
  /// In en, this message translates to:
  /// **'Sales Overview'**
  String get salesOverview;

  /// No description provided for @totalOrders.
  ///
  /// In en, this message translates to:
  /// **'Total Orders'**
  String get totalOrders;

  /// No description provided for @totalSalesValue.
  ///
  /// In en, this message translates to:
  /// **'Total Sales Value'**
  String get totalSalesValue;

  /// No description provided for @inventorySnapshot.
  ///
  /// In en, this message translates to:
  /// **'Inventory Snapshot'**
  String get inventorySnapshot;

  /// No description provided for @totalInventoryValue.
  ///
  /// In en, this message translates to:
  /// **'Total Inventory Value'**
  String get totalInventoryValue;

  /// No description provided for @netEquity.
  ///
  /// In en, this message translates to:
  /// **'Net Equity'**
  String get netEquity;

  /// No description provided for @noDataForPeriod.
  ///
  /// In en, this message translates to:
  /// **'No data for this period'**
  String get noDataForPeriod;

  /// No description provided for @amountWithCurrency.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String amountWithCurrency(String currency);

  /// No description provided for @assetsSection.
  ///
  /// In en, this message translates to:
  /// **'Assets (What You Own)'**
  String get assetsSection;

  /// No description provided for @liabilitiesSection.
  ///
  /// In en, this message translates to:
  /// **'Liabilities (What You Owe)'**
  String get liabilitiesSection;

  /// No description provided for @unpaidInvoices.
  ///
  /// In en, this message translates to:
  /// **'Other Receivables'**
  String get unpaidInvoices;

  /// No description provided for @receivables.
  ///
  /// In en, this message translates to:
  /// **'Accounts Receivable'**
  String get receivables;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get lowStock;

  /// No description provided for @asOfDate.
  ///
  /// In en, this message translates to:
  /// **'As of {date}'**
  String asOfDate(String date);

  /// No description provided for @yearPeriod.
  ///
  /// In en, this message translates to:
  /// **'Year {year}'**
  String yearPeriod(int year);

  /// No description provided for @shareSummary.
  ///
  /// In en, this message translates to:
  /// **'Share Summary'**
  String get shareSummary;

  /// No description provided for @editField.
  ///
  /// In en, this message translates to:
  /// **'Edit {field}'**
  String editField(String field);

  /// No description provided for @currentValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Current value: {currency} {value}'**
  String currentValueLabel(String currency, String value);

  /// No description provided for @enterAnAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount'**
  String get enterAnAmount;

  /// No description provided for @enterAValidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get enterAValidNumber;

  /// No description provided for @amountCannotBeNegative.
  ///
  /// In en, this message translates to:
  /// **'Amount cannot be negative'**
  String get amountCannotBeNegative;

  /// No description provided for @aiAnalysisComingSoon.
  ///
  /// In en, this message translates to:
  /// **'AI analysis — coming soon!'**
  String get aiAnalysisComingSoon;

  /// No description provided for @bsInsightEmpty.
  ///
  /// In en, this message translates to:
  /// **'Start by adding your cash & bank balances, cash adjustments, and liabilities to get a snapshot of your financial position.'**
  String get bsInsightEmpty;

  /// No description provided for @bsInsightHighDebt.
  ///
  /// In en, this message translates to:
  /// **'Your debt-to-asset ratio is {ratio}%, which is high. Consider prioritizing debt repayment to improve your financial health.'**
  String bsInsightHighDebt(String ratio);

  /// No description provided for @bsInsightModerateDebt.
  ///
  /// In en, this message translates to:
  /// **'Your debt-to-asset ratio is {ratio}%. This is moderate — consider reducing liabilities to build a stronger equity position.'**
  String bsInsightModerateDebt(String ratio);

  /// No description provided for @bsInsightCashExceedsLoan.
  ///
  /// In en, this message translates to:
  /// **'Your cash adjustment exceeds your loan balance. Consider paying down the loan to reduce interest expenses.'**
  String get bsInsightCashExceedsLoan;

  /// No description provided for @bsInsightPositiveEquity.
  ///
  /// In en, this message translates to:
  /// **'Your net equity is positive at {amount}. Keep monitoring your balance sheet to maintain a healthy position.'**
  String bsInsightPositiveEquity(String amount);

  /// No description provided for @bsInsightNegativeEquity.
  ///
  /// In en, this message translates to:
  /// **'Your liabilities exceed your assets. Focus on increasing revenue or reducing debt to improve your equity position.'**
  String get bsInsightNegativeEquity;

  /// No description provided for @operatingActivities.
  ///
  /// In en, this message translates to:
  /// **'Operating Activities'**
  String get operatingActivities;

  /// No description provided for @investingActivities.
  ///
  /// In en, this message translates to:
  /// **'Investing Activities'**
  String get investingActivities;

  /// No description provided for @financingActivities.
  ///
  /// In en, this message translates to:
  /// **'Financing Activities'**
  String get financingActivities;

  /// No description provided for @netOperatingCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Net Operating Cash Flow'**
  String get netOperatingCashFlow;

  /// No description provided for @netInvestingCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Net Investing Cash Flow'**
  String get netInvestingCashFlow;

  /// No description provided for @netFinancingCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Net Financing Cash Flow'**
  String get netFinancingCashFlow;

  /// No description provided for @gaapCashFlowNote.
  ///
  /// In en, this message translates to:
  /// **'Cash flows classified per operating / investing / financing activities.'**
  String get gaapCashFlowNote;

  /// No description provided for @openingCapital.
  ///
  /// In en, this message translates to:
  /// **'Opening Capital'**
  String get openingCapital;

  /// No description provided for @retainedEarnings.
  ///
  /// In en, this message translates to:
  /// **'Retained Earnings'**
  String get retainedEarnings;

  /// No description provided for @openingCapitalHint.
  ///
  /// In en, this message translates to:
  /// **'Capital invested into the business at the start'**
  String get openingCapitalHint;

  /// No description provided for @autoCalculated.
  ///
  /// In en, this message translates to:
  /// **'Auto-calculated'**
  String get autoCalculated;

  /// No description provided for @reconAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Reconciliation Adjustment'**
  String get reconAdjustment;

  /// No description provided for @capitalAutoHint.
  ///
  /// In en, this message translates to:
  /// **'Tap to override with your actual invested capital'**
  String get capitalAutoHint;

  /// No description provided for @currentSnapshot.
  ///
  /// In en, this message translates to:
  /// **'current'**
  String get currentSnapshot;

  /// No description provided for @currentSnapshotFootnote.
  ///
  /// In en, this message translates to:
  /// **'Items marked (current) reflect present-day values, not the historical date selected.'**
  String get currentSnapshotFootnote;

  /// No description provided for @catLoanReceived.
  ///
  /// In en, this message translates to:
  /// **'Loan Received'**
  String get catLoanReceived;

  /// No description provided for @catLoanRepayment.
  ///
  /// In en, this message translates to:
  /// **'Loan Repayment'**
  String get catLoanRepayment;

  /// No description provided for @catEquityInjection.
  ///
  /// In en, this message translates to:
  /// **'Capital Injection'**
  String get catEquityInjection;

  /// No description provided for @catOwnerWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Owner Withdrawal'**
  String get catOwnerWithdrawal;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

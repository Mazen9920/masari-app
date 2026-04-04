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
  /// **'Revvo'**
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
  /// **'vs last month'**
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

  /// No description provided for @missingCosts.
  ///
  /// In en, this message translates to:
  /// **'Missing Costs'**
  String get missingCosts;

  /// No description provided for @productsNeedPricing.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{product} other{products}} need pricing'**
  String productsNeedPricing(int count);

  /// No description provided for @saveAll.
  ///
  /// In en, this message translates to:
  /// **'Save All'**
  String get saveAll;

  /// No description provided for @allProductsHaveCosts.
  ///
  /// In en, this message translates to:
  /// **'All products have costs!'**
  String get allProductsHaveCosts;

  /// No description provided for @allProductsHaveCostsDesc.
  ///
  /// In en, this message translates to:
  /// **'Every product and variant has a recorded cost price.'**
  String get allProductsHaveCostsDesc;

  /// No description provided for @variantsMissingCost.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{variant} other{variants}} missing cost'**
  String variantsMissingCost(int count);

  /// No description provided for @priceLabel.
  ///
  /// In en, this message translates to:
  /// **'Price: {currency} {price}'**
  String priceLabel(String currency, String price);

  /// No description provided for @sameCostForAllVariants.
  ///
  /// In en, this message translates to:
  /// **'Same cost for all variants'**
  String get sameCostForAllVariants;

  /// No description provided for @costPrice.
  ///
  /// In en, this message translates to:
  /// **'Cost Price'**
  String get costPrice;

  /// No description provided for @productsUpdatedCount.
  ///
  /// In en, this message translates to:
  /// **'Updated {count} {count, plural, =1{product} other{products}}'**
  String productsUpdatedCount(int count);

  /// No description provided for @sortStockLowToHigh.
  ///
  /// In en, this message translates to:
  /// **'Stock: Low to High'**
  String get sortStockLowToHigh;

  /// No description provided for @sortStockHighToLow.
  ///
  /// In en, this message translates to:
  /// **'Stock: High to Low'**
  String get sortStockHighToLow;

  /// No description provided for @sortNameAZ.
  ///
  /// In en, this message translates to:
  /// **'Name: A-Z'**
  String get sortNameAZ;

  /// No description provided for @sortValueHighToLow.
  ///
  /// In en, this message translates to:
  /// **'Value: High to Low'**
  String get sortValueHighToLow;

  /// No description provided for @stockStatus.
  ///
  /// In en, this message translates to:
  /// **'Stock Status'**
  String get stockStatus;

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'In Stock'**
  String get inStock;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @supplier.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get supplier;

  /// No description provided for @priceRangeCurrency.
  ///
  /// In en, this message translates to:
  /// **'Price Range ({currency})'**
  String priceRangeCurrency(String currency);

  /// No description provided for @min.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get min;

  /// No description provided for @max.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get max;

  /// No description provided for @resetAll.
  ///
  /// In en, this message translates to:
  /// **'Reset All'**
  String get resetAll;

  /// No description provided for @notEnoughStockAvailable.
  ///
  /// In en, this message translates to:
  /// **'Not enough stock. Available: {count}'**
  String notEnoughStockAvailable(int count);

  /// No description provided for @breakdownError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String breakdownError(String error);

  /// No description provided for @breakdownComplete.
  ///
  /// In en, this message translates to:
  /// **'Breakdown complete — {qty} {name} processed'**
  String breakdownComplete(int qty, String name);

  /// No description provided for @breakdownNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Breakdown recipe not configured'**
  String get breakdownNotConfigured;

  /// No description provided for @breakdownNotConfiguredDesc.
  ///
  /// In en, this message translates to:
  /// **'Add a breakdown recipe in product settings to enable this feature.'**
  String get breakdownNotConfiguredDesc;

  /// No description provided for @breakDown.
  ///
  /// In en, this message translates to:
  /// **'Break Down'**
  String get breakDown;

  /// No description provided for @sourceLabel.
  ///
  /// In en, this message translates to:
  /// **'Source: {name}'**
  String sourceLabel(String name);

  /// No description provided for @inStockCount.
  ///
  /// In en, this message translates to:
  /// **'{count} in stock'**
  String inStockCount(int count);

  /// No description provided for @exceedsAvailableStock.
  ///
  /// In en, this message translates to:
  /// **'Exceeds available stock ({count})'**
  String exceedsAvailableStock(int count);

  /// No description provided for @costAllocationPreview.
  ///
  /// In en, this message translates to:
  /// **'Cost Allocation Preview'**
  String get costAllocationPreview;

  /// No description provided for @methodLabel.
  ///
  /// In en, this message translates to:
  /// **'Method: {method}'**
  String methodLabel(String method);

  /// No description provided for @sourceCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Source cost ({qty} × {currency} {cost})'**
  String sourceCostLabel(int qty, String currency, String cost);

  /// No description provided for @outputs.
  ///
  /// In en, this message translates to:
  /// **'Outputs'**
  String get outputs;

  /// No description provided for @unitsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} units'**
  String unitsCount(int count);

  /// No description provided for @breakDownAction.
  ///
  /// In en, this message translates to:
  /// **'Break Down {qty} {name}'**
  String breakDownAction(int qty, String name);

  /// No description provided for @addRawMaterial.
  ///
  /// In en, this message translates to:
  /// **'Add Raw Material'**
  String get addRawMaterial;

  /// No description provided for @addMaterialDesc.
  ///
  /// In en, this message translates to:
  /// **'Add a raw material to track inventory consumption.'**
  String get addMaterialDesc;

  /// No description provided for @autoGenerate.
  ///
  /// In en, this message translates to:
  /// **'Auto-generate'**
  String get autoGenerate;

  /// No description provided for @fromList.
  ///
  /// In en, this message translates to:
  /// **'From List'**
  String get fromList;

  /// No description provided for @chooseSupplier.
  ///
  /// In en, this message translates to:
  /// **'Choose supplier'**
  String get chooseSupplier;

  /// No description provided for @costPriceInfo.
  ///
  /// In en, this message translates to:
  /// **'Cost price is used to calculate total material value.'**
  String get costPriceInfo;

  /// No description provided for @selectMaterialType.
  ///
  /// In en, this message translates to:
  /// **'Select material type...'**
  String get selectMaterialType;

  /// No description provided for @optionalDetails.
  ///
  /// In en, this message translates to:
  /// **'Optional Details'**
  String get optionalDetails;

  /// No description provided for @saveMaterial.
  ///
  /// In en, this message translates to:
  /// **'Save Material'**
  String get saveMaterial;

  /// No description provided for @saveAndAddAnother.
  ///
  /// In en, this message translates to:
  /// **'Save & Add Another'**
  String get saveAndAddAnother;

  /// No description provided for @inventorySettings.
  ///
  /// In en, this message translates to:
  /// **'Inventory Settings'**
  String get inventorySettings;

  /// No description provided for @stockManagement.
  ///
  /// In en, this message translates to:
  /// **'Stock Management'**
  String get stockManagement;

  /// No description provided for @autoUpdateStock.
  ///
  /// In en, this message translates to:
  /// **'Auto-update Stock'**
  String get autoUpdateStock;

  /// No description provided for @autoUpdateStockDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically decrease stock on sales'**
  String get autoUpdateStockDesc;

  /// No description provided for @defaultUnitDesc.
  ///
  /// In en, this message translates to:
  /// **'Default unit for new items'**
  String get defaultUnitDesc;

  /// No description provided for @alertsAndNotifications.
  ///
  /// In en, this message translates to:
  /// **'Alerts & Notifications'**
  String get alertsAndNotifications;

  /// No description provided for @alertThreshold.
  ///
  /// In en, this message translates to:
  /// **'Alert Threshold'**
  String get alertThreshold;

  /// No description provided for @notifyWhenStockBelow.
  ///
  /// In en, this message translates to:
  /// **'Notify when stock is below'**
  String get notifyWhenStockBelow;

  /// No description provided for @units.
  ///
  /// In en, this message translates to:
  /// **'units'**
  String get units;

  /// No description provided for @configurationSection.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get configurationSection;

  /// No description provided for @manageCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage Categories'**
  String get manageCategories;

  /// No description provided for @manageCategoriesDesc.
  ///
  /// In en, this message translates to:
  /// **'Edit existing groupings'**
  String get manageCategoriesDesc;

  /// No description provided for @manageSuppliers.
  ///
  /// In en, this message translates to:
  /// **'Manage Suppliers'**
  String get manageSuppliers;

  /// No description provided for @manageSuppliersDesc.
  ///
  /// In en, this message translates to:
  /// **'Edit vendor details'**
  String get manageSuppliersDesc;

  /// No description provided for @advancedSection.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advancedSection;

  /// No description provided for @valuationMethod.
  ///
  /// In en, this message translates to:
  /// **'Valuation Method'**
  String get valuationMethod;

  /// No description provided for @currencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyLabel;

  /// No description provided for @currencyDesc.
  ///
  /// In en, this message translates to:
  /// **'Used across all inventory screens'**
  String get currencyDesc;

  /// No description provided for @productBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Product Breakdown'**
  String get productBreakdown;

  /// No description provided for @productBreakdownDesc.
  ///
  /// In en, this message translates to:
  /// **'Enable breakdown & selling options'**
  String get productBreakdownDesc;

  /// No description provided for @hideOutOfStockItems.
  ///
  /// In en, this message translates to:
  /// **'Hide out-of-stock items'**
  String get hideOutOfStockItems;

  /// No description provided for @hideOutOfStockDesc.
  ///
  /// In en, this message translates to:
  /// **'Remove from main inventory view'**
  String get hideOutOfStockDesc;

  /// No description provided for @shopifySync.
  ///
  /// In en, this message translates to:
  /// **'Shopify Sync'**
  String get shopifySync;

  /// No description provided for @hideShopifyDrafts.
  ///
  /// In en, this message translates to:
  /// **'Hide drafted products'**
  String get hideShopifyDrafts;

  /// No description provided for @hideShopifyDraftsDesc.
  ///
  /// In en, this message translates to:
  /// **'Hide Shopify products with draft status'**
  String get hideShopifyDraftsDesc;

  /// No description provided for @inventorySync.
  ///
  /// In en, this message translates to:
  /// **'Inventory Sync'**
  String get inventorySync;

  /// No description provided for @inventorySyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Sync stock levels with Shopify'**
  String get inventorySyncDesc;

  /// No description provided for @syncMode.
  ///
  /// In en, this message translates to:
  /// **'Sync Mode'**
  String get syncMode;

  /// No description provided for @syncModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose how inventory stays in sync'**
  String get syncModeDesc;

  /// No description provided for @alwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always-On'**
  String get alwaysOn;

  /// No description provided for @alwaysOnDesc.
  ///
  /// In en, this message translates to:
  /// **'Real-time sync every 30 seconds'**
  String get alwaysOnDesc;

  /// No description provided for @onDemand.
  ///
  /// In en, this message translates to:
  /// **'On-Demand'**
  String get onDemand;

  /// No description provided for @onDemandDesc.
  ///
  /// In en, this message translates to:
  /// **'Sync manually when you choose'**
  String get onDemandDesc;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @settingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Settings saved'**
  String get settingsSaved;

  /// No description provided for @fifoDesc.
  ///
  /// In en, this message translates to:
  /// **'First In, First Out — oldest stock sold first'**
  String get fifoDesc;

  /// No description provided for @lifoDesc.
  ///
  /// In en, this message translates to:
  /// **'Last In, First Out — newest stock sold first'**
  String get lifoDesc;

  /// No description provided for @averageCostDesc.
  ///
  /// In en, this message translates to:
  /// **'Weighted average of all purchase costs'**
  String get averageCostDesc;

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
  /// **'How much cash did you start with before using Revvo?'**
  String get openingCashHelpText;

  /// No description provided for @tapToSetStartingCash.
  ///
  /// In en, this message translates to:
  /// **'Tap to set your starting cash'**
  String get tapToSetStartingCash;

  /// No description provided for @openingCashDialogDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter the cash you had before you started tracking transactions in Revvo.'**
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

  /// No description provided for @vsOpeningBalance.
  ///
  /// In en, this message translates to:
  /// **'vs opening balance'**
  String get vsOpeningBalance;

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

  /// No description provided for @accounts.
  ///
  /// In en, this message translates to:
  /// **'Accounts'**
  String get accounts;

  /// No description provided for @countOutstanding.
  ///
  /// In en, this message translates to:
  /// **'{count} outstanding'**
  String countOutstanding(int count);

  /// No description provided for @analytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analytics;

  /// No description provided for @compareLabel.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get compareLabel;

  /// No description provided for @salesMetric.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesMetric;

  /// No description provided for @profitMetric.
  ///
  /// In en, this message translates to:
  /// **'Profit'**
  String get profitMetric;

  /// No description provided for @ordersMetric.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get ordersMetric;

  /// No description provided for @recentTransactions.
  ///
  /// In en, this message translates to:
  /// **'Recent Transactions'**
  String get recentTransactions;

  /// No description provided for @customizeDashboard.
  ///
  /// In en, this message translates to:
  /// **'Customize Dashboard'**
  String get customizeDashboard;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @toggleSectionsHint.
  ///
  /// In en, this message translates to:
  /// **'Toggle sections on/off and drag to reorder.'**
  String get toggleSectionsHint;

  /// No description provided for @totalIncomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Income: {amount}'**
  String totalIncomeLabel(String amount);

  /// No description provided for @noSalesInPeriod.
  ///
  /// In en, this message translates to:
  /// **'No sales in this period'**
  String get noSalesInPeriod;

  /// No description provided for @allProductsWellStocked.
  ///
  /// In en, this message translates to:
  /// **'All products are well stocked'**
  String get allProductsWellStocked;

  /// No description provided for @unsavedChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Are you sure you want to leave?'**
  String get unsavedChangesMessage;

  /// No description provided for @tabLabel.
  ///
  /// In en, this message translates to:
  /// **'{tab} tab'**
  String tabLabel(String tab);

  /// No description provided for @newCategory.
  ///
  /// In en, this message translates to:
  /// **'New Category'**
  String get newCategory;

  /// No description provided for @editCategory.
  ///
  /// In en, this message translates to:
  /// **'Edit Category'**
  String get editCategory;

  /// No description provided for @saveCategory.
  ///
  /// In en, this message translates to:
  /// **'Save Category'**
  String get saveCategory;

  /// No description provided for @deleteCategory.
  ///
  /// In en, this message translates to:
  /// **'Delete Category'**
  String get deleteCategory;

  /// No description provided for @categoryName.
  ///
  /// In en, this message translates to:
  /// **'Category Name'**
  String get categoryName;

  /// No description provided for @type.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get type;

  /// No description provided for @icon.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get icon;

  /// No description provided for @colorTag.
  ///
  /// In en, this message translates to:
  /// **'Color Tag'**
  String get colorTag;

  /// No description provided for @color.
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get color;

  /// No description provided for @monthlyLimit.
  ///
  /// In en, this message translates to:
  /// **'Monthly Limit'**
  String get monthlyLimit;

  /// No description provided for @enableMonthlyBudget.
  ///
  /// In en, this message translates to:
  /// **'Enable Monthly Budget'**
  String get enableMonthlyBudget;

  /// No description provided for @categoryAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'A category named \"{name}\" already exists'**
  String categoryAlreadyExists(String name);

  /// No description provided for @invalidBudgetAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid budget amount'**
  String get invalidBudgetAmount;

  /// No description provided for @budgetCannotBeNegative.
  ///
  /// In en, this message translates to:
  /// **'Budget limit cannot be negative'**
  String get budgetCannotBeNegative;

  /// No description provided for @budgetExceedsMax.
  ///
  /// In en, this message translates to:
  /// **'Budget limit cannot exceed 10,000,000'**
  String get budgetExceedsMax;

  /// No description provided for @budgetAlertHint.
  ///
  /// In en, this message translates to:
  /// **'We will alert you when you reach 80% of this budget.'**
  String get budgetAlertHint;

  /// No description provided for @deleteCategoryConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? This action cannot be undone.'**
  String deleteCategoryConfirm(String name);

  /// No description provided for @budgetRemovedNotice.
  ///
  /// In en, this message translates to:
  /// **'Budget removed — income categories don\'t have budgets'**
  String get budgetRemovedNotice;

  /// No description provided for @egConsulting.
  ///
  /// In en, this message translates to:
  /// **'e.g. Consulting'**
  String get egConsulting;

  /// No description provided for @egGroceries.
  ///
  /// In en, this message translates to:
  /// **'e.g. Groceries'**
  String get egGroceries;

  /// No description provided for @income.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get income;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// No description provided for @googleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in failed'**
  String get googleSignInFailed;

  /// No description provided for @appleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in failed'**
  String get appleSignInFailed;

  /// No description provided for @loggingIn.
  ///
  /// In en, this message translates to:
  /// **'Logging in…'**
  String get loggingIn;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get logIn;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @logInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to manage your finances.'**
  String get logInSubtitle;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// No description provided for @pleaseEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email'**
  String get pleaseEnterValidEmail;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @pleaseEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get pleaseEnterPassword;

  /// No description provided for @enterEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email address first'**
  String get enterEmailFirst;

  /// No description provided for @sendingResetLink.
  ///
  /// In en, this message translates to:
  /// **'Sending password reset link…'**
  String get sendingResetLink;

  /// No description provided for @resetLinkSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset link sent to {email}'**
  String resetLinkSent(String email);

  /// No description provided for @failedToSendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Failed to send reset link'**
  String get failedToSendResetLink;

  /// No description provided for @failedToSendResetLinkError.
  ///
  /// In en, this message translates to:
  /// **'Failed to send reset link: {error}'**
  String failedToSendResetLinkError(String error);

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @dontHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get dontHaveAccount;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @agreeToTermsError.
  ///
  /// In en, this message translates to:
  /// **'Please agree to the Terms of Service'**
  String get agreeToTermsError;

  /// No description provided for @signUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign up failed'**
  String get signUpFailed;

  /// No description provided for @creatingAccount.
  ///
  /// In en, this message translates to:
  /// **'Creating account…'**
  String get creatingAccount;

  /// No description provided for @createYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Your Account'**
  String get createYourAccount;

  /// No description provided for @signUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start managing your business finances with AI.'**
  String get signUpSubtitle;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullName;

  /// No description provided for @pleaseEnterName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get pleaseEnterName;

  /// No description provided for @workEmail.
  ///
  /// In en, this message translates to:
  /// **'Work Email'**
  String get workEmail;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordMinLength;

  /// No description provided for @selectCountry.
  ///
  /// In en, this message translates to:
  /// **'Select Country'**
  String get selectCountry;

  /// No description provided for @iAgreeTo.
  ///
  /// In en, this message translates to:
  /// **'I agree to the '**
  String get iAgreeTo;

  /// No description provided for @termsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// No description provided for @andWord.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get andWord;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @alreadyHaveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account? '**
  String get alreadyHaveAccount;

  /// No description provided for @orContinueWith.
  ///
  /// In en, this message translates to:
  /// **'or continue with'**
  String get orContinueWith;

  /// No description provided for @google.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get google;

  /// No description provided for @apple.
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get apple;

  /// No description provided for @setupStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String setupStepOf(int current, int total);

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @pleaseEnterBusinessName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your business name'**
  String get pleaseEnterBusinessName;

  /// No description provided for @tellUsAboutBusiness.
  ///
  /// In en, this message translates to:
  /// **'Tell us about your business'**
  String get tellUsAboutBusiness;

  /// No description provided for @setupStep1Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Help Revvo tailor your financial experience to your specific needs.'**
  String get setupStep1Subtitle;

  /// No description provided for @businessName.
  ///
  /// In en, this message translates to:
  /// **'Business Name'**
  String get businessName;

  /// No description provided for @egCairoCoffeeHouse.
  ///
  /// In en, this message translates to:
  /// **'e.g. Cairo Coffee House'**
  String get egCairoCoffeeHouse;

  /// No description provided for @industry.
  ///
  /// In en, this message translates to:
  /// **'Industry'**
  String get industry;

  /// No description provided for @selectIndustry.
  ///
  /// In en, this message translates to:
  /// **'Select Industry'**
  String get selectIndustry;

  /// No description provided for @businessStageQuestion.
  ///
  /// In en, this message translates to:
  /// **'What stage is your business in?'**
  String get businessStageQuestion;

  /// No description provided for @industryFoodBeverage.
  ///
  /// In en, this message translates to:
  /// **'Food & Beverage'**
  String get industryFoodBeverage;

  /// No description provided for @industryRetailFashion.
  ///
  /// In en, this message translates to:
  /// **'Retail & Fashion'**
  String get industryRetailFashion;

  /// No description provided for @industryTechnology.
  ///
  /// In en, this message translates to:
  /// **'Technology'**
  String get industryTechnology;

  /// No description provided for @industryProfessionalServices.
  ///
  /// In en, this message translates to:
  /// **'Professional Services'**
  String get industryProfessionalServices;

  /// No description provided for @industryEcommerce.
  ///
  /// In en, this message translates to:
  /// **'E-Commerce'**
  String get industryEcommerce;

  /// No description provided for @industryHealthcare.
  ///
  /// In en, this message translates to:
  /// **'Healthcare'**
  String get industryHealthcare;

  /// No description provided for @industryEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get industryEducation;

  /// No description provided for @industryRealEstate.
  ///
  /// In en, this message translates to:
  /// **'Real Estate'**
  String get industryRealEstate;

  /// No description provided for @industryManufacturing.
  ///
  /// In en, this message translates to:
  /// **'Manufacturing'**
  String get industryManufacturing;

  /// No description provided for @industryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get industryOther;

  /// No description provided for @stageJustAnIdea.
  ///
  /// In en, this message translates to:
  /// **'Just an idea'**
  String get stageJustAnIdea;

  /// No description provided for @stageLessThan6Months.
  ///
  /// In en, this message translates to:
  /// **'Less than 6 months'**
  String get stageLessThan6Months;

  /// No description provided for @stage1To3Years.
  ///
  /// In en, this message translates to:
  /// **'1–3 years'**
  String get stage1To3Years;

  /// No description provided for @stage3PlusYears.
  ///
  /// In en, this message translates to:
  /// **'3+ years'**
  String get stage3PlusYears;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currency;

  /// No description provided for @whatsYourMainGoal.
  ///
  /// In en, this message translates to:
  /// **'What\'s Your Main Goal?'**
  String get whatsYourMainGoal;

  /// No description provided for @setupStep2Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Select the one that matters most right now. We\'ll customize your dashboard based on this.'**
  String get setupStep2Subtitle;

  /// No description provided for @goalTrackProfitSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor margins and net profit in real-time.'**
  String get goalTrackProfitSubtitle;

  /// No description provided for @goalCashFlowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage incoming and outgoing payments.'**
  String get goalCashFlowSubtitle;

  /// No description provided for @goalGrowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Secure funding and plan for expansion.'**
  String get goalGrowSubtitle;

  /// No description provided for @goalReportsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automate P&L and balance sheet generation.'**
  String get goalReportsSubtitle;

  /// No description provided for @chooseYourPlan.
  ///
  /// In en, this message translates to:
  /// **'Choose your plan'**
  String get chooseYourPlan;

  /// No description provided for @setupStep3Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Select the plan that fits your business. You can change this anytime.'**
  String get setupStep3Subtitle;

  /// No description provided for @letsGo.
  ///
  /// In en, this message translates to:
  /// **'Let\'s Go!'**
  String get letsGo;

  /// No description provided for @changePlanAnytime.
  ///
  /// In en, this message translates to:
  /// **'You can change your plan anytime in settings.'**
  String get changePlanAnytime;

  /// No description provided for @launchMode.
  ///
  /// In en, this message translates to:
  /// **'Launch Mode'**
  String get launchMode;

  /// No description provided for @launchModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Free forever. Track income, expenses, inventory & suppliers with simple reports.'**
  String get launchModeSubtitle;

  /// No description provided for @freeBadge.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get freeBadge;

  /// No description provided for @growthMode.
  ///
  /// In en, this message translates to:
  /// **'Growth Mode'**
  String get growthMode;

  /// No description provided for @growthModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Advanced sales, P&L, balance sheet, AI insights, Shopify integration & more.'**
  String get growthModeSubtitle;

  /// No description provided for @popularBadge.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get popularBadge;

  /// No description provided for @proMode.
  ///
  /// In en, this message translates to:
  /// **'Pro Mode'**
  String get proMode;

  /// No description provided for @proModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Full control: multi-store, investor reports, advanced modeling & unlimited users.'**
  String get proModeSubtitle;

  /// No description provided for @comingSoonBadge.
  ///
  /// In en, this message translates to:
  /// **'Coming Soon'**
  String get comingSoonBadge;

  /// No description provided for @lossLabel.
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get lossLabel;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @revvoAiInsight.
  ///
  /// In en, this message translates to:
  /// **'REVVO AI INSIGHT'**
  String get revvoAiInsight;

  /// No description provided for @viewTransactions.
  ///
  /// In en, this message translates to:
  /// **'View Transactions'**
  String get viewTransactions;

  /// No description provided for @viewSales.
  ///
  /// In en, this message translates to:
  /// **'View Sales'**
  String get viewSales;

  /// No description provided for @checkInventory.
  ///
  /// In en, this message translates to:
  /// **'Check Inventory'**
  String get checkInventory;

  /// No description provided for @viewAnalytics.
  ///
  /// In en, this message translates to:
  /// **'View Analytics'**
  String get viewAnalytics;

  /// No description provided for @insightSpendingUp.
  ///
  /// In en, this message translates to:
  /// **'Your {category} spending is up '**
  String insightSpendingUp(String category);

  /// No description provided for @insightSpendingUpDetail.
  ///
  /// In en, this message translates to:
  /// **'You spent {current} on {category} this period, compared to {previous} in the previous period.'**
  String insightSpendingUpDetail(
    String current,
    String category,
    String previous,
  );

  /// No description provided for @insightRevenueDropped.
  ///
  /// In en, this message translates to:
  /// **'Revenue has dropped '**
  String get insightRevenueDropped;

  /// No description provided for @insightRevenueDropDetail.
  ///
  /// In en, this message translates to:
  /// **'Current revenue is {current} compared to {previous} in the previous period. Consider reviewing your sales strategy.'**
  String insightRevenueDropDetail(String current, String previous);

  /// No description provided for @insightLowStock.
  ///
  /// In en, this message translates to:
  /// **'You have '**
  String get insightLowStock;

  /// No description provided for @insightLowStockBold.
  ///
  /// In en, this message translates to:
  /// **'{count} products running low on stock.'**
  String insightLowStockBold(int count);

  /// No description provided for @insightLowStockDetail.
  ///
  /// In en, this message translates to:
  /// **'{names} need restocking soon to avoid stockouts.'**
  String insightLowStockDetail(String names);

  /// No description provided for @andMore.
  ///
  /// In en, this message translates to:
  /// **' and more'**
  String get andMore;

  /// No description provided for @insightProfitMargin.
  ///
  /// In en, this message translates to:
  /// **'Your profit margin is '**
  String get insightProfitMargin;

  /// No description provided for @insightProfitMarginDetail.
  ///
  /// In en, this message translates to:
  /// **'With {revenue} in revenue and {expenses} in expenses, your margin is tight. Look for ways to reduce costs or increase prices.'**
  String insightProfitMarginDetail(String revenue, String expenses);

  /// No description provided for @insightRevenueGrowing.
  ///
  /// In en, this message translates to:
  /// **'Revenue is growing — up '**
  String get insightRevenueGrowing;

  /// No description provided for @insightRevenueGrowDetail.
  ///
  /// In en, this message translates to:
  /// **'You earned {current} this period, compared to {previous} previously. Keep up the momentum.'**
  String insightRevenueGrowDetail(String current, String previous);

  /// No description provided for @insightExpensesDown.
  ///
  /// In en, this message translates to:
  /// **'Expenses are down '**
  String get insightExpensesDown;

  /// No description provided for @insightExpensesDownDetail.
  ///
  /// In en, this message translates to:
  /// **'You spent {current} this period vs {previous} previously. Great cost management!'**
  String insightExpensesDownDetail(String current, String previous);

  /// No description provided for @accountsArAp.
  ///
  /// In en, this message translates to:
  /// **'Accounts (AR / AP)'**
  String get accountsArAp;

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'Date Range'**
  String get dateRange;

  /// No description provided for @fixedDates.
  ///
  /// In en, this message translates to:
  /// **'Fixed dates'**
  String get fixedDates;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @selectStartDate.
  ///
  /// In en, this message translates to:
  /// **'Select start date'**
  String get selectStartDate;

  /// No description provided for @selectEnd.
  ///
  /// In en, this message translates to:
  /// **'Select end'**
  String get selectEnd;

  /// No description provided for @periodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get periodToday;

  /// No description provided for @periodYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get periodYesterday;

  /// No description provided for @periodLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get periodLast7Days;

  /// No description provided for @periodLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get periodLast30Days;

  /// No description provided for @periodLast90Days.
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get periodLast90Days;

  /// No description provided for @periodLast365Days.
  ///
  /// In en, this message translates to:
  /// **'Last 365 days'**
  String get periodLast365Days;

  /// No description provided for @periodLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last Month'**
  String get periodLastMonth;

  /// No description provided for @periodLast12Months.
  ///
  /// In en, this message translates to:
  /// **'Last 12 months'**
  String get periodLast12Months;

  /// No description provided for @periodLastYear.
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get periodLastYear;

  /// No description provided for @periodWeekToDate.
  ///
  /// In en, this message translates to:
  /// **'Week to date'**
  String get periodWeekToDate;

  /// No description provided for @periodMonthToDate.
  ///
  /// In en, this message translates to:
  /// **'Month to date'**
  String get periodMonthToDate;

  /// No description provided for @periodQuarterToDate.
  ///
  /// In en, this message translates to:
  /// **'Quarter to date'**
  String get periodQuarterToDate;

  /// No description provided for @periodYearToDate.
  ///
  /// In en, this message translates to:
  /// **'Year to date'**
  String get periodYearToDate;

  /// No description provided for @periodCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get periodCustom;

  /// No description provided for @vsYesterday.
  ///
  /// In en, this message translates to:
  /// **'vs yesterday'**
  String get vsYesterday;

  /// No description provided for @vsDayBefore.
  ///
  /// In en, this message translates to:
  /// **'vs day before'**
  String get vsDayBefore;

  /// No description provided for @vsPrior7Days.
  ///
  /// In en, this message translates to:
  /// **'vs prior 7 days'**
  String get vsPrior7Days;

  /// No description provided for @vsPrior30Days.
  ///
  /// In en, this message translates to:
  /// **'vs prior 30 days'**
  String get vsPrior30Days;

  /// No description provided for @vsPrior90Days.
  ///
  /// In en, this message translates to:
  /// **'vs prior 90 days'**
  String get vsPrior90Days;

  /// No description provided for @vsPrior365Days.
  ///
  /// In en, this message translates to:
  /// **'vs prior 365 days'**
  String get vsPrior365Days;

  /// No description provided for @vsMonthBefore.
  ///
  /// In en, this message translates to:
  /// **'vs month before'**
  String get vsMonthBefore;

  /// No description provided for @vsPrior12Months.
  ///
  /// In en, this message translates to:
  /// **'vs prior 12 months'**
  String get vsPrior12Months;

  /// No description provided for @vsPriorYear.
  ///
  /// In en, this message translates to:
  /// **'vs prior year'**
  String get vsPriorYear;

  /// No description provided for @vsLastWeek.
  ///
  /// In en, this message translates to:
  /// **'vs last week'**
  String get vsLastWeek;

  /// No description provided for @vsLastQuarter.
  ///
  /// In en, this message translates to:
  /// **'vs last quarter'**
  String get vsLastQuarter;

  /// No description provided for @vsLastYear.
  ///
  /// In en, this message translates to:
  /// **'vs last year'**
  String get vsLastYear;

  /// No description provided for @vsPriorPeriod.
  ///
  /// In en, this message translates to:
  /// **'vs prior period'**
  String get vsPriorPeriod;

  /// No description provided for @managementHub.
  ///
  /// In en, this message translates to:
  /// **'Management Hub'**
  String get managementHub;

  /// No description provided for @searchInventorySuppliers.
  ///
  /// In en, this message translates to:
  /// **'Search inventory, suppliers…'**
  String get searchInventorySuppliers;

  /// No description provided for @yourWorkspace.
  ///
  /// In en, this message translates to:
  /// **'YOUR WORKSPACE'**
  String get yourWorkspace;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'QUICK ACTIONS'**
  String get quickActions;

  /// No description provided for @inventoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory'**
  String get inventoryTitle;

  /// No description provided for @inventorySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Products, stock & reorders'**
  String get inventorySubtitle;

  /// No description provided for @suppliersTitle.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliersTitle;

  /// No description provided for @suppliersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vendors, purchases & payables'**
  String get suppliersSubtitle;

  /// No description provided for @budgetCategories.
  ///
  /// In en, this message translates to:
  /// **'Budget & Categories'**
  String get budgetCategories;

  /// No description provided for @budgetCategoriesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Organize expenses & income'**
  String get budgetCategoriesSubtitle;

  /// No description provided for @productAction.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get productAction;

  /// No description provided for @supplierAction.
  ///
  /// In en, this message translates to:
  /// **'Supplier'**
  String get supplierAction;

  /// No description provided for @categoryAction.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryAction;

  /// No description provided for @settingsAction.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsAction;

  /// No description provided for @nLow.
  ///
  /// In en, this message translates to:
  /// **'{count} low'**
  String nLow(int count);

  /// No description provided for @nItems.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String nItems(int count);

  /// No description provided for @nDues.
  ///
  /// In en, this message translates to:
  /// **'{count} dues'**
  String nDues(int count);

  /// No description provided for @nVendors.
  ///
  /// In en, this message translates to:
  /// **'{count} vendors'**
  String nVendors(int count);

  /// No description provided for @nActive.
  ///
  /// In en, this message translates to:
  /// **'{count} active'**
  String nActive(int count);

  /// No description provided for @nProductsOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'{count} Products Out of Stock'**
  String nProductsOutOfStock(int count);

  /// No description provided for @reorderSoonSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reorder soon to avoid missed sales.'**
  String get reorderSoonSubtitle;

  /// No description provided for @nProductsRunningLow.
  ///
  /// In en, this message translates to:
  /// **'{count} Products Running Low'**
  String nProductsRunningLow(int count);

  /// No description provided for @reviewStockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review stock levels and reorder before they run out.'**
  String get reviewStockSubtitle;

  /// No description provided for @nSupplierPaymentsDue.
  ///
  /// In en, this message translates to:
  /// **'{count} Supplier Payments Due'**
  String nSupplierPaymentsDue(int count);

  /// No description provided for @checkOutstandingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Check outstanding balances to stay on top of payables.'**
  String get checkOutstandingSubtitle;

  /// No description provided for @inventoryHealthy.
  ///
  /// In en, this message translates to:
  /// **'Inventory Healthy'**
  String get inventoryHealthy;

  /// No description provided for @inventoryHealthySubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} products tracked, avg value {avg} per item.'**
  String inventoryHealthySubtitle(int count, String avg);

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// No description provided for @getStartedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add your first product to start tracking inventory.'**
  String get getStartedSubtitle;

  /// No description provided for @hubSettings.
  ///
  /// In en, this message translates to:
  /// **'Hub Settings'**
  String get hubSettings;

  /// No description provided for @layoutPreferences.
  ///
  /// In en, this message translates to:
  /// **'Layout Preferences'**
  String get layoutPreferences;

  /// No description provided for @hubLayout.
  ///
  /// In en, this message translates to:
  /// **'Hub Layout'**
  String get hubLayout;

  /// No description provided for @gridLayout.
  ///
  /// In en, this message translates to:
  /// **'Grid (2×2)'**
  String get gridLayout;

  /// No description provided for @listLayout.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get listLayout;

  /// No description provided for @showQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Show Quick Actions'**
  String get showQuickActions;

  /// No description provided for @showQuickActionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shortcuts below main cards'**
  String get showQuickActionsSubtitle;

  /// No description provided for @showInsightsBanner.
  ///
  /// In en, this message translates to:
  /// **'Show Insights Banner'**
  String get showInsightsBanner;

  /// No description provided for @showInsightsBannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly summaries & tips'**
  String get showInsightsBannerSubtitle;

  /// No description provided for @dashboardCustomization.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Customization'**
  String get dashboardCustomization;

  /// No description provided for @defaultManageTab.
  ///
  /// In en, this message translates to:
  /// **'Default Manage Tab'**
  String get defaultManageTab;

  /// No description provided for @hubOverview.
  ///
  /// In en, this message translates to:
  /// **'Hub Overview'**
  String get hubOverview;

  /// No description provided for @pinnedActions.
  ///
  /// In en, this message translates to:
  /// **'Pinned Actions'**
  String get pinnedActions;

  /// No description provided for @editAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get addProduct;

  /// No description provided for @newSupplier.
  ///
  /// In en, this message translates to:
  /// **'New Supplier'**
  String get newSupplier;

  /// No description provided for @notificationsAndBadges.
  ///
  /// In en, this message translates to:
  /// **'Notifications & Badges'**
  String get notificationsAndBadges;

  /// No description provided for @lowStockAlertsToggle.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alerts'**
  String get lowStockAlertsToggle;

  /// No description provided for @lowStockAlertsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notify when items hit minimum'**
  String get lowStockAlertsSubtitle;

  /// No description provided for @paymentDueReminders.
  ///
  /// In en, this message translates to:
  /// **'Payment Due Reminders'**
  String get paymentDueReminders;

  /// No description provided for @paymentDueRemindersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Alerts for upcoming vendor payments'**
  String get paymentDueRemindersSubtitle;

  /// No description provided for @showStatBadges.
  ///
  /// In en, this message translates to:
  /// **'Show Stat Badges on Cards'**
  String get showStatBadges;

  /// No description provided for @showStatBadgesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Display mini-stats on hub cards'**
  String get showStatBadgesSubtitle;

  /// No description provided for @pinnedActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Pinned Actions'**
  String get pinnedActionsTitle;

  /// No description provided for @pinnedActionsInstructions.
  ///
  /// In en, this message translates to:
  /// **'Drag and drop to reorder the actions that appear on your Manage Hub. The first {count} will be visible by default.'**
  String pinnedActionsInstructions(int count);

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// No description provided for @pinnedActionsSaved.
  ///
  /// In en, this message translates to:
  /// **'Pinned actions saved'**
  String get pinnedActionsSaved;

  /// No description provided for @hiddenFromDashboard.
  ///
  /// In en, this message translates to:
  /// **'HIDDEN FROM DASHBOARD'**
  String get hiddenFromDashboard;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// No description provided for @cashFlowTab.
  ///
  /// In en, this message translates to:
  /// **'Cash Flow'**
  String get cashFlowTab;

  /// No description provided for @performanceTab.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get performanceTab;

  /// No description provided for @exportAndShare.
  ///
  /// In en, this message translates to:
  /// **'Export & Share'**
  String get exportAndShare;

  /// No description provided for @upgradeToExport.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Growth to export'**
  String get upgradeToExport;

  /// No description provided for @aboutReports.
  ///
  /// In en, this message translates to:
  /// **'About Reports'**
  String get aboutReports;

  /// No description provided for @aboutPnl.
  ///
  /// In en, this message translates to:
  /// **'Profit & Loss shows revenue, expenses, and net profit for any period.'**
  String get aboutPnl;

  /// No description provided for @aboutBalanceSheet.
  ///
  /// In en, this message translates to:
  /// **'Balance Sheet displays assets, liabilities, and equity at a point in time.'**
  String get aboutBalanceSheet;

  /// No description provided for @aboutCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Cash Flow tracks money in and out with forecasted balances.'**
  String get aboutCashFlow;

  /// No description provided for @aboutRealTime.
  ///
  /// In en, this message translates to:
  /// **'Data updates in real-time as you add transactions.'**
  String get aboutRealTime;

  /// No description provided for @aboutExport.
  ///
  /// In en, this message translates to:
  /// **'Tap the share icon to export PDF or share reports.'**
  String get aboutExport;

  /// No description provided for @aboutPerformance.
  ///
  /// In en, this message translates to:
  /// **'Track your business performance and cash flow.'**
  String get aboutPerformance;

  /// No description provided for @aboutAutoUpdate.
  ///
  /// In en, this message translates to:
  /// **'Reports update automatically as you add transactions.'**
  String get aboutAutoUpdate;

  /// No description provided for @upgradeForBalanceSheet.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Growth for Balance Sheet, full exports, and AI insights.'**
  String get upgradeForBalanceSheet;

  /// No description provided for @selectPeriod.
  ///
  /// In en, this message translates to:
  /// **'Select Period'**
  String get selectPeriod;

  /// No description provided for @monthEnd.
  ///
  /// In en, this message translates to:
  /// **'Month End'**
  String get monthEnd;

  /// No description provided for @yearEnd.
  ///
  /// In en, this message translates to:
  /// **'Year End'**
  String get yearEnd;

  /// No description provided for @monthlyReportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'P&L, cash flow, sales & inventory summary'**
  String get monthlyReportSubtitle;

  /// No description provided for @generateSharePdf.
  ///
  /// In en, this message translates to:
  /// **'Generate & Share PDF'**
  String get generateSharePdf;

  /// No description provided for @transactionData.
  ///
  /// In en, this message translates to:
  /// **'Transaction Data'**
  String get transactionData;

  /// No description provided for @transactionDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All transactions in CSV spreadsheet format'**
  String get transactionDataSubtitle;

  /// No description provided for @fromLabel.
  ///
  /// In en, this message translates to:
  /// **'FROM'**
  String get fromLabel;

  /// No description provided for @toLabel.
  ///
  /// In en, this message translates to:
  /// **'TO'**
  String get toLabel;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @profitLossStatement.
  ///
  /// In en, this message translates to:
  /// **'Profit & Loss Statement'**
  String get profitLossStatement;

  /// No description provided for @pnlSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed P&L breakdown PDF'**
  String get pnlSubtitle;

  /// No description provided for @monthlyPeriod.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get monthlyPeriod;

  /// No description provided for @quarterlyPeriod.
  ///
  /// In en, this message translates to:
  /// **'Quarterly'**
  String get quarterlyPeriod;

  /// No description provided for @annualPeriod.
  ///
  /// In en, this message translates to:
  /// **'Annual'**
  String get annualPeriod;

  /// No description provided for @exportPdf.
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get exportPdf;

  /// No description provided for @selectDateRange.
  ///
  /// In en, this message translates to:
  /// **'Select Date Range'**
  String get selectDateRange;

  /// No description provided for @confirmFilter.
  ///
  /// In en, this message translates to:
  /// **'Confirm Filter'**
  String get confirmFilter;

  /// No description provided for @noTransactionsInRange.
  ///
  /// In en, this message translates to:
  /// **'No transactions in selected range'**
  String get noTransactionsInRange;

  /// No description provided for @reportPreview.
  ///
  /// In en, this message translates to:
  /// **'Report Preview'**
  String get reportPreview;

  /// No description provided for @reportDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Report downloaded to device'**
  String get reportDownloaded;

  /// No description provided for @shareOptionsOpening.
  ///
  /// In en, this message translates to:
  /// **'Share options opening...'**
  String get shareOptionsOpening;

  /// No description provided for @shareViaWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Share via WhatsApp'**
  String get shareViaWhatsApp;

  /// No description provided for @otherShareOptions.
  ///
  /// In en, this message translates to:
  /// **'Other Share Options'**
  String get otherShareOptions;

  /// No description provided for @reportSharedWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Report shared via WhatsApp'**
  String get reportSharedWhatsApp;

  /// No description provided for @budgetAndCategories.
  ///
  /// In en, this message translates to:
  /// **'Budget & Categories'**
  String get budgetAndCategories;

  /// No description provided for @expenseLabel.
  ///
  /// In en, this message translates to:
  /// **'Expense'**
  String get expenseLabel;

  /// No description provided for @incomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get incomeLabel;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'THIS MONTH'**
  String get thisMonth;

  /// No description provided for @detailsLabel.
  ///
  /// In en, this message translates to:
  /// **'DETAILS'**
  String get detailsLabel;

  /// No description provided for @topCategory.
  ///
  /// In en, this message translates to:
  /// **'Top category: '**
  String get topCategory;

  /// No description provided for @nUncategorized.
  ///
  /// In en, this message translates to:
  /// **'{count} Uncategorized'**
  String nUncategorized(int count);

  /// No description provided for @pleaseReviewTransactions.
  ///
  /// In en, this message translates to:
  /// **'Please review these transactions'**
  String get pleaseReviewTransactions;

  /// No description provided for @reviewLabel.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewLabel;

  /// No description provided for @nTransactionsCategorized.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{transaction} other{transactions}} categorized'**
  String nTransactionsCategorized(int count);

  /// No description provided for @noCategoriesYet.
  ///
  /// In en, this message translates to:
  /// **'No Categories Yet'**
  String get noCategoriesYet;

  /// No description provided for @addTransactionsToSeeBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Add transactions to see category breakdowns'**
  String get addTransactionsToSeeBreakdown;

  /// No description provided for @insightLabel.
  ///
  /// In en, this message translates to:
  /// **'Insight: '**
  String get insightLabel;

  /// No description provided for @askAiComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Ask AI (Coming Soon)'**
  String get askAiComingSoon;

  /// No description provided for @filterAndSort.
  ///
  /// In en, this message translates to:
  /// **'Filter & Sort'**
  String get filterAndSort;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort By'**
  String get sortBy;

  /// No description provided for @highestAmount.
  ///
  /// In en, this message translates to:
  /// **'Highest Amount'**
  String get highestAmount;

  /// No description provided for @mostTransactions.
  ///
  /// In en, this message translates to:
  /// **'Most Transactions'**
  String get mostTransactions;

  /// No description provided for @lowestAmount.
  ///
  /// In en, this message translates to:
  /// **'Lowest Amount'**
  String get lowestAmount;

  /// No description provided for @nameAZ.
  ///
  /// In en, this message translates to:
  /// **'Name (A-Z)'**
  String get nameAZ;

  /// No description provided for @thisMonthFilter.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get thisMonthFilter;

  /// No description provided for @lastMonthFilter.
  ///
  /// In en, this message translates to:
  /// **'Last Month'**
  String get lastMonthFilter;

  /// No description provided for @quarterToDate.
  ///
  /// In en, this message translates to:
  /// **'Quarter to Date'**
  String get quarterToDate;

  /// No description provided for @customFilter.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customFilter;

  /// No description provided for @categoryStatus.
  ///
  /// In en, this message translates to:
  /// **'Category Status'**
  String get categoryStatus;

  /// No description provided for @hideEmptyCategories.
  ///
  /// In en, this message translates to:
  /// **'Hide Empty Categories'**
  String get hideEmptyCategories;

  /// No description provided for @showOnlyOverBudget.
  ///
  /// In en, this message translates to:
  /// **'Show Only Over Budget'**
  String get showOnlyOverBudget;

  /// No description provided for @categoryTypes.
  ///
  /// In en, this message translates to:
  /// **'Category Types'**
  String get categoryTypes;

  /// No description provided for @operationalType.
  ///
  /// In en, this message translates to:
  /// **'Operational'**
  String get operationalType;

  /// No description provided for @marketingType.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get marketingType;

  /// No description provided for @fixedCostsType.
  ///
  /// In en, this message translates to:
  /// **'Fixed Costs'**
  String get fixedCostsType;

  /// No description provided for @variableType.
  ///
  /// In en, this message translates to:
  /// **'Variable'**
  String get variableType;

  /// No description provided for @applyFilters.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters'**
  String get applyFilters;

  /// No description provided for @addLabel.
  ///
  /// In en, this message translates to:
  /// **'+ Add'**
  String get addLabel;

  /// No description provided for @categoryArchived.
  ///
  /// In en, this message translates to:
  /// **'{name} archived'**
  String categoryArchived(String name);

  /// No description provided for @undoLabel.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoLabel;

  /// No description provided for @deleteCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteCategoryTitle(String name);

  /// No description provided for @deleteCategoryHasTx.
  ///
  /// In en, this message translates to:
  /// **'This category has {count} {count, plural, =1{transaction} other{transactions}}. Deleting it will mark them as uncategorized.'**
  String deleteCategoryHasTx(int count);

  /// No description provided for @deleteCategoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'This will permanently remove this category.'**
  String get deleteCategoryEmpty;

  /// No description provided for @categoryDeleted.
  ///
  /// In en, this message translates to:
  /// **'{name} deleted'**
  String categoryDeleted(String name);

  /// No description provided for @archiveAction.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @aiSuggestsMerging.
  ///
  /// In en, this message translates to:
  /// **'AI suggests merging '**
  String get aiSuggestsMerging;

  /// No description provided for @toSimplifyTracking.
  ///
  /// In en, this message translates to:
  /// **' to simplify your tracking.'**
  String get toSimplifyTracking;

  /// No description provided for @reviewSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Review Suggestion'**
  String get reviewSuggestion;

  /// No description provided for @budgetOverview.
  ///
  /// In en, this message translates to:
  /// **'Budget Overview'**
  String get budgetOverview;

  /// No description provided for @monthlyBudgetLabel.
  ///
  /// In en, this message translates to:
  /// **'Monthly Budget'**
  String get monthlyBudgetLabel;

  /// No description provided for @overBudget.
  ///
  /// In en, this message translates to:
  /// **'Over Budget'**
  String get overBudget;

  /// No description provided for @nPercentUsed.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Used'**
  String nPercentUsed(int percent);

  /// No description provided for @overBy.
  ///
  /// In en, this message translates to:
  /// **'Over by {currency} {amount}'**
  String overBy(String currency, String amount);

  /// No description provided for @amountRemaining.
  ///
  /// In en, this message translates to:
  /// **'{currency} {amount} remaining'**
  String amountRemaining(String currency, String amount);

  /// No description provided for @overStatus.
  ///
  /// In en, this message translates to:
  /// **'Over'**
  String get overStatus;

  /// No description provided for @nearStatus.
  ///
  /// In en, this message translates to:
  /// **'Near'**
  String get nearStatus;

  /// No description provided for @safeStatus.
  ///
  /// In en, this message translates to:
  /// **'Safe'**
  String get safeStatus;

  /// No description provided for @nearLimitStatus.
  ///
  /// In en, this message translates to:
  /// **'Near limit'**
  String get nearLimitStatus;

  /// No description provided for @onTrackStatus.
  ///
  /// In en, this message translates to:
  /// **'On track'**
  String get onTrackStatus;

  /// No description provided for @currentSpend.
  ///
  /// In en, this message translates to:
  /// **'CURRENT SPEND'**
  String get currentSpend;

  /// No description provided for @nTransactionsThisMonth.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{transaction} other{transactions}} this month'**
  String nTransactionsThisMonth(int count);

  /// No description provided for @percentUsed.
  ///
  /// In en, this message translates to:
  /// **'{percent}% Used'**
  String percentUsed(int percent);

  /// No description provided for @amountLeft.
  ///
  /// In en, this message translates to:
  /// **'{currency} {amount} Left'**
  String amountLeft(String currency, String amount);

  /// No description provided for @approachingBudgetLimit.
  ///
  /// In en, this message translates to:
  /// **'Approaching budget limit'**
  String get approachingBudgetLimit;

  /// No description provided for @threeMonthTrend.
  ///
  /// In en, this message translates to:
  /// **'3 Month Trend'**
  String get threeMonthTrend;

  /// No description provided for @transactionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactionsLabel;

  /// No description provided for @noTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet'**
  String get noTransactionsYet;

  /// No description provided for @noBudgetSet.
  ///
  /// In en, this message translates to:
  /// **'No budget set'**
  String get noBudgetSet;

  /// No description provided for @editLabel.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editLabel;

  /// No description provided for @setBudget.
  ///
  /// In en, this message translates to:
  /// **'Set Budget'**
  String get setBudget;

  /// No description provided for @setMonthlyBudget.
  ///
  /// In en, this message translates to:
  /// **'SET MONTHLY BUDGET'**
  String get setMonthlyBudget;

  /// No description provided for @removeLabel.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLabel;

  /// No description provided for @cancelLabel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelLabel;

  /// No description provided for @saveLabel.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveLabel;

  /// No description provided for @enterValidBudget.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid budget amount'**
  String get enterValidBudget;

  /// No description provided for @nTransactionsNeedCategory.
  ///
  /// In en, this message translates to:
  /// **'{count} transactions need a category'**
  String nTransactionsNeedCategory(int count);

  /// No description provided for @saveNChanges.
  ///
  /// In en, this message translates to:
  /// **'Save {count} {count, plural, =1{Change} other{Changes}}'**
  String saveNChanges(int count);

  /// No description provided for @catGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get catGroceries;

  /// No description provided for @catIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get catIncome;

  /// No description provided for @catTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get catTransport;

  /// No description provided for @catEntertainment.
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get catEntertainment;

  /// No description provided for @catBills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get catBills;

  /// No description provided for @catHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get catHealth;

  /// No description provided for @catEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get catEducation;

  /// No description provided for @catShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get catShopping;

  /// No description provided for @catFoodDining.
  ///
  /// In en, this message translates to:
  /// **'Food & Dining'**
  String get catFoodDining;

  /// No description provided for @catGifts.
  ///
  /// In en, this message translates to:
  /// **'Gifts'**
  String get catGifts;

  /// No description provided for @catTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get catTravel;

  /// No description provided for @catFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get catFamily;

  /// No description provided for @catPets.
  ///
  /// In en, this message translates to:
  /// **'Pets'**
  String get catPets;

  /// No description provided for @catInvestments.
  ///
  /// In en, this message translates to:
  /// **'Investments'**
  String get catInvestments;

  /// No description provided for @catUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get catUtilities;

  /// No description provided for @catInsurance.
  ///
  /// In en, this message translates to:
  /// **'Insurance'**
  String get catInsurance;

  /// No description provided for @catSubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get catSubscriptions;

  /// No description provided for @catDonations.
  ///
  /// In en, this message translates to:
  /// **'Donations'**
  String get catDonations;

  /// No description provided for @catPersonalCare.
  ///
  /// In en, this message translates to:
  /// **'Personal Care'**
  String get catPersonalCare;

  /// No description provided for @catSupplierPayment.
  ///
  /// In en, this message translates to:
  /// **'Supplier Payment'**
  String get catSupplierPayment;

  /// No description provided for @catSalesRevenue.
  ///
  /// In en, this message translates to:
  /// **'Sales Revenue'**
  String get catSalesRevenue;

  /// No description provided for @catCostOfGoodsSold.
  ///
  /// In en, this message translates to:
  /// **'Cost of Goods Sold'**
  String get catCostOfGoodsSold;

  /// No description provided for @catShippingFees.
  ///
  /// In en, this message translates to:
  /// **'Shipping Fees'**
  String get catShippingFees;

  /// No description provided for @catCapitalInjection.
  ///
  /// In en, this message translates to:
  /// **'Capital Injection'**
  String get catCapitalInjection;

  /// No description provided for @catOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get catOther;

  /// No description provided for @catUncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get catUncategorized;

  /// No description provided for @catTaxPayable.
  ///
  /// In en, this message translates to:
  /// **'Tax Payable'**
  String get catTaxPayable;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileSectionAccount.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get profileSectionAccount;

  /// No description provided for @profileEditProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get profileEditProfile;

  /// No description provided for @profileEditProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Name, email, phone'**
  String get profileEditProfileSubtitle;

  /// No description provided for @profileBusinessInfo.
  ///
  /// In en, this message translates to:
  /// **'Business Info'**
  String get profileBusinessInfo;

  /// No description provided for @profileBusinessInfoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Company details & tax ID'**
  String get profileBusinessInfoSubtitle;

  /// No description provided for @profileCurrencyLanguage.
  ///
  /// In en, this message translates to:
  /// **'Currency & Language'**
  String get profileCurrencyLanguage;

  /// No description provided for @profileManageSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage Subscription'**
  String get profileManageSubscription;

  /// No description provided for @profileCurrentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current plan: {tier}'**
  String profileCurrentPlan(String tier);

  /// No description provided for @profileSectionApp.
  ///
  /// In en, this message translates to:
  /// **'APP'**
  String get profileSectionApp;

  /// No description provided for @profileNotificationPreferences.
  ///
  /// In en, this message translates to:
  /// **'Notification Preferences'**
  String get profileNotificationPreferences;

  /// No description provided for @profileNotificationPrefSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Push, email & alerts'**
  String get profileNotificationPrefSubtitle;

  /// No description provided for @profileShopifyIntegration.
  ///
  /// In en, this message translates to:
  /// **'Shopify Integration'**
  String get profileShopifyIntegration;

  /// No description provided for @profileShopifyConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get profileShopifyConnected;

  /// No description provided for @profileShopifyNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get profileShopifyNotConnected;

  /// No description provided for @profileSecurityPin.
  ///
  /// In en, this message translates to:
  /// **'Security & PIN'**
  String get profileSecurityPin;

  /// No description provided for @profileSecuritySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Biometrics, password'**
  String get profileSecuritySubtitle;

  /// No description provided for @profileDataBackup.
  ///
  /// In en, this message translates to:
  /// **'Data & Backup'**
  String get profileDataBackup;

  /// No description provided for @profileDataBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Export, restore, auto-backup'**
  String get profileDataBackupSubtitle;

  /// No description provided for @profileSectionSupport.
  ///
  /// In en, this message translates to:
  /// **'SUPPORT'**
  String get profileSectionSupport;

  /// No description provided for @profileHelpCenter.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get profileHelpCenter;

  /// No description provided for @profileHelpCenterSubtitle.
  ///
  /// In en, this message translates to:
  /// **'FAQ & contact support'**
  String get profileHelpCenterSubtitle;

  /// No description provided for @profileAboutRevvo.
  ///
  /// In en, this message translates to:
  /// **'About Revvo'**
  String get profileAboutRevvo;

  /// No description provided for @profileVersionInfo.
  ///
  /// In en, this message translates to:
  /// **'Version 1.0.0'**
  String get profileVersionInfo;

  /// No description provided for @profileMyBusiness.
  ///
  /// In en, this message translates to:
  /// **'My Business'**
  String get profileMyBusiness;

  /// No description provided for @profileTierPlan.
  ///
  /// In en, this message translates to:
  /// **'{tier} Plan'**
  String profileTierPlan(String tier);

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get signOut;

  /// No description provided for @signOutConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get signOutConfirm;

  /// No description provided for @editProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfileTitle;

  /// No description provided for @editProfileChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Profile Photo'**
  String get editProfileChangePhoto;

  /// No description provided for @editProfileTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take a Photo'**
  String get editProfileTakePhoto;

  /// No description provided for @editProfileChooseGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get editProfileChooseGallery;

  /// No description provided for @editProfileNameEmpty.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get editProfileNameEmpty;

  /// No description provided for @editProfileFullName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get editProfileFullName;

  /// No description provided for @editProfileEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get editProfileEmail;

  /// No description provided for @editProfilePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get editProfilePhone;

  /// No description provided for @businessInfoTitle.
  ///
  /// In en, this message translates to:
  /// **'Business Info'**
  String get businessInfoTitle;

  /// No description provided for @businessInfoUploadLogo.
  ///
  /// In en, this message translates to:
  /// **'Upload Logo'**
  String get businessInfoUploadLogo;

  /// No description provided for @businessInfoName.
  ///
  /// In en, this message translates to:
  /// **'Business Name'**
  String get businessInfoName;

  /// No description provided for @businessInfoType.
  ///
  /// In en, this message translates to:
  /// **'Business Type'**
  String get businessInfoType;

  /// No description provided for @businessInfoAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get businessInfoAddress;

  /// No description provided for @businessInfoTaxId.
  ///
  /// In en, this message translates to:
  /// **'Tax ID / VAT Number'**
  String get businessInfoTaxId;

  /// No description provided for @businessInfoTaxNote.
  ///
  /// In en, this message translates to:
  /// **'Tax ID is required for generating official invoices and receipts.'**
  String get businessInfoTaxNote;

  /// No description provided for @currencyLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Currency & Language'**
  String get currencyLanguageTitle;

  /// No description provided for @currencySection.
  ///
  /// In en, this message translates to:
  /// **'CURRENCY'**
  String get currencySection;

  /// No description provided for @languageSection.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get languageSection;

  /// No description provided for @currencyChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Currency?'**
  String get currencyChangeTitle;

  /// No description provided for @currencyChangeMessage.
  ///
  /// In en, this message translates to:
  /// **'Switching to {code} will update all displayed amounts. Existing data will not be converted.'**
  String currencyChangeMessage(String code);

  /// No description provided for @currencyChangeBtn.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get currencyChangeBtn;

  /// No description provided for @currencyEgp.
  ///
  /// In en, this message translates to:
  /// **'Egyptian Pound'**
  String get currencyEgp;

  /// No description provided for @currencyUsd.
  ///
  /// In en, this message translates to:
  /// **'US Dollar'**
  String get currencyUsd;

  /// No description provided for @currencyEur.
  ///
  /// In en, this message translates to:
  /// **'Euro'**
  String get currencyEur;

  /// No description provided for @currencySar.
  ///
  /// In en, this message translates to:
  /// **'Saudi Riyal'**
  String get currencySar;

  /// No description provided for @currencyAed.
  ///
  /// In en, this message translates to:
  /// **'UAE Dirham'**
  String get currencyAed;

  /// No description provided for @currencyGbp.
  ///
  /// In en, this message translates to:
  /// **'British Pound'**
  String get currencyGbp;

  /// No description provided for @notificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notificationsTitle;

  /// No description provided for @notificationsSectionChannels.
  ///
  /// In en, this message translates to:
  /// **'CHANNELS'**
  String get notificationsSectionChannels;

  /// No description provided for @notificationsPush.
  ///
  /// In en, this message translates to:
  /// **'Push Notifications'**
  String get notificationsPush;

  /// No description provided for @notificationsPushSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get instant alerts on your device'**
  String get notificationsPushSubtitle;

  /// No description provided for @notificationsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Notifications'**
  String get notificationsEmail;

  /// No description provided for @notificationsEmailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Receive updates via email'**
  String get notificationsEmailSubtitle;

  /// No description provided for @notificationsSectionAlerts.
  ///
  /// In en, this message translates to:
  /// **'ALERTS'**
  String get notificationsSectionAlerts;

  /// No description provided for @notificationsLowStock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alerts'**
  String get notificationsLowStock;

  /// No description provided for @notificationsLowStockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When items hit minimum quantity'**
  String get notificationsLowStockSubtitle;

  /// No description provided for @notificationsPaymentReminders.
  ///
  /// In en, this message translates to:
  /// **'Payment Reminders'**
  String get notificationsPaymentReminders;

  /// No description provided for @notificationsPaymentSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upcoming vendor payments'**
  String get notificationsPaymentSubtitle;

  /// No description provided for @notificationsSales.
  ///
  /// In en, this message translates to:
  /// **'New Sales'**
  String get notificationsSales;

  /// No description provided for @notificationsSalesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'When a new sale is recorded'**
  String get notificationsSalesSubtitle;

  /// No description provided for @notificationsShopifyOrders.
  ///
  /// In en, this message translates to:
  /// **'Shopify Orders'**
  String get notificationsShopifyOrders;

  /// No description provided for @notificationsShopifySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Orders synced from Shopify'**
  String get notificationsShopifySubtitle;

  /// No description provided for @notificationsBilling.
  ///
  /// In en, this message translates to:
  /// **'Subscription & Billing'**
  String get notificationsBilling;

  /// No description provided for @notificationsBillingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Payments, renewals, and expiry alerts'**
  String get notificationsBillingSubtitle;

  /// No description provided for @notificationsSectionReports.
  ///
  /// In en, this message translates to:
  /// **'REPORTS'**
  String get notificationsSectionReports;

  /// No description provided for @notificationsWeeklyDigest.
  ///
  /// In en, this message translates to:
  /// **'Weekly Digest'**
  String get notificationsWeeklyDigest;

  /// No description provided for @notificationsWeeklySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Summary every Monday morning'**
  String get notificationsWeeklySubtitle;

  /// No description provided for @notificationsMonthlyReport.
  ///
  /// In en, this message translates to:
  /// **'Monthly Report'**
  String get notificationsMonthlyReport;

  /// No description provided for @notificationsMonthlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Detailed report on the 1st'**
  String get notificationsMonthlySubtitle;

  /// No description provided for @securityTitle.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get securityTitle;

  /// No description provided for @securityStatus.
  ///
  /// In en, this message translates to:
  /// **'Security Status'**
  String get securityStatus;

  /// No description provided for @securityProtected.
  ///
  /// In en, this message translates to:
  /// **'Protected'**
  String get securityProtected;

  /// No description provided for @securityBasic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get securityBasic;

  /// No description provided for @securitySectionAuth.
  ///
  /// In en, this message translates to:
  /// **'AUTHENTICATION'**
  String get securitySectionAuth;

  /// No description provided for @securityAppLock.
  ///
  /// In en, this message translates to:
  /// **'App Lock (PIN)'**
  String get securityAppLock;

  /// No description provided for @securityAppLockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Require PIN to open app'**
  String get securityAppLockSubtitle;

  /// No description provided for @securityBiometric.
  ///
  /// In en, this message translates to:
  /// **'Biometric Login'**
  String get securityBiometric;

  /// No description provided for @securityBiometricSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Face ID / Touch ID'**
  String get securityBiometricSubtitle;

  /// No description provided for @securitySectionPassword.
  ///
  /// In en, this message translates to:
  /// **'PASSWORD'**
  String get securitySectionPassword;

  /// No description provided for @securityChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get securityChangePassword;

  /// No description provided for @securityPasswordLastChanged.
  ///
  /// In en, this message translates to:
  /// **'Last changed 30 days ago'**
  String get securityPasswordLastChanged;

  /// No description provided for @securityPasswordComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Password change flow coming soon'**
  String get securityPasswordComingSoon;

  /// No description provided for @securitySectionSessions.
  ///
  /// In en, this message translates to:
  /// **'SESSIONS'**
  String get securitySectionSessions;

  /// No description provided for @securityActiveSessions.
  ///
  /// In en, this message translates to:
  /// **'Active Sessions'**
  String get securityActiveSessions;

  /// No description provided for @securityActiveDevices.
  ///
  /// In en, this message translates to:
  /// **'1 device currently active'**
  String get securityActiveDevices;

  /// No description provided for @securityOneActiveSession.
  ///
  /// In en, this message translates to:
  /// **'1 active session on this device'**
  String get securityOneActiveSession;

  /// No description provided for @securitySignOutAll.
  ///
  /// In en, this message translates to:
  /// **'Sign Out All Devices'**
  String get securitySignOutAll;

  /// No description provided for @securitySignOutAllSubtitle.
  ///
  /// In en, this message translates to:
  /// **'End all other sessions'**
  String get securitySignOutAllSubtitle;

  /// No description provided for @securitySignOutAllTitle.
  ///
  /// In en, this message translates to:
  /// **'Sign Out All Devices?'**
  String get securitySignOutAllTitle;

  /// No description provided for @securitySignOutAllMessage.
  ///
  /// In en, this message translates to:
  /// **'This will end all sessions on other devices. You will stay logged in on this device.'**
  String get securitySignOutAllMessage;

  /// No description provided for @securityAllSessionsEnded.
  ///
  /// In en, this message translates to:
  /// **'All other sessions ended'**
  String get securityAllSessionsEnded;

  /// No description provided for @securitySignOutAllButton.
  ///
  /// In en, this message translates to:
  /// **'Sign Out All'**
  String get securitySignOutAllButton;

  /// No description provided for @dataBackupTitle.
  ///
  /// In en, this message translates to:
  /// **'Data & Backup'**
  String get dataBackupTitle;

  /// No description provided for @dataBackupLastBackup.
  ///
  /// In en, this message translates to:
  /// **'Last Backup'**
  String get dataBackupLastBackup;

  /// No description provided for @dataBackupNoBackups.
  ///
  /// In en, this message translates to:
  /// **'No backups yet'**
  String get dataBackupNoBackups;

  /// No description provided for @dataBackupSectionBackup.
  ///
  /// In en, this message translates to:
  /// **'BACKUP'**
  String get dataBackupSectionBackup;

  /// No description provided for @dataBackupAutoBackup.
  ///
  /// In en, this message translates to:
  /// **'Auto-Backup'**
  String get dataBackupAutoBackup;

  /// No description provided for @dataBackupAutoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Backup data daily to cloud'**
  String get dataBackupAutoSubtitle;

  /// No description provided for @dataBackupNow.
  ///
  /// In en, this message translates to:
  /// **'Backup Now'**
  String get dataBackupNow;

  /// No description provided for @dataBackupComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Backup feature coming soon'**
  String get dataBackupComingSoon;

  /// No description provided for @dataBackupRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore Data'**
  String get dataBackupRestore;

  /// No description provided for @dataBackupRestoreMessage.
  ///
  /// In en, this message translates to:
  /// **'This will replace your current data with the latest backup. This action cannot be undone.'**
  String get dataBackupRestoreMessage;

  /// No description provided for @dataBackupRestored.
  ///
  /// In en, this message translates to:
  /// **'Data restored from backup'**
  String get dataBackupRestored;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @dataBackupSectionExport.
  ///
  /// In en, this message translates to:
  /// **'EXPORT'**
  String get dataBackupSectionExport;

  /// No description provided for @dataBackupExportAll.
  ///
  /// In en, this message translates to:
  /// **'Export All Data'**
  String get dataBackupExportAll;

  /// No description provided for @dataBackupExportComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Export feature coming soon'**
  String get dataBackupExportComingSoon;

  /// No description provided for @dataBackupSectionDanger.
  ///
  /// In en, this message translates to:
  /// **'DANGER ZONE'**
  String get dataBackupSectionDanger;

  /// No description provided for @dataBackupDeleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete All Data'**
  String get dataBackupDeleteAll;

  /// No description provided for @dataBackupDeleteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Permanently erase everything'**
  String get dataBackupDeleteSubtitle;

  /// No description provided for @dataBackupDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. All your transactions, inventory and settings will be permanently deleted.'**
  String get dataBackupDeleteMessage;

  /// No description provided for @dataBackupDeleteEverything.
  ///
  /// In en, this message translates to:
  /// **'Delete Everything'**
  String get dataBackupDeleteEverything;

  /// No description provided for @dataBackupConfirmEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email to confirm'**
  String get dataBackupConfirmEmail;

  /// No description provided for @dataBackupConfirmEmailHint.
  ///
  /// In en, this message translates to:
  /// **'your@email.com'**
  String get dataBackupConfirmEmailHint;

  /// No description provided for @dataBackupEmailMismatch.
  ///
  /// In en, this message translates to:
  /// **'Email does not match your account'**
  String get dataBackupEmailMismatch;

  /// No description provided for @dataBackupDeleting.
  ///
  /// In en, this message translates to:
  /// **'Deleting your account...'**
  String get dataBackupDeleting;

  /// No description provided for @dataBackupDeleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Account deleted successfully'**
  String get dataBackupDeleteSuccess;

  /// No description provided for @dataBackupDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account. Please try again.'**
  String get dataBackupDeleteFailed;

  /// No description provided for @helpCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Help Center'**
  String get helpCenterTitle;

  /// No description provided for @helpCenterSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for help...'**
  String get helpCenterSearchHint;

  /// No description provided for @helpCenterSectionQuickHelp.
  ///
  /// In en, this message translates to:
  /// **'QUICK HELP'**
  String get helpCenterSectionQuickHelp;

  /// No description provided for @helpCenterGettingStarted.
  ///
  /// In en, this message translates to:
  /// **'Getting\nStarted'**
  String get helpCenterGettingStarted;

  /// No description provided for @helpCenterTransactionsHelp.
  ///
  /// In en, this message translates to:
  /// **'Transactions\nHelp'**
  String get helpCenterTransactionsHelp;

  /// No description provided for @helpCenterReportsGuide.
  ///
  /// In en, this message translates to:
  /// **'Reports\nGuide'**
  String get helpCenterReportsGuide;

  /// No description provided for @helpCenterSectionFaq.
  ///
  /// In en, this message translates to:
  /// **'FREQUENTLY ASKED'**
  String get helpCenterSectionFaq;

  /// No description provided for @helpCenterFaqAddTransactionQ.
  ///
  /// In en, this message translates to:
  /// **'How do I add a new transaction?'**
  String get helpCenterFaqAddTransactionQ;

  /// No description provided for @helpCenterFaqAddTransactionA.
  ///
  /// In en, this message translates to:
  /// **'Tap the + button at the bottom of the screen to add income or expense transactions.'**
  String get helpCenterFaqAddTransactionA;

  /// No description provided for @helpCenterFaqExportQ.
  ///
  /// In en, this message translates to:
  /// **'How do I export my reports?'**
  String get helpCenterFaqExportQ;

  /// No description provided for @helpCenterFaqExportA.
  ///
  /// In en, this message translates to:
  /// **'Go to Reports > Tap the share icon in the top right to access the Export & Share center.'**
  String get helpCenterFaqExportA;

  /// No description provided for @helpCenterFaqInventoryQ.
  ///
  /// In en, this message translates to:
  /// **'How do I manage my inventory?'**
  String get helpCenterFaqInventoryQ;

  /// No description provided for @helpCenterFaqInventoryA.
  ///
  /// In en, this message translates to:
  /// **'Navigate to the Manage tab > Inventory to view, add, and track your products and materials.'**
  String get helpCenterFaqInventoryA;

  /// No description provided for @helpCenterFaqRecurringQ.
  ///
  /// In en, this message translates to:
  /// **'How do I set up recurring transactions?'**
  String get helpCenterFaqRecurringQ;

  /// No description provided for @helpCenterFaqRecurringA.
  ///
  /// In en, this message translates to:
  /// **'Go to Cash Flow > Coming Up section > Tap \"Manage\" to add scheduled transactions.'**
  String get helpCenterFaqRecurringA;

  /// No description provided for @helpCenterFaqCurrencyQ.
  ///
  /// In en, this message translates to:
  /// **'Can I change my currency?'**
  String get helpCenterFaqCurrencyQ;

  /// No description provided for @helpCenterFaqCurrencyA.
  ///
  /// In en, this message translates to:
  /// **'Yes! Go to Profile > Currency & Language to change your default currency.'**
  String get helpCenterFaqCurrencyA;

  /// No description provided for @helpCenterSectionMoreHelp.
  ///
  /// In en, this message translates to:
  /// **'NEED MORE HELP?'**
  String get helpCenterSectionMoreHelp;

  /// No description provided for @helpCenterContactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact Support'**
  String get helpCenterContactSupport;

  /// No description provided for @helpCenterSupportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'re here to help 24/7'**
  String get helpCenterSupportSubtitle;

  /// No description provided for @helpCenterChat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get helpCenterChat;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Revvo'**
  String get aboutTitle;

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Revvo'**
  String get appName;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Smart Financial Management'**
  String get aboutTagline;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version} (Build {buildNumber})'**
  String aboutVersion(String version, String buildNumber);

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @aboutTermsOfService.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get aboutTermsOfService;

  /// No description provided for @aboutOpeningTerms.
  ///
  /// In en, this message translates to:
  /// **'Opening Terms of Service...'**
  String get aboutOpeningTerms;

  /// No description provided for @aboutPrivacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get aboutPrivacyPolicy;

  /// No description provided for @aboutOpeningPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Opening Privacy Policy...'**
  String get aboutOpeningPrivacy;

  /// No description provided for @aboutOpenSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get aboutOpenSourceLicenses;

  /// No description provided for @aboutRateApp.
  ///
  /// In en, this message translates to:
  /// **'Rate the App'**
  String get aboutRateApp;

  /// No description provided for @aboutRateThankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you! Opening app store...'**
  String get aboutRateThankYou;

  /// No description provided for @aboutShareRevvo.
  ///
  /// In en, this message translates to:
  /// **'Share Revvo'**
  String get aboutShareRevvo;

  /// No description provided for @aboutShareCopied.
  ///
  /// In en, this message translates to:
  /// **'Share link copied to clipboard!'**
  String get aboutShareCopied;

  /// No description provided for @aboutMadeIn.
  ///
  /// In en, this message translates to:
  /// **'Made with ❤️ in Egypt'**
  String get aboutMadeIn;

  /// No description provided for @aboutCopyright.
  ///
  /// In en, this message translates to:
  /// **'© 2026 Revvo. All rights reserved.'**
  String get aboutCopyright;

  /// No description provided for @subscriptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Plan'**
  String get subscriptionTitle;

  /// No description provided for @subscriptionFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get subscriptionFree;

  /// No description provided for @subscriptionAvailableUpgrades.
  ///
  /// In en, this message translates to:
  /// **'Available Upgrades'**
  String get subscriptionAvailableUpgrades;

  /// No description provided for @subscriptionManagePlan.
  ///
  /// In en, this message translates to:
  /// **'Manage Plan'**
  String get subscriptionManagePlan;

  /// No description provided for @subscriptionSaveYearly.
  ///
  /// In en, this message translates to:
  /// **'Save 20% on yearly'**
  String get subscriptionSaveYearly;

  /// No description provided for @subscriptionFaqTitle.
  ///
  /// In en, this message translates to:
  /// **'Frequently Asked Questions'**
  String get subscriptionFaqTitle;

  /// No description provided for @subscriptionLaunchMode.
  ///
  /// In en, this message translates to:
  /// **'Launch Mode'**
  String get subscriptionLaunchMode;

  /// No description provided for @subscriptionLaunchDesc.
  ///
  /// In en, this message translates to:
  /// **'Perfect for early-stage startups.'**
  String get subscriptionLaunchDesc;

  /// No description provided for @subscriptionForever.
  ///
  /// In en, this message translates to:
  /// **'Forever'**
  String get subscriptionForever;

  /// No description provided for @subscriptionGrowthMode.
  ///
  /// In en, this message translates to:
  /// **'Growth Mode'**
  String get subscriptionGrowthMode;

  /// No description provided for @subscriptionGrowthDesc.
  ///
  /// In en, this message translates to:
  /// **'For scaling businesses.'**
  String get subscriptionGrowthDesc;

  /// No description provided for @subscriptionPerMonth.
  ///
  /// In en, this message translates to:
  /// **'/mo'**
  String get subscriptionPerMonth;

  /// No description provided for @subscriptionProMode.
  ///
  /// In en, this message translates to:
  /// **'Pro Mode'**
  String get subscriptionProMode;

  /// No description provided for @subscriptionProDesc.
  ///
  /// In en, this message translates to:
  /// **'For established enterprises.'**
  String get subscriptionProDesc;

  /// No description provided for @subscriptionFeatureEverythingLaunch.
  ///
  /// In en, this message translates to:
  /// **'Everything in Launch Mode'**
  String get subscriptionFeatureEverythingLaunch;

  /// No description provided for @subscriptionFeatureSalesCogs.
  ///
  /// In en, this message translates to:
  /// **'Sales system with COGS tracking'**
  String get subscriptionFeatureSalesCogs;

  /// No description provided for @subscriptionFeatureGoodsReceiving.
  ///
  /// In en, this message translates to:
  /// **'Goods receiving & inventory auto-link'**
  String get subscriptionFeatureGoodsReceiving;

  /// No description provided for @subscriptionFeatureIncomeStatement.
  ///
  /// In en, this message translates to:
  /// **'Full Income Statement (P&L)'**
  String get subscriptionFeatureIncomeStatement;

  /// No description provided for @subscriptionFeatureBalanceSheet.
  ///
  /// In en, this message translates to:
  /// **'Balance Sheet'**
  String get subscriptionFeatureBalanceSheet;

  /// No description provided for @subscriptionFeatureRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring transactions'**
  String get subscriptionFeatureRecurring;

  /// No description provided for @subscriptionFeatureAiInsights.
  ///
  /// In en, this message translates to:
  /// **'AI financial insights'**
  String get subscriptionFeatureAiInsights;

  /// No description provided for @subscriptionFeatureShopify.
  ///
  /// In en, this message translates to:
  /// **'Shopify integration & order sync'**
  String get subscriptionFeatureShopify;

  /// No description provided for @subscriptionFeature5Team.
  ///
  /// In en, this message translates to:
  /// **'5 Team members'**
  String get subscriptionFeature5Team;

  /// No description provided for @subscriptionFeatureEverythingGrowth.
  ///
  /// In en, this message translates to:
  /// **'Everything in Growth Mode'**
  String get subscriptionFeatureEverythingGrowth;

  /// No description provided for @subscriptionFeatureFinancialModeling.
  ///
  /// In en, this message translates to:
  /// **'Advanced financial modeling'**
  String get subscriptionFeatureFinancialModeling;

  /// No description provided for @subscriptionFeatureInvestorDash.
  ///
  /// In en, this message translates to:
  /// **'Investor reporting dashboard'**
  String get subscriptionFeatureInvestorDash;

  /// No description provided for @subscriptionFeatureMultiStore.
  ///
  /// In en, this message translates to:
  /// **'Multi-store management'**
  String get subscriptionFeatureMultiStore;

  /// No description provided for @subscriptionFeatureUnlimitedApi.
  ///
  /// In en, this message translates to:
  /// **'Unlimited users & full API access'**
  String get subscriptionFeatureUnlimitedApi;

  /// No description provided for @subscriptionFeatureIncomeExpense.
  ///
  /// In en, this message translates to:
  /// **'Income & expense tracking'**
  String get subscriptionFeatureIncomeExpense;

  /// No description provided for @subscriptionFeatureProfitLoss.
  ///
  /// In en, this message translates to:
  /// **'Simple profit/loss report'**
  String get subscriptionFeatureProfitLoss;

  /// No description provided for @subscriptionFeatureCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Cash flow overview'**
  String get subscriptionFeatureCashFlow;

  /// No description provided for @subscriptionFeatureBasicInventory.
  ///
  /// In en, this message translates to:
  /// **'Basic inventory & stock'**
  String get subscriptionFeatureBasicInventory;

  /// No description provided for @subscriptionFeatureSupplierLedger.
  ///
  /// In en, this message translates to:
  /// **'Supplier ledger & purchases'**
  String get subscriptionFeatureSupplierLedger;

  /// No description provided for @subscriptionFeatureCustomCategories.
  ///
  /// In en, this message translates to:
  /// **'Custom categories'**
  String get subscriptionFeatureCustomCategories;

  /// No description provided for @subscriptionFeature1Admin.
  ///
  /// In en, this message translates to:
  /// **'1 Admin User'**
  String get subscriptionFeature1Admin;

  /// No description provided for @subscriptionFeatureSimpleCashOverview.
  ///
  /// In en, this message translates to:
  /// **'Simple money in/out overview'**
  String get subscriptionFeatureSimpleCashOverview;

  /// No description provided for @subscriptionFeatureUpTo20Products.
  ///
  /// In en, this message translates to:
  /// **'Up to 20 products'**
  String get subscriptionFeatureUpTo20Products;

  /// No description provided for @subscriptionFeatureUnlimitedProducts.
  ///
  /// In en, this message translates to:
  /// **'Unlimited products'**
  String get subscriptionFeatureUnlimitedProducts;

  /// No description provided for @subscriptionFeatureSupplierManagement.
  ///
  /// In en, this message translates to:
  /// **'Supplier management & ledger'**
  String get subscriptionFeatureSupplierManagement;

  /// No description provided for @subscriptionFeatureFullCashFlowAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Full GAAP Cash Flow analysis'**
  String get subscriptionFeatureFullCashFlowAnalysis;

  /// No description provided for @subscriptionActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get subscriptionActive;

  /// No description provided for @subscriptionEverythingLaunchPlus.
  ///
  /// In en, this message translates to:
  /// **'Everything in Launch, plus:'**
  String get subscriptionEverythingLaunchPlus;

  /// No description provided for @subscriptionFeatureBudgetLimits.
  ///
  /// In en, this message translates to:
  /// **'Budget limits per category'**
  String get subscriptionFeatureBudgetLimits;

  /// No description provided for @subscriptionFeaturePurchaseDash.
  ///
  /// In en, this message translates to:
  /// **'Purchase & payment dashboards'**
  String get subscriptionFeaturePurchaseDash;

  /// No description provided for @subscriptionFeatureRawMaterials.
  ///
  /// In en, this message translates to:
  /// **'Raw materials tracking'**
  String get subscriptionFeatureRawMaterials;

  /// No description provided for @subscriptionFeatureReportExport.
  ///
  /// In en, this message translates to:
  /// **'Report export & share'**
  String get subscriptionFeatureReportExport;

  /// No description provided for @subscriptionCurrentPlan.
  ///
  /// In en, this message translates to:
  /// **'Current Plan'**
  String get subscriptionCurrentPlan;

  /// No description provided for @subscriptionSwitchToLaunch.
  ///
  /// In en, this message translates to:
  /// **'Switch to Launch Mode'**
  String get subscriptionSwitchToLaunch;

  /// No description provided for @subscriptionSwitchToGrowth.
  ///
  /// In en, this message translates to:
  /// **'Switch to Growth'**
  String get subscriptionSwitchToGrowth;

  /// No description provided for @subscriptionSwitchedToGrowth.
  ///
  /// In en, this message translates to:
  /// **'Switched to Growth Mode!'**
  String get subscriptionSwitchedToGrowth;

  /// No description provided for @subscriptionUpgradeToGrowth.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Growth'**
  String get subscriptionUpgradeToGrowth;

  /// No description provided for @subscriptionMostPopular.
  ///
  /// In en, this message translates to:
  /// **'MOST POPULAR'**
  String get subscriptionMostPopular;

  /// No description provided for @subscriptionEverythingGrowthPlus.
  ///
  /// In en, this message translates to:
  /// **'Everything in Growth, plus:'**
  String get subscriptionEverythingGrowthPlus;

  /// No description provided for @subscriptionAddedToWaitlist.
  ///
  /// In en, this message translates to:
  /// **'Added to Pro Mode waitlist!'**
  String get subscriptionAddedToWaitlist;

  /// No description provided for @subscriptionJoinWaitlist.
  ///
  /// In en, this message translates to:
  /// **'Join Waitlist'**
  String get subscriptionJoinWaitlist;

  /// No description provided for @subscriptionSwitchLaunchTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to Launch Mode?'**
  String get subscriptionSwitchLaunchTitle;

  /// No description provided for @subscriptionSwitchLaunchMessage.
  ///
  /// In en, this message translates to:
  /// **'You will lose access to Growth features like Balance Sheet, Income Statement, AI Insights, and more. Your data will be preserved.'**
  String get subscriptionSwitchLaunchMessage;

  /// No description provided for @subscriptionShopifyDisconnectWarning.
  ///
  /// In en, this message translates to:
  /// **' Your Shopify integration will also be disconnected.'**
  String get subscriptionShopifyDisconnectWarning;

  /// No description provided for @subscriptionSwitchToTierTitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to {tier}?'**
  String subscriptionSwitchToTierTitle(String tier);

  /// No description provided for @subscriptionSwitchGenericMessage.
  ///
  /// In en, this message translates to:
  /// **'Your data will be preserved. Feature access will change based on the new plan.'**
  String get subscriptionSwitchGenericMessage;

  /// No description provided for @subscriptionSwitchedToTier.
  ///
  /// In en, this message translates to:
  /// **'Switched to {tier} Mode'**
  String subscriptionSwitchedToTier(String tier);

  /// No description provided for @subscriptionSwitchToTierButton.
  ///
  /// In en, this message translates to:
  /// **'Switch to {tier}'**
  String subscriptionSwitchToTierButton(String tier);

  /// No description provided for @subscriptionComparisonComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Full feature comparison coming soon'**
  String get subscriptionComparisonComingSoon;

  /// No description provided for @subscriptionCompareFeatures.
  ///
  /// In en, this message translates to:
  /// **'Compare full feature matrix'**
  String get subscriptionCompareFeatures;

  /// No description provided for @subscriptionFaqShopifyQ.
  ///
  /// In en, this message translates to:
  /// **'Does Growth Mode include Shopify integration?'**
  String get subscriptionFaqShopifyQ;

  /// No description provided for @subscriptionFaqShopifyA.
  ///
  /// In en, this message translates to:
  /// **'Yes! Growth Mode includes full Shopify e-commerce integration: real-time order sync, inventory management, and product mapping between your Shopify store and Revvo.'**
  String get subscriptionFaqShopifyA;

  /// No description provided for @subscriptionFaqShopifyHowQ.
  ///
  /// In en, this message translates to:
  /// **'How does Shopify integration work?'**
  String get subscriptionFaqShopifyHowQ;

  /// No description provided for @subscriptionFaqShopifyHowA.
  ///
  /// In en, this message translates to:
  /// **'After upgrading to Growth Mode, you connect your Shopify store once through a secure OAuth process. After that, your Shopify orders automatically sync as Revvo sales in real-time. You can also sync inventory on-demand between Shopify and Revvo.'**
  String get subscriptionFaqShopifyHowA;

  /// No description provided for @subscriptionFaqDowngradeQ.
  ///
  /// In en, this message translates to:
  /// **'Can I downgrade later?'**
  String get subscriptionFaqDowngradeQ;

  /// No description provided for @subscriptionFaqDowngradeA.
  ///
  /// In en, this message translates to:
  /// **'Yes, you can switch between plans at any time. Your data will be preserved, but access to plan-specific features will change. If you downgrade from Growth, your Shopify connection will be paused but existing data is kept.'**
  String get subscriptionFaqDowngradeA;

  /// No description provided for @subscriptionFaqEnterpriseQ.
  ///
  /// In en, this message translates to:
  /// **'Do you offer custom enterprise plans?'**
  String get subscriptionFaqEnterpriseQ;

  /// No description provided for @subscriptionFaqEnterpriseA.
  ///
  /// In en, this message translates to:
  /// **'Absolutely. For organizations needing custom integrations or dedicated support, please contact our sales team directly.'**
  String get subscriptionFaqEnterpriseA;

  /// No description provided for @subscriptionGrowthPrice.
  ///
  /// In en, this message translates to:
  /// **'{currency} 249'**
  String subscriptionGrowthPrice(String currency);

  /// No description provided for @subscriptionProPrice.
  ///
  /// In en, this message translates to:
  /// **'{currency} 749'**
  String subscriptionProPrice(String currency);

  /// No description provided for @subscriptionSubscribeOnWeb.
  ///
  /// In en, this message translates to:
  /// **'Subscribe on Web'**
  String get subscriptionSubscribeOnWeb;

  /// No description provided for @subscriptionManageOnWeb.
  ///
  /// In en, this message translates to:
  /// **'Manage on Web'**
  String get subscriptionManageOnWeb;

  /// No description provided for @subscriptionOpenBilling.
  ///
  /// In en, this message translates to:
  /// **'Open Billing Portal'**
  String get subscriptionOpenBilling;

  /// No description provided for @subscriptionRefreshing.
  ///
  /// In en, this message translates to:
  /// **'Refreshing subscription...'**
  String get subscriptionRefreshing;

  /// No description provided for @subscriptionRefreshed.
  ///
  /// In en, this message translates to:
  /// **'Subscription status updated'**
  String get subscriptionRefreshed;

  /// No description provided for @subscriptionGracePeriod.
  ///
  /// In en, this message translates to:
  /// **'Grace Period'**
  String get subscriptionGracePeriod;

  /// No description provided for @subscriptionExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get subscriptionExpired;

  /// No description provided for @subscriptionExpiresOn.
  ///
  /// In en, this message translates to:
  /// **'Expires {date}'**
  String subscriptionExpiresOn(String date);

  /// No description provided for @subscriptionGraceMessage.
  ///
  /// In en, this message translates to:
  /// **'Your subscription has expired. Renew within {days} days to keep Growth features.'**
  String subscriptionGraceMessage(int days);

  /// No description provided for @subscriptionExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'Your Growth subscription has expired. Subscribe again to restore access.'**
  String get subscriptionExpiredMessage;

  /// No description provided for @subscriptionRenew.
  ///
  /// In en, this message translates to:
  /// **'Renew Subscription'**
  String get subscriptionRenew;

  /// No description provided for @subscriptionSetupGrowthLater.
  ///
  /// In en, this message translates to:
  /// **'You can subscribe to Growth anytime from Settings.'**
  String get subscriptionSetupGrowthLater;

  /// No description provided for @orderCancelledBanner.
  ///
  /// In en, this message translates to:
  /// **'This order has been cancelled'**
  String get orderCancelledBanner;

  /// No description provided for @refunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get refunded;

  /// No description provided for @partiallyPaid.
  ///
  /// In en, this message translates to:
  /// **'Partially Paid'**
  String get partiallyPaid;

  /// No description provided for @fulfilled.
  ///
  /// In en, this message translates to:
  /// **'Fulfilled'**
  String get fulfilled;

  /// No description provided for @partiallyFulfilled.
  ///
  /// In en, this message translates to:
  /// **'Partially Fulfilled'**
  String get partiallyFulfilled;

  /// No description provided for @unfulfilled.
  ///
  /// In en, this message translates to:
  /// **'Unfulfilled'**
  String get unfulfilled;

  /// No description provided for @inProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get inProgress;

  /// No description provided for @fulfillment.
  ///
  /// In en, this message translates to:
  /// **'Fulfillment'**
  String get fulfillment;

  /// No description provided for @syncedFromShopify.
  ///
  /// In en, this message translates to:
  /// **'Synced from Shopify — statuses update automatically'**
  String get syncedFromShopify;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @shipped.
  ///
  /// In en, this message translates to:
  /// **'Shipped'**
  String get shipped;

  /// No description provided for @orderShippedFulfilled.
  ///
  /// In en, this message translates to:
  /// **'Order shipped & fulfilled'**
  String get orderShippedFulfilled;

  /// No description provided for @markedPartiallyShipped.
  ///
  /// In en, this message translates to:
  /// **'Marked as partially shipped'**
  String get markedPartiallyShipped;

  /// No description provided for @markedUnfulfilled.
  ///
  /// In en, this message translates to:
  /// **'Marked as unfulfilled'**
  String get markedUnfulfilled;

  /// No description provided for @fulfillmentStatus.
  ///
  /// In en, this message translates to:
  /// **'Fulfillment Status'**
  String get fulfillmentStatus;

  /// No description provided for @cannotCancelHere.
  ///
  /// In en, this message translates to:
  /// **'Cannot Cancel Here'**
  String get cannotCancelHere;

  /// No description provided for @cannotCancelHereMsg.
  ///
  /// In en, this message translates to:
  /// **'Shopify order #{orderNumber} is marked as paid.\n\nPaid orders must be cancelled directly on Shopify (which will handle the refund automatically).\n\nOnce cancelled on Shopify, it will sync to Revvo automatically.'**
  String cannotCancelHereMsg(String orderNumber);

  /// No description provided for @keepOrder.
  ///
  /// In en, this message translates to:
  /// **'Keep Order'**
  String get keepOrder;

  /// No description provided for @cancelOrderConfirmShopify.
  ///
  /// In en, this message translates to:
  /// **'This sale is linked to Shopify order #{orderNumber}.\n\nCancelling here will:\n• Restore stock in Revvo\n• Create reversal accounting entries\n• Cancel the order on Shopify\n\nThis action cannot be undone.'**
  String cancelOrderConfirmShopify(String orderNumber);

  /// No description provided for @cancelOrderConfirmManual.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to cancel this order?\n\nThis will:\n• Restore stock\n• Create reversal accounting entries\n\nThis action cannot be undone.'**
  String get cancelOrderConfirmManual;

  /// No description provided for @statusUpdatedLocallyOnly.
  ///
  /// In en, this message translates to:
  /// **'Status updated locally only. Shopify order status is not affected.'**
  String get statusUpdatedLocallyOnly;

  /// No description provided for @cogsZeroWarning.
  ///
  /// In en, this message translates to:
  /// **'COGS is zero — profit numbers may be inaccurate.'**
  String get cogsZeroWarning;

  /// No description provided for @paymentSyncedToShopify.
  ///
  /// In en, this message translates to:
  /// **'Payment synced to Shopify'**
  String get paymentSyncedToShopify;

  /// No description provided for @shopifyPaymentSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Shopify payment sync failed for order: {error}'**
  String shopifyPaymentSyncFailed(String error);

  /// No description provided for @shopifyCancelFailedMsg.
  ///
  /// In en, this message translates to:
  /// **'Shopify cancel failed: {error}'**
  String shopifyCancelFailedMsg(String error);

  /// No description provided for @itemsToFulfill.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{item} other{items}} to fulfill'**
  String itemsToFulfill(int count);

  /// No description provided for @partiallyShipped.
  ///
  /// In en, this message translates to:
  /// **'Partially Shipped'**
  String get partiallyShipped;

  /// No description provided for @orderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled'**
  String get orderCancelled;

  /// No description provided for @orderCancelledDetail.
  ///
  /// In en, this message translates to:
  /// **'Order cancelled — stock restored, reversal entries created'**
  String get orderCancelledDetail;

  /// No description provided for @orderRefunded.
  ///
  /// In en, this message translates to:
  /// **'Order refunded'**
  String get orderRefunded;

  /// No description provided for @orderRefundedDetail.
  ///
  /// In en, this message translates to:
  /// **'Order refunded — stock restored, reversal entries created'**
  String get orderRefundedDetail;

  /// No description provided for @missingCostOfGoods.
  ///
  /// In en, this message translates to:
  /// **'Missing Cost of Goods'**
  String get missingCostOfGoods;

  /// No description provided for @fix.
  ///
  /// In en, this message translates to:
  /// **'Fix'**
  String get fix;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'Items ({count})'**
  String itemsCount(int count);

  /// No description provided for @totals.
  ///
  /// In en, this message translates to:
  /// **'Totals'**
  String get totals;

  /// No description provided for @editCogs.
  ///
  /// In en, this message translates to:
  /// **'Edit COGS'**
  String get editCogs;

  /// No description provided for @updatePaymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Update Payment Status'**
  String get updatePaymentStatus;

  /// No description provided for @shipOrder.
  ///
  /// In en, this message translates to:
  /// **'Ship Order'**
  String get shipOrder;

  /// No description provided for @orderMarkedAsPaid.
  ///
  /// In en, this message translates to:
  /// **'Order marked as paid'**
  String get orderMarkedAsPaid;

  /// No description provided for @markAsPaidAmount.
  ///
  /// In en, this message translates to:
  /// **'Mark as Paid — {currency} {amount}'**
  String markAsPaidAmount(String currency, String amount);

  /// No description provided for @shippingCarrier.
  ///
  /// In en, this message translates to:
  /// **'Shipping Carrier'**
  String get shippingCarrier;

  /// No description provided for @trackingNumber.
  ///
  /// In en, this message translates to:
  /// **'Tracking Number'**
  String get trackingNumber;

  /// No description provided for @markAsFullyFulfilled.
  ///
  /// In en, this message translates to:
  /// **'Mark as fully fulfilled'**
  String get markAsFullyFulfilled;

  /// No description provided for @allItemsMarkedShipped.
  ///
  /// In en, this message translates to:
  /// **'All items in this order will be marked as shipped'**
  String get allItemsMarkedShipped;

  /// No description provided for @shipFulfillOrder.
  ///
  /// In en, this message translates to:
  /// **'Ship & Fulfill Order'**
  String get shipFulfillOrder;

  /// No description provided for @shipPartialOrder.
  ///
  /// In en, this message translates to:
  /// **'Ship Partial Order'**
  String get shipPartialOrder;

  /// No description provided for @fedex.
  ///
  /// In en, this message translates to:
  /// **'FedEx'**
  String get fedex;

  /// No description provided for @aramex.
  ///
  /// In en, this message translates to:
  /// **'Aramex'**
  String get aramex;

  /// No description provided for @egyptPost.
  ///
  /// In en, this message translates to:
  /// **'Egypt Post'**
  String get egyptPost;

  /// No description provided for @editSale.
  ///
  /// In en, this message translates to:
  /// **'Edit Sale'**
  String get editSale;

  /// No description provided for @recordSale.
  ///
  /// In en, this message translates to:
  /// **'Record Sale'**
  String get recordSale;

  /// No description provided for @saveSale.
  ///
  /// In en, this message translates to:
  /// **'Save sale'**
  String get saveSale;

  /// No description provided for @saveSaleButton.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveSaleButton;

  /// No description provided for @addNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Add notes (optional)'**
  String get addNotesOptional;

  /// No description provided for @variantsStockInfo.
  ///
  /// In en, this message translates to:
  /// **'{count} variants · Stock: {stock}'**
  String variantsStockInfo(int count, int stock);

  /// No description provided for @variantPriceStock.
  ///
  /// In en, this message translates to:
  /// **'{currency} {price} · {stock} in stock'**
  String variantPriceStock(String currency, String price, int stock);

  /// No description provided for @saleRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded sale of {currency} {amount}'**
  String saleRecorded(String currency, String amount);

  /// No description provided for @saleUpdated.
  ///
  /// In en, this message translates to:
  /// **'Updated sale of {currency} {amount}'**
  String saleUpdated(String currency, String amount);

  /// No description provided for @customer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customer;

  /// No description provided for @customerNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Customer name (optional)'**
  String get customerNameOptional;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @toggleShippingHint.
  ///
  /// In en, this message translates to:
  /// **'Toggle on to add shipping details'**
  String get toggleShippingHint;

  /// No description provided for @shippingAddress.
  ///
  /// In en, this message translates to:
  /// **'Shipping address'**
  String get shippingAddress;

  /// No description provided for @shippingMethodHint.
  ///
  /// In en, this message translates to:
  /// **'Method (e.g. Aramex)'**
  String get shippingMethodHint;

  /// No description provided for @trackingNumberOrLink.
  ///
  /// In en, this message translates to:
  /// **'Tracking number or link'**
  String get trackingNumberOrLink;

  /// No description provided for @lessDetails.
  ///
  /// In en, this message translates to:
  /// **'Less details'**
  String get lessDetails;

  /// No description provided for @moreDetails.
  ///
  /// In en, this message translates to:
  /// **'More details'**
  String get moreDetails;

  /// No description provided for @shippingNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Shipping notes (optional)'**
  String get shippingNotesOptional;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get addItem;

  /// No description provided for @productItemName.
  ///
  /// In en, this message translates to:
  /// **'Product / item name'**
  String get productItemName;

  /// No description provided for @qty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get qty;

  /// No description provided for @unitPrice.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get unitPrice;

  /// No description provided for @costLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost: {currency} {amount}'**
  String costLabel(String currency, String amount);

  /// No description provided for @stockLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock: {count}'**
  String stockLabel(int count);

  /// No description provided for @noProductsInInventory.
  ///
  /// In en, this message translates to:
  /// **'No products in inventory. Add products first.'**
  String get noProductsInInventory;

  /// No description provided for @selectProduct.
  ///
  /// In en, this message translates to:
  /// **'Select Product'**
  String get selectProduct;

  /// No description provided for @searchProducts.
  ///
  /// In en, this message translates to:
  /// **'Search products…'**
  String get searchProducts;

  /// No description provided for @noProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No products found'**
  String get noProductsFound;

  /// No description provided for @productPriceInfo.
  ///
  /// In en, this message translates to:
  /// **'Sell: {currency} {sellPrice} · Cost: {currency2} {costPrice} · Stock: {stock}'**
  String productPriceInfo(
    String currency,
    String sellPrice,
    String currency2,
    String costPrice,
    int stock,
  );

  /// No description provided for @selectVariant.
  ///
  /// In en, this message translates to:
  /// **'Select Variant — {name}'**
  String selectVariant(String name);

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @summary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get summary;

  /// No description provided for @updateSale.
  ///
  /// In en, this message translates to:
  /// **'Update Sale'**
  String get updateSale;

  /// No description provided for @confirmSale.
  ///
  /// In en, this message translates to:
  /// **'Confirm Sale'**
  String get confirmSale;

  /// No description provided for @confirmSaleTotal.
  ///
  /// In en, this message translates to:
  /// **'Confirm Sale · {currency} {amount}'**
  String confirmSaleTotal(String currency, String amount);

  /// No description provided for @errorAddItem.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item with a name, quantity, and price'**
  String get errorAddItem;

  /// No description provided for @errorTotalZero.
  ///
  /// In en, this message translates to:
  /// **'Sale total must be greater than zero'**
  String get errorTotalZero;

  /// No description provided for @errorPartialZero.
  ///
  /// In en, this message translates to:
  /// **'Partial payment amount must be greater than zero'**
  String get errorPartialZero;

  /// No description provided for @errorPartialExceedsTotal.
  ///
  /// In en, this message translates to:
  /// **'Partial amount must be less than the total. Use \"Paid\" for full payment.'**
  String get errorPartialExceedsTotal;

  /// No description provided for @errorNoValidItems.
  ///
  /// In en, this message translates to:
  /// **'No valid items — each item needs a name, quantity, and price'**
  String get errorNoValidItems;

  /// No description provided for @insufficientStock.
  ///
  /// In en, this message translates to:
  /// **'Insufficient Stock'**
  String get insufficientStock;

  /// No description provided for @insufficientStockMsg.
  ///
  /// In en, this message translates to:
  /// **'The following items exceed available stock:\n\n{items}\n\nContinue anyway?'**
  String insufficientStockMsg(String items);

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @belowCostPrice.
  ///
  /// In en, this message translates to:
  /// **'Below-Cost Price'**
  String get belowCostPrice;

  /// No description provided for @belowCostMsg.
  ///
  /// In en, this message translates to:
  /// **'You are selling below cost price:\n\n{items}\n\nThis will result in a loss. Continue?'**
  String belowCostMsg(String items);

  /// No description provided for @sellAnyway.
  ///
  /// In en, this message translates to:
  /// **'Sell Anyway'**
  String get sellAnyway;

  /// No description provided for @shopifyOrderWarning.
  ///
  /// In en, this message translates to:
  /// **'Shopify Order Warning'**
  String get shopifyOrderWarning;

  /// No description provided for @shopifyOrderWarningMsg.
  ///
  /// In en, this message translates to:
  /// **'This sale is linked to a Shopify order.\n\nLine-item changes (quantities, prices, products) will NOT sync back to Shopify.\n\nEdit the line items on Shopify directly for financial accuracy.'**
  String get shopifyOrderWarningMsg;

  /// No description provided for @saveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save Anyway'**
  String get saveAnyway;

  /// No description provided for @failedToSaveSale.
  ///
  /// In en, this message translates to:
  /// **'Failed to save sale. Please try again.'**
  String get failedToSaveSale;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @bankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank Transfer'**
  String get bankTransfer;

  /// No description provided for @instaPay.
  ///
  /// In en, this message translates to:
  /// **'InstaPay'**
  String get instaPay;

  /// No description provided for @vodafoneCash.
  ///
  /// In en, this message translates to:
  /// **'Vodafone Cash'**
  String get vodafoneCash;

  /// No description provided for @amountPaidLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount Paid'**
  String get amountPaidLabel;

  /// No description provided for @salesHeader.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesHeader;

  /// No description provided for @selectOrders.
  ///
  /// In en, this message translates to:
  /// **'Select orders'**
  String get selectOrders;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// No description provided for @salesMarkedPaid.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{sale} other{sales}} marked as paid'**
  String salesMarkedPaid(int count);

  /// No description provided for @salesMarkedPaidShopify.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{sale} other{sales}} marked as paid ({shopifyCount} Shopify — local only, not synced to Shopify)'**
  String salesMarkedPaidShopify(int count, int shopifyCount);

  /// No description provided for @cancelOrders.
  ///
  /// In en, this message translates to:
  /// **'Cancel Orders'**
  String get cancelOrders;

  /// No description provided for @cancelOrdersBulkMsg.
  ///
  /// In en, this message translates to:
  /// **'Cancel {count} selected {count, plural, =1{order} other{orders}}?\n\nThis will restore stock and create reversal accounting entries. This cannot be undone.'**
  String cancelOrdersBulkMsg(int count);

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @ordersCancelledDetail.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{order} other{orders}} cancelled — stock & accounting reverted'**
  String ordersCancelledDetail(int count);

  /// No description provided for @shopifyCancelFailed.
  ///
  /// In en, this message translates to:
  /// **'Shopify cancel failed for order: {error}'**
  String shopifyCancelFailed(String error);

  /// No description provided for @searchSales.
  ///
  /// In en, this message translates to:
  /// **'Search sales...'**
  String get searchSales;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @noSalesFound.
  ///
  /// In en, this message translates to:
  /// **'No sales found'**
  String get noSalesFound;

  /// No description provided for @tapPlusToRecordFirstSale.
  ///
  /// In en, this message translates to:
  /// **'Tap + to record your first sale'**
  String get tapPlusToRecordFirstSale;

  /// No description provided for @markAsPaid.
  ///
  /// In en, this message translates to:
  /// **'Mark as Paid'**
  String get markAsPaid;

  /// No description provided for @noCogs.
  ///
  /// In en, this message translates to:
  /// **'No COGS'**
  String get noCogs;

  /// No description provided for @lastSyncTimeAgo.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String lastSyncTimeAgo(String time);

  /// No description provided for @syncingOrdersFromShopify.
  ///
  /// In en, this message translates to:
  /// **'Syncing orders from Shopify'**
  String get syncingOrdersFromShopify;

  /// No description provided for @saleItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{item} other{items}} · {date}'**
  String saleItemsCount(int count, String date);

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @allSources.
  ///
  /// In en, this message translates to:
  /// **'All Sources'**
  String get allSources;

  /// No description provided for @manualSource.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manualSource;

  /// No description provided for @timeAgoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get timeAgoJustNow;

  /// No description provided for @timeAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String timeAgoMinutes(int count);

  /// No description provided for @timeAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String timeAgoHours(int count);

  /// No description provided for @timeAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String timeAgoDays(int count);

  /// No description provided for @editCostOfGoods.
  ///
  /// In en, this message translates to:
  /// **'Edit Cost of Goods'**
  String get editCostOfGoods;

  /// No description provided for @enterCostPricePerUnit.
  ///
  /// In en, this message translates to:
  /// **'Enter the cost price per unit for each item'**
  String get enterCostPricePerUnit;

  /// No description provided for @totalCogs.
  ///
  /// In en, this message translates to:
  /// **'Total COGS'**
  String get totalCogs;

  /// No description provided for @cogsUpdated.
  ///
  /// In en, this message translates to:
  /// **'COGS updated — {currency} {amount}'**
  String cogsUpdated(String currency, String amount);

  /// No description provided for @failedUpdateCogs.
  ///
  /// In en, this message translates to:
  /// **'Failed to update COGS: {error}'**
  String failedUpdateCogs(String error);

  /// No description provided for @shopifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Shopify'**
  String get shopifyTitle;

  /// No description provided for @shopifyConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect Your Shopify Store'**
  String get shopifyConnectTitle;

  /// No description provided for @shopifyConnectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set up a one-time connection between Revvo\nand Shopify. Orders will sync automatically\nand inventory sync is available on-demand.'**
  String get shopifyConnectSubtitle;

  /// No description provided for @shopifyStartSetupWizard.
  ///
  /// In en, this message translates to:
  /// **'Start Setup Wizard'**
  String get shopifyStartSetupWizard;

  /// No description provided for @shopifyAlwaysOnOrderSync.
  ///
  /// In en, this message translates to:
  /// **'Always-On Order Sync'**
  String get shopifyAlwaysOnOrderSync;

  /// No description provided for @shopifyAlwaysOnOrderSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Shopify orders automatically become Revvo sales in real-time via webhooks.'**
  String get shopifyAlwaysOnOrderSyncDesc;

  /// No description provided for @shopifyOnDemandInventory.
  ///
  /// In en, this message translates to:
  /// **'On-Demand Inventory'**
  String get shopifyOnDemandInventory;

  /// No description provided for @shopifyOnDemandInventoryDesc.
  ///
  /// In en, this message translates to:
  /// **'Pull stock from Shopify or push your Revvo stock levels to Shopify anytime.'**
  String get shopifyOnDemandInventoryDesc;

  /// No description provided for @shopifySecureOAuth.
  ///
  /// In en, this message translates to:
  /// **'Secure OAuth 2.0'**
  String get shopifySecureOAuth;

  /// No description provided for @shopifySecureOAuthDesc.
  ///
  /// In en, this message translates to:
  /// **'Industry-standard authentication. Tokens are encrypted server-side.'**
  String get shopifySecureOAuthDesc;

  /// No description provided for @shopifyDisconnectAnytime.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Anytime'**
  String get shopifyDisconnectAnytime;

  /// No description provided for @shopifyDisconnectAnytimeDesc.
  ///
  /// In en, this message translates to:
  /// **'You can disconnect your Shopify store at any time from settings.'**
  String get shopifyDisconnectAnytimeDesc;

  /// No description provided for @shopifySectionConnection.
  ///
  /// In en, this message translates to:
  /// **'CONNECTION'**
  String get shopifySectionConnection;

  /// No description provided for @shopifyStore.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get shopifyStore;

  /// No description provided for @shopifyDomain.
  ///
  /// In en, this message translates to:
  /// **'Domain'**
  String get shopifyDomain;

  /// No description provided for @shopifyConnectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get shopifyConnectedLabel;

  /// No description provided for @shopifyLastOrderSync.
  ///
  /// In en, this message translates to:
  /// **'Last Order Sync'**
  String get shopifyLastOrderSync;

  /// No description provided for @shopifyLastInventorySync.
  ///
  /// In en, this message translates to:
  /// **'Last Inventory Sync'**
  String get shopifyLastInventorySync;

  /// No description provided for @shopifySectionSyncSettings.
  ///
  /// In en, this message translates to:
  /// **'SYNC SETTINGS'**
  String get shopifySectionSyncSettings;

  /// No description provided for @shopifyOrderSync.
  ///
  /// In en, this message translates to:
  /// **'Order Sync'**
  String get shopifyOrderSync;

  /// No description provided for @shopifyOrderSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Shopify orders → Revvo sales'**
  String get shopifyOrderSyncDesc;

  /// No description provided for @shopifyAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get shopifyAlwaysOn;

  /// No description provided for @shopifyInventorySync.
  ///
  /// In en, this message translates to:
  /// **'Inventory Sync'**
  String get shopifyInventorySync;

  /// No description provided for @shopifyInvAutoSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-syncs on every refresh'**
  String get shopifyInvAutoSyncDesc;

  /// No description provided for @shopifyInvManualSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'Sync manually via sync bar'**
  String get shopifyInvManualSyncDesc;

  /// No description provided for @shopifyOnDemand.
  ///
  /// In en, this message translates to:
  /// **'On demand'**
  String get shopifyOnDemand;

  /// No description provided for @shopifySectionLocation.
  ///
  /// In en, this message translates to:
  /// **'SHOPIFY LOCATION'**
  String get shopifySectionLocation;

  /// No description provided for @shopifySectionActions.
  ///
  /// In en, this message translates to:
  /// **'ACTIONS'**
  String get shopifySectionActions;

  /// No description provided for @shopifyProductMappings.
  ///
  /// In en, this message translates to:
  /// **'Product Mappings'**
  String get shopifyProductMappings;

  /// No description provided for @shopifyProductMappingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Link Shopify ↔ Revvo products'**
  String get shopifyProductMappingsDesc;

  /// No description provided for @shopifyReimportOrders.
  ///
  /// In en, this message translates to:
  /// **'Re-import Historical Orders'**
  String get shopifyReimportOrders;

  /// No description provided for @shopifyReimportOrdersDesc.
  ///
  /// In en, this message translates to:
  /// **'Import past Shopify orders'**
  String get shopifyReimportOrdersDesc;

  /// No description provided for @shopifyInvSyncAuto.
  ///
  /// In en, this message translates to:
  /// **'Inventory Sync (Auto)'**
  String get shopifyInvSyncAuto;

  /// No description provided for @shopifyInvSyncManual.
  ///
  /// In en, this message translates to:
  /// **'Inventory Sync (Manual)'**
  String get shopifyInvSyncManual;

  /// No description provided for @shopifyInvSyncAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-syncing every 30 s — tap for manual push/pull'**
  String get shopifyInvSyncAutoDesc;

  /// No description provided for @shopifyInvSyncManualDesc.
  ///
  /// In en, this message translates to:
  /// **'Pull or push stock levels manually'**
  String get shopifyInvSyncManualDesc;

  /// No description provided for @shopifySyncHistoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync History'**
  String get shopifySyncHistoryLabel;

  /// No description provided for @shopifySyncHistoryDesc.
  ///
  /// In en, this message translates to:
  /// **'View sync activity log'**
  String get shopifySyncHistoryDesc;

  /// No description provided for @shopifyDisconnectButton.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Shopify'**
  String get shopifyDisconnectButton;

  /// No description provided for @shopifyInvSyncMode.
  ///
  /// In en, this message translates to:
  /// **'Inventory Sync Mode'**
  String get shopifyInvSyncMode;

  /// No description provided for @shopifyModeAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always On'**
  String get shopifyModeAlwaysOn;

  /// No description provided for @shopifyModeAlwaysOnDesc.
  ///
  /// In en, this message translates to:
  /// **'Inventory auto-syncs on every refresh — no manual intervention'**
  String get shopifyModeAlwaysOnDesc;

  /// No description provided for @shopifyModeOnDemand.
  ///
  /// In en, this message translates to:
  /// **'On Demand'**
  String get shopifyModeOnDemand;

  /// No description provided for @shopifyModeOnDemandDesc.
  ///
  /// In en, this message translates to:
  /// **'Persistent sync bar in inventory — pull or push manually'**
  String get shopifyModeOnDemandDesc;

  /// No description provided for @shopifyInvSyncSetAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Inventory sync set to Always On'**
  String get shopifyInvSyncSetAlwaysOn;

  /// No description provided for @shopifyInvSyncSetOnDemand.
  ///
  /// In en, this message translates to:
  /// **'Inventory sync set to On Demand'**
  String get shopifyInvSyncSetOnDemand;

  /// No description provided for @shopifyDisconnectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Shopify?'**
  String get shopifyDisconnectConfirm;

  /// No description provided for @shopifyDisconnectMessage.
  ///
  /// In en, this message translates to:
  /// **'This will remove the connection to \"{shopName}\" and delete all product mappings. Your existing sales and inventory data will be kept.'**
  String shopifyDisconnectMessage(String shopName);

  /// No description provided for @shopifyDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Shopify disconnected'**
  String get shopifyDisconnected;

  /// No description provided for @shopifyTimeMinAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min ago'**
  String shopifyTimeMinAgo(int minutes);

  /// No description provided for @shopifyTimeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String shopifyTimeHoursAgo(int hours);

  /// No description provided for @shopifyTimeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String shopifyTimeDaysAgo(int days);

  /// No description provided for @shopifyStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get shopifyStatusConnected;

  /// No description provided for @shopifyStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get shopifyStatusError;

  /// No description provided for @shopifyStatusDisconnected.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get shopifyStatusDisconnected;

  /// No description provided for @shopifySelectLocation.
  ///
  /// In en, this message translates to:
  /// **'Select Location'**
  String get shopifySelectLocation;

  /// No description provided for @shopifyLocationSet.
  ///
  /// In en, this message translates to:
  /// **'Location set'**
  String get shopifyLocationSet;

  /// No description provided for @shopifyNoLocationSelected.
  ///
  /// In en, this message translates to:
  /// **'No location selected'**
  String get shopifyNoLocationSelected;

  /// No description provided for @shopifyTapToChangeLocation.
  ///
  /// In en, this message translates to:
  /// **'Tap to change location'**
  String get shopifyTapToChangeLocation;

  /// No description provided for @shopifySelectLocationToSync.
  ///
  /// In en, this message translates to:
  /// **'Select which Shopify location to sync'**
  String get shopifySelectLocationToSync;

  /// No description provided for @shopifySetup.
  ///
  /// In en, this message translates to:
  /// **'Shopify Setup'**
  String get shopifySetup;

  /// No description provided for @shopifyStepCount.
  ///
  /// In en, this message translates to:
  /// **'Step {current}/5'**
  String shopifyStepCount(int current);

  /// No description provided for @shopifyExitSetup.
  ///
  /// In en, this message translates to:
  /// **'Exit Setup?'**
  String get shopifyExitSetup;

  /// No description provided for @shopifyExitActiveMessage.
  ///
  /// In en, this message translates to:
  /// **'Your Shopify connection is active. You can finish setup later from the Manage screen.'**
  String get shopifyExitActiveMessage;

  /// No description provided for @shopifyExitIncompleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Your setup is not complete. You can restart anytime from the Manage screen.'**
  String get shopifyExitIncompleteMessage;

  /// No description provided for @shopifyContinueSetup.
  ///
  /// In en, this message translates to:
  /// **'Continue Setup'**
  String get shopifyContinueSetup;

  /// No description provided for @shopifyExitButton.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get shopifyExitButton;

  /// No description provided for @shopifyStep1Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter your Shopify store domain to get started.\nThis is a one-time setup.'**
  String get shopifyStep1Subtitle;

  /// No description provided for @shopifyShopDomain.
  ///
  /// In en, this message translates to:
  /// **'SHOP DOMAIN'**
  String get shopifyShopDomain;

  /// No description provided for @shopifyHintStoreName.
  ///
  /// In en, this message translates to:
  /// **'your-store'**
  String get shopifyHintStoreName;

  /// No description provided for @shopifyDomainSuffix.
  ///
  /// In en, this message translates to:
  /// **'.myshopify.com'**
  String get shopifyDomainSuffix;

  /// No description provided for @shopifyValidationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Please enter your Shopify store name'**
  String get shopifyValidationEmpty;

  /// No description provided for @shopifyConnectToShopify.
  ///
  /// In en, this message translates to:
  /// **'Connect to Shopify'**
  String get shopifyConnectToShopify;

  /// No description provided for @shopifySecureOAuthConnection.
  ///
  /// In en, this message translates to:
  /// **'Secure OAuth Connection'**
  String get shopifySecureOAuthConnection;

  /// No description provided for @shopifySecureOAuthConnectionDesc.
  ///
  /// In en, this message translates to:
  /// **'We never see your Shopify password. Authorization uses industry-standard OAuth 2.0.'**
  String get shopifySecureOAuthConnectionDesc;

  /// No description provided for @shopifyAlwaysOnSync.
  ///
  /// In en, this message translates to:
  /// **'Always-On Sync'**
  String get shopifyAlwaysOnSync;

  /// No description provided for @shopifyAlwaysOnSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'After setup, Shopify orders automatically sync to Revvo in real-time via webhooks.'**
  String get shopifyAlwaysOnSyncDesc;

  /// No description provided for @shopifyDisconnectAnytimeSetup.
  ///
  /// In en, this message translates to:
  /// **'Disconnect Anytime'**
  String get shopifyDisconnectAnytimeSetup;

  /// No description provided for @shopifyDisconnectAnytimeSetupDesc.
  ///
  /// In en, this message translates to:
  /// **'You can disconnect your Shopify store at any time from the settings.'**
  String get shopifyDisconnectAnytimeSetupDesc;

  /// No description provided for @shopifyDataAccess.
  ///
  /// In en, this message translates to:
  /// **'Data Revvo Will Access'**
  String get shopifyDataAccess;

  /// No description provided for @shopifyDataOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders — customer name, email, phone, shipping address, items, and totals. Stored in your private Revvo account to populate your sales ledger.'**
  String get shopifyDataOrders;

  /// No description provided for @shopifyDataInventory.
  ///
  /// In en, this message translates to:
  /// **'Inventory — product titles, variants, and stock levels. Used to keep your Revvo inventory in sync with Shopify.'**
  String get shopifyDataInventory;

  /// No description provided for @shopifyDataPrivacy.
  ///
  /// In en, this message translates to:
  /// **'This data is never shared with third parties or used for marketing. It is accessible only by you and deleted when you delete your account.'**
  String get shopifyDataPrivacy;

  /// No description provided for @shopifyInvalidStoreName.
  ///
  /// In en, this message translates to:
  /// **'Invalid store name'**
  String get shopifyInvalidStoreName;

  /// No description provided for @shopifyOAuthConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected!'**
  String get shopifyOAuthConnected;

  /// No description provided for @shopifyOAuthAuthorizing.
  ///
  /// In en, this message translates to:
  /// **'Authorizing…'**
  String get shopifyOAuthAuthorizing;

  /// No description provided for @shopifyOAuthSuccess.
  ///
  /// In en, this message translates to:
  /// **'Your Shopify store is now connected to Revvo.'**
  String get shopifyOAuthSuccess;

  /// No description provided for @shopifyOAuthInstructions.
  ///
  /// In en, this message translates to:
  /// **'Complete the authorization in your browser.\nWhen done, come back here.'**
  String get shopifyOAuthInstructions;

  /// No description provided for @shopifyAuthorizedInBrowser.
  ///
  /// In en, this message translates to:
  /// **'I\'ve Authorized in Browser'**
  String get shopifyAuthorizedInBrowser;

  /// No description provided for @shopifyAuthNotDetected.
  ///
  /// In en, this message translates to:
  /// **'Authorization not detected yet.\nMake sure you approved the app on Shopify,\nthen tap the button again.'**
  String get shopifyAuthNotDetected;

  /// No description provided for @shopifyChangeStore.
  ///
  /// In en, this message translates to:
  /// **'Change Store'**
  String get shopifyChangeStore;

  /// No description provided for @shopifySelectYourLocation.
  ///
  /// In en, this message translates to:
  /// **'Select Your Location'**
  String get shopifySelectYourLocation;

  /// No description provided for @shopifyLocationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Revvo will sync inventory with this Shopify location.\nIf you have multiple locations, pick your primary one.'**
  String get shopifyLocationSubtitle;

  /// No description provided for @shopifyPrimaryLocation.
  ///
  /// In en, this message translates to:
  /// **'Primary location'**
  String get shopifyPrimaryLocation;

  /// No description provided for @shopifyContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get shopifyContinue;

  /// No description provided for @shopifyNoLocationsFound.
  ///
  /// In en, this message translates to:
  /// **'No locations found'**
  String get shopifyNoLocationsFound;

  /// No description provided for @shopifyNoLocationsMessage.
  ///
  /// In en, this message translates to:
  /// **'Make sure your Shopify store has at least one active location.'**
  String get shopifyNoLocationsMessage;

  /// No description provided for @shopifyRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get shopifyRetry;

  /// No description provided for @shopifyProductsSynced.
  ///
  /// In en, this message translates to:
  /// **'Products & Inventory Synced!'**
  String get shopifyProductsSynced;

  /// No description provided for @shopifySyncProductsInventory.
  ///
  /// In en, this message translates to:
  /// **'Sync Products & Inventory'**
  String get shopifySyncProductsInventory;

  /// No description provided for @shopifySyncingProducts.
  ///
  /// In en, this message translates to:
  /// **'Importing your Shopify products and inventory levels into Revvo…'**
  String get shopifySyncingProducts;

  /// No description provided for @shopifyProductsSyncedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} product(s) imported with current inventory levels.'**
  String shopifyProductsSyncedCount(int count);

  /// No description provided for @shopifySyncProductsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We\'ll import your products and their current inventory levels from Shopify.'**
  String get shopifySyncProductsSubtitle;

  /// No description provided for @shopifySetProductCosts.
  ///
  /// In en, this message translates to:
  /// **'Set Product Costs'**
  String get shopifySetProductCosts;

  /// No description provided for @shopifyCostGuidance.
  ///
  /// In en, this message translates to:
  /// **'For accurate profit tracking, set the cost price for each product in your inventory.\n\nYou can import historical orders anytime from Shopify Settings → Re-import Historical Orders.'**
  String get shopifyCostGuidance;

  /// No description provided for @shopifySyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to sync products. Please try again.'**
  String get shopifySyncFailed;

  /// No description provided for @shopifyReadyToSync.
  ///
  /// In en, this message translates to:
  /// **'Ready to Sync!'**
  String get shopifyReadyToSync;

  /// No description provided for @shopifySetupSummary.
  ///
  /// In en, this message translates to:
  /// **'Here\'s a summary of your setup:'**
  String get shopifySetupSummary;

  /// No description provided for @shopifyAlwaysOnRealtime.
  ///
  /// In en, this message translates to:
  /// **'Always on (real-time)'**
  String get shopifyAlwaysOnRealtime;

  /// No description provided for @shopifyProductsSyncedLabel.
  ///
  /// In en, this message translates to:
  /// **'Products Synced'**
  String get shopifyProductsSyncedLabel;

  /// No description provided for @shopifyProductsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} product(s)'**
  String shopifyProductsCount(int count);

  /// No description provided for @shopifyStartSyncing.
  ///
  /// In en, this message translates to:
  /// **'Start Syncing'**
  String get shopifyStartSyncing;

  /// No description provided for @shopifyImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Shopify Orders'**
  String get shopifyImportTitle;

  /// No description provided for @shopifyImportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import historical orders from your Shopify store.\nMaximum 3 months back.'**
  String get shopifyImportSubtitle;

  /// No description provided for @shopifyImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get shopifyImporting;

  /// No description provided for @shopifyRangeDays.
  ///
  /// In en, this message translates to:
  /// **'Range: {days} day(s)'**
  String shopifyRangeDays(int days);

  /// No description provided for @shopifyImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import Failed'**
  String get shopifyImportFailed;

  /// No description provided for @shopifyLoadSyncHistoryError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load sync history:\n{error}'**
  String shopifyLoadSyncHistoryError(String error);

  /// No description provided for @shopifyNoSyncHistory.
  ///
  /// In en, this message translates to:
  /// **'No Sync History'**
  String get shopifyNoSyncHistory;

  /// No description provided for @shopifyNoSyncHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Sync actions will appear here once\nyou sync orders or inventory.'**
  String get shopifyNoSyncHistoryMessage;

  /// No description provided for @shopifyClearLogsMessage.
  ///
  /// In en, this message translates to:
  /// **'This will delete all sync log entries. This cannot be undone.'**
  String get shopifyClearLogsMessage;

  /// No description provided for @shopifyFailedLoadSyncHistory.
  ///
  /// In en, this message translates to:
  /// **'Failed to load sync history:\\n{error}'**
  String shopifyFailedLoadSyncHistory(String error);

  /// No description provided for @shopifyDirectionToRevvo.
  ///
  /// In en, this message translates to:
  /// **'Shopify → Revvo'**
  String get shopifyDirectionToRevvo;

  /// No description provided for @shopifyDirectionToShopify.
  ///
  /// In en, this message translates to:
  /// **'Revvo → Shopify'**
  String get shopifyDirectionToShopify;

  /// No description provided for @shopifyRefId.
  ///
  /// In en, this message translates to:
  /// **'Shopify #{orderId}'**
  String shopifyRefId(String orderId);

  /// No description provided for @shopifySaleRef.
  ///
  /// In en, this message translates to:
  /// **'Sale {saleId}…'**
  String shopifySaleRef(String saleId);

  /// No description provided for @shopifyActionOrderImported.
  ///
  /// In en, this message translates to:
  /// **'Order Imported'**
  String get shopifyActionOrderImported;

  /// No description provided for @shopifyActionOrderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Order Updated'**
  String get shopifyActionOrderUpdated;

  /// No description provided for @shopifyActionOrderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Order Cancelled'**
  String get shopifyActionOrderCancelled;

  /// No description provided for @shopifyActionOrderPush.
  ///
  /// In en, this message translates to:
  /// **'Order Push'**
  String get shopifyActionOrderPush;

  /// No description provided for @shopifyActionInventoryPull.
  ///
  /// In en, this message translates to:
  /// **'Inventory Pull'**
  String get shopifyActionInventoryPull;

  /// No description provided for @shopifyActionInventoryPush.
  ///
  /// In en, this message translates to:
  /// **'Inventory Push'**
  String get shopifyActionInventoryPush;

  /// No description provided for @shopifyActionProductUpdated.
  ///
  /// In en, this message translates to:
  /// **'Product Updated'**
  String get shopifyActionProductUpdated;

  /// No description provided for @shopifyActionStockLevelUpdate.
  ///
  /// In en, this message translates to:
  /// **'Stock Level Update'**
  String get shopifyActionStockLevelUpdate;

  /// No description provided for @shopifyActionRefundProcessed.
  ///
  /// In en, this message translates to:
  /// **'Refund Processed'**
  String get shopifyActionRefundProcessed;

  /// No description provided for @shopifyInventorySyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Inventory Sync'**
  String get shopifyInventorySyncTitle;

  /// No description provided for @shopifyLoadMappingsError.
  ///
  /// In en, this message translates to:
  /// **'Failed to load mappings:\n{error}'**
  String shopifyLoadMappingsError(String error);

  /// No description provided for @shopifyNoProductMappings.
  ///
  /// In en, this message translates to:
  /// **'No Product Mappings'**
  String get shopifyNoProductMappings;

  /// No description provided for @shopifyNoProductMappingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Link your Revvo products to Shopify products first\nusing the Product Mappings screen.'**
  String get shopifyNoProductMappingsDesc;

  /// No description provided for @shopifyPullInfo.
  ///
  /// In en, this message translates to:
  /// **'Pull will update stock levels in Revvo to match Shopify for all mapped products.  Review the preview before confirming.'**
  String get shopifyPullInfo;

  /// No description provided for @shopifyMappedProductsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} MAPPED PRODUCT(S)'**
  String shopifyMappedProductsCount(int count);

  /// No description provided for @shopifyPushInfo.
  ///
  /// In en, this message translates to:
  /// **'Push will overwrite Shopify stock levels with your Revvo inventory values. Select products, then review the preview.'**
  String get shopifyPushInfo;

  /// No description provided for @shopifySelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All ({count})'**
  String shopifySelectAll(int count);

  /// No description provided for @shopifyFetchPreviewCount.
  ///
  /// In en, this message translates to:
  /// **'Fetch Preview ({count})'**
  String shopifyFetchPreviewCount(int count);

  /// No description provided for @shopifyConfirmPullCount.
  ///
  /// In en, this message translates to:
  /// **'Confirm Pull ({count} changes)'**
  String shopifyConfirmPullCount(int count);

  /// No description provided for @shopifyConfirmPushCount.
  ///
  /// In en, this message translates to:
  /// **'Confirm Push ({count} changes)'**
  String shopifyConfirmPushCount(int count);

  /// No description provided for @shopifyLoadingStatus.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get shopifyLoadingStatus;

  /// No description provided for @shopifySyncingStatus.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get shopifySyncingStatus;

  /// No description provided for @shopifyNoChanges.
  ///
  /// In en, this message translates to:
  /// **'No Changes'**
  String get shopifyNoChanges;

  /// No description provided for @shopifyPreviewChangeSummary.
  ///
  /// In en, this message translates to:
  /// **'{changed} variant(s) will change, {unchanged} unchanged'**
  String shopifyPreviewChangeSummary(int changed, int unchanged);

  /// No description provided for @shopifyAllInSync.
  ///
  /// In en, this message translates to:
  /// **'All variants are already in sync!'**
  String get shopifyAllInSync;

  /// No description provided for @shopifyTableProduct.
  ///
  /// In en, this message translates to:
  /// **'PRODUCT'**
  String get shopifyTableProduct;

  /// No description provided for @shopifyTableRevvo.
  ///
  /// In en, this message translates to:
  /// **'REVVO'**
  String get shopifyTableRevvo;

  /// No description provided for @shopifyTableShopify.
  ///
  /// In en, this message translates to:
  /// **'SHOPIFY'**
  String get shopifyTableShopify;

  /// No description provided for @shopifyTableDelta.
  ///
  /// In en, this message translates to:
  /// **'DELTA'**
  String get shopifyTableDelta;

  /// No description provided for @shopifyUnchangedCount.
  ///
  /// In en, this message translates to:
  /// **'UNCHANGED ({count})'**
  String shopifyUnchangedCount(int count);

  /// No description provided for @shopifySkippedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} variant(s) skipped'**
  String shopifySkippedCount(int count);

  /// No description provided for @shopifyVariantInfo.
  ///
  /// In en, this message translates to:
  /// **'{variantCount} variant(s) · {totalStock} in stock'**
  String shopifyVariantInfo(int variantCount, int totalStock);

  /// No description provided for @shopifyMappingInfo.
  ///
  /// In en, this message translates to:
  /// **'{count} mapping(s) · {totalStock} in stock'**
  String shopifyMappingInfo(int count, int totalStock);

  /// No description provided for @shopifyAutoLinked.
  ///
  /// In en, this message translates to:
  /// **'Auto-linked {count} existing product(s)'**
  String shopifyAutoLinked(int count);

  /// No description provided for @shopifyFailedLoadProducts.
  ///
  /// In en, this message translates to:
  /// **'Failed to load Shopify products'**
  String get shopifyFailedLoadProducts;

  /// No description provided for @shopifyProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'Shopify Products'**
  String get shopifyProductsTitle;

  /// No description provided for @shopifyAutoMatch.
  ///
  /// In en, this message translates to:
  /// **'Auto-Match'**
  String get shopifyAutoMatch;

  /// No description provided for @shopifyImportAllProducts.
  ///
  /// In en, this message translates to:
  /// **'Import All {count} Products to Revvo'**
  String shopifyImportAllProducts(int count);

  /// No description provided for @shopifyNoProducts.
  ///
  /// In en, this message translates to:
  /// **'No Shopify products'**
  String get shopifyNoProducts;

  /// No description provided for @shopifyNoProductsDesc.
  ///
  /// In en, this message translates to:
  /// **'Your Shopify store has no products yet.\nAdd products in Shopify first.'**
  String get shopifyNoProductsDesc;

  /// No description provided for @shopifyImportedProduct.
  ///
  /// In en, this message translates to:
  /// **'Imported \"{title}\"'**
  String shopifyImportedProduct(String title);

  /// No description provided for @shopifyImportError.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String shopifyImportError(String error);

  /// No description provided for @shopifyImportCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Import {count} Products'**
  String shopifyImportCountTitle(int count);

  /// No description provided for @shopifyImportAllConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will create {count} new product(s) in your Revvo inventory from Shopify and link them automatically.\n\nVariants, SKUs, prices, and stock levels will be imported.'**
  String shopifyImportAllConfirmMessage(int count);

  /// No description provided for @shopifyImportAll.
  ///
  /// In en, this message translates to:
  /// **'Import All'**
  String get shopifyImportAll;

  /// No description provided for @shopifyImportedCount.
  ///
  /// In en, this message translates to:
  /// **'Successfully imported {count} product(s)'**
  String shopifyImportedCount(int count);

  /// No description provided for @shopifyImportPartial.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} of {total}. Error: {error}'**
  String shopifyImportPartial(int imported, int total, String error);

  /// No description provided for @shopifyNoRevvoProducts.
  ///
  /// In en, this message translates to:
  /// **'No Revvo products yet — use Import instead'**
  String get shopifyNoRevvoProducts;

  /// No description provided for @shopifyLinkToRevvo.
  ///
  /// In en, this message translates to:
  /// **'Link to Revvo Product'**
  String get shopifyLinkToRevvo;

  /// No description provided for @shopifyLinkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Link \"{title}\" to an existing Revvo product'**
  String shopifyLinkSubtitle(String title);

  /// No description provided for @shopifySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or SKU...'**
  String get shopifySearchHint;

  /// No description provided for @shopifyNoMatchingProducts.
  ///
  /// In en, this message translates to:
  /// **'No matching products'**
  String get shopifyNoMatchingProducts;

  /// No description provided for @shopifyLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked \"{shopTitle}\" → \"{revvoName}\"'**
  String shopifyLinked(String shopTitle, String revvoName);

  /// No description provided for @shopifyMatchedBySku.
  ///
  /// In en, this message translates to:
  /// **'Matched {count} product(s) by SKU'**
  String shopifyMatchedBySku(int count);

  /// No description provided for @shopifyNoMatchesBySku.
  ///
  /// In en, this message translates to:
  /// **'No new matches found — SKUs don\'t match'**
  String get shopifyNoMatchesBySku;

  /// No description provided for @shopifyAutoMatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto-match failed'**
  String get shopifyAutoMatchFailed;

  /// No description provided for @shopifyMappingRemoved.
  ///
  /// In en, this message translates to:
  /// **'Mapping removed'**
  String get shopifyMappingRemoved;

  /// No description provided for @shopifyVariantsLinked.
  ///
  /// In en, this message translates to:
  /// **'{count} variant(s) linked'**
  String shopifyVariantsLinked(int count);

  /// No description provided for @shopifyVariantsNotImported.
  ///
  /// In en, this message translates to:
  /// **'{count} variant(s) · Not imported'**
  String shopifyVariantsNotImported(int count);

  /// No description provided for @shopifyVariantLabel.
  ///
  /// In en, this message translates to:
  /// **'Shopify Variant'**
  String get shopifyVariantLabel;

  /// No description provided for @shopifyImportButton.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get shopifyImportButton;

  /// No description provided for @shopifyLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get shopifyLinkButton;

  /// No description provided for @shopifyMapped.
  ///
  /// In en, this message translates to:
  /// **'Mapped'**
  String get shopifyMapped;

  /// No description provided for @shopifyUnmapped.
  ///
  /// In en, this message translates to:
  /// **'Unmapped'**
  String get shopifyUnmapped;

  /// No description provided for @shopifyImportFailedError.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String shopifyImportFailedError(String error);

  /// No description provided for @shopifyConnectedTo.
  ///
  /// In en, this message translates to:
  /// **'Shopify · {shopName}'**
  String shopifyConnectedTo(String shopName);

  /// No description provided for @shopifyLastSyncJustNow.
  ///
  /// In en, this message translates to:
  /// **'Last sync: just now'**
  String get shopifyLastSyncJustNow;

  /// No description provided for @shopifyLastSyncMinAgo.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {minutes} min ago'**
  String shopifyLastSyncMinAgo(int minutes);

  /// No description provided for @shopifyLastSyncHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {hours}h ago'**
  String shopifyLastSyncHoursAgo(int hours);

  /// No description provided for @shopifyLastSyncDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {days}d ago'**
  String shopifyLastSyncDaysAgo(int days);

  /// No description provided for @shopifyIntegrationReady.
  ///
  /// In en, this message translates to:
  /// **'Shopify integration ready'**
  String get shopifyIntegrationReady;

  /// No description provided for @shopifyTapToConnect.
  ///
  /// In en, this message translates to:
  /// **'Tap to connect your store and start syncing.'**
  String get shopifyTapToConnect;

  /// No description provided for @shopifySetupButton.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get shopifySetupButton;

  /// No description provided for @shopifyConnectionErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Shopify connection error'**
  String get shopifyConnectionErrorTitle;

  /// No description provided for @shopifyDisconnectedTitle.
  ///
  /// In en, this message translates to:
  /// **'Shopify disconnected'**
  String get shopifyDisconnectedTitle;

  /// No description provided for @shopifyReauthorize.
  ///
  /// In en, this message translates to:
  /// **'Re-authorize \"{shopName}\" to resume syncing.'**
  String shopifyReauthorize(String shopName);

  /// No description provided for @shopifyReconnectMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{shopName}\" was disconnected. Reconnect to resume.'**
  String shopifyReconnectMessage(String shopName);

  /// No description provided for @shopifyFixButton.
  ///
  /// In en, this message translates to:
  /// **'Fix'**
  String get shopifyFixButton;

  /// No description provided for @shopifyBadge.
  ///
  /// In en, this message translates to:
  /// **'Shopify'**
  String get shopifyBadge;

  /// No description provided for @shopifyViewButton.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get shopifyViewButton;

  /// No description provided for @shopifyLinkedToShopify.
  ///
  /// In en, this message translates to:
  /// **'Linked to Shopify'**
  String get shopifyLinkedToShopify;

  /// No description provided for @shopifyLastSyncTime.
  ///
  /// In en, this message translates to:
  /// **'Last sync: {time}'**
  String shopifyLastSyncTime(String time);

  /// No description provided for @shopifySyncPushingOrder.
  ///
  /// In en, this message translates to:
  /// **'Pushing order to Shopify…'**
  String get shopifySyncPushingOrder;

  /// No description provided for @shopifySyncOrderFailed.
  ///
  /// In en, this message translates to:
  /// **'Order sync failed'**
  String get shopifySyncOrderFailed;

  /// No description provided for @shopifySyncPulling.
  ///
  /// In en, this message translates to:
  /// **'Pulling Shopify changes…'**
  String get shopifySyncPulling;

  /// No description provided for @shopifySyncPushing.
  ///
  /// In en, this message translates to:
  /// **'Pushing local changes to Shopify…'**
  String get shopifySyncPushing;

  /// No description provided for @shopifySyncProductDetails.
  ///
  /// In en, this message translates to:
  /// **'Syncing product details…'**
  String get shopifySyncProductDetails;

  /// No description provided for @shopifySyncFailed2.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get shopifySyncFailed2;

  /// No description provided for @shopifySyncResult.
  ///
  /// In en, this message translates to:
  /// **'Synced — pushed {pushed}, pulled {pulled}{detail}'**
  String shopifySyncResult(int pushed, int pulled, String detail);

  /// No description provided for @shopifySyncProductsUpdated.
  ///
  /// In en, this message translates to:
  /// **', {count} product(s) updated'**
  String shopifySyncProductsUpdated(int count);

  /// No description provided for @shopifyPullingInventory.
  ///
  /// In en, this message translates to:
  /// **'Pulling inventory from Shopify…'**
  String get shopifyPullingInventory;

  /// No description provided for @shopifyPushingInventory.
  ///
  /// In en, this message translates to:
  /// **'Pushing inventory to Shopify…'**
  String get shopifyPushingInventory;

  /// No description provided for @shopifyUpdatedVariants.
  ///
  /// In en, this message translates to:
  /// **'Updated {count} variant(s) from Shopify'**
  String shopifyUpdatedVariants(int count);

  /// No description provided for @shopifyInventoryPullFailed.
  ///
  /// In en, this message translates to:
  /// **'Inventory pull failed'**
  String get shopifyInventoryPullFailed;

  /// No description provided for @shopifyMissingPushData.
  ///
  /// In en, this message translates to:
  /// **'Missing product/variant/stock for push'**
  String get shopifyMissingPushData;

  /// No description provided for @shopifyInventoryPushed.
  ///
  /// In en, this message translates to:
  /// **'Inventory pushed to Shopify'**
  String get shopifyInventoryPushed;

  /// No description provided for @shopifyInventoryPushFailed.
  ///
  /// In en, this message translates to:
  /// **'Inventory push failed'**
  String get shopifyInventoryPushFailed;

  /// No description provided for @shopifyFetchingStock.
  ///
  /// In en, this message translates to:
  /// **'Fetching Shopify stock levels…'**
  String get shopifyFetchingStock;

  /// No description provided for @shopifyFetchPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch preview'**
  String get shopifyFetchPreviewFailed;

  /// No description provided for @shopifyNoPreviewData.
  ///
  /// In en, this message translates to:
  /// **'No preview data — please fetch preview first'**
  String get shopifyNoPreviewData;

  /// No description provided for @shopifyApplyingChanges.
  ///
  /// In en, this message translates to:
  /// **'Applying stock changes…'**
  String get shopifyApplyingChanges;

  /// No description provided for @shopifyPullFailed.
  ///
  /// In en, this message translates to:
  /// **'Pull failed'**
  String get shopifyPullFailed;

  /// No description provided for @shopifyComparingStock.
  ///
  /// In en, this message translates to:
  /// **'Comparing stock levels…'**
  String get shopifyComparingStock;

  /// No description provided for @shopifyPushedVariants.
  ///
  /// In en, this message translates to:
  /// **'Pushed {count} variant(s) to Shopify'**
  String shopifyPushedVariants(int count);

  /// No description provided for @shopifyPushFailed.
  ///
  /// In en, this message translates to:
  /// **'Push failed'**
  String get shopifyPushFailed;

  /// No description provided for @shopifySyncingProductsFromShopify.
  ///
  /// In en, this message translates to:
  /// **'Syncing products from Shopify…'**
  String get shopifySyncingProductsFromShopify;

  /// No description provided for @shopifyPullingInventoryLevels.
  ///
  /// In en, this message translates to:
  /// **'Pulling inventory levels…'**
  String get shopifyPullingInventoryLevels;

  /// No description provided for @shopifySyncedProducts.
  ///
  /// In en, this message translates to:
  /// **'Synced {count} product(s) from Shopify'**
  String shopifySyncedProducts(int count);

  /// No description provided for @shopifyProductSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Product sync failed'**
  String get shopifyProductSyncFailed;

  /// No description provided for @shopifyImportingOrders.
  ///
  /// In en, this message translates to:
  /// **'Importing Shopify orders…'**
  String get shopifyImportingOrders;

  /// No description provided for @shopifyImportResult.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} order(s), skipped {skipped}, {errors} error(s)'**
  String shopifyImportResult(int imported, int skipped, int errors);

  /// No description provided for @shopifyOrderImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Order import failed'**
  String get shopifyOrderImportFailed;

  /// No description provided for @shopifyWebhookOrderCreated.
  ///
  /// In en, this message translates to:
  /// **'New Shopify order #{orderNumber} synced'**
  String shopifyWebhookOrderCreated(String orderNumber);

  /// No description provided for @shopifyWebhookOrderCreatedFallback.
  ///
  /// In en, this message translates to:
  /// **'New Shopify order synced'**
  String get shopifyWebhookOrderCreatedFallback;

  /// No description provided for @shopifyWebhookOrderUpdated.
  ///
  /// In en, this message translates to:
  /// **'Shopify order #{orderNumber} updated'**
  String shopifyWebhookOrderUpdated(String orderNumber);

  /// No description provided for @shopifyWebhookOrderUpdatedFallback.
  ///
  /// In en, this message translates to:
  /// **'Shopify order updated'**
  String get shopifyWebhookOrderUpdatedFallback;

  /// No description provided for @shopifyWebhookOrderCancelled.
  ///
  /// In en, this message translates to:
  /// **'Shopify order #{orderNumber} cancelled'**
  String shopifyWebhookOrderCancelled(String orderNumber);

  /// No description provided for @shopifyWebhookOrderCancelledFallback.
  ///
  /// In en, this message translates to:
  /// **'Shopify order cancelled'**
  String get shopifyWebhookOrderCancelledFallback;

  /// No description provided for @shopifyWebhookProductUpdated.
  ///
  /// In en, this message translates to:
  /// **'Shopify product \"{title}\" updated'**
  String shopifyWebhookProductUpdated(String title);

  /// No description provided for @shopifyWebhookProductUpdatedFallback.
  ///
  /// In en, this message translates to:
  /// **'Shopify product updated'**
  String get shopifyWebhookProductUpdatedFallback;

  /// No description provided for @shopifyWebhookProductCreated.
  ///
  /// In en, this message translates to:
  /// **'New Shopify product \"{title}\" imported'**
  String shopifyWebhookProductCreated(String title);

  /// No description provided for @shopifyWebhookProductCreatedFallback.
  ///
  /// In en, this message translates to:
  /// **'New Shopify product imported'**
  String get shopifyWebhookProductCreatedFallback;

  /// No description provided for @shopifyWebhookProductDeleted.
  ///
  /// In en, this message translates to:
  /// **'Shopify product \"{title}\" deleted'**
  String shopifyWebhookProductDeleted(String title);

  /// No description provided for @shopifyWebhookProductDeletedFallback.
  ///
  /// In en, this message translates to:
  /// **'Shopify product unlinked'**
  String get shopifyWebhookProductDeletedFallback;

  /// No description provided for @shopifyWebhookInventoryUpdate.
  ///
  /// In en, this message translates to:
  /// **'Shopify inventory level updated'**
  String get shopifyWebhookInventoryUpdate;

  /// No description provided for @shopifyWebhookFallback.
  ///
  /// In en, this message translates to:
  /// **'Shopify webhook: {topic}'**
  String shopifyWebhookFallback(String topic);

  /// No description provided for @shopifyNoShopifyLevelFound.
  ///
  /// In en, this message translates to:
  /// **'no Shopify level found'**
  String get shopifyNoShopifyLevelFound;

  /// No description provided for @addNewProduct.
  ///
  /// In en, this message translates to:
  /// **'Add New Product'**
  String get addNewProduct;

  /// No description provided for @basicsFirst.
  ///
  /// In en, this message translates to:
  /// **'Basics first — you can add details later.'**
  String get basicsFirst;

  /// No description provided for @costPriceStockNotNegative.
  ///
  /// In en, this message translates to:
  /// **'Cost, price, and stock must not be negative'**
  String get costPriceStockNotNegative;

  /// No description provided for @costExceedsSellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Cost exceeds selling price'**
  String get costExceedsSellingPrice;

  /// No description provided for @costExceedsDesc.
  ///
  /// In en, this message translates to:
  /// **'The cost ({cost}) is higher than the selling price ({price}). This means you\'d be selling at a loss.'**
  String costExceedsDesc(String cost, String price);

  /// No description provided for @duplicateSku.
  ///
  /// In en, this message translates to:
  /// **'Duplicate SKU'**
  String get duplicateSku;

  /// No description provided for @duplicateSkuDesc.
  ///
  /// In en, this message translates to:
  /// **'A product with the same SKU already exists. Save anyway?'**
  String get duplicateSkuDesc;

  /// No description provided for @failedToSaveProduct.
  ///
  /// In en, this message translates to:
  /// **'Failed to save product'**
  String get failedToSaveProduct;

  /// No description provided for @uploadProductPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload Product Photo'**
  String get uploadProductPhoto;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get changePhoto;

  /// No description provided for @physical.
  ///
  /// In en, this message translates to:
  /// **'Physical'**
  String get physical;

  /// No description provided for @service.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get service;

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Product Name'**
  String get productName;

  /// No description provided for @sellingPrice.
  ///
  /// In en, this message translates to:
  /// **'Selling Price'**
  String get sellingPrice;

  /// No description provided for @profitMarginAuto.
  ///
  /// In en, this message translates to:
  /// **'Profit margin will be calculated automatically.'**
  String get profitMarginAuto;

  /// No description provided for @productVariants.
  ///
  /// In en, this message translates to:
  /// **'PRODUCT VARIANTS'**
  String get productVariants;

  /// No description provided for @addOption.
  ///
  /// In en, this message translates to:
  /// **'Add Option'**
  String get addOption;

  /// No description provided for @addOptionsHint.
  ///
  /// In en, this message translates to:
  /// **'Add options like Color, Size to create variants.'**
  String get addOptionsHint;

  /// No description provided for @optionNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Color, Size, Material'**
  String get optionNameHint;

  /// No description provided for @addValueTitle.
  ///
  /// In en, this message translates to:
  /// **'Add {optionName} Value'**
  String addValueTitle(String optionName);

  /// No description provided for @valueHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Red, Large, Cotton'**
  String get valueHint;

  /// No description provided for @variantsGenerated.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{variant} other{variants}} generated'**
  String variantsGenerated(int count);

  /// No description provided for @startStock.
  ///
  /// In en, this message translates to:
  /// **'START STOCK'**
  String get startStock;

  /// No description provided for @startingStockLabel.
  ///
  /// In en, this message translates to:
  /// **'Starting Stock'**
  String get startingStockLabel;

  /// No description provided for @rawMaterialsOptional.
  ///
  /// In en, this message translates to:
  /// **'RAW MATERIALS (OPTIONAL)'**
  String get rawMaterialsOptional;

  /// No description provided for @thisIsRawMaterial.
  ///
  /// In en, this message translates to:
  /// **'This is a raw material'**
  String get thisIsRawMaterial;

  /// No description provided for @selectBaseMaterialType.
  ///
  /// In en, this message translates to:
  /// **'Select Base Material Type'**
  String get selectBaseMaterialType;

  /// No description provided for @selectType.
  ///
  /// In en, this message translates to:
  /// **'Select type...'**
  String get selectType;

  /// No description provided for @wastePercentageEstimate.
  ///
  /// In en, this message translates to:
  /// **'Waste Percentage estimate'**
  String get wastePercentageEstimate;

  /// No description provided for @saveProduct.
  ///
  /// In en, this message translates to:
  /// **'Save Product'**
  String get saveProduct;

  /// No description provided for @selectUom.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectUom;

  /// No description provided for @addPhotoLabel.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get addPhotoLabel;

  /// No description provided for @productImage.
  ///
  /// In en, this message translates to:
  /// **'Product Image'**
  String get productImage;

  /// No description provided for @productMedia.
  ///
  /// In en, this message translates to:
  /// **'Product Media'**
  String get productMedia;

  /// No description provided for @basicInformation.
  ///
  /// In en, this message translates to:
  /// **'Basic Information'**
  String get basicInformation;

  /// No description provided for @pricingSection.
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get pricingSection;

  /// No description provided for @pricingStrategy.
  ///
  /// In en, this message translates to:
  /// **'Pricing Strategy'**
  String get pricingStrategy;

  /// No description provided for @variantPricing.
  ///
  /// In en, this message translates to:
  /// **'Variant Pricing'**
  String get variantPricing;

  /// No description provided for @applyCostToAllVariants.
  ///
  /// In en, this message translates to:
  /// **'Apply cost to all variants'**
  String get applyCostToAllVariants;

  /// No description provided for @setCostForAllVariants.
  ///
  /// In en, this message translates to:
  /// **'Set Cost for All Variants'**
  String get setCostForAllVariants;

  /// No description provided for @costPriceFromBreakdown.
  ///
  /// In en, this message translates to:
  /// **'COST PRICE (from breakdown)'**
  String get costPriceFromBreakdown;

  /// No description provided for @unitLabel.
  ///
  /// In en, this message translates to:
  /// **'UNIT'**
  String get unitLabel;

  /// No description provided for @storageLocationLabel.
  ///
  /// In en, this message translates to:
  /// **'STORAGE LOCATION'**
  String get storageLocationLabel;

  /// No description provided for @selectLocation.
  ///
  /// In en, this message translates to:
  /// **'Select location'**
  String get selectLocation;

  /// No description provided for @breakdownRecipe.
  ///
  /// In en, this message translates to:
  /// **'Breakdown Recipe'**
  String get breakdownRecipe;

  /// No description provided for @stockConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Stock Configuration'**
  String get stockConfiguration;

  /// No description provided for @defineBreakdownDesc.
  ///
  /// In en, this message translates to:
  /// **'Define how one variant breaks down into others'**
  String get defineBreakdownDesc;

  /// No description provided for @sourceVariant.
  ///
  /// In en, this message translates to:
  /// **'SOURCE VARIANT'**
  String get sourceVariant;

  /// No description provided for @selectSourceVariant.
  ///
  /// In en, this message translates to:
  /// **'Select source variant'**
  String get selectSourceVariant;

  /// No description provided for @outputVariantsQty.
  ///
  /// In en, this message translates to:
  /// **'OUTPUT VARIANTS (qty per 1 source unit)'**
  String get outputVariantsQty;

  /// No description provided for @advancedSettings.
  ///
  /// In en, this message translates to:
  /// **'Advanced Settings'**
  String get advancedSettings;

  /// No description provided for @supplierLabel.
  ///
  /// In en, this message translates to:
  /// **'SUPPLIER'**
  String get supplierLabel;

  /// No description provided for @noSuppliersYetLabel.
  ///
  /// In en, this message translates to:
  /// **'No suppliers yet'**
  String get noSuppliersYetLabel;

  /// No description provided for @manufacturedProduct.
  ///
  /// In en, this message translates to:
  /// **'Manufactured Product'**
  String get manufacturedProduct;

  /// No description provided for @manufacturedDesc.
  ///
  /// In en, this message translates to:
  /// **'Goods receipts adjust stock only — cost is managed separately'**
  String get manufacturedDesc;

  /// No description provided for @deleteProduct.
  ///
  /// In en, this message translates to:
  /// **'Delete Product'**
  String get deleteProduct;

  /// No description provided for @deleteProductConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete Product?'**
  String get deleteProductConfirm;

  /// No description provided for @deleteProductDesc.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone. The product and its movement history will be permanently removed.'**
  String get deleteProductDesc;

  /// No description provided for @productNotFound.
  ///
  /// In en, this message translates to:
  /// **'Product not found'**
  String get productNotFound;

  /// No description provided for @productNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Product name is required'**
  String get productNameRequired;

  /// No description provided for @failedToUpdateProduct.
  ///
  /// In en, this message translates to:
  /// **'Failed to update product'**
  String get failedToUpdateProduct;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit Product'**
  String get editProduct;

  /// No description provided for @productNameUpperLabel.
  ///
  /// In en, this message translates to:
  /// **'PRODUCT NAME'**
  String get productNameUpperLabel;

  /// No description provided for @skuUpperLabel.
  ///
  /// In en, this message translates to:
  /// **'SKU'**
  String get skuUpperLabel;

  /// No description provided for @categoryUpperLabel.
  ///
  /// In en, this message translates to:
  /// **'CATEGORY'**
  String get categoryUpperLabel;

  /// No description provided for @costPriceUpperLabel.
  ///
  /// In en, this message translates to:
  /// **'COST PRICE'**
  String get costPriceUpperLabel;

  /// No description provided for @sellingPriceUpperLabel.
  ///
  /// In en, this message translates to:
  /// **'SELLING PRICE'**
  String get sellingPriceUpperLabel;

  /// No description provided for @reorderPointUpperLabel.
  ///
  /// In en, this message translates to:
  /// **'REORDER POINT'**
  String get reorderPointUpperLabel;

  /// No description provided for @typeSupplierNameField.
  ///
  /// In en, this message translates to:
  /// **'Type supplier name...'**
  String get typeSupplierNameField;

  /// No description provided for @breakdownSourceNotExist.
  ///
  /// In en, this message translates to:
  /// **'Breakdown source variant no longer exists'**
  String get breakdownSourceNotExist;

  /// No description provided for @saveGoodsReceipt.
  ///
  /// In en, this message translates to:
  /// **'Save goods receipt'**
  String get saveGoodsReceipt;

  /// No description provided for @supplierAndPurchase.
  ///
  /// In en, this message translates to:
  /// **'Supplier & Purchase'**
  String get supplierAndPurchase;

  /// No description provided for @selectSupplier.
  ///
  /// In en, this message translates to:
  /// **'Select Supplier'**
  String get selectSupplier;

  /// No description provided for @linkToPurchaseOrder.
  ///
  /// In en, this message translates to:
  /// **'Link to Purchase Order'**
  String get linkToPurchaseOrder;

  /// No description provided for @linkToPurchaseOrderOptional.
  ///
  /// In en, this message translates to:
  /// **'Link to Purchase Order (optional)'**
  String get linkToPurchaseOrderOptional;

  /// No description provided for @manualEntryNoPO.
  ///
  /// In en, this message translates to:
  /// **'Manual entry (no PO)'**
  String get manualEntryNoPO;

  /// No description provided for @itemsReceived.
  ///
  /// In en, this message translates to:
  /// **'Items Received'**
  String get itemsReceived;

  /// No description provided for @ordered.
  ///
  /// In en, this message translates to:
  /// **'Ordered'**
  String get ordered;

  /// No description provided for @totalCost.
  ///
  /// In en, this message translates to:
  /// **'Total Cost'**
  String get totalCost;

  /// No description provided for @updateInventoryStock.
  ///
  /// In en, this message translates to:
  /// **'Update Inventory Stock'**
  String get updateInventoryStock;

  /// No description provided for @increaseProductQuantities.
  ///
  /// In en, this message translates to:
  /// **'Increase product quantities by received amounts'**
  String get increaseProductQuantities;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @confirmReceiptTotal.
  ///
  /// In en, this message translates to:
  /// **'Confirm Receipt · {currency} {total}'**
  String confirmReceiptTotal(String currency, String total);

  /// No description provided for @pleaseSelectSupplier.
  ///
  /// In en, this message translates to:
  /// **'Please select a supplier'**
  String get pleaseSelectSupplier;

  /// No description provided for @addAtLeastOneItem.
  ///
  /// In en, this message translates to:
  /// **'Add at least one item with a received quantity'**
  String get addAtLeastOneItem;

  /// No description provided for @receivedExceedsOrdered.
  ///
  /// In en, this message translates to:
  /// **'{name}: received qty ({received}) exceeds ordered qty ({ordered})'**
  String receivedExceedsOrdered(String name, String received, String ordered);

  /// No description provided for @failedToSaveGoodsReceipt.
  ///
  /// In en, this message translates to:
  /// **'Failed to save goods receipt'**
  String get failedToSaveGoodsReceipt;

  /// No description provided for @itemsCouldNotSync.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) could not be synced to inventory'**
  String itemsCouldNotSync(int count);

  /// No description provided for @priceChangeAlert.
  ///
  /// In en, this message translates to:
  /// **'Price Change Alert'**
  String get priceChangeAlert;

  /// No description provided for @significantCostChange.
  ///
  /// In en, this message translates to:
  /// **'The following items have a significant cost change (≥10%):'**
  String get significantCostChange;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got It'**
  String get gotIt;

  /// No description provided for @receivedGoodsWorth.
  ///
  /// In en, this message translates to:
  /// **'Received goods worth {currency} {total}'**
  String receivedGoodsWorth(String currency, String total);

  /// No description provided for @searchProductOrMaterial.
  ///
  /// In en, this message translates to:
  /// **'Search product or material'**
  String get searchProductOrMaterial;

  /// No description provided for @selectVariantTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Variant — {name}'**
  String selectVariantTitle(String name);

  /// No description provided for @costStockInfo.
  ///
  /// In en, this message translates to:
  /// **'Cost: {cost} · Stock: {stock}'**
  String costStockInfo(String cost, String stock);

  /// No description provided for @outLabel.
  ///
  /// In en, this message translates to:
  /// **'Out'**
  String get outLabel;

  /// No description provided for @searchProductsSku.
  ///
  /// In en, this message translates to:
  /// **'Search products, SKU...'**
  String get searchProductsSku;

  /// No description provided for @syncInventoryWithShopify.
  ///
  /// In en, this message translates to:
  /// **'Sync inventory with Shopify'**
  String get syncInventoryWithShopify;

  /// No description provided for @productsMissingCost.
  ///
  /// In en, this message translates to:
  /// **'{count} product(s) missing cost'**
  String productsMissingCost(int count);

  /// No description provided for @tapToRecordCostPrices.
  ///
  /// In en, this message translates to:
  /// **'Tap to record cost prices'**
  String get tapToRecordCostPrices;

  /// No description provided for @addStock.
  ///
  /// In en, this message translates to:
  /// **'Add Stock'**
  String get addStock;

  /// No description provided for @adjustStock.
  ///
  /// In en, this message translates to:
  /// **'Adjust Stock'**
  String get adjustStock;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @rawMaterials.
  ///
  /// In en, this message translates to:
  /// **'Raw Materials'**
  String get rawMaterials;

  /// No description provided for @allCount.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String allCount(int count);

  /// No description provided for @lowStockCount.
  ///
  /// In en, this message translates to:
  /// **'Low stock ({count})'**
  String lowStockCount(int count);

  /// No description provided for @outOfStockCount.
  ///
  /// In en, this message translates to:
  /// **'Out of stock ({count})'**
  String outOfStockCount(int count);

  /// No description provided for @noProductsMatchSearch.
  ///
  /// In en, this message translates to:
  /// **'No products match your search'**
  String get noProductsMatchSearch;

  /// No description provided for @tryChangingSearchOrFilters.
  ///
  /// In en, this message translates to:
  /// **'Try changing your search or filters'**
  String get tryChangingSearchOrFilters;

  /// No description provided for @addFirstProductToGetStarted.
  ///
  /// In en, this message translates to:
  /// **'Add your first product to get started'**
  String get addFirstProductToGetStarted;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @couldNotReadFile.
  ///
  /// In en, this message translates to:
  /// **'Could not read file'**
  String get couldNotReadFile;

  /// No description provided for @csvExceeds5Mb.
  ///
  /// In en, this message translates to:
  /// **'CSV file exceeds 5 MB limit'**
  String get csvExceeds5Mb;

  /// No description provided for @csvEmptyOrNoData.
  ///
  /// In en, this message translates to:
  /// **'CSV file is empty or has no data rows'**
  String get csvEmptyOrNoData;

  /// No description provided for @csvMustHaveNameColumn.
  ///
  /// In en, this message translates to:
  /// **'CSV must have a \"Name\" column'**
  String get csvMustHaveNameColumn;

  /// No description provided for @importedSkippedDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} product(s), skipped {skipped} duplicate(s)'**
  String importedSkippedDuplicates(int imported, int skipped);

  /// No description provided for @failedToImportCsv.
  ///
  /// In en, this message translates to:
  /// **'Failed to import CSV. Check file format.'**
  String get failedToImportCsv;

  /// No description provided for @inventoryOptions.
  ///
  /// In en, this message translates to:
  /// **'Inventory Options'**
  String get inventoryOptions;

  /// No description provided for @importFromCsv.
  ///
  /// In en, this message translates to:
  /// **'Import from CSV'**
  String get importFromCsv;

  /// No description provided for @exportInventory.
  ///
  /// In en, this message translates to:
  /// **'Export Inventory'**
  String get exportInventory;

  /// No description provided for @importFromShopify.
  ///
  /// In en, this message translates to:
  /// **'Import from Shopify'**
  String get importFromShopify;

  /// No description provided for @syncInventory.
  ///
  /// In en, this message translates to:
  /// **'Sync Inventory'**
  String get syncInventory;

  /// No description provided for @chooseARawMaterial.
  ///
  /// In en, this message translates to:
  /// **'Choose a raw material...'**
  String get chooseARawMaterial;

  /// No description provided for @chooseAVariant.
  ///
  /// In en, this message translates to:
  /// **'Choose a variant...'**
  String get chooseAVariant;

  /// No description provided for @quantityLabel.
  ///
  /// In en, this message translates to:
  /// **'QUANTITY'**
  String get quantityLabel;

  /// No description provided for @reasonLabel.
  ///
  /// In en, this message translates to:
  /// **'REASON'**
  String get reasonLabel;

  /// No description provided for @addMaterial.
  ///
  /// In en, this message translates to:
  /// **'Add Material'**
  String get addMaterial;

  /// No description provided for @selectProductUpper.
  ///
  /// In en, this message translates to:
  /// **'SELECT PRODUCT'**
  String get selectProductUpper;

  /// No description provided for @selectVariantUpper.
  ///
  /// In en, this message translates to:
  /// **'SELECT VARIANT'**
  String get selectVariantUpper;

  /// No description provided for @inventoryCostValue.
  ///
  /// In en, this message translates to:
  /// **'Inventory Cost Value'**
  String get inventoryCostValue;

  /// No description provided for @realTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Real-time'**
  String get realTimeLabel;

  /// No description provided for @outStock.
  ///
  /// In en, this message translates to:
  /// **'Out Stock'**
  String get outStock;

  /// No description provided for @importedProductsFromCsv.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} product(s) from CSV'**
  String importedProductsFromCsv(int imported);

  /// No description provided for @stockActionUnits.
  ///
  /// In en, this message translates to:
  /// **'{title} ({qty} units)'**
  String stockActionUnits(String title, int qty);

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @productDetails.
  ///
  /// In en, this message translates to:
  /// **'Product Details'**
  String get productDetails;

  /// No description provided for @recalculateOutputCosts.
  ///
  /// In en, this message translates to:
  /// **'Recalculate Output Costs'**
  String get recalculateOutputCosts;

  /// No description provided for @replaceCostLayers.
  ///
  /// In en, this message translates to:
  /// **'Replace cost layers?'**
  String get replaceCostLayers;

  /// No description provided for @replaceCostLayersDesc.
  ///
  /// In en, this message translates to:
  /// **'This will delete existing cost layers for all output variants and recalculate based on the current source cost and recipe. Continue?'**
  String get replaceCostLayersDesc;

  /// No description provided for @outputCostsRecalculated.
  ///
  /// In en, this message translates to:
  /// **'Output costs recalculated'**
  String get outputCostsRecalculated;

  /// No description provided for @quickAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Quick Adjustment'**
  String get quickAdjustment;

  /// No description provided for @manualCorrection.
  ///
  /// In en, this message translates to:
  /// **'Manual Correction'**
  String get manualCorrection;

  /// No description provided for @negativeStockDesc.
  ///
  /// In en, this message translates to:
  /// **'This adjustment would make the stock negative. Continue anyway?'**
  String get negativeStockDesc;

  /// No description provided for @enterValidUnitCost.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid unit cost'**
  String get enterValidUnitCost;

  /// No description provided for @restockPlus.
  ///
  /// In en, this message translates to:
  /// **'Restock +{qty}'**
  String restockPlus(int qty);

  /// No description provided for @currentInventory.
  ///
  /// In en, this message translates to:
  /// **'CURRENT INVENTORY'**
  String get currentInventory;

  /// No description provided for @unitsLabel.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get unitsLabel;

  /// No description provided for @pricing.
  ///
  /// In en, this message translates to:
  /// **'PRICING'**
  String get pricing;

  /// No description provided for @cost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get cost;

  /// No description provided for @selling.
  ///
  /// In en, this message translates to:
  /// **'Selling'**
  String get selling;

  /// No description provided for @margin.
  ///
  /// In en, this message translates to:
  /// **'Margin'**
  String get margin;

  /// No description provided for @costOverview.
  ///
  /// In en, this message translates to:
  /// **'COST OVERVIEW'**
  String get costOverview;

  /// No description provided for @avgCost.
  ///
  /// In en, this message translates to:
  /// **'Avg Cost'**
  String get avgCost;

  /// No description provided for @lastCost.
  ///
  /// In en, this message translates to:
  /// **'Last Cost'**
  String get lastCost;

  /// No description provided for @lowestCost.
  ///
  /// In en, this message translates to:
  /// **'Lowest'**
  String get lowestCost;

  /// No description provided for @recentCostHistory.
  ///
  /// In en, this message translates to:
  /// **'RECENT COST HISTORY'**
  String get recentCostHistory;

  /// No description provided for @variantsLabel.
  ///
  /// In en, this message translates to:
  /// **'Variants'**
  String get variantsLabel;

  /// No description provided for @recentMovements.
  ///
  /// In en, this message translates to:
  /// **'RECENT MOVEMENTS'**
  String get recentMovements;

  /// No description provided for @noMovementsYet.
  ///
  /// In en, this message translates to:
  /// **'No movements yet'**
  String get noMovementsYet;

  /// No description provided for @costBySupplier.
  ///
  /// In en, this message translates to:
  /// **'Cost by Supplier'**
  String get costBySupplier;

  /// No description provided for @supplierHeader.
  ///
  /// In en, this message translates to:
  /// **'SUPPLIER'**
  String get supplierHeader;

  /// No description provided for @avgHeader.
  ///
  /// In en, this message translates to:
  /// **'AVG'**
  String get avgHeader;

  /// No description provided for @lastHeader.
  ///
  /// In en, this message translates to:
  /// **'LAST'**
  String get lastHeader;

  /// No description provided for @ordersHeader.
  ///
  /// In en, this message translates to:
  /// **'ORDERS'**
  String get ordersHeader;

  /// No description provided for @bestLabel.
  ///
  /// In en, this message translates to:
  /// **'BEST'**
  String get bestLabel;

  /// No description provided for @avgLastCostIn.
  ///
  /// In en, this message translates to:
  /// **'Avg & Last cost in {currency}'**
  String avgLastCostIn(String currency);

  /// No description provided for @breakdownHistory.
  ///
  /// In en, this message translates to:
  /// **'Breakdown History'**
  String get breakdownHistory;

  /// No description provided for @saveAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Save Adjustment'**
  String get saveAdjustment;

  /// No description provided for @adjustmentFailed.
  ///
  /// In en, this message translates to:
  /// **'Adjustment failed'**
  String get adjustmentFailed;

  /// No description provided for @negativeStockTitle.
  ///
  /// In en, this message translates to:
  /// **'Negative stock'**
  String get negativeStockTitle;

  /// No description provided for @negativeStockWillBring.
  ///
  /// In en, this message translates to:
  /// **'This adjustment will bring stock to {stock}. Continue?'**
  String negativeStockWillBring(int stock);

  /// No description provided for @howManyUnitsToRestock.
  ///
  /// In en, this message translates to:
  /// **'How many units to restock?'**
  String get howManyUnitsToRestock;

  /// No description provided for @restockFailed.
  ///
  /// In en, this message translates to:
  /// **'Restock failed'**
  String get restockFailed;

  /// No description provided for @totalValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Value'**
  String get totalValueLabel;

  /// No description provided for @valueLabel.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get valueLabel;

  /// No description provided for @lastDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Last: {date}'**
  String lastDateLabel(String date);

  /// No description provided for @moreCount.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String moreCount(int count);

  /// No description provided for @sourceCostValue.
  ///
  /// In en, this message translates to:
  /// **'Source cost: {currency} {cost}'**
  String sourceCostValue(String currency, String cost);

  /// No description provided for @conversionSummary.
  ///
  /// In en, this message translates to:
  /// **'{sourceQty} units → {outputCount} output{outputCount, plural, =1{} other{s}}'**
  String conversionSummary(int sourceQty, int outputCount);

  /// No description provided for @correctionReason.
  ///
  /// In en, this message translates to:
  /// **'Correction'**
  String get correctionReason;

  /// No description provided for @damageReason.
  ///
  /// In en, this message translates to:
  /// **'Damage'**
  String get damageReason;

  /// No description provided for @lossReason.
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get lossReason;

  /// No description provided for @returnReason.
  ///
  /// In en, this message translates to:
  /// **'Return'**
  String get returnReason;

  /// No description provided for @restockReason.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get restockReason;

  /// No description provided for @saleReason.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get saleReason;

  /// No description provided for @skuLabel.
  ///
  /// In en, this message translates to:
  /// **'SKU: {sku}'**
  String skuLabel(String sku);

  /// No description provided for @supplierInfoLabel.
  ///
  /// In en, this message translates to:
  /// **'Supplier: {name}'**
  String supplierInfoLabel(String name);

  /// No description provided for @retailWithValue.
  ///
  /// In en, this message translates to:
  /// **'Retail: {currency} {value}'**
  String retailWithValue(String currency, String value);

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @hideDraftedProducts.
  ///
  /// In en, this message translates to:
  /// **'Hide drafted products'**
  String get hideDraftedProducts;

  /// No description provided for @hideDraftedProductsDesc.
  ///
  /// In en, this message translates to:
  /// **'Hide Shopify products with draft status'**
  String get hideDraftedProductsDesc;

  /// No description provided for @inventorySyncLabel.
  ///
  /// In en, this message translates to:
  /// **'Inventory Sync'**
  String get inventorySyncLabel;

  /// No description provided for @syncStockWithShopify.
  ///
  /// In en, this message translates to:
  /// **'Sync stock levels with Shopify'**
  String get syncStockWithShopify;

  /// No description provided for @syncModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync Mode'**
  String get syncModeLabel;

  /// No description provided for @chooseHowSync.
  ///
  /// In en, this message translates to:
  /// **'Choose how inventory stays in sync'**
  String get chooseHowSync;

  /// No description provided for @alwaysOnLabel.
  ///
  /// In en, this message translates to:
  /// **'Always-On'**
  String get alwaysOnLabel;

  /// No description provided for @onDemandLabel.
  ///
  /// In en, this message translates to:
  /// **'On-Demand'**
  String get onDemandLabel;

  /// No description provided for @fifoDescription.
  ///
  /// In en, this message translates to:
  /// **'First In, First Out — oldest stock sold first'**
  String get fifoDescription;

  /// No description provided for @lifoDescription.
  ///
  /// In en, this message translates to:
  /// **'Last In, First Out — newest stock sold first'**
  String get lifoDescription;

  /// No description provided for @averageCostDescription.
  ///
  /// In en, this message translates to:
  /// **'Weighted average of all purchase costs'**
  String get averageCostDescription;

  /// No description provided for @valuationMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'Valuation Method'**
  String get valuationMethodTitle;

  /// No description provided for @unitOfMeasureTitle.
  ///
  /// In en, this message translates to:
  /// **'Unit of Measure'**
  String get unitOfMeasureTitle;

  /// No description provided for @currencyTitle.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get currencyTitle;

  /// No description provided for @variantNegativeError.
  ///
  /// In en, this message translates to:
  /// **'{name}: cost, price, and stock must not be negative'**
  String variantNegativeError(String name);

  /// No description provided for @egFigure8Straps.
  ///
  /// In en, this message translates to:
  /// **'e.g. Figure-8 Straps'**
  String get egFigure8Straps;

  /// No description provided for @skuUpperOnly.
  ///
  /// In en, this message translates to:
  /// **'SKU'**
  String get skuUpperOnly;

  /// No description provided for @skuPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'SKU-123456'**
  String get skuPlaceholder;

  /// No description provided for @selectACategory.
  ///
  /// In en, this message translates to:
  /// **'Select a category'**
  String get selectACategory;

  /// No description provided for @importedCategory.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get importedCategory;

  /// No description provided for @fifoLabel.
  ///
  /// In en, this message translates to:
  /// **'FIFO'**
  String get fifoLabel;

  /// No description provided for @lifoLabel.
  ///
  /// In en, this message translates to:
  /// **'LIFO'**
  String get lifoLabel;

  /// No description provided for @averageLabel.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get averageLabel;

  /// No description provided for @kilogramsKg.
  ///
  /// In en, this message translates to:
  /// **'Kilograms (kg)'**
  String get kilogramsKg;

  /// No description provided for @materialFabric.
  ///
  /// In en, this message translates to:
  /// **'Fabric'**
  String get materialFabric;

  /// No description provided for @materialPlastic.
  ///
  /// In en, this message translates to:
  /// **'Plastic'**
  String get materialPlastic;

  /// No description provided for @materialWood.
  ///
  /// In en, this message translates to:
  /// **'Wood'**
  String get materialWood;

  /// No description provided for @materialMetal.
  ///
  /// In en, this message translates to:
  /// **'Metal'**
  String get materialMetal;

  /// No description provided for @materialLiquid.
  ///
  /// In en, this message translates to:
  /// **'Liquid'**
  String get materialLiquid;

  /// No description provided for @materialPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get materialPaper;

  /// No description provided for @materialOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get materialOther;

  /// No description provided for @egMatCot.
  ///
  /// In en, this message translates to:
  /// **'e.g. MAT-COT-4832'**
  String get egMatCot;

  /// No description provided for @egKilogramsLiters.
  ///
  /// In en, this message translates to:
  /// **'e.g. Kilograms, Liters...'**
  String get egKilogramsLiters;

  /// No description provided for @egGymGear.
  ///
  /// In en, this message translates to:
  /// **'e.g. Gym Gear, Supplements...'**
  String get egGymGear;

  /// No description provided for @variantCount.
  ///
  /// In en, this message translates to:
  /// **'{count} {count, plural, =1{variant} other{variants}}'**
  String variantCount(int count);

  /// No description provided for @qtyHint.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get qtyHint;

  /// No description provided for @poPrefix.
  ///
  /// In en, this message translates to:
  /// **'PO {ref}'**
  String poPrefix(String ref);

  /// No description provided for @purchaseFallback.
  ///
  /// In en, this message translates to:
  /// **'Purchase {id}'**
  String purchaseFallback(String id);

  /// No description provided for @perUnitCost.
  ///
  /// In en, this message translates to:
  /// **'{currency} {cost}/unit'**
  String perUnitCost(String currency, String cost);

  /// No description provided for @totalCostValue.
  ///
  /// In en, this message translates to:
  /// **'total {currency} {cost}'**
  String totalCostValue(String currency, String cost);

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// No description provided for @restockReason2.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get restockReason2;

  /// No description provided for @saleReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get saleReasonLabel;

  /// No description provided for @warehouseAShelf3.
  ///
  /// In en, this message translates to:
  /// **'Warehouse A - Shelf 3'**
  String get warehouseAShelf3;

  /// No description provided for @warehouseAShelf4.
  ///
  /// In en, this message translates to:
  /// **'Warehouse A - Shelf 4'**
  String get warehouseAShelf4;

  /// No description provided for @warehouseBLabel.
  ///
  /// In en, this message translates to:
  /// **'Warehouse B'**
  String get warehouseBLabel;

  /// No description provided for @displayStoreLabel.
  ///
  /// In en, this message translates to:
  /// **'Display Store'**
  String get displayStoreLabel;

  /// No description provided for @periodThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get periodThisWeek;

  /// No description provided for @periodThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get periodThisMonth;

  /// No description provided for @allTransactionsTab.
  ///
  /// In en, this message translates to:
  /// **'All Transactions'**
  String get allTransactionsTab;

  /// No description provided for @salesTab.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesTab;

  /// No description provided for @nSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} Selected'**
  String nSelected(int count);

  /// No description provided for @readyForBulkActions.
  ///
  /// In en, this message translates to:
  /// **'Ready for bulk actions'**
  String get readyForBulkActions;

  /// No description provided for @cancelOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel Orders'**
  String get cancelOrdersTitle;

  /// No description provided for @cancelOrdersBody.
  ///
  /// In en, this message translates to:
  /// **'Cancel {count} selected order(s)?\n\nThis will restore stock and create reversal accounting entries. This cannot be undone.'**
  String cancelOrdersBody(int count);

  /// No description provided for @nSalesMarkedPaid.
  ///
  /// In en, this message translates to:
  /// **'{count} sale(s) marked as paid'**
  String nSalesMarkedPaid(int count);

  /// No description provided for @nOrdersCancelled.
  ///
  /// In en, this message translates to:
  /// **'{count} order(s) cancelled (stock & accounting reverted)'**
  String nOrdersCancelled(int count);

  /// No description provided for @transactionDuplicated.
  ///
  /// In en, this message translates to:
  /// **'Transaction duplicated'**
  String get transactionDuplicated;

  /// No description provided for @deleteTransaction.
  ///
  /// In en, this message translates to:
  /// **'Delete Transaction'**
  String get deleteTransaction;

  /// No description provided for @deleteTransactionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this transaction?'**
  String get deleteTransactionConfirm;

  /// No description provided for @transactionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Transaction deleted'**
  String get transactionDeleted;

  /// No description provided for @noTransactionsFound.
  ///
  /// In en, this message translates to:
  /// **'No Transactions Found'**
  String get noTransactionsFound;

  /// No description provided for @tryAdjustingFilters.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your filters or period'**
  String get tryAdjustingFilters;

  /// No description provided for @failedToLoadSales.
  ///
  /// In en, this message translates to:
  /// **'Failed to load sales'**
  String get failedToLoadSales;

  /// No description provided for @connectYourShopifyStore.
  ///
  /// In en, this message translates to:
  /// **'Connect your Shopify store'**
  String get connectYourShopifyStore;

  /// No description provided for @syncOrdersInventoryProducts.
  ///
  /// In en, this message translates to:
  /// **'Sync orders, inventory & products automatically.'**
  String get syncOrdersInventoryProducts;

  /// No description provided for @connectShopify.
  ///
  /// In en, this message translates to:
  /// **'Connect Shopify'**
  String get connectShopify;

  /// No description provided for @shopifyIntegration.
  ///
  /// In en, this message translates to:
  /// **'Shopify Integration'**
  String get shopifyIntegration;

  /// No description provided for @shopifyIntegrationUpgradeDesc.
  ///
  /// In en, this message translates to:
  /// **'Sync your Shopify store with Revvo. Available on Growth Mode.'**
  String get shopifyIntegrationUpgradeDesc;

  /// No description provided for @upgradeToGrowth.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Growth'**
  String get upgradeToGrowth;

  /// No description provided for @copyAction.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyAction;

  /// No description provided for @fulfillmentPartialShip.
  ///
  /// In en, this message translates to:
  /// **'Partial Ship'**
  String get fulfillmentPartialShip;

  /// No description provided for @paymentPending.
  ///
  /// In en, this message translates to:
  /// **'Payment pending'**
  String get paymentPending;

  /// No description provided for @transactionDetail.
  ///
  /// In en, this message translates to:
  /// **'Transaction Detail'**
  String get transactionDetail;

  /// No description provided for @duplicateAction.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateAction;

  /// No description provided for @duplicateTransaction.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Transaction'**
  String get duplicateTransaction;

  /// No description provided for @cancelledStatus.
  ///
  /// In en, this message translates to:
  /// **'CANCELLED'**
  String get cancelledStatus;

  /// No description provided for @completedStatus.
  ///
  /// In en, this message translates to:
  /// **'COMPLETED'**
  String get completedStatus;

  /// No description provided for @dateAndTime.
  ///
  /// In en, this message translates to:
  /// **'Date & Time'**
  String get dateAndTime;

  /// No description provided for @paymentMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethodLabel;

  /// No description provided for @noteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get noteLabel;

  /// No description provided for @transactionId.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID'**
  String get transactionId;

  /// No description provided for @newExpense.
  ///
  /// In en, this message translates to:
  /// **'New Expense'**
  String get newExpense;

  /// No description provided for @newOtherIncome.
  ///
  /// In en, this message translates to:
  /// **'New Other Income'**
  String get newOtherIncome;

  /// No description provided for @newTransaction.
  ///
  /// In en, this message translates to:
  /// **'New Transaction'**
  String get newTransaction;

  /// No description provided for @editTransaction.
  ///
  /// In en, this message translates to:
  /// **'Edit Transaction'**
  String get editTransaction;

  /// No description provided for @amountLabel.
  ///
  /// In en, this message translates to:
  /// **'AMOUNT'**
  String get amountLabel;

  /// No description provided for @mostUsedAndRecent.
  ///
  /// In en, this message translates to:
  /// **'MOST USED & RECENT'**
  String get mostUsedAndRecent;

  /// No description provided for @paymentMethodSection.
  ///
  /// In en, this message translates to:
  /// **'Payment Method'**
  String get paymentMethodSection;

  /// No description provided for @addNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Add a note (optional)'**
  String get addNoteOptional;

  /// No description provided for @saveTransaction.
  ///
  /// In en, this message translates to:
  /// **'Save Transaction'**
  String get saveTransaction;

  /// No description provided for @savedReadyForNext.
  ///
  /// In en, this message translates to:
  /// **'Saved! Ready for next transaction.'**
  String get savedReadyForNext;

  /// No description provided for @pleaseEnterValidAmount.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid amount'**
  String get pleaseEnterValidAmount;

  /// No description provided for @transactionUpdated.
  ///
  /// In en, this message translates to:
  /// **'Transaction updated'**
  String get transactionUpdated;

  /// No description provided for @paymentCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentCash;

  /// No description provided for @paymentCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get paymentCard;

  /// No description provided for @paymentBank.
  ///
  /// In en, this message translates to:
  /// **'Bank'**
  String get paymentBank;

  /// No description provided for @paymentWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get paymentWallet;

  /// No description provided for @selectPayee.
  ///
  /// In en, this message translates to:
  /// **'Select Payee'**
  String get selectPayee;

  /// No description provided for @payeeNameOptional.
  ///
  /// In en, this message translates to:
  /// **'Payee Name (Optional)'**
  String get payeeNameOptional;

  /// No description provided for @addCustomCategory.
  ///
  /// In en, this message translates to:
  /// **'+ Add Custom Category'**
  String get addCustomCategory;

  /// No description provided for @enterCustomCategory.
  ///
  /// In en, this message translates to:
  /// **'Enter custom category...'**
  String get enterCustomCategory;

  /// No description provided for @allCategoriesComingSoon.
  ///
  /// In en, this message translates to:
  /// **'All categories view coming soon'**
  String get allCategoriesComingSoon;

  /// No description provided for @seeAllLabel.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAllLabel;

  /// No description provided for @moreLabel.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreLabel;

  /// No description provided for @filterTransactions.
  ///
  /// In en, this message translates to:
  /// **'Filter Transactions'**
  String get filterTransactions;

  /// No description provided for @resetLabel.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetLabel;

  /// No description provided for @transactionType.
  ///
  /// In en, this message translates to:
  /// **'Transaction Type'**
  String get transactionType;

  /// No description provided for @amountRange.
  ///
  /// In en, this message translates to:
  /// **'Amount Range'**
  String get amountRange;

  /// No description provided for @filterSales.
  ///
  /// In en, this message translates to:
  /// **'Filter Sales'**
  String get filterSales;

  /// No description provided for @paymentStatus.
  ///
  /// In en, this message translates to:
  /// **'Payment Status'**
  String get paymentStatus;

  /// No description provided for @searchTransactions.
  ///
  /// In en, this message translates to:
  /// **'Search transactions...'**
  String get searchTransactions;

  /// No description provided for @suggestedLabel.
  ///
  /// In en, this message translates to:
  /// **'SUGGESTED'**
  String get suggestedLabel;

  /// No description provided for @noResultsFound.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResultsFound;

  /// No description provided for @tryDifferentSearchTerm.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term'**
  String get tryDifferentSearchTerm;

  /// No description provided for @scheduledTransactions.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Transactions'**
  String get scheduledTransactions;

  /// No description provided for @addRecurrence.
  ///
  /// In en, this message translates to:
  /// **'Add Recurrence'**
  String get addRecurrence;

  /// No description provided for @noScheduledTransactions.
  ///
  /// In en, this message translates to:
  /// **'No Scheduled Transactions'**
  String get noScheduledTransactions;

  /// No description provided for @scheduledTransactionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Add rent, salaries, or subscriptions\nto automate your cash flow forecast.'**
  String get scheduledTransactionsEmpty;

  /// No description provided for @pausedLabel.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get pausedLabel;

  /// No description provided for @nextLabel.
  ///
  /// In en, this message translates to:
  /// **'Next:'**
  String get nextLabel;

  /// No description provided for @editScheduledTransaction.
  ///
  /// In en, this message translates to:
  /// **'Edit Scheduled Transaction'**
  String get editScheduledTransaction;

  /// No description provided for @newRecurringTransaction.
  ///
  /// In en, this message translates to:
  /// **'New Recurring Transaction'**
  String get newRecurringTransaction;

  /// No description provided for @titleExample.
  ///
  /// In en, this message translates to:
  /// **'Title (e.g., Office Rent)'**
  String get titleExample;

  /// No description provided for @frequencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get frequencyLabel;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @saveScheduledTransaction.
  ///
  /// In en, this message translates to:
  /// **'Save Scheduled Transaction'**
  String get saveScheduledTransaction;

  /// No description provided for @whatWouldYouLikeToRecord.
  ///
  /// In en, this message translates to:
  /// **'What would you like to record?'**
  String get whatWouldYouLikeToRecord;

  /// No description provided for @nItemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String nItemsCount(int count);

  /// No description provided for @growthBadge.
  ///
  /// In en, this message translates to:
  /// **'GROWTH'**
  String get growthBadge;

  /// No description provided for @pausedBadge.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get pausedBadge;

  /// No description provided for @titleFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Title (e.g., Office Rent)'**
  String get titleFieldHint;

  /// No description provided for @amountFieldHint.
  ///
  /// In en, this message translates to:
  /// **'Amount ({currency})'**
  String amountFieldHint(String currency);

  /// No description provided for @weekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get weekly;

  /// No description provided for @searchSuggestionGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get searchSuggestionGroceries;

  /// No description provided for @searchSuggestionNetflix.
  ///
  /// In en, this message translates to:
  /// **'Netflix'**
  String get searchSuggestionNetflix;

  /// No description provided for @searchSuggestionUber.
  ///
  /// In en, this message translates to:
  /// **'Uber'**
  String get searchSuggestionUber;

  /// No description provided for @recentActivity.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivity;

  /// No description provided for @overdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdue;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @supplierStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Supplier Status'**
  String get supplierStatusLabel;

  /// No description provided for @outstandingBalanceRange.
  ///
  /// In en, this message translates to:
  /// **'Outstanding Balance Range'**
  String get outstandingBalanceRange;

  /// No description provided for @balanceHighToLow.
  ///
  /// In en, this message translates to:
  /// **'Balance (High to Low)'**
  String get balanceHighToLow;

  /// No description provided for @alphabetical.
  ///
  /// In en, this message translates to:
  /// **'A-Z'**
  String get alphabetical;

  /// No description provided for @overdueAmount.
  ///
  /// In en, this message translates to:
  /// **'Overdue Amount'**
  String get overdueAmount;

  /// No description provided for @hasBalanceDue.
  ///
  /// In en, this message translates to:
  /// **'Has Balance Due'**
  String get hasBalanceDue;

  /// No description provided for @withBalanceDue.
  ///
  /// In en, this message translates to:
  /// **'With balance due'**
  String get withBalanceDue;

  /// No description provided for @overdueWithCount.
  ///
  /// In en, this message translates to:
  /// **'Overdue ({count})'**
  String overdueWithCount(int count);

  /// No description provided for @recentlyUsed.
  ///
  /// In en, this message translates to:
  /// **'Recently used'**
  String get recentlyUsed;

  /// No description provided for @addSupplier.
  ///
  /// In en, this message translates to:
  /// **'Add Supplier'**
  String get addSupplier;

  /// No description provided for @recordPurchaseAction.
  ///
  /// In en, this message translates to:
  /// **'Record Purchase'**
  String get recordPurchaseAction;

  /// No description provided for @recordPaymentAction.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get recordPaymentAction;

  /// No description provided for @amountDue.
  ///
  /// In en, this message translates to:
  /// **'{amount} due'**
  String amountDue(String amount);

  /// No description provided for @overdueDays.
  ///
  /// In en, this message translates to:
  /// **'Overdue {days}d'**
  String overdueDays(int days);

  /// No description provided for @supplierDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Supplier Detail'**
  String get supplierDetailTitle;

  /// No description provided for @purchaseButton.
  ///
  /// In en, this message translates to:
  /// **'Purchase'**
  String get purchaseButton;

  /// No description provided for @receiveGoodsButton.
  ///
  /// In en, this message translates to:
  /// **'Receive Goods'**
  String get receiveGoodsButton;

  /// No description provided for @categoryColon.
  ///
  /// In en, this message translates to:
  /// **'Category: {name}'**
  String categoryColon(String name);

  /// No description provided for @totalDue.
  ///
  /// In en, this message translates to:
  /// **'TOTAL DUE'**
  String get totalDue;

  /// No description provided for @callAction.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callAction;

  /// No description provided for @noPhoneNumberAvailable.
  ///
  /// In en, this message translates to:
  /// **'No phone number available'**
  String get noPhoneNumberAvailable;

  /// No description provided for @cannotMakeCall.
  ///
  /// In en, this message translates to:
  /// **'Cannot make a call from this device'**
  String get cannotMakeCall;

  /// No description provided for @whatsAppAction.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsAppAction;

  /// No description provided for @cannotOpenWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Cannot open WhatsApp'**
  String get cannotOpenWhatsApp;

  /// No description provided for @emailAction.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailAction;

  /// No description provided for @noEmailAvailable.
  ///
  /// In en, this message translates to:
  /// **'No email address available'**
  String get noEmailAvailable;

  /// No description provided for @invalidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get invalidEmailAddress;

  /// No description provided for @cannotOpenEmailApp.
  ///
  /// In en, this message translates to:
  /// **'Cannot open email app'**
  String get cannotOpenEmailApp;

  /// No description provided for @totalPurchased.
  ///
  /// In en, this message translates to:
  /// **'Total Purchased'**
  String get totalPurchased;

  /// No description provided for @lastPurchaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Last Purchase'**
  String get lastPurchaseLabel;

  /// No description provided for @totalPaymentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Payments'**
  String get totalPaymentsLabel;

  /// No description provided for @goodsReceivedLabel.
  ///
  /// In en, this message translates to:
  /// **'Goods Received'**
  String get goodsReceivedLabel;

  /// No description provided for @noActivityHelp.
  ///
  /// In en, this message translates to:
  /// **'Record a purchase, payment, or receive goods to get started.'**
  String get noActivityHelp;

  /// No description provided for @purchaseReference.
  ///
  /// In en, this message translates to:
  /// **'Purchase #{ref}'**
  String purchaseReference(String ref);

  /// No description provided for @purchaseItemCount.
  ///
  /// In en, this message translates to:
  /// **'Purchase — {count} item(s)'**
  String purchaseItemCount(int count);

  /// No description provided for @paymentMethodDash.
  ///
  /// In en, this message translates to:
  /// **'Payment — {method}'**
  String paymentMethodDash(String method);

  /// No description provided for @receivedItemCount.
  ///
  /// In en, this message translates to:
  /// **'Received {count} item(s)'**
  String receivedItemCount(int count);

  /// No description provided for @viewDetailsAction.
  ///
  /// In en, this message translates to:
  /// **'View Details'**
  String get viewDetailsAction;

  /// No description provided for @deleteReceiptConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This will delete the receipt and reverse the inventory stock adjustment. Continue?'**
  String get deleteReceiptConfirmation;

  /// No description provided for @receiptDeleted.
  ///
  /// In en, this message translates to:
  /// **'Receipt deleted'**
  String get receiptDeleted;

  /// No description provided for @addNewSupplier.
  ///
  /// In en, this message translates to:
  /// **'Add New Supplier'**
  String get addNewSupplier;

  /// No description provided for @addSupplierSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your supplier to start tracking purchases.'**
  String get addSupplierSubtitle;

  /// No description provided for @saveSupplier.
  ///
  /// In en, this message translates to:
  /// **'Save Supplier'**
  String get saveSupplier;

  /// No description provided for @invalidEmailValidation.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get invalidEmailValidation;

  /// No description provided for @phoneMinDigitsValidation.
  ///
  /// In en, this message translates to:
  /// **'Phone number must have at least 7 digits'**
  String get phoneMinDigitsValidation;

  /// No description provided for @supplierAddedMsg.
  ///
  /// In en, this message translates to:
  /// **'{name} added'**
  String supplierAddedMsg(String name);

  /// No description provided for @supplierBasics.
  ///
  /// In en, this message translates to:
  /// **'SUPPLIER BASICS'**
  String get supplierBasics;

  /// No description provided for @supplierIdField.
  ///
  /// In en, this message translates to:
  /// **'Supplier ID'**
  String get supplierIdField;

  /// No description provided for @contactInfoSection.
  ///
  /// In en, this message translates to:
  /// **'CONTACT INFO'**
  String get contactInfoSection;

  /// No description provided for @emailAddressField.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddressField;

  /// No description provided for @whatsAppAvailable.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp Available'**
  String get whatsAppAvailable;

  /// No description provided for @canCommunicateWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Can communicate via WhatsApp?'**
  String get canCommunicateWhatsApp;

  /// No description provided for @paymentDetailsSection.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT DETAILS'**
  String get paymentDetailsSection;

  /// No description provided for @paymentTermsLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment Terms'**
  String get paymentTermsLabel;

  /// No description provided for @startingBalanceDebt.
  ///
  /// In en, this message translates to:
  /// **'Starting Balance (Debt)'**
  String get startingBalanceDebt;

  /// No description provided for @locationAndNotes.
  ///
  /// In en, this message translates to:
  /// **'LOCATION & NOTES'**
  String get locationAndNotes;

  /// No description provided for @addressField.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressField;

  /// No description provided for @notesField.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesField;

  /// No description provided for @additionalDetailsHint.
  ///
  /// In en, this message translates to:
  /// **'Add any additional details here...'**
  String get additionalDetailsHint;

  /// No description provided for @editSupplierTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Supplier'**
  String get editSupplierTitle;

  /// No description provided for @deleteSupplierTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Supplier'**
  String get deleteSupplierTitle;

  /// No description provided for @deleteSupplierConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? This action cannot be undone.'**
  String deleteSupplierConfirmation(String name);

  /// No description provided for @supplierUpdatedMsg.
  ///
  /// In en, this message translates to:
  /// **'{name} updated'**
  String supplierUpdatedMsg(String name);

  /// No description provided for @businessInfoSection.
  ///
  /// In en, this message translates to:
  /// **'BUSINESS INFO'**
  String get businessInfoSection;

  /// No description provided for @selectCategory.
  ///
  /// In en, this message translates to:
  /// **'Select Category'**
  String get selectCategory;

  /// No description provided for @selectLabel.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get selectLabel;

  /// No description provided for @contactDetailsSection.
  ///
  /// In en, this message translates to:
  /// **'CONTACT DETAILS'**
  String get contactDetailsSection;

  /// No description provided for @financialsSection.
  ///
  /// In en, this message translates to:
  /// **'FINANCIALS'**
  String get financialsSection;

  /// No description provided for @defaultTerms.
  ///
  /// In en, this message translates to:
  /// **'Default Terms'**
  String get defaultTerms;

  /// No description provided for @selectTerms.
  ///
  /// In en, this message translates to:
  /// **'Select Terms'**
  String get selectTerms;

  /// No description provided for @selectCurrency.
  ///
  /// In en, this message translates to:
  /// **'Select Currency'**
  String get selectCurrency;

  /// No description provided for @trackPayables.
  ///
  /// In en, this message translates to:
  /// **'Track Payables'**
  String get trackPayables;

  /// No description provided for @locationSection.
  ///
  /// In en, this message translates to:
  /// **'LOCATION'**
  String get locationSection;

  /// No description provided for @officeAddress.
  ///
  /// In en, this message translates to:
  /// **'Office Address'**
  String get officeAddress;

  /// No description provided for @optionalLabel.
  ///
  /// In en, this message translates to:
  /// **'(Optional)'**
  String get optionalLabel;

  /// No description provided for @confirmPurchase.
  ///
  /// In en, this message translates to:
  /// **'Confirm Purchase'**
  String get confirmPurchase;

  /// No description provided for @purchaseRecorded.
  ///
  /// In en, this message translates to:
  /// **'Purchase recorded'**
  String get purchaseRecorded;

  /// No description provided for @recordPurchaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Record Purchase'**
  String get recordPurchaseTitle;

  /// No description provided for @detailsSection.
  ///
  /// In en, this message translates to:
  /// **'DETAILS'**
  String get detailsSection;

  /// No description provided for @selectASupplier.
  ///
  /// In en, this message translates to:
  /// **'Select a supplier'**
  String get selectASupplier;

  /// No description provided for @purchaseDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchase Date'**
  String get purchaseDateLabel;

  /// No description provided for @referenceNoLabel.
  ///
  /// In en, this message translates to:
  /// **'Reference No.'**
  String get referenceNoLabel;

  /// No description provided for @selectSupplierTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Supplier'**
  String get selectSupplierTitle;

  /// No description provided for @addNewSupplierPlus.
  ///
  /// In en, this message translates to:
  /// **'+ Add New Supplier'**
  String get addNewSupplierPlus;

  /// No description provided for @whatAreYouPurchasing.
  ///
  /// In en, this message translates to:
  /// **'What are you purchasing?'**
  String get whatAreYouPurchasing;

  /// No description provided for @materialsUsedInProduction.
  ///
  /// In en, this message translates to:
  /// **'Materials used in production'**
  String get materialsUsedInProduction;

  /// No description provided for @finishedGoodsForResale.
  ///
  /// In en, this message translates to:
  /// **'Finished goods for resale'**
  String get finishedGoodsForResale;

  /// No description provided for @processingAndAssemblyCosts.
  ///
  /// In en, this message translates to:
  /// **'Processing & assembly costs'**
  String get processingAndAssemblyCosts;

  /// No description provided for @itemsPurchasedSection.
  ///
  /// In en, this message translates to:
  /// **'ITEMS PURCHASED'**
  String get itemsPurchasedSection;

  /// No description provided for @itemLabel.
  ///
  /// In en, this message translates to:
  /// **'ITEM'**
  String get itemLabel;

  /// No description provided for @tapToSelectItem.
  ///
  /// In en, this message translates to:
  /// **'Tap to select item'**
  String get tapToSelectItem;

  /// No description provided for @qtyLabel.
  ///
  /// In en, this message translates to:
  /// **'QTY'**
  String get qtyLabel;

  /// No description provided for @unitPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'UNIT PRICE'**
  String get unitPriceLabel;

  /// No description provided for @addItemAction.
  ///
  /// In en, this message translates to:
  /// **'Add Item'**
  String get addItemAction;

  /// No description provided for @subtotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotalLabel;

  /// No description provided for @taxLabel.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get taxLabel;

  /// No description provided for @totalAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Amount'**
  String get totalAmountLabel;

  /// No description provided for @paymentStatusSection.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT STATUS'**
  String get paymentStatusSection;

  /// No description provided for @fullyPaid.
  ///
  /// In en, this message translates to:
  /// **'Fully Paid'**
  String get fullyPaid;

  /// No description provided for @dueDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Due Date'**
  String get dueDateLabel;

  /// No description provided for @selectDueDateHint.
  ///
  /// In en, this message translates to:
  /// **'Select due date'**
  String get selectDueDateHint;

  /// No description provided for @alertWillBeSent.
  ///
  /// In en, this message translates to:
  /// **'Alert will be sent on this date.'**
  String get alertWillBeSent;

  /// No description provided for @dueDateForRemaining.
  ///
  /// In en, this message translates to:
  /// **'Due Date for Remaining'**
  String get dueDateForRemaining;

  /// No description provided for @purchaseFullyPaid.
  ///
  /// In en, this message translates to:
  /// **'This purchase is fully paid'**
  String get purchaseFullyPaid;

  /// No description provided for @rawMaterialLabel.
  ///
  /// In en, this message translates to:
  /// **'Raw Material'**
  String get rawMaterialLabel;

  /// No description provided for @productLabel.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get productLabel;

  /// No description provided for @manufacturingFee.
  ///
  /// In en, this message translates to:
  /// **'Manufacturing Fee'**
  String get manufacturingFee;

  /// No description provided for @purchaseDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase Details'**
  String get purchaseDetailsTitle;

  /// No description provided for @totalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalLabel;

  /// No description provided for @viewProfile.
  ///
  /// In en, this message translates to:
  /// **'View Profile'**
  String get viewProfile;

  /// No description provided for @dateIssued.
  ///
  /// In en, this message translates to:
  /// **'Date Issued'**
  String get dateIssued;

  /// No description provided for @itemsBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Items Breakdown'**
  String get itemsBreakdown;

  /// No description provided for @onReceipt.
  ///
  /// In en, this message translates to:
  /// **'On Receipt'**
  String get onReceipt;

  /// No description provided for @net15.
  ///
  /// In en, this message translates to:
  /// **'Net 15'**
  String get net15;

  /// No description provided for @net30.
  ///
  /// In en, this message translates to:
  /// **'Net 30'**
  String get net30;

  /// No description provided for @net60.
  ///
  /// In en, this message translates to:
  /// **'Net 60'**
  String get net60;

  /// No description provided for @notAvailableLabel.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get notAvailableLabel;

  /// No description provided for @termsLabel.
  ///
  /// In en, this message translates to:
  /// **'Terms'**
  String get termsLabel;

  /// No description provided for @paymentDueOnReceipt.
  ///
  /// In en, this message translates to:
  /// **'Payment is due upon receipt of goods.'**
  String get paymentDueOnReceipt;

  /// No description provided for @paymentDueWithinDays.
  ///
  /// In en, this message translates to:
  /// **'Payment is due within {days} days of the invoice date.'**
  String paymentDueWithinDays(String days);

  /// No description provided for @editPurchase.
  ///
  /// In en, this message translates to:
  /// **'Edit Purchase'**
  String get editPurchase;

  /// No description provided for @paymentExceedsOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Payment Exceeds Outstanding'**
  String get paymentExceedsOutstanding;

  /// No description provided for @paymentExceedsOutstandingBody.
  ///
  /// In en, this message translates to:
  /// **'The payment amount exceeds the total outstanding ({amount}) on the selected purchases. The excess will be applied to the supplier balance.\n\nDo you want to proceed?'**
  String paymentExceedsOutstandingBody(String amount);

  /// No description provided for @proceedAction.
  ///
  /// In en, this message translates to:
  /// **'Proceed'**
  String get proceedAction;

  /// No description provided for @paymentExceedsBalance.
  ///
  /// In en, this message translates to:
  /// **'Payment Exceeds Balance'**
  String get paymentExceedsBalance;

  /// No description provided for @paymentExceedsBalanceBody.
  ///
  /// In en, this message translates to:
  /// **'This payment exceeds the supplier\'s current balance ({amount}). The balance will become negative (advance/credit).\n\nDo you want to proceed?'**
  String paymentExceedsBalanceBody(String amount);

  /// No description provided for @paymentRecorded.
  ///
  /// In en, this message translates to:
  /// **'Payment recorded'**
  String get paymentRecorded;

  /// No description provided for @confirmPayment.
  ///
  /// In en, this message translates to:
  /// **'Confirm Payment'**
  String get confirmPayment;

  /// No description provided for @payingTo.
  ///
  /// In en, this message translates to:
  /// **'PAYING TO'**
  String get payingTo;

  /// No description provided for @changeAction.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeAction;

  /// No description provided for @totalBalanceDue.
  ///
  /// In en, this message translates to:
  /// **'Total Balance Due'**
  String get totalBalanceDue;

  /// No description provided for @recordPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Record Payment'**
  String get recordPaymentTitle;

  /// No description provided for @amountToPay.
  ///
  /// In en, this message translates to:
  /// **'Amount to Pay'**
  String get amountToPay;

  /// No description provided for @paymentDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment Date'**
  String get paymentDateLabel;

  /// No description provided for @openInvoices.
  ///
  /// In en, this message translates to:
  /// **'Open Invoices'**
  String get openInvoices;

  /// No description provided for @noOpenInvoices.
  ///
  /// In en, this message translates to:
  /// **'No open invoices for this supplier'**
  String get noOpenInvoices;

  /// No description provided for @uploadReceipt.
  ///
  /// In en, this message translates to:
  /// **'Upload Receipt'**
  String get uploadReceipt;

  /// No description provided for @paymentDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Details'**
  String get paymentDetailsTitle;

  /// No description provided for @paymentSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Payment Successful'**
  String get paymentSuccessful;

  /// No description provided for @paidTo.
  ///
  /// In en, this message translates to:
  /// **'Paid To'**
  String get paidTo;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @appliedToInvoices.
  ///
  /// In en, this message translates to:
  /// **'Applied to Invoices'**
  String get appliedToInvoices;

  /// No description provided for @noInvoicesLinked.
  ///
  /// In en, this message translates to:
  /// **'No invoices linked'**
  String get noInvoicesLinked;

  /// No description provided for @attachmentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachmentsLabel;

  /// No description provided for @receiptLabel.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receiptLabel;

  /// No description provided for @noAttachments.
  ///
  /// In en, this message translates to:
  /// **'No attachments'**
  String get noAttachments;

  /// No description provided for @downloadPdfReceipt.
  ///
  /// In en, this message translates to:
  /// **'Download PDF Receipt'**
  String get downloadPdfReceipt;

  /// No description provided for @repeatPayment.
  ///
  /// In en, this message translates to:
  /// **'Repeat Payment'**
  String get repeatPayment;

  /// No description provided for @editPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Payment'**
  String get editPaymentTitle;

  /// No description provided for @paymentUpdated.
  ///
  /// In en, this message translates to:
  /// **'Payment updated'**
  String get paymentUpdated;

  /// No description provided for @deletePaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Payment'**
  String get deletePaymentTitle;

  /// No description provided for @deletePaymentConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this payment record? This action cannot be undone.'**
  String get deletePaymentConfirmation;

  /// No description provided for @lockedLabel.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get lockedLabel;

  /// No description provided for @paymentAmountSection.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT AMOUNT'**
  String get paymentAmountSection;

  /// No description provided for @noLinkedInvoices.
  ///
  /// In en, this message translates to:
  /// **'No linked invoices'**
  String get noLinkedInvoices;

  /// No description provided for @addNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Add a note…'**
  String get addNoteHint;

  /// No description provided for @paymentsSummary.
  ///
  /// In en, this message translates to:
  /// **'Payments Summary'**
  String get paymentsSummary;

  /// No description provided for @totalPaymentsMonth.
  ///
  /// In en, this message translates to:
  /// **'Total Payments ({month})'**
  String totalPaymentsMonth(String month);

  /// No description provided for @paidLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paidLabel;

  /// No description provided for @paymentTrends.
  ///
  /// In en, this message translates to:
  /// **'Payment Trends'**
  String get paymentTrends;

  /// No description provided for @lastSixMonths.
  ///
  /// In en, this message translates to:
  /// **'Last 6 Months'**
  String get lastSixMonths;

  /// No description provided for @paymentMethodsLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment Methods'**
  String get paymentMethodsLabel;

  /// No description provided for @noDataLabel.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get noDataLabel;

  /// No description provided for @recentPayments.
  ///
  /// In en, this message translates to:
  /// **'Recent Payments'**
  String get recentPayments;

  /// No description provided for @allPayments.
  ///
  /// In en, this message translates to:
  /// **'All Payments'**
  String get allPayments;

  /// No description provided for @noPaymentsYet.
  ///
  /// In en, this message translates to:
  /// **'No payments yet'**
  String get noPaymentsYet;

  /// No description provided for @purchasesSummary.
  ///
  /// In en, this message translates to:
  /// **'Purchases Summary'**
  String get purchasesSummary;

  /// No description provided for @totalPurchasesMonth.
  ///
  /// In en, this message translates to:
  /// **'Total Purchases ({month})'**
  String totalPurchasesMonth(String month);

  /// No description provided for @itemsOrdered.
  ///
  /// In en, this message translates to:
  /// **'Items Ordered'**
  String get itemsOrdered;

  /// No description provided for @avgOrder.
  ///
  /// In en, this message translates to:
  /// **'Avg. Order'**
  String get avgOrder;

  /// No description provided for @purchaseVolume.
  ///
  /// In en, this message translates to:
  /// **'Purchase Volume'**
  String get purchaseVolume;

  /// No description provided for @recentPurchases.
  ///
  /// In en, this message translates to:
  /// **'Recent Purchases'**
  String get recentPurchases;

  /// No description provided for @allPurchases.
  ///
  /// In en, this message translates to:
  /// **'All Purchases'**
  String get allPurchases;

  /// No description provided for @noPurchasesYet.
  ///
  /// In en, this message translates to:
  /// **'No purchases yet'**
  String get noPurchasesYet;

  /// No description provided for @receiptDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Receipt Details'**
  String get receiptDetailsTitle;

  /// No description provided for @totalCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Cost'**
  String get totalCostLabel;

  /// No description provided for @fulfilmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Fulfilment'**
  String get fulfilmentLabel;

  /// No description provided for @itemsReceivedLabel.
  ///
  /// In en, this message translates to:
  /// **'Items Received'**
  String get itemsReceivedLabel;

  /// No description provided for @deleteReceiptReverseConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This will delete the receipt and reverse the inventory stock adjustment. Continue?'**
  String get deleteReceiptReverseConfirmation;

  /// No description provided for @allDates.
  ///
  /// In en, this message translates to:
  /// **'All dates'**
  String get allDates;

  /// No description provided for @receiptCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} Receipt(s)'**
  String receiptCountLabel(int count);

  /// No description provided for @pendingCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} Pending'**
  String pendingCountLabel(int count);

  /// No description provided for @confirmedLabel.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmedLabel;

  /// No description provided for @receiptsVerified.
  ///
  /// In en, this message translates to:
  /// **'Receipts verified'**
  String get receiptsVerified;

  /// No description provided for @pendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingLabel;

  /// No description provided for @allConfirmed.
  ///
  /// In en, this message translates to:
  /// **'All confirmed ✓'**
  String get allConfirmed;

  /// No description provided for @awaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Awaiting review'**
  String get awaitingReview;

  /// No description provided for @rejectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejectedLabel;

  /// No description provided for @receiveItemsAction.
  ///
  /// In en, this message translates to:
  /// **'Receive Items'**
  String get receiveItemsAction;

  /// No description provided for @receivedItemsLabel.
  ///
  /// In en, this message translates to:
  /// **'Received Items'**
  String get receivedItemsLabel;

  /// No description provided for @fullyReceivedLabel.
  ///
  /// In en, this message translates to:
  /// **'Fully received'**
  String get fullyReceivedLabel;

  /// No description provided for @orderedItems.
  ///
  /// In en, this message translates to:
  /// **'Ordered Items'**
  String get orderedItems;

  /// No description provided for @receiptsLabel.
  ///
  /// In en, this message translates to:
  /// **'Receipts'**
  String get receiptsLabel;

  /// No description provided for @itemsReceivedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) received'**
  String itemsReceivedCount(int count);

  /// No description provided for @adjustStockForQuantityChanges.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock for quantity changes'**
  String get adjustStockForQuantityChanges;

  /// No description provided for @selectItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Select Item'**
  String get selectItemTitle;

  /// No description provided for @searchInventoryHint.
  ///
  /// In en, this message translates to:
  /// **'Search inventory...'**
  String get searchInventoryHint;

  /// No description provided for @noMatchingItems.
  ///
  /// In en, this message translates to:
  /// **'No matching items found.'**
  String get noMatchingItems;

  /// No description provided for @addAsCustomItem.
  ///
  /// In en, this message translates to:
  /// **'Add \"{name}\" as custom item'**
  String addAsCustomItem(String name);

  /// No description provided for @writeCustomItem.
  ///
  /// In en, this message translates to:
  /// **'Write a custom item'**
  String get writeCustomItem;

  /// No description provided for @customItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Custom Item'**
  String get customItemTitle;

  /// No description provided for @enterItemNameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter item name...'**
  String get enterItemNameHint;

  /// No description provided for @addAction.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addAction;

  /// No description provided for @purchasesLabel.
  ///
  /// In en, this message translates to:
  /// **'Purchases'**
  String get purchasesLabel;

  /// No description provided for @paymentsLabel.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get paymentsLabel;

  /// No description provided for @suppliersLabel.
  ///
  /// In en, this message translates to:
  /// **'Suppliers'**
  String get suppliersLabel;

  /// No description provided for @supplierCategoryPackaging.
  ///
  /// In en, this message translates to:
  /// **'Packaging'**
  String get supplierCategoryPackaging;

  /// No description provided for @supplierCategoryRawMaterials.
  ///
  /// In en, this message translates to:
  /// **'Raw Materials'**
  String get supplierCategoryRawMaterials;

  /// No description provided for @supplierCategoryLogistics.
  ///
  /// In en, this message translates to:
  /// **'Logistics'**
  String get supplierCategoryLogistics;

  /// No description provided for @supplierCategoryMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Maintenance'**
  String get supplierCategoryMaintenance;

  /// No description provided for @supplierCategoryWholesale.
  ///
  /// In en, this message translates to:
  /// **'Wholesale'**
  String get supplierCategoryWholesale;

  /// No description provided for @supplierCategoryGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get supplierCategoryGeneral;

  /// No description provided for @paymentMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get paymentMethodCash;

  /// No description provided for @paymentMethodBankTransfer.
  ///
  /// In en, this message translates to:
  /// **'Bank Transfer'**
  String get paymentMethodBankTransfer;

  /// No description provided for @paymentMethodInstaPay.
  ///
  /// In en, this message translates to:
  /// **'InstaPay'**
  String get paymentMethodInstaPay;

  /// No description provided for @paymentMethodVodafoneCash.
  ///
  /// In en, this message translates to:
  /// **'Vodafone Cash'**
  String get paymentMethodVodafoneCash;

  /// No description provided for @minLabel.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get minLabel;

  /// No description provided for @maxLabel.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get maxLabel;

  /// No description provided for @saveChangesWithTotal.
  ///
  /// In en, this message translates to:
  /// **'Save Changes · {total}'**
  String saveChangesWithTotal(String total);

  /// No description provided for @paymentCount.
  ///
  /// In en, this message translates to:
  /// **'{count} Payment(s)'**
  String paymentCount(int count);

  /// No description provided for @deleteReceipt.
  ///
  /// In en, this message translates to:
  /// **'Delete Receipt'**
  String get deleteReceipt;

  /// No description provided for @paidBadge.
  ///
  /// In en, this message translates to:
  /// **'PAID'**
  String get paidBadge;

  /// No description provided for @addressHint.
  ///
  /// In en, this message translates to:
  /// **'Street, Building, City'**
  String get addressHint;

  /// No description provided for @supplierIdHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. SUP-001'**
  String get supplierIdHint;

  /// No description provided for @optionalHint.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optionalHint;

  /// No description provided for @manufacturingFeeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Stitching fee, Printing...'**
  String get manufacturingFeeHint;

  /// No description provided for @nItemsBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} Items'**
  String nItemsBadge(int count);

  /// No description provided for @purchaseRefTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchase #{ref}'**
  String purchaseRefTitle(String ref);

  /// No description provided for @shareDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date: {date}'**
  String shareDateLabel(String date);

  /// No description provided for @shareSupplierLabel.
  ///
  /// In en, this message translates to:
  /// **'Supplier: {name}'**
  String shareSupplierLabel(String name);

  /// No description provided for @shareStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String shareStatusLabel(String status);

  /// No description provided for @shareTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total: {total}'**
  String shareTotalLabel(String total);

  /// No description provided for @shareItemsLabel.
  ///
  /// In en, this message translates to:
  /// **'Items:'**
  String get shareItemsLabel;

  /// No description provided for @balanceDueSuffix.
  ///
  /// In en, this message translates to:
  /// **'{amount} due'**
  String balanceDueSuffix(String amount);

  /// No description provided for @nOpenBadge.
  ///
  /// In en, this message translates to:
  /// **'{count} Open'**
  String nOpenBadge(int count);

  /// No description provided for @paymentRefHint.
  ///
  /// In en, this message translates to:
  /// **'Add payment reference details...'**
  String get paymentRefHint;

  /// No description provided for @supplierPaymentTitle.
  ///
  /// In en, this message translates to:
  /// **'Supplier Payment — {name}'**
  String supplierPaymentTitle(String name);

  /// No description provided for @nMoreItems.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String nMoreItems(int count);

  /// No description provided for @poNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'PO #{ref}'**
  String poNumberLabel(String ref);

  /// No description provided for @linkedPoTotal.
  ///
  /// In en, this message translates to:
  /// **'Total: {amount} · {count} {count, plural, =1{item} other{items}}'**
  String linkedPoTotal(String amount, int count);

  /// No description provided for @receivedOfOrdered.
  ///
  /// In en, this message translates to:
  /// **'Received {received} of {ordered} · {cost} ea'**
  String receivedOfOrdered(String received, String ordered, String cost);

  /// No description provided for @receiptDeletedReversal.
  ///
  /// In en, this message translates to:
  /// **'Receipt deleted – reversal'**
  String get receiptDeletedReversal;

  /// No description provided for @poRefSupplier.
  ///
  /// In en, this message translates to:
  /// **'PO #{ref} – {supplier}'**
  String poRefSupplier(String ref, String supplier);

  /// No description provided for @itemsReceivedProgress.
  ///
  /// In en, this message translates to:
  /// **'{received} / {ordered} items received'**
  String itemsReceivedProgress(int received, int ordered);

  /// No description provided for @receiptEditAdded.
  ///
  /// In en, this message translates to:
  /// **'Receipt edit – added'**
  String get receiptEditAdded;

  /// No description provided for @receiptEditReduced.
  ///
  /// In en, this message translates to:
  /// **'Receipt edit – reduced'**
  String get receiptEditReduced;

  /// No description provided for @supplierNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Al-Amal Supplies'**
  String get supplierNameHint;

  /// No description provided for @categoryHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Packaging'**
  String get categoryHint;

  /// No description provided for @supplierEmailHint.
  ///
  /// In en, this message translates to:
  /// **'supplier@example.com'**
  String get supplierEmailHint;

  /// No description provided for @currencyEgpDisplay.
  ///
  /// In en, this message translates to:
  /// **'EGP - Egyptian Pound'**
  String get currencyEgpDisplay;

  /// No description provided for @currencyUsdDisplay.
  ///
  /// In en, this message translates to:
  /// **'USD - US Dollar'**
  String get currencyUsdDisplay;

  /// No description provided for @currencyEurDisplay.
  ///
  /// In en, this message translates to:
  /// **'EUR - Euro'**
  String get currencyEurDisplay;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'+20 xxx xxx xxxx'**
  String get phoneHint;

  /// No description provided for @createCategory.
  ///
  /// In en, this message translates to:
  /// **'Create Category'**
  String get createCategory;

  /// No description provided for @tierLaunch.
  ///
  /// In en, this message translates to:
  /// **'Launch'**
  String get tierLaunch;

  /// No description provided for @tierGrowth.
  ///
  /// In en, this message translates to:
  /// **'Growth'**
  String get tierGrowth;

  /// No description provided for @tierPro.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get tierPro;

  /// No description provided for @featureBalanceSheet.
  ///
  /// In en, this message translates to:
  /// **'Balance Sheet'**
  String get featureBalanceSheet;

  /// No description provided for @featureBalanceSheetDesc.
  ///
  /// In en, this message translates to:
  /// **'Full balance sheet with assets, liabilities & equity tracking'**
  String get featureBalanceSheetDesc;

  /// No description provided for @featureIncomeStatement.
  ///
  /// In en, this message translates to:
  /// **'Income Statement'**
  String get featureIncomeStatement;

  /// No description provided for @featureIncomeStatementDesc.
  ///
  /// In en, this message translates to:
  /// **'Revenue, COGS, gross profit & operating expenses breakdown'**
  String get featureIncomeStatementDesc;

  /// No description provided for @featureExportReports.
  ///
  /// In en, this message translates to:
  /// **'Export Reports'**
  String get featureExportReports;

  /// No description provided for @featureExportReportsDesc.
  ///
  /// In en, this message translates to:
  /// **'Export & share your financial reports as PDF'**
  String get featureExportReportsDesc;

  /// No description provided for @featureBudgetLimits.
  ///
  /// In en, this message translates to:
  /// **'Budget Limits'**
  String get featureBudgetLimits;

  /// No description provided for @featureBudgetLimitsDesc.
  ///
  /// In en, this message translates to:
  /// **'Set spending limits per category and track them'**
  String get featureBudgetLimitsDesc;

  /// No description provided for @featurePurchasesDashboard.
  ///
  /// In en, this message translates to:
  /// **'Purchases Dashboard'**
  String get featurePurchasesDashboard;

  /// No description provided for @featurePurchasesDashboardDesc.
  ///
  /// In en, this message translates to:
  /// **'Overview of all purchases with analytics'**
  String get featurePurchasesDashboardDesc;

  /// No description provided for @featurePaymentsDashboard.
  ///
  /// In en, this message translates to:
  /// **'Payments Dashboard'**
  String get featurePaymentsDashboard;

  /// No description provided for @featurePaymentsDashboardDesc.
  ///
  /// In en, this message translates to:
  /// **'Overview of all supplier payments with analytics'**
  String get featurePaymentsDashboardDesc;

  /// No description provided for @featureRawMaterials.
  ///
  /// In en, this message translates to:
  /// **'Raw Materials'**
  String get featureRawMaterials;

  /// No description provided for @featureRawMaterialsDesc.
  ///
  /// In en, this message translates to:
  /// **'Track raw materials with scrap percentage & material types'**
  String get featureRawMaterialsDesc;

  /// No description provided for @featureInventorySettings.
  ///
  /// In en, this message translates to:
  /// **'Inventory Settings'**
  String get featureInventorySettings;

  /// No description provided for @featureInventorySettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Advanced inventory configuration & alerts'**
  String get featureInventorySettingsDesc;

  /// No description provided for @featureStockMovements.
  ///
  /// In en, this message translates to:
  /// **'Stock Movement History'**
  String get featureStockMovements;

  /// No description provided for @featureStockMovementsDesc.
  ///
  /// In en, this message translates to:
  /// **'Full history of all stock changes & movements'**
  String get featureStockMovementsDesc;

  /// No description provided for @featureRecurringTransactions.
  ///
  /// In en, this message translates to:
  /// **'Recurring Transactions'**
  String get featureRecurringTransactions;

  /// No description provided for @featureRecurringTransactionsDesc.
  ///
  /// In en, this message translates to:
  /// **'Schedule recurring income & expense entries'**
  String get featureRecurringTransactionsDesc;

  /// No description provided for @featureAiInsights.
  ///
  /// In en, this message translates to:
  /// **'AI Insights'**
  String get featureAiInsights;

  /// No description provided for @featureAiInsightsDesc.
  ///
  /// In en, this message translates to:
  /// **'Get AI-powered financial analysis & advice'**
  String get featureAiInsightsDesc;

  /// No description provided for @featureHubCustomization.
  ///
  /// In en, this message translates to:
  /// **'Hub Customization'**
  String get featureHubCustomization;

  /// No description provided for @featureHubCustomizationDesc.
  ///
  /// In en, this message translates to:
  /// **'Customize your management hub layout & quick actions'**
  String get featureHubCustomizationDesc;

  /// No description provided for @featureGoodsReceiving.
  ///
  /// In en, this message translates to:
  /// **'Goods Receiving'**
  String get featureGoodsReceiving;

  /// No description provided for @featureGoodsReceivingDesc.
  ///
  /// In en, this message translates to:
  /// **'Track received items vs ordered & auto-update inventory'**
  String get featureGoodsReceivingDesc;

  /// No description provided for @featureSalesCogs.
  ///
  /// In en, this message translates to:
  /// **'Sales & COGS'**
  String get featureSalesCogs;

  /// No description provided for @featureSalesCogsDesc.
  ///
  /// In en, this message translates to:
  /// **'Record sales, track cost of goods sold & gross profit'**
  String get featureSalesCogsDesc;

  /// No description provided for @featurePaymentSettings.
  ///
  /// In en, this message translates to:
  /// **'Payment Settings'**
  String get featurePaymentSettings;

  /// No description provided for @featurePaymentSettingsDesc.
  ///
  /// In en, this message translates to:
  /// **'Control whether supplier payments create transactions'**
  String get featurePaymentSettingsDesc;

  /// No description provided for @featureShopifyIntegration.
  ///
  /// In en, this message translates to:
  /// **'Shopify Integration'**
  String get featureShopifyIntegration;

  /// No description provided for @featureShopifyIntegrationDesc.
  ///
  /// In en, this message translates to:
  /// **'Connect your Shopify store for two-way order and inventory sync'**
  String get featureShopifyIntegrationDesc;

  /// No description provided for @featureManufacturingMode.
  ///
  /// In en, this message translates to:
  /// **'Manufacturing Mode'**
  String get featureManufacturingMode;

  /// No description provided for @featureManufacturingModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Flag products as manufactured to decouple goods receipt from cost layers'**
  String get featureManufacturingModeDesc;

  /// No description provided for @featureSupplierManagement.
  ///
  /// In en, this message translates to:
  /// **'Supplier Management'**
  String get featureSupplierManagement;

  /// No description provided for @featureSupplierManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Track suppliers, record purchases & payments'**
  String get featureSupplierManagementDesc;

  /// No description provided for @featureFullCashFlow.
  ///
  /// In en, this message translates to:
  /// **'Full Cash Flow Analysis'**
  String get featureFullCashFlow;

  /// No description provided for @featureFullCashFlowDesc.
  ///
  /// In en, this message translates to:
  /// **'GAAP operating, investing & financing breakdown with drill-down'**
  String get featureFullCashFlowDesc;

  /// No description provided for @limitReached.
  ///
  /// In en, this message translates to:
  /// **'Limit reached'**
  String get limitReached;

  /// No description provided for @productLimitReachedTitle.
  ///
  /// In en, this message translates to:
  /// **'Product Limit Reached'**
  String get productLimitReachedTitle;

  /// No description provided for @productLimitReachedBody.
  ///
  /// In en, this message translates to:
  /// **'You can add up to {limit} products on the Launch plan. Upgrade to Growth for unlimited products.'**
  String productLimitReachedBody(int limit);

  /// No description provided for @unlockGrowthTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock More with Growth'**
  String get unlockGrowthTitle;

  /// No description provided for @unlockGrowthSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Take your business further with powerful tools'**
  String get unlockGrowthSubtitle;

  /// No description provided for @notifOutOfStockTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} — Out of Stock'**
  String notifOutOfStockTitle(String name);

  /// No description provided for @notifOutOfStockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All variants are out of stock. Reorder now to avoid lost sales.'**
  String get notifOutOfStockSubtitle;

  /// No description provided for @notifVariantStockLeft.
  ///
  /// In en, this message translates to:
  /// **'{name}: {count} left'**
  String notifVariantStockLeft(String name, String count);

  /// No description provided for @notifLowStockTitle.
  ///
  /// In en, this message translates to:
  /// **'{name} — Low Stock'**
  String notifLowStockTitle(String name);

  /// No description provided for @notifUnitsRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} units remaining'**
  String notifUnitsRemaining(String count);

  /// No description provided for @notifOverdueTitle.
  ///
  /// In en, this message translates to:
  /// **'Overdue: {name}'**
  String notifOverdueTitle(String name);

  /// No description provided for @notifOverdueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{currency} {amount} outstanding — {days} day(s) past due (Ref: {ref})'**
  String notifOverdueSubtitle(
    String currency,
    String amount,
    String days,
    String ref,
  );

  /// No description provided for @notifPaymentDueTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment Due: {name}'**
  String notifPaymentDueTitle(String name);

  /// No description provided for @notifPaymentDueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{currency} {amount} due in {days} day(s) (Ref: {ref})'**
  String notifPaymentDueSubtitle(
    String currency,
    String amount,
    String days,
    String ref,
  );

  /// No description provided for @notifUnpaidSaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Unpaid Sale: {name}'**
  String notifUnpaidSaleTitle(String name);

  /// No description provided for @notifOutstandingFrom.
  ///
  /// In en, this message translates to:
  /// **'{currency} {amount} outstanding from {date}'**
  String notifOutstandingFrom(String currency, String amount, String date);

  /// No description provided for @notifUnpaidSalesTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} Unpaid Sales'**
  String notifUnpaidSalesTitle(String count);

  /// No description provided for @notifTotalOutstanding.
  ///
  /// In en, this message translates to:
  /// **'{currency} {amount} total outstanding'**
  String notifTotalOutstanding(String currency, String amount);

  /// No description provided for @notifScheduledOverdueTitle.
  ///
  /// In en, this message translates to:
  /// **'Overdue: {title}'**
  String notifScheduledOverdueTitle(String title);

  /// No description provided for @notifScheduledOverdueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{type} of {currency} {amount} was due {date}'**
  String notifScheduledOverdueSubtitle(
    String type,
    String currency,
    String amount,
    String date,
  );

  /// No description provided for @notifScheduledUpcomingTitle.
  ///
  /// In en, this message translates to:
  /// **'Upcoming: {title}'**
  String notifScheduledUpcomingTitle(String title);

  /// No description provided for @notifScheduledDueToday.
  ///
  /// In en, this message translates to:
  /// **'{type} of {currency} {amount} due today'**
  String notifScheduledDueToday(String type, String currency, String amount);

  /// No description provided for @notifScheduledDueInDays.
  ///
  /// In en, this message translates to:
  /// **'{type} of {currency} {amount} due in {days} day(s)'**
  String notifScheduledDueInDays(
    String type,
    String currency,
    String amount,
    String days,
  );

  /// No description provided for @loginFailedError.
  ///
  /// In en, this message translates to:
  /// **'Login failed: {error}'**
  String loginFailedError(String error);

  /// No description provided for @signupFailedError.
  ///
  /// In en, this message translates to:
  /// **'Signup failed: {error}'**
  String signupFailedError(String error);

  /// No description provided for @googleSignInFailedError.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in failed: {error}'**
  String googleSignInFailedError(String error);

  /// No description provided for @appleSignInFailedError.
  ///
  /// In en, this message translates to:
  /// **'Apple sign-in failed: {error}'**
  String appleSignInFailedError(String error);

  /// No description provided for @userFallbackName.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userFallbackName;

  /// No description provided for @unknownStatus.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownStatus;

  /// No description provided for @defaultVariantName.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultVariantName;

  /// No description provided for @budgetsTitle.
  ///
  /// In en, this message translates to:
  /// **'Budgets'**
  String get budgetsTitle;

  /// No description provided for @paymentsDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Payments Dashboard'**
  String get paymentsDashboardTitle;

  /// No description provided for @purchasesDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchases Dashboard'**
  String get purchasesDashboardTitle;

  /// No description provided for @salesTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesTitle;

  /// No description provided for @aiInsightsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Insights'**
  String get aiInsightsTitle;

  /// No description provided for @productMappingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Product Mappings'**
  String get productMappingsTitle;

  /// No description provided for @syncHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Sync History'**
  String get syncHistoryTitle;

  /// No description provided for @receiptNotFound.
  ///
  /// In en, this message translates to:
  /// **'Receipt not found'**
  String get receiptNotFound;

  /// No description provided for @tierModeFeature.
  ///
  /// In en, this message translates to:
  /// **'{tier} Mode Feature'**
  String tierModeFeature(String tier);

  /// No description provided for @compareAllPlans.
  ///
  /// In en, this message translates to:
  /// **'Compare all plans'**
  String get compareAllPlans;

  /// No description provided for @tierMode.
  ///
  /// In en, this message translates to:
  /// **'{tier} Mode'**
  String tierMode(String tier);

  /// No description provided for @somethingWentWrongShort.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrongShort;

  /// No description provided for @uploadPhoto.
  ///
  /// In en, this message translates to:
  /// **'Upload Photo'**
  String get uploadPhoto;

  /// No description provided for @revvoExport.
  ///
  /// In en, this message translates to:
  /// **'Revvo Export'**
  String get revvoExport;

  /// No description provided for @readAll.
  ///
  /// In en, this message translates to:
  /// **'Read All'**
  String get readAll;

  /// No description provided for @walkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get walkIn;

  /// No description provided for @stockLeftReorder.
  ///
  /// In en, this message translates to:
  /// **'{current} left (reorder at {reorder})'**
  String stockLeftReorder(int current, int reorder);

  /// No description provided for @nUnitsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} units'**
  String nUnitsCount(String count);

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'Track Your Money Effortlessly'**
  String get onboardingTitle1;

  /// No description provided for @onboardingHighlight1.
  ///
  /// In en, this message translates to:
  /// **'Effortlessly'**
  String get onboardingHighlight1;

  /// No description provided for @onboardingSubtitle1.
  ///
  /// In en, this message translates to:
  /// **'Automatically categorize income and expenses. No accounting degree needed.'**
  String get onboardingSubtitle1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'AI Does the Hard Work'**
  String get onboardingTitle2;

  /// No description provided for @onboardingHighlight2.
  ///
  /// In en, this message translates to:
  /// **'Hard Work'**
  String get onboardingHighlight2;

  /// No description provided for @onboardingSubtitle2.
  ///
  /// In en, this message translates to:
  /// **'Smart insights, error detection, and plain-English explanations of your finances.'**
  String get onboardingSubtitle2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Grow With Confidence'**
  String get onboardingTitle3;

  /// No description provided for @onboardingHighlight3.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get onboardingHighlight3;

  /// No description provided for @onboardingSubtitle3.
  ///
  /// In en, this message translates to:
  /// **'Monthly reports, profitability tracking, and business valuation — all automated.'**
  String get onboardingSubtitle3;

  /// No description provided for @onboardingSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get onboardingNext;

  /// No description provided for @onboardingIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get onboardingIncome;

  /// No description provided for @onboardingAutoCategorized.
  ///
  /// In en, this message translates to:
  /// **'Auto-categorized'**
  String get onboardingAutoCategorized;

  /// No description provided for @onboardingUnsorted.
  ///
  /// In en, this message translates to:
  /// **'Unsorted'**
  String get onboardingUnsorted;

  /// No description provided for @onboardingAiQuote.
  ///
  /// In en, this message translates to:
  /// **'\"Your cash flow looks healthier this month.\"'**
  String get onboardingAiQuote;

  /// No description provided for @countryEgypt.
  ///
  /// In en, this message translates to:
  /// **'Egypt'**
  String get countryEgypt;

  /// No description provided for @countrySaudiArabia.
  ///
  /// In en, this message translates to:
  /// **'Saudi Arabia'**
  String get countrySaudiArabia;

  /// No description provided for @countryUAE.
  ///
  /// In en, this message translates to:
  /// **'UAE'**
  String get countryUAE;

  /// No description provided for @countryKuwait.
  ///
  /// In en, this message translates to:
  /// **'Kuwait'**
  String get countryKuwait;

  /// No description provided for @countryBahrain.
  ///
  /// In en, this message translates to:
  /// **'Bahrain'**
  String get countryBahrain;

  /// No description provided for @countryQatar.
  ///
  /// In en, this message translates to:
  /// **'Qatar'**
  String get countryQatar;

  /// No description provided for @countryOman.
  ///
  /// In en, this message translates to:
  /// **'Oman'**
  String get countryOman;

  /// No description provided for @countryJordan.
  ///
  /// In en, this message translates to:
  /// **'Jordan'**
  String get countryJordan;

  /// No description provided for @countryUS.
  ///
  /// In en, this message translates to:
  /// **'US'**
  String get countryUS;

  /// No description provided for @countryUK.
  ///
  /// In en, this message translates to:
  /// **'UK'**
  String get countryUK;

  /// No description provided for @aiGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hi there! I\'m your Revvo AI Assistant. How can I help you analyze your finances today?'**
  String get aiGreeting;

  /// No description provided for @aiPreviewResponse.
  ///
  /// In en, this message translates to:
  /// **'I\'m currently in preview mode. When connected to a real AI backend, I\'ll be able to analyze your Revvo financial data and provide deep insights. Stay tuned!'**
  String get aiPreviewResponse;

  /// No description provided for @aiTitle.
  ///
  /// In en, this message translates to:
  /// **'Revvo AI'**
  String get aiTitle;

  /// No description provided for @aiPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get aiPreview;

  /// No description provided for @aiHint.
  ///
  /// In en, this message translates to:
  /// **'Ask Revvo AI...'**
  String get aiHint;

  /// No description provided for @aiVoiceSoon.
  ///
  /// In en, this message translates to:
  /// **'Voice input coming soon'**
  String get aiVoiceSoon;

  /// No description provided for @aiSuggestCashFlow1.
  ///
  /// In en, this message translates to:
  /// **'Analyze my cash flow this month'**
  String get aiSuggestCashFlow1;

  /// No description provided for @aiSuggestCashFlow2.
  ///
  /// In en, this message translates to:
  /// **'Why is my cash balance low?'**
  String get aiSuggestCashFlow2;

  /// No description provided for @aiSuggestCashFlow3.
  ///
  /// In en, this message translates to:
  /// **'Forecast next month\'s expenses'**
  String get aiSuggestCashFlow3;

  /// No description provided for @aiSuggestProfit1.
  ///
  /// In en, this message translates to:
  /// **'Where am I overspending?'**
  String get aiSuggestProfit1;

  /// No description provided for @aiSuggestProfit2.
  ///
  /// In en, this message translates to:
  /// **'How can I increase my net profit?'**
  String get aiSuggestProfit2;

  /// No description provided for @aiSuggestProfit3.
  ///
  /// In en, this message translates to:
  /// **'Compare last month\'s revenue'**
  String get aiSuggestProfit3;

  /// No description provided for @aiSuggestCategory1.
  ///
  /// In en, this message translates to:
  /// **'Which category breaks my budget?'**
  String get aiSuggestCategory1;

  /// No description provided for @aiSuggestCategory2.
  ///
  /// In en, this message translates to:
  /// **'Suggest limits for my expenses'**
  String get aiSuggestCategory2;

  /// No description provided for @aiSuggestCategory3.
  ///
  /// In en, this message translates to:
  /// **'Create a category report'**
  String get aiSuggestCategory3;

  /// No description provided for @aiSuggestDefault1.
  ///
  /// In en, this message translates to:
  /// **'Give me a financial summary'**
  String get aiSuggestDefault1;

  /// No description provided for @aiSuggestDefault2.
  ///
  /// In en, this message translates to:
  /// **'How to reduce operating costs?'**
  String get aiSuggestDefault2;

  /// No description provided for @aiSuggestDefault3.
  ///
  /// In en, this message translates to:
  /// **'Show me my top expenses'**
  String get aiSuggestDefault3;

  /// No description provided for @noNotifications.
  ///
  /// In en, this message translates to:
  /// **'No notifications'**
  String get noNotifications;

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'You\'re all caught up!'**
  String get allCaughtUp;

  /// No description provided for @todayLabel.
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get todayLabel;

  /// No description provided for @earlierLabel.
  ///
  /// In en, this message translates to:
  /// **'EARLIER'**
  String get earlierLabel;

  /// No description provided for @ok.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @errorWithDetails.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithDetails(String error);

  /// No description provided for @trackingHintExample.
  ///
  /// In en, this message translates to:
  /// **'e.g. 1Z999AA10123456784'**
  String get trackingHintExample;

  /// No description provided for @reportMonthTitle.
  ///
  /// In en, this message translates to:
  /// **'{month} REPORT'**
  String reportMonthTitle(String month);

  /// No description provided for @reportGenerated.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get reportGenerated;

  /// No description provided for @reportCashflowTrend.
  ///
  /// In en, this message translates to:
  /// **'CASHFLOW TREND'**
  String get reportCashflowTrend;

  /// No description provided for @reportTopExpenses.
  ///
  /// In en, this message translates to:
  /// **'TOP EXPENSES'**
  String get reportTopExpenses;

  /// No description provided for @reportAiAnalysis.
  ///
  /// In en, this message translates to:
  /// **'AI Analysis'**
  String get reportAiAnalysis;

  /// No description provided for @reportAiAnalysisPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'AI-powered insights will appear here based on your financial data.'**
  String get reportAiAnalysisPlaceholder;

  /// No description provided for @reportPoweredBy.
  ///
  /// In en, this message translates to:
  /// **'Powered by Revvo'**
  String get reportPoweredBy;

  /// No description provided for @reportPageOf.
  ///
  /// In en, this message translates to:
  /// **'Page {current} of {total}'**
  String reportPageOf(int current, int total);

  /// No description provided for @reportVsLastMonth.
  ///
  /// In en, this message translates to:
  /// **'vs {amount} last mo.'**
  String reportVsLastMonth(String amount);

  /// No description provided for @expenseSalaries.
  ///
  /// In en, this message translates to:
  /// **'Salaries'**
  String get expenseSalaries;

  /// No description provided for @expenseRent.
  ///
  /// In en, this message translates to:
  /// **'Rent'**
  String get expenseRent;

  /// No description provided for @expenseMarketing.
  ///
  /// In en, this message translates to:
  /// **'Marketing'**
  String get expenseMarketing;

  /// No description provided for @expenseSoftware.
  ///
  /// In en, this message translates to:
  /// **'Software'**
  String get expenseSoftware;

  /// No description provided for @pdfGeneratedOn.
  ///
  /// In en, this message translates to:
  /// **'Generated {date}'**
  String pdfGeneratedOn(String date);

  /// No description provided for @pdfFooterLabel.
  ///
  /// In en, this message translates to:
  /// **'Revvo - Financial Report'**
  String get pdfFooterLabel;

  /// No description provided for @categoryGroceries.
  ///
  /// In en, this message translates to:
  /// **'Groceries'**
  String get categoryGroceries;

  /// No description provided for @categoryIncome.
  ///
  /// In en, this message translates to:
  /// **'Income'**
  String get categoryIncome;

  /// No description provided for @categoryTransport.
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get categoryTransport;

  /// No description provided for @categoryEntertainment.
  ///
  /// In en, this message translates to:
  /// **'Entertainment'**
  String get categoryEntertainment;

  /// No description provided for @categoryBills.
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get categoryBills;

  /// No description provided for @categoryHealth.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get categoryHealth;

  /// No description provided for @categoryEducation.
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get categoryEducation;

  /// No description provided for @categoryShopping.
  ///
  /// In en, this message translates to:
  /// **'Shopping'**
  String get categoryShopping;

  /// No description provided for @categoryFoodDining.
  ///
  /// In en, this message translates to:
  /// **'Food & Dining'**
  String get categoryFoodDining;

  /// No description provided for @categoryGifts.
  ///
  /// In en, this message translates to:
  /// **'Gifts'**
  String get categoryGifts;

  /// No description provided for @categoryTravel.
  ///
  /// In en, this message translates to:
  /// **'Travel'**
  String get categoryTravel;

  /// No description provided for @categoryFamily.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get categoryFamily;

  /// No description provided for @categoryPets.
  ///
  /// In en, this message translates to:
  /// **'Pets'**
  String get categoryPets;

  /// No description provided for @categoryInvestments.
  ///
  /// In en, this message translates to:
  /// **'Investments'**
  String get categoryInvestments;

  /// No description provided for @categoryUtilities.
  ///
  /// In en, this message translates to:
  /// **'Utilities'**
  String get categoryUtilities;

  /// No description provided for @categoryInsurance.
  ///
  /// In en, this message translates to:
  /// **'Insurance'**
  String get categoryInsurance;

  /// No description provided for @categorySubscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get categorySubscriptions;

  /// No description provided for @categoryDonations.
  ///
  /// In en, this message translates to:
  /// **'Donations'**
  String get categoryDonations;

  /// No description provided for @categoryPersonalCare.
  ///
  /// In en, this message translates to:
  /// **'Personal Care'**
  String get categoryPersonalCare;

  /// No description provided for @categorySupplierPayment.
  ///
  /// In en, this message translates to:
  /// **'Supplier Payment'**
  String get categorySupplierPayment;

  /// No description provided for @categorySalesRevenue.
  ///
  /// In en, this message translates to:
  /// **'Sales Revenue'**
  String get categorySalesRevenue;

  /// No description provided for @categoryCogs.
  ///
  /// In en, this message translates to:
  /// **'Cost of Goods Sold'**
  String get categoryCogs;

  /// No description provided for @categoryShippingFees.
  ///
  /// In en, this message translates to:
  /// **'Shipping Fees'**
  String get categoryShippingFees;

  /// No description provided for @categoryLoanReceived.
  ///
  /// In en, this message translates to:
  /// **'Loan Received'**
  String get categoryLoanReceived;

  /// No description provided for @categoryLoanRepayment.
  ///
  /// In en, this message translates to:
  /// **'Loan Repayment'**
  String get categoryLoanRepayment;

  /// No description provided for @categoryCapitalInjection.
  ///
  /// In en, this message translates to:
  /// **'Capital Injection'**
  String get categoryCapitalInjection;

  /// No description provided for @categoryOwnerWithdrawal.
  ///
  /// In en, this message translates to:
  /// **'Owner Withdrawal'**
  String get categoryOwnerWithdrawal;

  /// No description provided for @categoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOther;

  /// No description provided for @categoryUncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get categoryUncategorized;

  /// No description provided for @categoryTaxPayable.
  ///
  /// In en, this message translates to:
  /// **'Tax Payable'**
  String get categoryTaxPayable;

  /// No description provided for @preparingReport.
  ///
  /// In en, this message translates to:
  /// **'Preparing report…'**
  String get preparingReport;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline — changes will sync when back online'**
  String get offlineBanner;

  /// No description provided for @updateRequiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Update Required'**
  String get updateRequiredTitle;

  /// No description provided for @updateRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'A new version of Revvo is available. Please update to continue using the app.'**
  String get updateRequiredBody;

  /// No description provided for @updateNow.
  ///
  /// In en, this message translates to:
  /// **'Update Now'**
  String get updateNow;

  /// No description provided for @maintenanceTitle.
  ///
  /// In en, this message translates to:
  /// **'Under Maintenance'**
  String get maintenanceTitle;

  /// No description provided for @maintenanceBody.
  ///
  /// In en, this message translates to:
  /// **'Revvo is undergoing scheduled maintenance. We\'ll be back shortly.'**
  String get maintenanceBody;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @subscriptionSubscribeMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get subscriptionSubscribeMonthly;

  /// No description provided for @subscriptionSubscribeYearly.
  ///
  /// In en, this message translates to:
  /// **'Yearly — Save 20%'**
  String get subscriptionSubscribeYearly;

  /// No description provided for @subscriptionRestorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchases'**
  String get subscriptionRestorePurchases;

  /// No description provided for @payWithCard.
  ///
  /// In en, this message translates to:
  /// **'Pay with Local Card'**
  String get payWithCard;

  /// No description provided for @paymobProcessing.
  ///
  /// In en, this message translates to:
  /// **'Preparing checkout…'**
  String get paymobProcessing;

  /// No description provided for @paymobPaymentFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment failed. Please try again.'**
  String get paymobPaymentFailed;

  /// No description provided for @paymobManageBilling.
  ///
  /// In en, this message translates to:
  /// **'Manage Billing'**
  String get paymobManageBilling;

  /// No description provided for @subscriptionAutoRenewDisclosure.
  ///
  /// In en, this message translates to:
  /// **'Payment will be charged to your {platform} account at confirmation. Subscription automatically renews unless canceled at least 24 hours before the end of the current period. Manage subscriptions in your {platform} account settings.'**
  String subscriptionAutoRenewDisclosure(String platform);

  /// No description provided for @subscriptionTermsNotice.
  ///
  /// In en, this message translates to:
  /// **'By subscribing, you agree to our {terms} and {privacy}.'**
  String subscriptionTermsNotice(String terms, String privacy);

  /// No description provided for @manageAppleSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage in App Store'**
  String get manageAppleSubscription;

  /// No description provided for @manageGoogleSubscription.
  ///
  /// In en, this message translates to:
  /// **'Manage in Google Play'**
  String get manageGoogleSubscription;

  /// No description provided for @paymentMethodSavedCard.
  ///
  /// In en, this message translates to:
  /// **'Saved Card'**
  String get paymentMethodSavedCard;

  /// No description provided for @paymentMethodCardEnding.
  ///
  /// In en, this message translates to:
  /// **'{brand} ending in {last4}'**
  String paymentMethodCardEnding(String brand, String last4);

  /// No description provided for @autoRenewLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-Renew'**
  String get autoRenewLabel;

  /// No description provided for @autoRenewEnabled.
  ///
  /// In en, this message translates to:
  /// **'Your subscription will renew automatically.'**
  String get autoRenewEnabled;

  /// No description provided for @autoRenewDisabled.
  ///
  /// In en, this message translates to:
  /// **'Auto-renew is off. Renew manually before expiry.'**
  String get autoRenewDisabled;

  /// No description provided for @removeCard.
  ///
  /// In en, this message translates to:
  /// **'Remove Card'**
  String get removeCard;

  /// No description provided for @removeCardConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove Saved Card?'**
  String get removeCardConfirmTitle;

  /// No description provided for @removeCardConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will disable auto-renew and remove your saved payment method.'**
  String get removeCardConfirmMessage;

  /// No description provided for @removeCardSuccess.
  ///
  /// In en, this message translates to:
  /// **'Card removed successfully.'**
  String get removeCardSuccess;

  /// No description provided for @autoRenewToggleError.
  ///
  /// In en, this message translates to:
  /// **'Failed to update auto-renew. Please try again.'**
  String get autoRenewToggleError;

  /// No description provided for @removeCardError.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove card. Please try again.'**
  String get removeCardError;

  /// No description provided for @paymentSourcePaymob.
  ///
  /// In en, this message translates to:
  /// **'Card Payment'**
  String get paymentSourcePaymob;

  /// No description provided for @paymentSourceIap.
  ///
  /// In en, this message translates to:
  /// **'App Store / Google Play'**
  String get paymentSourceIap;

  /// No description provided for @noSavedPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'No saved payment method'**
  String get noSavedPaymentMethod;

  /// No description provided for @billingTitle.
  ///
  /// In en, this message translates to:
  /// **'Billing & Payments'**
  String get billingTitle;

  /// No description provided for @billingPaymentMethod.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT METHOD'**
  String get billingPaymentMethod;

  /// No description provided for @billingPaymentHistory.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT HISTORY'**
  String get billingPaymentHistory;

  /// No description provided for @billingPlanManagement.
  ///
  /// In en, this message translates to:
  /// **'PLAN MANAGEMENT'**
  String get billingPlanManagement;

  /// No description provided for @billingDangerZone.
  ///
  /// In en, this message translates to:
  /// **'SUBSCRIPTION'**
  String get billingDangerZone;

  /// No description provided for @billingUpdateCard.
  ///
  /// In en, this message translates to:
  /// **'Update Card'**
  String get billingUpdateCard;

  /// No description provided for @billingAddCard.
  ///
  /// In en, this message translates to:
  /// **'Add Payment Card'**
  String get billingAddCard;

  /// No description provided for @billingChangeToMonthly.
  ///
  /// In en, this message translates to:
  /// **'Switch to Monthly'**
  String get billingChangeToMonthly;

  /// No description provided for @billingChangeToYearly.
  ///
  /// In en, this message translates to:
  /// **'Switch to Yearly'**
  String get billingChangeToYearly;

  /// No description provided for @billingNoPayments.
  ///
  /// In en, this message translates to:
  /// **'No payment history yet'**
  String get billingNoPayments;

  /// No description provided for @billingRenewal.
  ///
  /// In en, this message translates to:
  /// **'Renewal'**
  String get billingRenewal;

  /// No description provided for @billingCancelSubscription.
  ///
  /// In en, this message translates to:
  /// **'Cancel Subscription'**
  String get billingCancelSubscription;

  /// No description provided for @billingCancelConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Cancel Subscription?'**
  String get billingCancelConfirmTitle;

  /// No description provided for @billingCancelConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You will be downgraded to Launch Mode. Your data will be preserved but you will lose access to Growth features.'**
  String get billingCancelConfirmMessage;

  /// No description provided for @billingCancelledSuccess.
  ///
  /// In en, this message translates to:
  /// **'Subscription cancelled. You are now on Launch Mode.'**
  String get billingCancelledSuccess;

  /// No description provided for @billingReceipt.
  ///
  /// In en, this message translates to:
  /// **'Payment Receipt'**
  String get billingReceipt;

  /// No description provided for @billingReceiptPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get billingReceiptPlan;

  /// No description provided for @billingReceiptAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get billingReceiptAmount;

  /// No description provided for @billingReceiptDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get billingReceiptDate;

  /// No description provided for @billingReceiptStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get billingReceiptStatus;

  /// No description provided for @billingReceiptType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get billingReceiptType;

  /// No description provided for @billingReceiptTxId.
  ///
  /// In en, this message translates to:
  /// **'Transaction ID'**
  String get billingReceiptTxId;

  /// No description provided for @billingReceiptSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successful'**
  String get billingReceiptSuccess;

  /// No description provided for @billingReceiptFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get billingReceiptFailed;

  /// No description provided for @billingShareReceipt.
  ///
  /// In en, this message translates to:
  /// **'Share Receipt'**
  String get billingShareReceipt;

  /// No description provided for @taxCollectedLabel.
  ///
  /// In en, this message translates to:
  /// **'TAX COLLECTED (LIABILITY)'**
  String get taxCollectedLabel;

  /// No description provided for @taxCollectedNote.
  ///
  /// In en, this message translates to:
  /// **'This is tax you collected on behalf of the government — it is not revenue.'**
  String get taxCollectedNote;
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

# Revvo — Complete Project Memory (for AI Agents)

> A deep, end-to-end reference for the **Revvo** application (codename `masari_app` / `revvo_app`).
> Written to be handed to another AI agent as durable memory. Covers product, architecture,
> data model, the **accounting math**, integrations, the codebase layout, and hard-won gotchas.
>
> Repo root: `/Users/mazen/Development/projects/masari_app`
> Pubspec name: `revvo_app` · version `1.0.0+10` · Firebase project: `massari-574ff`

---

## 1. What Revvo Is

Revvo is a **mobile-first bookkeeping & financial-reporting app for small e-commerce / retail
businesses** (primarily Egypt / COD market). It lets a merchant:

- Record **sales** (manual or auto-synced from **Shopify**).
- Track **inventory** with COGS valuation (FIFO / LIFO / Average).
- Auto-generate **double-entry-style transactions** from each sale (revenue, COGS, shipping).
- Track **expenses, suppliers, purchases, goods receipts, loans, salaries, fixed assets**.
- Produce **GAAP/IFRS-style reports**: Profit & Loss, Balance Sheet, Cash Flow.
- Integrate **Shopify** (orders, products, inventory, returns, refunds) and **Bosta** (shipping/COD courier).
- Sell **subscriptions** (Launch / Growth / Pro tiers) via **Paymob** (web) and **In-App Purchase** (iOS/Android).

It is a **3-part system**:

| Part | Tech | Location | Purpose |
|------|------|----------|---------|
| **Mobile app** | Flutter (Dart, SDK ^3.11) | `lib/` | The merchant-facing app |
| **Cloud Functions** | TypeScript (Node 24, Firebase Functions v2) | `functions/src/` | Server logic: Shopify/Bosta sync, webhooks, billing, admin |
| **Admin dashboard** | Next.js (TypeScript, React) | `admin/` | Internal ops: user management, revenue/subscription analytics |

Backend is **Firebase**: Firestore (DB), Auth, Cloud Functions, Cloud Messaging, Crashlytics,
Remote Config, Storage.

---

## 2. Tech Stack & Key Dependencies

**Flutter app** (`pubspec.yaml`):
- State management: **flutter_riverpod ^3.2** (AsyncNotifier pattern everywhere)
- Routing: **go_router ^17**
- Firebase: `firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions`,
  `firebase_crashlytics`, `firebase_messaging`, `firebase_remote_config`, `firebase_storage`
- Auth providers: `google_sign_in`, `sign_in_with_apple`
- Payments: `in_app_purchase ^3.2`, `webview_flutter` (Paymob checkout)
- Reports/export: `pdf`, `printing`, `share_plus`, `csv`, `fl_chart`
- Misc: `intl` (i18n EN/AR), `timezone`, `uuid`, `crypto`, `connectivity_plus`,
  `cached_network_image`, `image_picker`, `file_picker`

**Cloud Functions**: `firebase-functions` v2, `firebase-admin`, region **us-central1**,
`maxInstances: 10`. Runtime **nodejs24**. Build via `tsc` (`npm run build`).

**Admin**: Next.js + Tailwind (`admin/`), uses Firebase Admin SDK.

---

## 3. Repository Layout

```
masari_app/
├── lib/                          # Flutter app
│   ├── main.dart                 # entry; Firebase init, offline persistence (UNLIMITED cache)
│   ├── firebase_options.dart
│   ├── l10n/                     # generated localizations (EN ~2632 keys, AR ~2125)
│   ├── core/
│   │   ├── config/               # app config, env
│   │   ├── navigation/           # app_router.dart (go_router)
│   │   ├── providers/            # Riverpod providers (app_providers.dart, repository_providers.dart,
│   │   │                         #   app_settings_provider.dart)
│   │   ├── repositories/         # interfaces + firestore/ implementations
│   │   ├── services/             # shopify_api_service, shopify_sync_service, bosta_*; integration logic
│   │   ├── theme/                # theming
│   │   └── utils/                # stock_computation.dart (FIFO/LIFO/avg), pdf reshaper, connectivity
│   ├── shared/
│   │   ├── models/               # Sale, Transaction, Product, CategoryData, Supplier, Purchase,
│   │   │                         #   Loan, Salary, FixedAsset, BalanceSheetEntries, Shopify*, Bosta*
│   │   ├── utils/                # cf_engine.dart (closing cash), money_utils.dart (roundMoney),
│   │   │                         #   report_constants.dart (P&L/CF rules)
│   │   ├── dtos/ · widgets/
│   └── features/                 # one folder per feature area (see below)
│       ├── ai/  auth/  bosta/  cash_flow/  categories/  dashboard/  inventory/  manage/
│       ├── notifications/  onboarding/  profile/  reports/  sales/  setup/  shopify/
│       ├── splash/  suppliers/  transactions/
├── functions/                    # Cloud Functions (TS) + MANY one-off JS migration/diagnostic scripts
│   └── src/                      # the deployed TS source (see §10)
├── admin/                        # Next.js internal admin dashboard
├── android/ ios/ macos/ web/ linux/ windows/   # Flutter platform shells
├── firestore.rules · firestore.indexes.json · storage.rules · firebase.json
├── shopify.app.toml              # Shopify app config (OAuth scopes, webhooks)
└── test/                         # Dart unit tests (reports calculations, etc.)
```

> ⚠️ `functions/` root contains **hundreds of ad-hoc `.js` scripts** (migrations, diagnostics,
> reconciliations). These are NOT deployed — only `functions/src/*.ts` is. Scripts connect to
> live Firestore via a service-account key (see §11).

---

## 4. The Accounting Model (CORE — read carefully)

Revvo uses **accrual accounting**. Revenue & COGS are recognized **at the point of sale**,
regardless of payment status. Everything reduces to a single ledger: the **`transactions`**
collection. Reports are computed by summing signed transaction amounts with category-specific rules.

### 4.1 Sale → auto-generated transactions

When a sale is created (manual or Shopify), the app/CF writes 2–3 ledger transactions with
**deterministic IDs** so they can be upserted/reversed idempotently:

| Txn ID pattern | Category | Sign | Meaning |
|----------------|----------|------|---------|
| `sale_rev_{saleId}` | `cat_sales_revenue` | **+** | Net revenue = `subtotal − discount` |
| `sale_cogs_{saleId}` | `cat_cogs` | **−** | Cost of goods sold (negative = cost) |
| `sale_ship_{saleId}` | `cat_shipping` | **+** | Shipping charged to customer (revenue) |

All default to `exclude_from_pl: false` (pure accrual; recognized immediately).

### 4.2 The money math (Dart getters — `lib/shared/models/sale_model.dart`)

```
lineTotal      = roundMoney(quantity * unitPrice)
lineCogs       = roundMoney(quantity * costPrice)
subtotal       = Σ lineTotal                                   # before tax/discount/shipping
total          = roundMoney(subtotal + tax − discount + shippingCost)
netRevenue     = roundMoney(subtotal − discount)               # EXCLUDES tax & shipping (GAAP/IFRS)
totalCogs      = Σ lineCogs
grossProfit    = roundMoney(netRevenue − totalCogs)
outstanding    = clamp(total − amountPaid, 0, ∞)
```

- **Tax** is a collected **liability**, NOT revenue → excluded from `netRevenue`.
- **Shipping** is tracked **separately** as `cat_shipping` revenue (positive), NOT folded into `netRevenue`.
- `roundMoney()` (`lib/shared/utils/money_utils.dart`) = round to 2 decimals. Server mirror: `round2()`.

> **CRITICAL**: `sale.total`, `subtotal`, `netRevenue` are **Dart computed getters** — they are
> **NOT stored** in Firestore. Server-side code must recompute from `items[]`:
> `Σ(qty*unit_price) + tax_amount − discount_amount + shipping_cost`.
> Helpers: `computeSaleTotal()` (bosta-sync.ts), `_computeSaleTotalFromFirestore()` (BS screen).

### 4.3 Enums stored as NUMERIC in Firestore (NOT strings)

```
PaymentStatus:      0=unpaid  1=partial  2=paid  3=refunded
OrderStatus:        0=pending 1=confirmed 2=processing 3=completed 4=cancelled
FulfillmentStatus:  0=unfulfilled 1=partial 2=fulfilled
```
> `order_status === "cancelled"` will **NEVER** match — it's `=== 4`. Same for all enums.

### 4.4 Reversals (cancellations / refunds)

Original transactions are **never deleted** (historical accuracy). Instead:

- **Reversal txn**: `sale_rev_{saleId}_reversal` (negative), `sale_ship_{saleId}_reversal`,
  `sale_cogs_{saleId}_reversal` (positive, since COGS was negative).
- For a fully-cancelled order, the reversal makes the order **net to zero** in P&L.
- Reversal amount for revenue = `−max(0, origRev − refundedRev)` so that
  `rev + reversal + Σrefunds = 0`. (Idempotent recompute-from-full-set — see §9.4.)
- Reversals are **dated to `cancelled_at` / refund date**, NOT the original order date, so the
  "Return" lands in the correct reporting month (matches Shopify — see §9).

### 4.5 The `exclude_from_pl` flag

A transaction with `exclude_from_pl: true` is **tracked but omitted from P&L**. Uses:
- **Open RMA returns** (Shopify returns with no cash refund yet) — tracked, excluded until refunded.
- **Shopify/backfill refund duplicates** that would double-deduct already-net revenue.
- Historic: COGS/shipping on unpaid sales under a cash-basis variant.

### 4.6 Category system (`lib/shared/models/category_data.dart`)

- Categories have `id`, `isExpense`, color/icon, optional `budget_limit`.
- **System/auto categories** (locked, machine-generated): `cat_sales_revenue`, `cat_cogs`,
  `cat_shipping`, `cat_shipping_expense`, `cat_bosta_cashout`.
- **Financing/equity**: `cat_loan_received`, `cat_loan_repayment`, `cat_equity_injection`,
  `cat_owner_withdrawal`, `cat_tax_payable`, `cat_salary_payment`, `cat_asset_sale`.
- **Cash-flow classification** (`cashFlowTypeFor()`):
  - Investing: `cat_investments`, `cat_asset_sale`
  - Financing: `cat_loan_received`, `cat_loan_repayment`, `cat_equity_injection`,
    `cat_owner_withdrawal`, `cat_salary_payment`
  - Operating: everything else (default)

---

## 5. The Reporting Engines

### 5.1 Profit & Loss (`lib/features/reports/.../profit_loss_screen.dart`)

P&L is computed by iterating transactions in the period and applying **sign conventions**
that MUST stay consistent across: the main loop, the previous-period (delta) loop, the trend
chart, AND the drill-down sheet (`widgets/category_breakdown_sheet.dart`):

```
cat_sales_revenue → revenue   += tx.amount        # SIGNED. Revenue is NET (Shopify already
                                                  #   deducts refunds; reversals are negative)
cat_cogs          → cogs      += −tx.amount        # negative=cost, positive=reversal
cat_shipping      → otherIncome += tx.amount       # shipping revenue, signed
cat_refunds       → normal expense path (else)     # see note ↓
else, isIncome    → otherIncome += abs(amount)
else (expense)    → operatingExpenses += abs(amount)
```

- **`cat_refunds` is NOT contra-revenue.** Revenue is already net of refunds. Shopify/backfill
  refund rows are DUPLICATES → flagged `exclude_from_pl: true`. Manual refunds (no `#`/shopify/
  backfill markers) stay as legit P&L deductions. (Trying to treat `cat_refunds` as
  contra-revenue is WRONG and double-counts — already tested and reverted.)
- **Net income** = revenue + otherIncome − cogs − operatingExpenses.
- Performance: loads current period first (fast paint), fetches previous period + sales in the
  background, merges via `setState`; uses `int _loadGen` guard to drop stale results.

### 5.2 Balance Sheet (`lib/features/reports/.../balance_sheet_screen.dart`)

- **Cash & Bank** = **CF closing balance** (uses the shared CF engine — accounting identity).
- **Accounts Receivable (AR)** = sum of outstanding COD sales (start from COD sales → check
  shipments, NOT shipments → sales). AR cutoff date historically `2025-03-01`.
- **Equity** = Opening Capital (editable, stored in `balance_sheet_entries`) + Retained Earnings
  (computed from prior-period P&L) + Current-Period Net Income. Equation validated independently.

### 5.3 Cash Flow (`lib/features/cash_flow/...` + `lib/shared/utils/cf_engine.dart`)

- **Single source of truth**: `cf_engine.dart` → `computeClosingCash()`. Both the Cash Flow
  screen and Balance Sheet call it.
- **GAAP sections**: Operating / Investing / Financing activities (via `cashFlowTypeFor()`).
- Three cash-transaction predicates (different perspectives):
  - `isCashFlowTransaction()` (report_constants.dart) — standard: excludes `cat_cogs`, includes supplier_payment.
  - `isCfUserCashTransaction()` (cf_engine.dart) — CF user: also excludes Bosta shipping txns + positive sale-linked accrual.
  - `isNonCfUserCashTransaction()` — non-CF: excludes positive sale-linked accrual (replaced by `amountPaid`).

---

## 6. Firestore Data Model

**Auth-scoped**: nearly every collection is filtered by `user_id` (the Firebase Auth UID).

### Key collections

```
users/{uid}
  subscription_tier:    "launch" | "growth" | "pro"        # NOTE: free tier = "launch"
  subscription_status:  "free" | "active" | "expired" | "cancelled" | "grace_period" | "suspended"
  subscription_plan:    "growth_monthly" | "growth_yearly" | "pro_monthly" | "pro_yearly"
  subscription_expires_at: Timestamp
  payment_source:       "paymob" | "iap"
  paymob_subscription_id, paymob_card_last4, ...

sales/{saleId}
  id, user_id, customer_name/phone/email, date (Timestamp),
  items: [{ product_id?, variant_id?, variant_name?, product_name, quantity, unit_price,
            cost_price, shopify_line_item_id? }],
  tax_amount, discount_amount (PRODUCT-ONLY — see §9.5), shipping_cost,
  payment_method, payment_status (0-3), amount_paid,
  order_status (0-4), fulfillment_status (0-2),
  external_order_id, external_source ("shopify"), shopify_order_number, order_number (manual seq),
  shipping_address/method/notes, tracking_number, delivery_status,
  bosta_delivery_id, bosta_state, bosta_fees, bosta_fee_breakdown, bosta_synced_at,
  created_at, updated_at
  # subtotal/total/netRevenue are NOT stored (Dart getters)

transactions/{transactionId}
  id, user_id, title, amount (SIGNED: + income, − expense), date_time (Timestamp),
  category_id, note?, payment_method, supplier_id?, sale_id?,
  exclude_from_pl (bool), is_estimate (bool), is_reconciliation (bool),
  created_at, updated_at

products/{id}          # with variants[], cost layers (FIFO/LIFO), stock
categories/{id}        # user + system categories
suppliers/, purchases/, goods_receipts/, payments/, loans/, salaries/, fixed_assets/
balance_sheet_entries/ # opening_capital etc.

shopify_connections/{uid}
  shop_domain, scopes[], access_token (ENCRYPTED, CF-only — never sent to client),
  sync_orders_enabled, sync_inventory_enabled, inventory_sync_mode ("always"|"on_demand"),
  inventory_sync_direction, webhook_ids{topic→id}, import_from_date, shopify_location_id/name,
  status ("active"|"disconnected"|"error"), last_order_sync_at, last_inventory_sync_at
shopify_product_mappings/   # Shopify product/variant ↔ Revvo product/variant
shopify_sync_log/           # per-operation logs (purged > 90 days)
shopify_webhook_queue/      # inbound webhook buffer (purged > 30 days)

bosta_connections/, bosta_shipment_mappings/, bosta_sync_log/
paymob_config/subscription_plans   # plan IDs
payment_logs/, payment_history/
```

### Indexes & queries
- Sales: `where(user_id ==).orderBy(date desc)`; range adds `date >=/<=`.
- **Keyset (cursor) pagination**, 20/page, via `startAfterDocument()`. Reports call `loadAll()`.
- **Cache-first reads**: range reads hit `Source.cache` first (instant), then background
  `Source.server` refresh. `forceServer: true` only on pull-to-refresh.
- Firestore **offline persistence** enabled (`cacheSizeBytes: UNLIMITED`).

### Write patterns
- Sale + its txns + stock written **atomically** (`runTransaction` online; `batch` offline,
  15s timeout fallback). Batch cap 250 (Firestore limit 500).
- **Optimistic UI**: Riverpod notifier updates state synchronously before the await; screens
  fire-and-forget the write (`ref.keepAlive()` keeps the bg write alive after dispose);
  rollback on failure.

---

## 7. App Feature Areas (`lib/features/`)

| Folder | What it does |
|--------|--------------|
| `auth/` | Email/Google/Apple sign-in |
| `onboarding/` `setup/` `splash/` | First-run, account setup, splash |
| `dashboard/` | Home metrics + `analytics_chart.dart` (Gross/Discounts/Returns/Net breakdown) |
| `sales/` | Sales list, record sale, sale detail (cancellation/reversal logic) |
| `inventory/` | Products, variants, stock, COGS valuation |
| `transactions/` | Ledger list, add/edit txn, filters |
| `reports/` | P&L, Balance Sheet, PDF export (`report_service.dart`) |
| `cash_flow/` | GAAP cash-flow screen (uses cf_engine) |
| `categories/` | Category management |
| `suppliers/` | Suppliers, purchases, goods receipts, payments |
| `shopify/` | 6 screens: Connect, Setup Wizard (5-step), Product Mapping, Import, Inventory Sync, Sync History |
| `bosta/` | Bosta courier connection + shipment tracking |
| `profile/` | Subscriptions, billing (Paymob checkout sheet, IAP), settings |
| `manage/` | Manage hub (integrations, etc.) |
| `notifications/` | FCM notifications |
| `ai/` | AI assistant features |

### State management
- Riverpod **AsyncNotifier** per domain (e.g. `SalesNotifier extends AsyncNotifier<List<Sale>>`
  in `app_providers.dart`). Methods: `build/loadMore/loadAll/refresh/refreshAll/addSale/
  addSaleAtomic/updateSale/removeSale`. `ref.keepAlive()` survives tab switches.
- Subscription tier read **once** on load into SharedPreferences (no realtime listener); refresh
  via `getSubscriptionStatus` CF on demand. **Admin tier changes aren't visible until app reopen/refresh.**

---

## 8. Dashboard "Sales" breakdown (what the merchant sees)

`lib/features/dashboard/widgets/analytics_chart.dart` renders a 4-line breakdown:

```
Gross Sales = Σ sale.subtotal                       (line items × price, before discounts)
Discounts   = Σ sale.discount_amount                (PRODUCT-only — see §9.5)
Returns     = Σ |negative cat_sales_revenue txns|   (refund + reversal txns), by txn date
Net Sales   = Gross − Discounts − Returns
```

- The **P&L "Revenue"** number is transaction-based (signed Σ `cat_sales_revenue` + `cat_shipping`)
  and ALWAYS matches Shopify to the penny. The **dashboard "Sales"** metric is also now
  transaction-based (a past bug had it sale-doc based and over-counting cancelled orders by ~89K/month — fixed).
- Returns **includes `*_reversal` txns** so fully-cancelled orders are removed from Net.

---

## 9. Shopify Integration (the most complex/important area)

### 9.1 Architecture
- Client → all Shopify API calls go through the **`shopifyProxy`** Cloud Function (token never
  leaves the server). Access token is **AES-256-GCM encrypted** in `shopify_connections/{uid}.access_token`.
- API version **2024-01**. OAuth scopes + webhook topics in `shopify.app.toml` and `shopify-auth.ts`.
- Scopes include `read_orders`, `write_orders`, `read_products`, `read_inventory`, `read_returns`.
- **Webhooks** → `storeWebhook` buffers into `shopify_webhook_queue` → `processShopifyWebhook`
  routes by topic to handlers in `shopify-processor.ts`.

### 9.2 Order lifecycle → ledger
- **orders/create** → builds a Sale doc + `sale_rev`/`sale_cogs`/`sale_ship` txns
  (`handleOrderCreated`, ~line 600 of shopify-processor.ts).
- **orders/updated** → `handleOrderUpdated`: diff line items + financials (`financialsChanged`),
  self-heals stale discount/tax/shipping. If `order_status === 4` (cancelled), calls
  `processRefundsOnCancelledOrder`.
- **orders/cancelled** → `handleOrderCancelled`: creates revenue/shipping reversals dated to
  `cancelled_at`, reducing by any already-recorded refunds.
- **refunds/create** → creates `sale_refund_{saleId}_{refundId}` (negative `cat_sales_revenue`)
  + `sale_ship_refund_{saleId}_{refundId}`, dated to `refund.created_at`.
- **returns/** (RMA) → `handleReturnEvent`: upserts `sale_return_{saleId}_{returnId}` (negative),
  **`exclude_from_pl: true`** (open returns excluded from P&L until a cash refund issues);
  self-deletes when fully refunded or cancelled/declined.

### 9.3 Revenue = NET; refunds attributed to refund month
- Shopify "Net Sales" = `Gross − Discounts − Returns`, with **returns attributed to the refund's
  created month** (Cairo timezone `Africa/Cairo` for month bucketing). Revvo mirrors this:
  reversals/refunds are dated to the refund/cancel date, not the original order date.

### 9.4 The cancel+refund double-count fix (idempotent recompute)
- A cancelled+refunded order historically created BOTH a `_reversal` AND a `sale_refund`, each
  deducting revenue → double-count. **Fix** (`processRefundsOnCancelledOrder`, now deployed):
  recompute the reversal from the **full** refund set every webhook:
  `reversal.amount = −max(0, round2(origRev − Σ refundedRev))`, set to 0 if target is 0.
  Idempotent → can't double-deduct regardless of event order. Same pattern for shipping.

### 9.5 Discounts are PRODUCT-ONLY (free-shipping gotcha)
- Shopify `order.total_discounts` **INCLUDES free-shipping (shipping_line) discounts** (e.g. an
  automatic "Enjoy free delivery on orders over 1500 EGP!" 100%-off shipping → 95/99 EGP).
- Shopify's **displayed "Discounts" line EXCLUDES shipping discounts** (they reduce the Shipping line).
- Therefore Revvo stores **product-only** discount:
  `discount_amount = total_discounts − Σ(shipping_line.price − shipping_line.discounted_price)`.
  Implemented in `shopify-processor.ts` (create ~L637, update ~L1219) and
  `shopify_sync_service.dart` (~L1722). The update path self-heals stale values.
- **`line_items[].total_discount` is ALWAYS 0 in API 2024-01** — do NOT use it. Order-level
  discount codes live in `order.total_discounts` and `discount_applications[]`.

### 9.6 Bulk import & products
- `shopify_sync_service.dart importOrders(from,to)`: max 3-month window, dedup by
  `external_order_id`, pre-fetches variant/product costs for COGS.
- Background "always" sync timer (30s) keeps product details + (optionally) inventory in sync.
- Inventory: pull (Shopify→Revvo) / push (Revvo→Shopify) with delta preview/confirm.

### 9.7 Reconciliation methodology (how to verify Revvo == Shopify)
- Compare per Cairo-month: **Gross** = `Σ li.price×qty` (orders created in month); **Discounts**
  = product-only; **Returns** = `Σ refund_line_items.subtotal` where `cairoMonth(refund.created_at)==month`,
  PLUS reversals; compare to Revvo negative `cat_sales_revenue` txns.
- Live Shopify numbers **grow intraday** as refunds post — always re-fetch before comparing.
- Reference reconciliation user (test): `EGYQnP7ughdUtTbn04UwUET534i1`.

---

## 10. Bosta Integration (COD courier / shipping expense)

- `bosta-proxy.ts` (API proxy) + `bosta-sync.ts` (sync, scheduled daily, cashouts).
- Shipping **expense** booked under `cat_shipping_expense` as daily estimates
  ("Bosta Shipping (Est.)") + `is_reconciliation` true-ups to actual invoices.
- Bosta API base `https://app.bosta.co/api/v2`, auth header `Authorization: <api_key>` (no Bearer).
- **Pagination quirk**: use `page` (1-indexed) + `perPage` (ignored, always 50). `pageNumber`/
  `pageLimit` are silently ignored. Results newest-first by `createdAt`.
- **Date filtering does NOT work server-side** — must filter client-side on `createdAt` + stop early.
- State filter works with **strings** (`state:['Delivered']`), not numeric codes.
- `businessReference` format `bd3cf0-3:#1319625` → order number after `:#`.

---

## 11. Cloud Functions Catalog (`functions/src/`, exported in `index.ts`)

**Shopify**: `shopifyAuthStart`, `storeAuthCallback` (OAuth), `storeWebhook`,
`processShopifyWebhook`, `backfillFulfillmentStatus`, `refreshShopifyOrder`,
`refreshAllShopifyOrders`, `reconcileShopifyOrders`, `backfillShopifyRefunds`,
`shopifyProxy`, `shopifyHealthCheck`, `shopifyDisconnect`, `shopifyEmbed`.

**Bosta**: `bostaProxy`, `syncBostaShipments`, `scheduledBostaSyncDaily`, `connectBosta`,
`disconnectBosta`, `migrateBostaToDaily`, `connectBostaDashboard`, `syncBostaCashouts`.

**Billing/Subscriptions**: `paymobWebhook`, `validateSubscriptions`, `getSubscriptionStatus`,
`cancelSubscription`, `sendPreExpiryReminders`, `toggleAutoRenew`, `removePaymentMethod`,
`getPaymentHistory`, `createPaymentIntent`, `setupSubscriptionPlans`, `getPaymobSubscription`,
`suspendSubscription`, `resumeSubscription`, `cancelPaymobSubscription`, `verifyIapReceipt`.

**Admin/Analytics**: `adminListUsers`, `adminUpdateUser`, `adminGetUser`, `adminResetPassword`,
`adminDisableUser`, `getRevenueMetrics`, `getSubscriptionMetrics`, `computeDailyMetrics`.

**Triggers/Scheduled**: `onSaleCreated` (FCM new-sale notification; skips Shopify sales),
`onSupplierDeleted` (cascade-delete purchases/payments/goods receipts/tagged txns),
`processRecurringTransactions` (daily), `purgeExpiredShopifyData` (daily retention cleanup),
`deleteUserData` (GDPR account deletion).

**Deploy**: `cd functions && firebase deploy --only functions`. Predeploy runs `tsc`.
> Transient `Internal error` at the secretmanager service-identity step can occur; a `--debug`
> run usually pushes through, then a clean deploy shows "No changes detected".

### Running ad-hoc scripts (non-deployed)
- Live Firestore via service-account key:
  `/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json`.
- Run from inside `functions/` (the terminal cwd sometimes resets to repo root → `MODULE_NOT_FOUND`;
  always `cd functions` first).
- Shopify token decrypt key (AES-256-GCM, hex): `9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332`.
- DNS to `firestore.googleapis.com` can intermittently fail; retry.

---

## 12. Subscriptions & Billing

- **Tiers**: `launch` (free), `growth`, `pro`. Shopify + advanced features gated to **Growth+**
  (`hasShopifyAccessProvider`).
- **Web/Android payments**: **Paymob**. Plans: `growth_monthly` (249 EGP/30d, id 9003),
  `growth_yearly` (2390 EGP/360d, id 9004); integration 4624125 (VPC/3DS). Plan IDs in
  `paymob_config/subscription_plans`.
- **iOS/Android store**: `in_app_purchase` → `verifyIapReceipt` CF.
- Flow: `createPaymentIntent` → WebView checkout → redirect `?success=true` → app polls
  `getSubscriptionStatus` (5×, 2s) while `paymobWebhook` updates the user doc.
- **Paymob HMAC gotcha (FIXED Apr 2026)**: Intention API v1 HMAC didn't match any documented
  formula. Fix: (1) card/subscription callbacks verified by matching `transaction_id` to
  `payment_logs`; (2) HMAC cascade (Python-bool → JS-bool → raw SHA-512); (3) **API verification
  fallback** via legacy `POST /api/auth/tokens` → `GET /api/acceptance/transactions/{id}`
  (uses `PAYMOB_API_KEY` secret). Empty `merchant_order_id` 3DS callbacks return 200.
- `getSubscriptionStatus` actively **downgrades** to `launch`/`expired` if `subscription_expires_at`
  is past — watch for timezone bugs causing premature downgrade.

---

## 13. Localization, Theming, Platforms

- **i18n**: EN (~2632 keys) + AR (~2125 keys) via `flutter_localizations` + generated `l10n/`.
  Arabic needs RTL + a PDF reshaper (`arabic_pdf_reshaper.dart`) for report exports.
- Currency formatting via `intl` `NumberFormat`; respect locale.
- Platforms: Android, iOS, macOS, Web, Linux, Windows shells present (primary: mobile).

---

## 14. Hard-Won Gotchas & Lessons (DO NOT relearn the hard way)

1. **`sale.total/subtotal/netRevenue` are computed getters, NOT stored.** Recompute server-side.
2. **Enums are numeric in Firestore** (`order_status === 4`, not `"cancelled"`).
3. **Revenue is NET.** Don't treat `cat_refunds` as contra-revenue — double-counts.
4. **Discounts must be product-only** (exclude free-shipping `shipping_line` discounts);
   `line_items[].total_discount` is always 0 in API 2024-01.
5. **Reversals/refunds dated to refund/cancel date** (Cairo TZ) so Returns land in the right month.
6. **Idempotent recompute** for cancel+refund reversals — never incrementally subtract only "new" refunds.
7. **Never create a refund txn for an order with no recorded revenue** (`origRev=0`) — it becomes
   a phantom net-new deduction. Guard migrations with `hasRecordedRevenue`. (A past backfill
   created 46 phantom refunds, −27,801.40, on no-revenue cancelled "skeleton" sale docs — had to delete.)
8. **Today is a live operating day** — webhooks create COGS/Bosta/manual txns continuously, so
   `created_at == today` can NOT isolate a migration's writes.
9. **Always dry-run migrations** (`--apply` flag pattern); scope with `created_at_min`; verify with
   reconciliation scripts after.
10. **`read_returns` scope** is required to receive RMA returns; without it Revvo under-counts
    returns; with it, open returns (no cash refund) must be `exclude_from_pl: true` to match Shopify Net Sales.
11. **Bosta**: `page`/`perPage` pagination, no server date filter, string state filters.
12. **Subscription tier is cached** in SharedPreferences — admin changes need an app refresh.
13. **NEVER run generic regexes/scripts across the whole Dart codebase** — a past `fix_quotes.py`
    caused 10,043 errors. Commit before experiments.
14. **Optimistic writes**: don't `await` the repo write before popping a screen; let the notifier
    update state synchronously and write in the background (`ref.keepAlive()`).
15. **CF Engine is the single source of truth** for closing cash — Balance Sheet "Cash & Bank"
    must equal CF closing balance.

---

## 15. Verified Reference State (reconciliation, as of 2026-06)

For test user `EGYQnP7ughdUtTbn04UwUET534i1`, **June 2026 fully reconciles with Shopify**:

| Line | Value | Match |
|------|-------|-------|
| Gross | 473,365 | ✓ |
| Discounts | 13,470.15 | gap 0 ✓ (product-only) |
| Returns | 108,196.70 | gap 0 ✓ (open returns excluded from P&L) |
| Net | 351,698.15 | ✓ |

All cancelled orders net to zero; 0 inconsistent orders. The returns + discount fixes are
**deployed** and self-healing on every future webhook.

---

*End of Revvo project memory. Keep this in sync as the codebase evolves — especially the
accounting sign conventions (§4, §5) and Shopify methodology (§9), which are the easiest to break.*

# Prompt: Reorganize Bookkeeping Transactions for Revvo Import

You are an expert accountant + data engineer. I will give you raw transaction
exports (10,000+ rows) from a small e-commerce business operating in **Egypt
(currency: EGP)**. The data was entered casually and is NOT in correct
double-entry / GAAP-aligned bookkeeping order. Your job is to **clean,
classify, and re-organize every transaction** into a strict output schema that
maps directly onto how the "Revvo" accounting app stores data, so it can be
imported and produce correct **Profit & Loss, Balance Sheet, and Cash Flow**
statements for the period **1 Jan 2026 → today**.

Read this entire spec before producing output.

---

## 1. How Revvo stores a transaction

Every transaction is a single row with these fields:

| Field | Meaning |
|---|---|
| `date` | ISO date `YYYY-MM-DD` (and time if known, else 12:00). |
| `title` | Short English description. NEVER Arabic. Translate/transliterate. |
| `amount` | **Single SIGNED number in EGP.** Negative = money OUT (expense / payment). Positive = money IN (income / receipt). There is no separate debit/credit column. |
| `category_id` | One ID from the canonical list in §3. This drives all 3 statements. |
| `payment_method` | One of: `Cash`, `Card`, `Bank`, `Wallet`. |
| `note` | Optional extra context (original Arabic text can go here). |
| `supplier_name` | Required ONLY for `cat_supplier_payment`. The vendor being paid. |
| `exclude_from_pl` | `true`/`false`. Usually derive from category (see §4). Default `false`. |

### Sign rules (critical)
- A purchase, bill, salary, ad spend, refund-to-customer, supplier payment,
  loan repayment, owner drawing → **negative**.
- A sale, other income, loan received, capital injection, asset sale → **positive**.
- Do NOT use absolute values. The sign IS the accounting direction.

---

## 2. The three statements (so you classify correctly)

Revvo derives all three from the category + sign + flags:

- **Profit & Loss (P&L):** Includes only *operating* income and expenses.
  EXCLUDES financing/investing categories (loans, owner equity, capital,
  investments, asset sale, supplier payments, and salary *payments*) — see §4.
- **Balance Sheet:** Driven by cumulative cash, payables, equity, assets.
  Financing/investing movements live here, not in P&L.
- **Cash Flow:** Real cash movements only. `cat_cogs` is a **non-cash accrual**
  entry and is excluded from cash flow. `cat_supplier_payment` IS a real cash
  outflow even though it's excluded from P&L.

You don't compute the statements — you just assign the correct `category_id`,
sign, and flags so Revvo computes them correctly.

---

## 3. Canonical category list (USE THESE IDs)

Prefer these built-in IDs. Only invent a custom one (see §5) if nothing fits.

### Income / Revenue (positive amounts)
| `category_id` | Use for |
|---|---|
| `cat_sales_revenue` | Revenue from a sale (manual / non-Shopify). *(Shopify orders are auto-generated — see §6.)* |
| `cat_shipping` | Shipping fees CHARGED to customers (revenue). |
| `cat_income` | Generic other operating income. |
| `cat_bosta_cashout` | Cash collected/released by Bosta courier (COD payouts). |

### Cost of Goods Sold
| `category_id` | Use for |
|---|---|
| `cat_cogs` | Cost of inventory sold. Non-cash accrual. Negative. |

### Operating Expenses (negative amounts — these hit P&L)
| `category_id` | Use for |
|---|---|
| `cat_shipping_expense` | Shipping/courier fees the business PAYS. |
| `cat_salary_expense` | Salary/wages EXPENSE (the cost incurred). |
| `cat_utilities` | Electricity, water, internet, phone, mobile recharge. |
| `cat_bills` | General bills. |
| `cat_subscriptions` | SaaS, software, recurring tools. |
| `cat_transport` | Uber, taxi, fuel, local transport. |
| `cat_food` | Food & dining, team meals, food allowance. |
| `cat_health` | Medical/health. |
| `cat_insurance` | Insurance premiums. |
| `cat_education` | Training, courses. |
| `cat_personal_care` | Personal care. |
| `cat_donations` | Donations / charity. |
| `cat_tax_payable` | Taxes. |
| `cat_other` | Use sparingly when truly nothing else fits. |

### Marketing/ads, packaging, office, rent, maintenance
These are **not built-in** but are common. Map to a custom category (see §5)
with a clean English name, e.g. `Marketing & Ads`, `Product Packaging`,
`Office Supplies`, `Rent`, `Maintenance & Repairs`, `Refunds`.

### Financing & Investing (EXCLUDED from P&L)
| `category_id` | Use for | Sign |
|---|---|---|
| `cat_supplier_payment` | Paying a supplier/vendor (settles payables). Needs `supplier_name`. | negative |
| `cat_loan_received` | Business RECEIVED a loan. | positive |
| `cat_loan_repayment` | Business REPAID a loan. | negative |
| `cat_equity_injection` | Owner put capital INTO the business. | positive |
| `cat_owner_withdrawal` | Owner took money OUT (drawings). | negative |
| `cat_salary_payment` | Actual CASH paid for salaries *(separate from `cat_salary_expense` accrual)*. | negative |
| `cat_investments` | Money invested OUT (buying investments/assets). | negative |
| `cat_asset_sale` | Proceeds from selling a fixed asset. | positive |
| `cat_employee_advance` | Advance / loan given TO an employee (سلفة). | negative |

### Fixed-asset & depreciation (investing / non-cash)
| `category_id` | Use for |
|---|---|
| `cat_depreciation` | Depreciation expense (non-cash). |
| `cat_asset_disposal` | Loss/entry on disposing an asset. |
| `cat_impairment_loss` | Asset impairment. |

---

## 4. Which categories are EXCLUDED from P&L

Set `exclude_from_pl = true` (or trust the category) for these — they are
balance-sheet / financing / investing movements, NOT operating P&L:

```
cat_investments, cat_loan_received, cat_loan_repayment,
cat_equity_injection, cat_owner_withdrawal, cat_salary_payment, cat_asset_sale
```

`cat_supplier_payment` is also excluded from P&L but IS a real cash outflow —
leave `exclude_from_pl = false` for it (Revvo handles it specially). Everything
else with a normal operating category stays in P&L (`exclude_from_pl = false`).

### Salary: expense vs payment (avoid double counting)
- If a row represents the **cost/obligation** of salary → `cat_salary_expense`.
- If it represents the **actual cash handed over** → `cat_salary_payment`.
- Do NOT tag the same money as both. If the business only records the cash
  payout (most common for this small business), use `cat_salary_expense` so it
  appears as an operating expense in P&L, UNLESS you can clearly see an accrual
  was already booked separately.
- When unsure, default salary/wage payouts to `cat_salary_expense`.

---

## 5. Custom categories

When no built-in fits (ads, packaging, rent, refunds, etc.):
- Provide a `category_id` of the form `cat_<clean_snake_case_english>` AND a
  `category_name` in **English** (Title Case).
- Reuse the SAME id/name for all rows of that type (be consistent — don't
  create `Marketing`, `marketing`, and `Ads` as three categories).
- Never use Arabic in `category_id` or `category_name`. Translate it.

Recommended custom categories for this business (reuse exactly):
`Marketing & Ads`, `Product Packaging`, `Office Supplies`, `Rent`,
`Maintenance & Repairs`, `Refunds`.

---

## 6. Shopify-generated entries — flag, don't assume

Revvo AUTO-generates these from Shopify orders, with IDs/titles like:
`COGS - #19953 — Shopify`, `#19951 — Shopify`, `Bosta Shipping (Est.) — …`.

The manual export **may or may not overlap** with Shopify-synced orders already
in Revvo (status: uncertain). So do NOT silently delete possible sales. Instead:

- If a row is **clearly** an auto-generated Shopify/Bosta sale, COGS, or
  shipping accrual (e.g. title contains `— Shopify`, `#<orderno>`, `Bosta
  Shipping`) → `action = skip`.
- If a row **looks like a sale/revenue but you're not sure** it's a Shopify
  duplicate → `action = review` (do NOT import yet; I will de-duplicate it
  against Revvo's existing data myself).
- Everything else (cash expenses, supplier payments, salaries, owner/loan
  movements, clearly-manual offline sales) → `action = import`.
- Whenever a row references an order number or external id, put it in
  `source_ref` so I can match and de-duplicate precisely.

Report in the summary how many rows are `skip`, `review`, and `import`.

---

## 7. Data cleaning rules

1. Translate/transliterate all Arabic titles to concise English. Keep the
   original Arabic in `note` if useful.
2. Normalize obvious duplicates of the same category name to one.
3. Fix signs: anything that is a cost/payment must be negative; receipts positive.
4. Parse dates to `YYYY-MM-DD`. Egypt is UTC+2/+3 — keep the calendar date as
   shown in my export.
5. Default `payment_method` to `Cash` when unknown (this business is mostly cash).
6. Map vendor/people names: a payment to a known supplier → `cat_supplier_payment`
   + `supplier_name`. A wage to staff → salary category. A “loan to <person>”
   that is staff → `cat_employee_advance`.
7. Flag anything genuinely ambiguous instead of guessing — see `confidence`.

---

## 8. REQUIRED OUTPUT — Part A: Transactions CSV

Return a single **CSV** (UTF-8) with EXACTLY these columns, in this order:

```
date,title,amount,category_id,category_name,payment_method,supplier_name,exclude_from_pl,note,source_ref,confidence,action
```

- `category_name`: only needed for custom categories (else leave blank).
- `supplier_name`: only for `cat_supplier_payment` (else blank).
- `exclude_from_pl`: `true`/`false`.
- `source_ref`: order number / external id if the row references one (else blank).
- `confidence`: `high` / `medium` / `low`.
- `action`: `import` / `review` / `skip`. Include ALL rows so I can audit.

## 9. REQUIRED OUTPUT — Part B: Opening balances

The data starts **1 Jan 2026**. The two earliest sheets (1 Jan → 9 Apr) plus
any context let you estimate the financial position at the START of the year.
Produce a small second CSV of opening balances as of `2026-01-01`:

```
account,amount,note
```

With one row for each of (use 0 if genuinely unknown, and say so):
- `opening_cash` — cash on hand at 1 Jan 2026
- `opening_bank` — bank balance at 1 Jan 2026
- `opening_inventory` — value of stock on hand
- `opening_accounts_payable` — total owed to suppliers
- `opening_accounts_receivable` — total owed by customers / courier
- `opening_fixed_assets` — net book value of equipment/assets
- `opening_owner_capital` — owner's capital invested to date
- `opening_loans_payable` — outstanding loans owed

These must follow the accounting identity: **Assets = Liabilities + Equity**.
If they don't balance, put the difference in `opening_owner_capital` and note it.

## 10. REQUIRED OUTPUT — Part C: Summary

After both CSVs, add a short **summary block**:
- total rows in, rows `import` / `review` / `skip` (and why),
- list of every distinct `category_id` used with a one-line definition,
- list of every custom category created (id + English name),
- every `low`-confidence or `review` row and why,
- how you derived each opening balance.

Process the FULL dataset — do not truncate or sample. If it's too large for one
message, output in clearly labeled parts (Part 1/N) covering all rows.

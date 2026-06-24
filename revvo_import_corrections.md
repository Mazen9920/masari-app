# Correction Pass: Fix the Revvo Import CSV

You previously produced `revvo_transactions.csv` and `revvo_opening_balances.csv`
from my bookkeeping data. They are a good first draft but have errors that would
make my financial statements wrong. Re-output BOTH CSVs with the fixes below.
Keep the exact same column schemas as before.

Context I've now confirmed about what's ALREADY in my Revvo app (do not
re-create these — they would double-count):

- **Accrual Sales Revenue + COGS already exist in Revvo, densely, from
  2026-02-23 through today.** Revvo is MISSING them only for **2026-01-01 →
  2026-02-22**.
- **My manual ledger** (expenses, supplier payments, salaries, ads, owner/loan
  movements) **already exists in Revvo from 2026-04-01 onward.** Revvo is MISSING
  it only for **2026-01-01 → 2026-03-31** (plus the first few days of April).

## FIX 1 — Stop double-counting revenue (most important)

The file books revenue twice: once as accrual `cat_sales_revenue` per Shopify
order, and again as `cat_income` "Cash Income" from Bosta / Paymob / etc.

Keep BOTH rows, but the "Cash Income" lines are **cash collected against
receivables, NOT income**. For every "Cash Income" row:
- Set `category_id = cat_bosta_cashout`
- Set `exclude_from_pl = true`  ← critical: keeps them out of the P&L
- Keep the amount positive (it's a real cash inflow for the cash-flow statement)
- Keep the payer (Bosta / Paymob / etc.) in `note`

This way revenue is counted once (accrual), and the cash receipts still show on
the balance sheet / cash flow without inflating profit.

## FIX 2 — Set the `action` column by date, so nothing duplicates

For **Shopify sale + COGS rows** (`cat_sales_revenue`, `cat_cogs`, and any
`cat_shipping` revenue tied to an order):
- date **2026-01-01 → 2026-02-22** → `action = import`
- date **2026-02-23 → today** → `action = skip`  (already in Revvo)

For **manual ledger rows** (everything else — rent, ads, salaries, supplier
payments, owner/loan, utilities, refunds, suspense, Cash Income, etc.):
- date **2026-01-01 → 2026-03-31** → `action = import`
- date **2026-04-01 → today** → `action = skip`  (already in Revvo)

Still output every row (including `skip`) so I can audit.

## FIX 3 — Reuse my EXISTING category IDs (don't fragment)

My Revvo account already has these custom categories. Map to them EXACTLY
instead of inventing new ones:

| If the expense is… | Use this exact `category_id` | `category_name` |
|---|---|---|
| Paid ads (Meta, TikTok), content production, influencer/affiliate, promotions | `cat_marketing` | Marketing |
| Product packaging | `cat_product_packaging` | product packaging |
| Office supplies / office furniture / Amazon office items | `cat_office_furniture` | office furniture |
| Rent | `cat_rent` | Rent |
| Maintenance & repairs | `cat_maintenance` | Maintenance & Repairs |
| Refunds / defects / customer returns | `cat_refunds` | refunds |
| Food allowance / team meals | `cat_food_allowance` | food allowance |
| Internet, phone, utilities, mobile recharge | `cat_utilities` | Utilities & Communications |
| SaaS / software subscriptions / bank fees / Shopify sub | `cat_subscriptions` | (built-in) |
| Transport / Uber / fuel | `cat_transport` | (built-in) |
| Salary / wages (expense) | `cat_salary_expense` | (built-in) |
| Advance / loan given to a worker (سلفة) | `cat_employee_advance` | (built-in) |
| R&D / samples / product testing | `cat_other` | Research & Development |

For built-in IDs (right column says "(built-in)") leave `category_name` blank.
When you must create a brand-new custom category, use
`category_id = cat_<clean_english_snake_case>` and an English `category_name` —
never Arabic, never an existing built-in id.

## FIX 4 — Supplier purchases stay OUT of P&L (keep as you did)

You correctly mapped raw-material / manufacturing / product purchases (Hassan,
Hanna, Khaled, Hisham, Haytham, George, etc.) to `cat_supplier_payment` with a
`supplier_name`. Keep that — those are inventory purchases (balance-sheet), and
the per-order `cat_cogs` accruals handle the P&L cost. Do NOT also book them as
expenses.

## FIX 5 — Specific re-maps

- "Loss on Disposal of Assets" → `category_id = cat_asset_disposal` (NOT refunds).
- "Suspense – Unclassified Outflows" → keep `category_id = cat_other`,
  `exclude_from_pl = false`, `confidence = low`. (I'll reclassify later.)

## FIX 6 — Opening balances: keep, with one note

Keep `revvo_opening_balances.csv` as-is, but in the summary explain the
`opening_owner_capital` plug (the +15,117 forced to balance) so I can confirm or
correct it. Everything else (inventory 277,707, AR 3,816, loans 197,500) stays.

## Output

Re-emit both CSVs with the same columns as before:
`date,title,amount,category_id,category_name,payment_method,supplier_name,exclude_from_pl,note,source_ref,confidence,action`
and `account,amount,note`.

Then a short summary: counts of `import` vs `skip` (split into Shopify-sales vs
manual), every category_id used, every Cash-Income row reclassified, and the
opening-capital plug explanation. Process the FULL dataset, no truncation.

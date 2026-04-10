#!/usr/bin/env node
/**
 * diagnose_gap.js — Shopify ↔ Revvo diagnostic comparison
 *
 * Compares Shopify's order-level financials with Firestore transactions
 * for a given date range to identify the exact source of revenue gaps.
 *
 * Usage:
 *   ENCRYPTION_KEY=<hex> node functions/diagnose_gap.js [period]
 *
 *   period: "l7d" (default), "mtd", "yesterday", "today"
 *   ENCRYPTION_KEY: the SHOPIFY_TOKEN_ENCRYPTION_KEY hex string
 *
 * If ENCRYPTION_KEY is not set, the script will try to read it from
 * GCP Secret Manager via `firebase functions:secrets:access`.
 */

process.env.GOOGLE_APPLICATION_CREDENTIALS =
  "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json";

const admin = require("firebase-admin");
const crypto = require("crypto");

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const SHOPIFY_API_VERSION = "2024-01";

// ── Crypto helpers (mirror shopify-auth.ts) ──────────────
function decrypt(encryptedStr, key) {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

// ── Date range helpers ───────────────────────────────────
function getRange(period) {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let start, end;

  switch (period) {
    case "today":
      start = today;
      end = now;
      break;
    case "yesterday": {
      start = new Date(today);
      start.setDate(start.getDate() - 1);
      end = new Date(today.getTime() - 1); // 23:59:59.999 yesterday
      break;
    }
    case "mtd":
      start = new Date(now.getFullYear(), now.getMonth(), 1);
      end = now;
      break;
    case "qtd": {
      const qMonth = Math.floor(now.getMonth() / 3) * 3;
      start = new Date(now.getFullYear(), qMonth, 1);
      end = now;
      break;
    }
    case "ytd":
      start = new Date(now.getFullYear(), 0, 1);
      end = now;
      break;
    case "l30d":
      start = new Date(today);
      start.setDate(start.getDate() - 30);
      end = now;
      break;
    case "l7d":
    default:
      start = new Date(today);
      start.setDate(start.getDate() - 7);
      end = now;
      break;
  }
  return { start, end, label: period.toUpperCase() };
}

// ── Shopify REST API helpers ─────────────────────────────
async function shopifyGet(shopDomain, token, path) {
  const url = `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}/${path}`;
  const res = await fetch(url, {
    headers: {
      "X-Shopify-Access-Token": token,
      "Content-Type": "application/json",
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Shopify API error ${res.status}: ${text}`);
  }
  return res.json();
}

async function fetchAllShopifyOrders(shopDomain, token, start, end) {
  const orders = [];
  let url =
    `orders.json?status=any&limit=250` +
    `&created_at_min=${start.toISOString()}` +
    `&created_at_max=${end.toISOString()}`;

  while (url) {
    const data = await shopifyGet(shopDomain, token, url);
    orders.push(...(data.orders || []));

    // Pagination via Link header is not available through fetch easily,
    // but Shopify REST returns at most 250. If we get 250, paginate.
    if (data.orders && data.orders.length === 250) {
      const lastId = data.orders[data.orders.length - 1].id;
      url =
        `orders.json?status=any&limit=250` +
        `&created_at_min=${start.toISOString()}` +
        `&created_at_max=${end.toISOString()}` +
        `&since_id=${lastId}`;
    } else {
      url = null;
    }
  }
  return orders;
}

// Also fetch orders cancelled within the range (even if created before)
async function fetchCancelledInRange(shopDomain, token, start, end) {
  // Shopify doesn't have a cancelled_at filter on REST, so we need to
  // fetch all cancelled orders updated in the range and filter client-side.
  const orders = [];
  let url =
    `orders.json?status=cancelled&limit=250` +
    `&updated_at_min=${start.toISOString()}` +
    `&updated_at_max=${end.toISOString()}`;

  while (url) {
    const data = await shopifyGet(shopDomain, token, url);
    orders.push(...(data.orders || []));
    if (data.orders && data.orders.length === 250) {
      const lastId = data.orders[data.orders.length - 1].id;
      url =
        `orders.json?status=cancelled&limit=250` +
        `&updated_at_min=${start.toISOString()}` +
        `&updated_at_max=${end.toISOString()}` +
        `&since_id=${lastId}`;
    } else {
      url = null;
    }
  }
  // Filter to those actually cancelled in the range
  return orders.filter((o) => {
    if (!o.cancelled_at) return false;
    const ct = new Date(o.cancelled_at);
    return ct >= start && ct <= end;
  });
}

// ── Shopify order-level calculations ─────────────────────
function shopifyOrderMetrics(order) {
  const lineItems = order.line_items || [];

  // Gross sales = sum(quantity × price) for each line item
  let grossSales = 0;
  for (const li of lineItems) {
    grossSales += (Number(li.quantity) || 0) * (Number(li.price) || 0);
  }

  // Total discounts (includes both product and shipping discounts)
  const totalDiscounts = Number(order.total_discounts) || 0;

  // Shipping: use discounted_price if available, else price
  let shippingCharge = 0;
  let shippingDiscount = 0;
  for (const sl of order.shipping_lines || []) {
    const gross = Number(sl.price) || 0;
    const discounted = sl.discounted_price != null
      ? Number(sl.discounted_price)
      : gross;
    shippingCharge += discounted;
    shippingDiscount += gross - discounted;
  }

  // Product discount = total_discounts - shipping discount
  const productDiscount = totalDiscounts - shippingDiscount;

  // Net sales = gross - product discounts (no shipping, no tax)
  const netSales = grossSales - productDiscount;

  // Refund amounts
  let refundAmount = 0;
  let refundShipping = 0;
  for (const refund of order.refunds || []) {
    for (const rli of refund.refund_line_items || []) {
      refundAmount += Number(rli.subtotal) || 0;
    }
    // Shipping refunds via order_adjustments
    for (const adj of refund.order_adjustments || []) {
      if (adj.kind === "shipping_refund") {
        refundShipping += Math.abs(Number(adj.amount) || 0);
      }
    }
  }

  // Total sales = gross - discounts - returns + shipping + taxes
  // But for our comparison (no tax), we use:
  //   netRevenue = netSales - refundAmount
  //   netShipping = shippingCharge - refundShipping
  //   totalSales = netRevenue + netShipping
  const netRevenue = netSales - refundAmount;
  const netShipping = shippingCharge - refundShipping;
  const totalSales = netRevenue + netShipping;

  return {
    orderId: order.id,
    orderNumber: order.order_number || order.name,
    createdAt: order.created_at,
    cancelledAt: order.cancelled_at,
    financialStatus: order.financial_status,
    grossSales,
    productDiscount,
    shippingDiscount,
    totalDiscounts,
    netSales,
    shippingCharge,
    refundAmount,
    refundShipping,
    netRevenue,
    netShipping,
    totalSales,
  };
}

// ── Firestore transactions ───────────────────────────────
async function getFirestoreTransactions(start, end) {
  // Fetch all user transactions and filter in-memory (avoids composite index)
  const snap = await db
    .collection("transactions")
    .where("user_id", "==", UID)
    .get();

  const all = snap.docs.map((d) => {
    const data = d.data();
    return {
      id: d.id,
      amount: Number(data.amount) || 0,
      category: data.category_id || "",
      saleId: data.sale_id || "",
      title: data.title || "",
      dateTime: data.date_time?.toDate?.() || null,
      createdAt: data.created_at?.toDate?.() || null,
      excludeFromPl: data.exclude_from_pl === true,
      note: data.note || "",
    };
  });

  return all.filter((t) => t.dateTime && t.dateTime >= start && t.dateTime <= end);
}

async function getFirestoreSales(start, end) {
  // Fetch all user sales and filter in-memory
  const snap = await db
    .collection("sales")
    .where("user_id", "==", UID)
    .get();

  const all = snap.docs.map((d) => {
    const data = d.data();
    return {
      id: d.id,
      saleId: data.id || d.id,
      externalOrderId: data.external_order_id || "",
      orderNumber: data.shopify_order_number || data.order_number || "",
      orderStatus: data.order_status,
      totalAmount: Number(data.total_amount) || 0,
      shippingCost: Number(data.shipping_cost) || 0,
      date: data.date?.toDate?.() || null,
    };
  });

  return all.filter((s) => s.date && s.date >= start && s.date <= end);
}

// Get ALL transactions for a sale (not date-filtered) to find reversals
async function getTransactionsForSale(saleId) {
  const snap = await db
    .collection("transactions")
    .where("sale_id", "==", saleId)
    .get();

  return snap.docs.map((d) => {
    const data = d.data();
    return {
      id: d.id,
      amount: Number(data.amount) || 0,
      category: data.category_id || "",
      saleId: data.sale_id || "",
      title: data.title || "",
      dateTime: data.date_time?.toDate?.() || null,
      createdAt: data.created_at?.toDate?.() || null,
      excludeFromPl: data.exclude_from_pl === true,
      note: data.note || "",
    };
  });
}

// ── Main analysis ────────────────────────────────────────
const EXCLUDED_CATS = new Set([
  "cat_investments",
  "cat_loan_received",
  "cat_loan_repayment",
  "cat_equity_injection",
  "cat_owner_withdrawal",
]);

function revvoCalc(txns) {
  let revenue = 0;
  let expenses = 0;
  let salesRev = 0;
  let shipping = 0;
  let cogs = 0;
  let otherIncome = 0;
  let otherExpense = 0;

  for (const t of txns) {
    if (t.excludeFromPl || EXCLUDED_CATS.has(t.category)) continue;
    const cat = t.category;
    const a = t.amount;

    if (cat === "cat_cogs") {
      expenses -= a; // COGS stored as negative, so -(-x) = +x
    } else if (cat === "cat_sales_revenue" || cat === "cat_shipping") {
      revenue += a; // signed: positive for sales, negative for refunds
    } else if (a > 0) {
      revenue += a;
      otherIncome += a;
    } else {
      expenses += Math.abs(a);
      otherExpense += Math.abs(a);
    }

    // Detail breakdown
    if (cat === "cat_sales_revenue") salesRev += a;
    else if (cat === "cat_shipping") shipping += a;
    else if (cat === "cat_cogs") cogs -= a;
  }

  return { revenue, expenses, salesRev, shipping, cogs, otherIncome, otherExpense };
}

function round2(n) {
  return Math.round(n * 100) / 100;
}

async function main() {
  const period = (process.argv[2] || "l7d").toLowerCase();
  const encKey = process.env.ENCRYPTION_KEY;

  if (!encKey) {
    console.error(
      "ERROR: Set ENCRYPTION_KEY env var to the SHOPIFY_TOKEN_ENCRYPTION_KEY hex string.\n" +
        "  Get it with: firebase functions:secrets:access SHOPIFY_TOKEN_ENCRYPTION_KEY\n"
    );
    process.exit(1);
  }

  const { start, end, label } = getRange(period);
  console.log(`\n╔══════════════════════════════════════════════════════════════╗`);
  console.log(`║  DIAGNOSTIC: ${label} (${start.toLocaleDateString()} → ${end.toLocaleDateString()})  ║`);
  console.log(`╚══════════════════════════════════════════════════════════════╝\n`);

  // ── 1. Get Shopify connection ──────────────────────────
  console.log("Reading Shopify connection...");
  const connDoc = await db
    .collection("shopify_connections")
    .doc(UID)
    .get();

  if (!connDoc.exists) {
    console.error("No Shopify connection found for user " + UID);
    process.exit(1);
  }

  const conn = connDoc.data();
  const shopDomain = conn.shop_domain;
  const accessToken = decrypt(conn.access_token, encKey.trim());
  console.log(`  Shop: ${shopDomain}\n`);

  // ── 2. Fetch Shopify orders ────────────────────────────
  console.log("Fetching Shopify orders created in range...");
  const shopifyOrders = await fetchAllShopifyOrders(
    shopDomain, accessToken, start, end
  );
  console.log(`  Found ${shopifyOrders.length} orders created in range`);

  console.log("Fetching orders cancelled in range (created earlier)...");
  const cancelledInRange = await fetchCancelledInRange(
    shopDomain, accessToken, start, end
  );
  // Filter out ones already in shopifyOrders
  const createdIds = new Set(shopifyOrders.map((o) => o.id));
  const extraCancelled = cancelledInRange.filter(
    (o) => !createdIds.has(o.id)
  );
  console.log(
    `  Found ${extraCancelled.length} additional orders cancelled in range (created before)\n`
  );

  // ── 3. Compute Shopify aggregates ──────────────────────
  console.log("═══ SHOPIFY ORDER-LEVEL ANALYSIS ═══\n");

  let shopGross = 0, shopDiscounts = 0, shopReturns = 0;
  let shopShipping = 0, shopShipRefunds = 0;
  let shopNetRev = 0, shopNetShip = 0, shopTotal = 0;
  let activeCount = 0, cancelledCount = 0, refundedCount = 0;

  const shopifyByOrderId = {};

  for (const order of shopifyOrders) {
    const m = shopifyOrderMetrics(order);
    shopifyByOrderId[String(order.id)] = m;

    if (order.cancelled_at) {
      cancelledCount++;
      // For cancelled orders created in range: Shopify shows them at 0
      // (original + reversal cancel out within the same order)
      // But we still track them for cross-referencing with Firestore
    } else {
      activeCount++;
    }
    if ((order.refunds || []).length > 0) refundedCount++;

    shopGross += m.grossSales;
    shopDiscounts += m.productDiscount;
    shopReturns += m.refundAmount;
    shopShipping += m.shippingCharge;
    shopShipRefunds += m.refundShipping;
    shopNetRev += m.netRevenue;
    shopNetShip += m.netShipping;
    shopTotal += m.totalSales;
  }

  // Also handle cancelled-in-range but created-before
  // These orders' RETURNS show up in Shopify analytics for this period
  // even though the original sale was in a prior period
  let cancelReversalTotal = 0;
  for (const order of extraCancelled) {
    const m = shopifyOrderMetrics(order);
    shopifyByOrderId[String(order.id)] = m;
    cancelledCount++;
    // The refund amounts from these cancellations affect the current period
    cancelReversalTotal += m.refundAmount + m.refundShipping;
  }

  console.log(`Orders: ${shopifyOrders.length} created (${activeCount} active, ${cancelledCount} cancelled), ${refundedCount} with refunds`);
  console.log(`Extra cancelled (created earlier): ${extraCancelled.length} (reversal total: ${round2(cancelReversalTotal)})`);
  console.log(`\n  Gross Sales:       ${round2(shopGross)}`);
  console.log(`  Product Discounts: -${round2(shopDiscounts)}`);
  console.log(`  Returns/Refunds:   -${round2(shopReturns)}`);
  console.log(`  ─────────────────────────`);
  console.log(`  Net Sales Revenue: ${round2(shopNetRev)}`);
  console.log(`  Shipping Charges:  ${round2(shopShipping)}`);
  console.log(`  Shipping Refunds:  -${round2(shopShipRefunds)}`);
  console.log(`  Net Shipping:      ${round2(shopNetShip)}`);
  console.log(`  ═════════════════════════`);
  console.log(`  TOTAL SALES:       ${round2(shopTotal)}\n`);

  // ── 4. Fetch & compute Firestore (Revvo) ───────────────
  console.log("═══ REVVO FIRESTORE ANALYSIS ═══\n");

  const firestoreTxns = await getFirestoreTransactions(start, end);
  const firestoreSales = await getFirestoreSales(start, end);

  // Filter to non-excluded, non-pl-excluded
  const revvoTxns = firestoreTxns.filter(
    (t) => !t.excludeFromPl && !EXCLUDED_CATS.has(t.category)
  );

  const r = revvoCalc(firestoreTxns);
  console.log(`Transactions in range: ${firestoreTxns.length} (${revvoTxns.length} after exclusions)`);
  console.log(`Sales in range: ${firestoreSales.length}`);
  console.log(`\n  Sales Revenue:  ${round2(r.salesRev)}`);
  console.log(`  Shipping:       ${round2(r.shipping)}`);
  console.log(`  COGS:           ${round2(r.cogs)}`);
  console.log(`  Other Income:   ${round2(r.otherIncome)}`);
  console.log(`  Other Expense:  ${round2(r.otherExpense)}`);
  console.log(`  ─────────────────────────`);
  console.log(`  REVENUE (app):  ${round2(r.revenue)}`);
  console.log(`  EXPENSES (app): ${round2(r.expenses)}\n`);

  // ── 5. Gap analysis ────────────────────────────────────
  console.log("═══ GAP ANALYSIS ═══\n");
  const revGap = round2(shopTotal - r.revenue);
  const salesGap = round2(shopNetRev - r.salesRev);
  const shipGap = round2(shopNetShip - r.shipping);
  console.log(`  Shopify Total Sales:  ${round2(shopTotal)}`);
  console.log(`  Revvo Revenue:        ${round2(r.revenue)}`);
  console.log(`  GAP:                  ${revGap}`);
  console.log(`    Sales gap:          ${salesGap} (Shopify NetRev ${round2(shopNetRev)} vs Revvo SalesRev ${round2(r.salesRev)})`);
  console.log(`    Shipping gap:       ${shipGap} (Shopify NetShip ${round2(shopNetShip)} vs Revvo Shipping ${round2(r.shipping)})\n`);

  // ── 6. Per-order comparison ────────────────────────────
  console.log("═══ PER-ORDER COMPARISON ═══\n");

  // Build sale lookup by external_order_id
  const saleByExtId = {};
  for (const s of firestoreSales) {
    if (s.externalOrderId) {
      saleByExtId[s.externalOrderId] = s;
    }
  }

  // Build transaction lookup by sale_id
  const txnsBySaleId = {};
  for (const t of firestoreTxns) {
    if (t.saleId) {
      if (!txnsBySaleId[t.saleId]) txnsBySaleId[t.saleId] = [];
      txnsBySaleId[t.saleId].push(t);
    }
  }

  const mismatches = [];
  const missingInFirestore = [];
  const wrongDateReversals = [];

  for (const order of [...shopifyOrders, ...extraCancelled]) {
    const shopifyId = String(order.id);
    const m = shopifyByOrderId[shopifyId];
    const sale = saleByExtId[shopifyId];

    if (!sale) {
      // Check if order is cancelled — might not have a sale
      if (!order.cancelled_at) {
        missingInFirestore.push({
          orderId: shopifyId,
          orderNumber: m.orderNumber,
          totalSales: m.totalSales,
        });
      }
      continue;
    }

    // Get all transactions for this sale (including reversals outside date range)
    const saleTxns = txnsBySaleId[sale.saleId] || [];

    // Compute Revvo net for this order from txns in the date range
    let revvoSalesRev = 0;
    let revvoShip = 0;
    for (const t of saleTxns) {
      if (t.excludeFromPl) continue;
      if (t.category === "cat_sales_revenue") revvoSalesRev += t.amount;
      else if (t.category === "cat_shipping") revvoShip += t.amount;
    }

    const revvoTotal = round2(revvoSalesRev + revvoShip);
    const shopTotal = round2(m.netRevenue + m.netShipping);

    // Check if amounts are close (within 1 EGP tolerance for rounding)
    if (Math.abs(revvoTotal - shopTotal) > 1) {
      mismatches.push({
        orderNumber: m.orderNumber,
        shopifyId,
        shopifyNetRev: round2(m.netRevenue),
        shopifyNetShip: round2(m.netShipping),
        shopifyTotal: shopTotal,
        revvoSalesRev: round2(revvoSalesRev),
        revvoShip: round2(revvoShip),
        revvoTotal,
        diff: round2(shopTotal - revvoTotal),
        isCancelled: !!order.cancelled_at,
        cancelledAt: order.cancelled_at,
        txnCount: saleTxns.length,
      });
    }

    // Check for wrong-date reversals
    for (const t of saleTxns) {
      if (t.title && t.title.startsWith("[Reversal]") && t.dateTime) {
        const cancelledAt = order.cancelled_at
          ? new Date(order.cancelled_at)
          : null;
        if (cancelledAt && t.createdAt) {
          // If the reversal date_time is more than 5 minutes from
          // the Shopify cancelled_at, it was probably set to
          // Timestamp.now() instead of cancelled_at
          const dtDiff = Math.abs(
            t.dateTime.getTime() - cancelledAt.getTime()
          );
          const createdDiff = Math.abs(
            t.createdAt.getTime() - t.dateTime.getTime()
          );
          if (dtDiff > 5 * 60 * 1000 && createdDiff < 60 * 1000) {
            // date_time ≈ created_at but ≠ cancelled_at → used Timestamp.now()
            wrongDateReversals.push({
              txnId: t.id,
              saleId: t.saleId,
              orderNumber: m.orderNumber,
              title: t.title,
              dateTime: t.dateTime.toISOString(),
              shouldBe: cancelledAt.toISOString(),
              diffMinutes: round2(dtDiff / 60000),
            });
          }
        }
      }
    }
  }

  if (missingInFirestore.length > 0) {
    console.log(
      `⚠ ${missingInFirestore.length} active Shopify orders NOT found in Firestore:`
    );
    for (const m of missingInFirestore.slice(0, 10)) {
      console.log(
        `  #${m.orderNumber} (${m.orderId}): ${round2(m.totalSales)}`
      );
    }
    if (missingInFirestore.length > 10)
      console.log(`  ... and ${missingInFirestore.length - 10} more`);
    console.log("");
  } else {
    console.log("✓ All active Shopify orders found in Firestore\n");
  }

  if (mismatches.length > 0) {
    console.log(
      `⚠ ${mismatches.length} orders with AMOUNT MISMATCHES (>1 EGP):`
    );
    let totalDiff = 0;
    for (const m of mismatches) {
      console.log(
        `  #${m.orderNumber} (${m.shopifyId}): ` +
          `Shopify=${m.shopifyTotal} vs Revvo=${m.revvoTotal} ` +
          `(diff=${m.diff})` +
          (m.isCancelled
            ? ` [CANCELLED ${m.cancelledAt}]`
            : "") +
          ` [${m.txnCount} txns]`
      );
      console.log(
        `    Shopify: rev=${m.shopifyNetRev}, ship=${m.shopifyNetShip}`
      );
      console.log(
        `    Revvo:   rev=${m.revvoSalesRev}, ship=${m.revvoShip}`
      );
      totalDiff += m.diff;
    }
    console.log(`\n  Sum of per-order diffs: ${round2(totalDiff)}`);
    console.log(`  Aggregate gap:         ${revGap}`);
    if (Math.abs(round2(totalDiff) - revGap) > 1) {
      console.log(
        `  ⚠ Diff-sum ≠ aggregate gap → some gap is from date-range boundary effects`
      );
    }
    console.log("");
  } else {
    console.log("✓ All orders match within 1 EGP tolerance\n");
  }

  if (wrongDateReversals.length > 0) {
    console.log(
      `⚠ ${wrongDateReversals.length} WRONG-DATE REVERSALS (used Timestamp.now() instead of cancelled_at):`
    );
    for (const r of wrongDateReversals) {
      console.log(
        `  ${r.txnId} (#${r.orderNumber}): date=${r.dateTime}, should=${r.shouldBe} (off by ${r.diffMinutes} min)`
      );
    }
    console.log("");
  } else {
    console.log("✓ No wrong-date reversals detected\n");
  }

  // ── 7. Transactions with no matching sale in range ─────
  console.log("═══ ORPHAN ANALYSIS ═══\n");

  // Find Shopify-related txns in range whose sale was created OUTSIDE the range
  const salesInRangeIds = new Set(firestoreSales.map((s) => s.saleId));
  const orphanTxns = revvoTxns.filter(
    (t) =>
      t.saleId &&
      !salesInRangeIds.has(t.saleId) &&
      (t.category === "cat_sales_revenue" ||
        t.category === "cat_shipping" ||
        t.category === "cat_cogs")
  );

  if (orphanTxns.length > 0) {
    let orphanRevenue = 0;
    let orphanShipping = 0;
    let orphanCogs = 0;
    const orphanSaleIds = new Set();

    for (const t of orphanTxns) {
      orphanSaleIds.add(t.saleId);
      if (t.category === "cat_sales_revenue") orphanRevenue += t.amount;
      else if (t.category === "cat_shipping") orphanShipping += t.amount;
      else if (t.category === "cat_cogs") orphanCogs -= t.amount;
    }

    console.log(
      `${orphanTxns.length} Shopify txns in range belong to sales OUTSIDE the range (${orphanSaleIds.size} sales):`
    );
    console.log(
      `  Revenue: ${round2(orphanRevenue)}, Shipping: ${round2(orphanShipping)}, COGS: ${round2(orphanCogs)}`
    );
    console.log(
      `  These are likely refund/reversal transactions for orders placed before the range.`
    );
    console.log(
      `  Shopify would also show these as returns in this period.\n`
    );

    // Show top orphans
    const orphanBySale = {};
    for (const t of orphanTxns) {
      if (!orphanBySale[t.saleId]) orphanBySale[t.saleId] = [];
      orphanBySale[t.saleId].push(t);
    }
    const orphanEntries = Object.entries(orphanBySale);
    console.log(`  Top orphan sales (by absolute impact):`);
    orphanEntries
      .map(([saleId, txns]) => {
        const sum = txns.reduce((a, t) => a + t.amount, 0);
        return { saleId, sum, txns };
      })
      .sort((a, b) => Math.abs(b.sum) - Math.abs(a.sum))
      .slice(0, 10)
      .forEach(({ saleId, sum, txns }) => {
        const titles = [...new Set(txns.map((t) => t.title))].join(", ");
        console.log(
          `    ${saleId}: net=${round2(sum)} (${txns.length} txns) — ${titles}`
        );
      });
    console.log("");
  } else {
    console.log("✓ No orphan Shopify transactions in range\n");
  }

  // ── Summary ────────────────────────────────────────────
  console.log("═══ SUMMARY ═══\n");
  console.log(`  Period:             ${label} (${start.toLocaleDateString()} → ${end.toLocaleDateString()})`);
  console.log(`  Shopify Total:      ${round2(shopTotal + cancelReversalTotal)} (orders: ${round2(shopTotal)}, extra cancellations: -${round2(cancelReversalTotal)})`);
  console.log(`  Revvo Revenue:      ${round2(r.revenue)}`);
  console.log(`  Gap:                ${revGap}`);
  console.log(`  Missing orders:     ${missingInFirestore.length}`);
  console.log(`  Amount mismatches:  ${mismatches.length}`);
  console.log(`  Wrong-date reversals: ${wrongDateReversals.length}`);
  console.log(`  Orphan txns:        ${orphanTxns.length}`);
  console.log("");

  process.exit(0);
}

main().catch((err) => {
  console.error("FATAL:", err);
  process.exit(1);
});

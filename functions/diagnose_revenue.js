/**
 * Diagnostic: Analyse Revvo vs Shopify discrepancies (read-only).
 *
 * 1. Per cancelled sale: sum all txn amounts → should net to zero
 * 2. Count orders by status
 * 3. Sum refund transactions
 * 4. Revenue & shipping totals for current month
 *
 * Usage:
 *   node diagnose_revenue.js [userId]
 *   (If no userId, runs across ALL users)
 */

const admin = require("firebase-admin");
const path = require("path");

const SA_PATH = path.resolve(
  "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
);

admin.initializeApp({
  credential: admin.credential.cert(require(SA_PATH)),
});

const db = admin.firestore();
const userId = process.argv[2] || null;

async function main() {
  console.log("=== REVVO REVENUE DIAGNOSTIC ===\n");

  // ── 1. Load all sales ──
  let salesQuery = db.collection("sales");
  if (userId) salesQuery = salesQuery.where("user_id", "==", userId);
  const salesSnap = await salesQuery.get();
  console.log(`Total sales documents: ${salesSnap.size}`);

  const salesById = new Map();
  const salesByStatus = { 0: 0, 1: 0, 2: 0, 3: 0, 4: 0, other: 0 };
  let shopifySales = 0;
  let nonShopifySales = 0;

  for (const doc of salesSnap.docs) {
    const d = doc.data();
    const id = d.id || doc.id;
    salesById.set(id, d);
    const status = d.order_status ?? "other";
    if (salesByStatus[status] !== undefined) salesByStatus[status]++;
    else salesByStatus.other++;
    if (d.external_source === "shopify") shopifySales++;
    else nonShopifySales++;
  }

  console.log("\nOrders by status:");
  console.log("  0 (pending):    ", salesByStatus[0]);
  console.log("  1 (confirmed):  ", salesByStatus[1]);
  console.log("  2 (processing): ", salesByStatus[2]);
  console.log("  3 (delivered):  ", salesByStatus[3]);
  console.log("  4 (cancelled):  ", salesByStatus[4]);
  console.log("  other:          ", salesByStatus.other);
  console.log(`  Shopify: ${shopifySales}  |  Non-Shopify: ${nonShopifySales}`);

  // ── 2. Load all transactions ──
  let txnQuery = db.collection("transactions");
  if (userId) txnQuery = txnQuery.where("user_id", "==", userId);
  const txnSnap = await txnQuery.get();
  console.log(`\nTotal transactions: ${txnSnap.size}`);

  // Group txns by sale_id
  const txnsBySale = new Map();
  let totalRevenue = 0;
  let totalShipping = 0;
  let totalCogs = 0;
  let refundCount = 0;
  let refundAmount = 0;
  let excludedCount = 0;

  // Monthly breakdown (current month)
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);
  let monthRevenue = 0;
  let monthShipping = 0;
  let monthCogs = 0;
  let monthRefundAmount = 0;
  let monthRefundCount = 0;

  for (const doc of txnSnap.docs) {
    const d = doc.data();
    const amt = Number(d.amount) || 0;
    const catId = d.category_id || "";
    const saleId = d.sale_id || null;
    const txnId = d.id || doc.id;
    const title = d.title || "";
    const excluded = d.exclude_from_pl === true;

    if (excluded) excludedCount++;

    if (saleId) {
      if (!txnsBySale.has(saleId)) txnsBySale.set(saleId, []);
      txnsBySale.get(saleId).push({ id: txnId, amount: amt, category: catId, title, excluded });
    }

    // Skip excluded for totals (matches how Revvo computes)
    if (excluded) continue;

    if (catId === "cat_sales_revenue") {
      totalRevenue += amt;
      if (amt < 0) { refundCount++; refundAmount += amt; }
    } else if (catId === "cat_shipping") {
      totalShipping += amt;
    } else if (catId === "cat_cogs") {
      totalCogs += amt;
    }

    // Monthly
    let txDate = null;
    if (d.date_time && d.date_time._seconds) {
      txDate = new Date(d.date_time._seconds * 1000);
    } else if (d.date_time && d.date_time.toDate) {
      txDate = d.date_time.toDate();
    }
    if (txDate && txDate >= monthStart && txDate <= monthEnd) {
      if (catId === "cat_sales_revenue") {
        monthRevenue += amt;
        if (amt < 0) { monthRefundCount++; monthRefundAmount += amt; }
      } else if (catId === "cat_shipping") {
        monthShipping += amt;
      } else if (catId === "cat_cogs") {
        monthCogs += amt;
      }
    }
  }

  console.log(`\nTransactions with exclude_from_pl=true: ${excludedCount}`);

  console.log("\n=== ALL-TIME TOTALS (non-excluded) ===");
  console.log(`  Sales Revenue:  ${totalRevenue.toFixed(2)}`);
  console.log(`  Shipping:       ${totalShipping.toFixed(2)}`);
  console.log(`  COGS:           ${totalCogs.toFixed(2)}`);
  console.log(`  Total (rev+ship): ${(totalRevenue + totalShipping).toFixed(2)}`);
  console.log(`  Refunds:        ${refundCount} txns, ${refundAmount.toFixed(2)}`);

  console.log(`\n=== THIS MONTH (${monthStart.toISOString().slice(0, 7)}) ===`);
  console.log(`  Sales Revenue:  ${monthRevenue.toFixed(2)}`);
  console.log(`  Shipping:       ${monthShipping.toFixed(2)}`);
  console.log(`  COGS:           ${monthCogs.toFixed(2)}`);
  console.log(`  Total (rev+ship): ${(monthRevenue + monthShipping).toFixed(2)}`);
  console.log(`  Refunds:        ${monthRefundCount} txns, ${monthRefundAmount.toFixed(2)}`);

  // ── 3. Cancelled sales that don't net to zero ──
  console.log("\n=== CANCELLED SALE NET-ZERO CHECK ===");
  let cancelledOk = 0;
  let cancelledBroken = 0;
  const brokenSales = [];

  for (const [saleId, sale] of salesById) {
    if (sale.order_status !== 4) continue;

    const txns = txnsBySale.get(saleId) || [];
    // Only count non-excluded txns (what the P&L sees)
    const plTxns = txns.filter(t => !t.excluded);
    const netAmount = plTxns.reduce((s, t) => s + t.amount, 0);

    if (Math.abs(netAmount) > 0.01) {
      cancelledBroken++;
      brokenSales.push({ saleId, netAmount: Math.round(netAmount * 100) / 100, txnCount: plTxns.length, allTxnCount: txns.length });
      if (cancelledBroken <= 10) {
        const orderNum = sale.shopify_order_number || sale.external_order_id || "?";
        console.log(`  LEAK: ${saleId} (order #${orderNum}) net=${netAmount.toFixed(2)} [${plTxns.length} P&L txns, ${txns.length} total]`);
        for (const t of txns) {
          const ex = t.excluded ? " [EXCLUDED]" : "";
          console.log(`    ${t.id}  ${t.amount >= 0 ? "+" : ""}${t.amount.toFixed(2)}  ${t.category}  "${t.title}"${ex}`);
        }
      }
    } else {
      cancelledOk++;
    }
  }

  console.log(`\nCancelled sales that net to zero: ${cancelledOk}`);
  console.log(`Cancelled sales with LEAK (don't net to zero): ${cancelledBroken}`);
  if (cancelledBroken > 10) console.log(`  (showing first 10 of ${cancelledBroken})`);

  if (brokenSales.length > 0) {
    const totalLeak = brokenSales.reduce((s, b) => s + b.netAmount, 0);
    console.log(`  Total revenue leak from cancelled orders: ${totalLeak.toFixed(2)}`);
  }

  // ── 4. Sales with NO transactions ──
  console.log("\n=== SALES WITH MISSING TRANSACTIONS ===");
  let missingTxnCount = 0;
  for (const [saleId, sale] of salesById) {
    if (sale.order_status === 4) continue; // skip cancelled
    const txns = txnsBySale.get(saleId) || [];
    if (txns.length === 0) {
      missingTxnCount++;
      if (missingTxnCount <= 5) {
        const orderNum = sale.shopify_order_number || sale.external_order_id || "?";
        console.log(`  NO TXNS: ${saleId} (order #${orderNum}) status=${sale.order_status}`);
      }
    }
  }
  console.log(`Total non-cancelled sales with zero transactions: ${missingTxnCount}`);

  // ── 5. Duplicate revenue/shipping check ──
  console.log("\n=== DUPLICATE TRANSACTION CHECK ===");
  let dupeRevCount = 0;
  let dupeShipCount = 0;
  for (const [saleId, txns] of txnsBySale) {
    const sale = salesById.get(saleId);
    if (!sale || sale.order_status === 4) continue; // skip cancelled
    const revTxns = txns.filter(t => t.category === "cat_sales_revenue" && t.amount > 0 && !t.title.startsWith("["));
    const shipTxns = txns.filter(t => t.category === "cat_shipping" && t.amount > 0 && !t.title.startsWith("["));
    if (revTxns.length > 1) {
      dupeRevCount++;
      if (dupeRevCount <= 3) {
        console.log(`  DUPE REV: ${saleId} has ${revTxns.length} positive revenue txns`);
        revTxns.forEach(t => console.log(`    ${t.id}  +${t.amount.toFixed(2)}`));
      }
    }
    if (shipTxns.length > 1) {
      dupeShipCount++;
      if (dupeShipCount <= 3) {
        console.log(`  DUPE SHIP: ${saleId} has ${shipTxns.length} positive shipping txns`);
        shipTxns.forEach(t => console.log(`    ${t.id}  +${t.amount.toFixed(2)}`));
      }
    }
  }
  console.log(`Sales with duplicate revenue txns: ${dupeRevCount}`);
  console.log(`Sales with duplicate shipping txns: ${dupeShipCount}`);

  console.log("\n=== DIAGNOSTIC COMPLETE ===");
}

main().catch((err) => {
  console.error("Diagnostic failed:", err);
  process.exit(1);
});

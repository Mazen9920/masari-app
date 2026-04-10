#!/usr/bin/env node
/**
 * Migration: Fix revenue transactions to use netRevenue instead of total.
 *
 * Previously, revenue transactions (cat_sales_revenue) stored sale.total
 * which includes tax + shipping — overstating revenue.
 * This script corrects them to use netRevenue = subtotal − discount.
 *
 * It also sets exclude_from_pl = true on COGS and shipping transactions
 * for unpaid/partial sales (cash-basis P&L).
 *
 * Idempotent: safe to run multiple times.
 *
 * Usage:
 *   node migrate_revenue_fix.js              # dry-run (default)
 *   node migrate_revenue_fix.js --commit     # actually write changes
 */
const {Firestore} = require("@google-cloud/firestore");
const fs = require("fs");
const path = require("path");

const PROJECT_ID = "massari-574ff";
const DRY_RUN = !process.argv.includes("--commit");

// Service account path
const SA_PATH = "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json";

// ── Helpers ──────────────────────────────────────────────────
function roundMoney(v) {
  return Math.round(v * 100) / 100;
}

/** PaymentStatus enum indices matching Dart model. */
const PS_UNPAID = 0;
const PS_PARTIAL = 1;
// const PS_PAID = 2;
// const PS_REFUNDED = 3;

/** OrderStatus.cancelled index. */
const OS_CANCELLED = 4;

// ── Main ─────────────────────────────────────────────────────
async function main() {
  console.log(DRY_RUN ? "=== DRY RUN (add --commit to write) ===" : "=== COMMITTING CHANGES ===");

  const db = new Firestore({
    projectId: PROJECT_ID,
    keyFilename: SA_PATH,
  });

  // Sales and transactions are top-level collections (not nested under users)
  const salesSnap = await db.collection("sales").get();
  let revenueFixed = 0;
  let excludeFixed = 0;
  let skipped = 0;

  console.log(`Total sales: ${salesSnap.size}`);

  let processed = 0;
  for (const saleDoc of salesSnap.docs) {
    processed++;
    if (processed % 50 === 0) console.log(`  ... processed ${processed}/${salesSnap.size}`);
    const sale = saleDoc.data();
    const saleId = saleDoc.id;

    // Skip cancelled orders
    const orderStatus = typeof sale.order_status === "number" ? sale.order_status : 1;
    if (orderStatus === OS_CANCELLED) {
      skipped++;
      continue;
    }

    // Compute netRevenue = subtotal − discount
    const items = sale.items || [];
    const subtotal = roundMoney(
      items.reduce((sum, item) => {
        const qty = Number(item.quantity) || 0;
        const price = Number(item.unit_price) || 0;
        return sum + roundMoney(qty * price);
      }, 0)
    );
    const discountAmount = Number(sale.discount_amount) || 0;
    const netRevenue = roundMoney(subtotal - discountAmount);

    // ── Fix 1: Revenue transaction amount ──
    const revTxnId = `sale_rev_${saleId}`;
    const revRef = db.collection("transactions").doc(revTxnId);
    const revSnap = await revRef.get();

    if (revSnap.exists) {
      const currentAmount = Number(revSnap.data().amount) || 0;
      if (processed <= 5) console.log(`  DEBUG ${revTxnId}: current=${currentAmount} netRev=${netRevenue} diff=${Math.abs(currentAmount - netRevenue)}`);
      if (Math.abs(currentAmount - netRevenue) > 0.005) {
        console.log(`  FIX ${revTxnId}: ${currentAmount} → ${netRevenue}`);
        if (!DRY_RUN) {
          await revRef.update({amount: netRevenue, updated_at: Firestore.Timestamp.now()});
        }
        revenueFixed++;
      }
    } else {
      console.log(`  MISS ${revTxnId} (not found)`);
    }

    // ── Fix 2: excludeFromPL on COGS/shipping for unpaid/partial ──
    const paymentStatus = typeof sale.payment_status === "number" ? sale.payment_status : 2;
    const isUnpaidOrPartial = paymentStatus === PS_UNPAID || paymentStatus === PS_PARTIAL;

    if (isUnpaidOrPartial) {
      for (const prefix of ["sale_cogs_", "sale_ship_"]) {
        const txnId = `${prefix}${saleId}`;
        const txnRef = db.collection("transactions").doc(txnId);
        const txnSnap = await txnRef.get();
        if (txnSnap.exists && txnSnap.data().exclude_from_pl !== true) {
          console.log(`  EXCLUDE ${txnId} (payment_status=${paymentStatus})`);
          if (!DRY_RUN) {
            await txnRef.update({exclude_from_pl: true, updated_at: Firestore.Timestamp.now()});
          }
          excludeFixed++;
        }
      }
    }
  }

  console.log(`\n${"=".repeat(50)}`);
  console.log(`Revenue transactions fixed:  ${revenueFixed}`);
  console.log(`Transactions excluded from P&L: ${excludeFixed}`);
  console.log(`Cancelled sales skipped:     ${skipped}`);
  if (DRY_RUN) console.log("\nThis was a DRY RUN. Run with --commit to apply changes.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

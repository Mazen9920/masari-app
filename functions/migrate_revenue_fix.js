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

// ── Auth helper (reuses Firebase CLI refresh token) ──────────
function getRefreshToken() {
  const cfgPath = path.join(process.env.HOME, ".config/configstore/firebase-tools.json");
  const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
  const token = cfg.tokens?.refresh_token;
  if (!token) throw new Error("No refresh token in firebase-tools.json");
  return token;
}

async function refreshAccessToken(refreshToken) {
  const https = require("https");
  const clientId = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
  const clientSecret = "j9iVZfS8kkCEFUPaAeJV0sAi";
  const postData = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    refresh_token: refreshToken,
    grant_type: "refresh_token",
  }).toString();

  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: "oauth2.googleapis.com",
      path: "/token",
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Content-Length": Buffer.byteLength(postData),
      },
    }, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => {
        const parsed = JSON.parse(data);
        if (parsed.access_token) resolve(parsed.access_token);
        else reject(new Error(`Token refresh failed: ${data}`));
      });
    });
    req.on("error", reject);
    req.write(postData);
    req.end();
  });
}

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

  const refreshToken = getRefreshToken();
  const accessToken = await refreshAccessToken(refreshToken);
  const db = new Firestore({
    projectId: PROJECT_ID,
    host: "firestore.googleapis.com",
    ssl: true,
    customHeaders: {Authorization: `Bearer ${accessToken}`},
  });

  const usersSnap = await db.collection("users").get();
  let revenueFixed = 0;
  let excludeFixed = 0;
  let skipped = 0;

  for (const userDoc of usersSnap.docs) {
    const userId = userDoc.id;
    const salesSnap = await db.collection("users").doc(userId).collection("sales").get();
    if (salesSnap.empty) continue;

    console.log(`\nUser ${userId}: ${salesSnap.size} sales`);

    for (const saleDoc of salesSnap.docs) {
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
      const revRef = db.collection("users").doc(userId).collection("transactions").doc(revTxnId);
      const revSnap = await revRef.get();

      if (revSnap.exists) {
        const currentAmount = Number(revSnap.data().amount) || 0;
        if (Math.abs(currentAmount - netRevenue) > 0.005) {
          console.log(`  FIX ${revTxnId}: ${currentAmount} → ${netRevenue}`);
          if (!DRY_RUN) {
            await revRef.update({amount: netRevenue, updated_at: Firestore.Timestamp.now()});
          }
          revenueFixed++;
        }
      }

      // ── Fix 2: excludeFromPL on COGS/shipping for unpaid/partial ──
      const paymentStatus = typeof sale.payment_status === "number" ? sale.payment_status : 2;
      const isUnpaidOrPartial = paymentStatus === PS_UNPAID || paymentStatus === PS_PARTIAL;

      if (isUnpaidOrPartial) {
        for (const prefix of ["sale_cogs_", "sale_ship_"]) {
          const txnId = `${prefix}${saleId}`;
          const txnRef = db.collection("users").doc(userId).collection("transactions").doc(txnId);
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

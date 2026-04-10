/**
 * Deep diagnostic for a single user — compare Revvo vs Shopify numbers.
 *
 * Usage: node diagnose_user.js <userId>
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
const userId = process.argv[2];
if (!userId) { console.error("Usage: node diagnose_user.js <userId>"); process.exit(1); }

async function main() {
  console.log(`=== USER DIAGNOSTIC: ${userId} ===\n`);

  // ── Sales ──
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", userId)
    .get();

  const byStatus = {};
  let shopifyCount = 0;
  const cancelledSaleIds = new Set();

  for (const doc of salesSnap.docs) {
    const d = doc.data();
    const st = d.order_status ?? "?";
    byStatus[st] = (byStatus[st] || 0) + 1;
    if (d.external_source === "shopify") shopifyCount++;
    if (st === 4) cancelledSaleIds.add(d.id || doc.id);
  }

  console.log(`Total sales: ${salesSnap.size} (${shopifyCount} Shopify)`);
  console.log("By status:", JSON.stringify(byStatus));

  // ── Transactions ──
  const txnSnap = await db.collection("transactions")
    .where("user_id", "==", userId)
    .get();

  console.log(`Total transactions: ${txnSnap.size}\n`);

  // This month filter
  const now = new Date();
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0, 23, 59, 59);

  let allRevPositive = 0;
  let allRevNegative = 0;
  let allShipPositive = 0;
  let allShipNegative = 0;
  let allCogs = 0;
  let monthRevPositive = 0;
  let monthRevNegative = 0;
  let monthShipPositive = 0;
  let monthShipNegative = 0;
  let monthCogs = 0;

  // Track refund txns
  const refundTxns = [];
  // Track all txns by saleId for cancelled check
  const txnsBySale = new Map();

  for (const doc of txnSnap.docs) {
    const d = doc.data();
    const amt = Number(d.amount) || 0;
    const catId = d.category_id || "";
    const saleId = d.sale_id || null;
    const txnId = d.id || doc.id;
    const title = d.title || "";
    const excluded = d.exclude_from_pl === true;

    if (saleId) {
      if (!txnsBySale.has(saleId)) txnsBySale.set(saleId, []);
      txnsBySale.get(saleId).push({ id: txnId, amount: amt, category: catId, title, excluded });
    }

    // Skip excluded
    if (excluded) continue;

    // All-time
    if (catId === "cat_sales_revenue") {
      if (amt >= 0) allRevPositive += amt; else allRevNegative += amt;
      if (amt < 0) refundTxns.push({ id: txnId, amount: amt, title, saleId });
    } else if (catId === "cat_shipping") {
      if (amt >= 0) allShipPositive += amt; else allShipNegative += amt;
    } else if (catId === "cat_cogs") {
      allCogs += amt;
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
        if (amt >= 0) monthRevPositive += amt; else monthRevNegative += amt;
      } else if (catId === "cat_shipping") {
        if (amt >= 0) monthShipPositive += amt; else monthShipNegative += amt;
      } else if (catId === "cat_cogs") {
        monthCogs += amt;
      }
    }
  }

  console.log("=== ALL-TIME ===");
  console.log(`Revenue (+): ${allRevPositive.toFixed(2)}`);
  console.log(`Revenue (-): ${allRevNegative.toFixed(2)} (refunds/reversals)`);
  console.log(`Revenue NET: ${(allRevPositive + allRevNegative).toFixed(2)}`);
  console.log(`Shipping (+): ${allShipPositive.toFixed(2)}`);
  console.log(`Shipping (-): ${allShipNegative.toFixed(2)}`);
  console.log(`Shipping NET: ${(allShipPositive + allShipNegative).toFixed(2)}`);
  console.log(`COGS: ${allCogs.toFixed(2)}`);
  console.log(`Total Rev+Ship: ${(allRevPositive + allRevNegative + allShipPositive + allShipNegative).toFixed(2)}`);

  console.log(`\n=== THIS MONTH (${monthStart.toISOString().slice(0, 7)}) ===`);
  console.log(`Revenue (+): ${monthRevPositive.toFixed(2)}`);
  console.log(`Revenue (-): ${monthRevNegative.toFixed(2)}`);
  console.log(`Revenue NET: ${(monthRevPositive + monthRevNegative).toFixed(2)}`);
  console.log(`Shipping (+): ${monthShipPositive.toFixed(2)}`);
  console.log(`Shipping (-): ${monthShipNegative.toFixed(2)}`);
  console.log(`Shipping NET: ${(monthShipPositive + monthShipNegative).toFixed(2)}`);
  console.log(`COGS: ${monthCogs.toFixed(2)}`);

  // Shopify breakdown for comparison
  console.log("\n=== SHOPIFY COMPARISON (this month) ===");
  console.log("Shopify Gross:    120,270");
  console.log("Shopify Discount:  -9,435");
  console.log("Shopify Returns: -13,155");
  console.log("Shopify Net:      97,680");
  console.log("Shopify Shipping: 16,656");
  console.log("Shopify Total:   114,336");
  console.log(`\nRevvo Revenue:  ${(monthRevPositive + monthRevNegative).toFixed(2)}`);
  console.log(`Revvo Shipping: ${(monthShipPositive + monthShipNegative).toFixed(2)}`);
  console.log(`Revvo Total:    ${(monthRevPositive + monthRevNegative + monthShipPositive + monthShipNegative).toFixed(2)}`);
  const gapRev = (monthRevPositive + monthRevNegative) - 97680.30;
  const gapShip = (monthShipPositive + monthShipNegative) - 16656;
  console.log(`\nGap Revenue:  ${gapRev >= 0 ? "+" : ""}${gapRev.toFixed(2)}`);
  console.log(`Gap Shipping: ${gapShip >= 0 ? "+" : ""}${gapShip.toFixed(2)}`);
  console.log(`Gap Total:    ${(gapRev + gapShip >= 0 ? "+" : "")}${(gapRev + gapShip).toFixed(2)}`);

  // ── Refund audit ──
  console.log("\n=== REFUND TRANSACTIONS (all-time) ===");
  console.log(`Total refund txns: ${refundTxns.length}`);
  console.log(`Total refund amount: ${refundTxns.reduce((s, t) => s + t.amount, 0).toFixed(2)}`);
  for (const r of refundTxns) {
    const isCancelledSale = r.saleId ? cancelledSaleIds.has(r.saleId) : false;
    console.log(`  ${r.id}  ${r.amount.toFixed(2)}  sale_cancelled=${isCancelledSale}  "${r.title}"`);
  }

  // ── Check cancelled sales net ──
  console.log("\n=== CANCELLED SALES NET CHECK ===");
  let leaks = 0;
  for (const saleId of cancelledSaleIds) {
    const txns = txnsBySale.get(saleId) || [];
    const net = txns.filter(t => !t.excluded).reduce((s, t) => s + t.amount, 0);
    if (Math.abs(net) > 0.01) {
      leaks++;
      console.log(`  LEAK: ${saleId} net=${net.toFixed(2)}`);
      for (const t of txns) {
        const ex = t.excluded ? " [EXCLUDED]" : "";
        console.log(`    ${t.id}  ${t.amount >= 0 ? "+" : ""}${t.amount.toFixed(2)} ${t.category} "${t.title}"${ex}`);
      }
    }
  }
  console.log(`Cancelled sales with leaks: ${leaks}`);

  console.log("\n=== DIAGNOSTIC COMPLETE ===");
}

main().catch((err) => {
  console.error("Diagnostic failed:", err);
  process.exit(1);
});

// Simulate the new analytics breakdown logic against current Firestore data.
const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const ms = new Date(2026, 3, 1), me = new Date(2026, 4, 1);

  // Sales in April (by sale.date)
  const salesSnap = await db.collection("sales").where("user_id","==",uid).get();
  let gross = 0, discounts = 0, saleCount = 0;
  for (const d of salesSnap.docs) {
    const s = d.data();
    const dt = s.date?.toDate ? s.date.toDate() : null;
    if (!dt || dt < ms || dt >= me) continue;
    const items = s.items || [];
    const subtotal = items.reduce((acc, it) => acc + (Number(it.unit_price) || 0) * (Number(it.quantity) || 0), 0);
    gross += subtotal;
    discounts += Number(s.discount_amount) || 0;
    saleCount++;
  }

  // Returns = refund txns (negative cat_sales_revenue, NOT ending _reversal)
  const txnSnap = await db.collection("transactions").where("user_id","==",uid).where("category_id","==","cat_sales_revenue").get();
  let returns = 0, returnCount = 0;
  for (const d of txnSnap.docs) {
    const t = d.data();
    if (t.exclude_from_pl) continue;
    const amt = Number(t.amount) || 0;
    if (amt >= 0) continue;
    if (d.id.endsWith("_reversal")) continue;
    const dt = t.date_time?.toDate ? t.date_time.toDate() : null;
    if (!dt || dt < ms || dt >= me) continue;
    returns += Math.abs(amt);
    returnCount++;
  }

  const net = gross - discounts - returns;
  console.log("=== NEW Revvo logic (Shopify-style, refunds only for Returns) ===");
  console.log(`  Sales count: ${saleCount}`);
  console.log(`  Gross: ${gross.toFixed(2)}`);
  console.log(`  Discounts: -${discounts.toFixed(2)}`);
  console.log(`  Returns: -${returns.toFixed(2)} (${returnCount} refund txns)`);
  console.log(`  Net Sales: ${net.toFixed(2)}`);
  console.log();
  console.log("Shopify shows: Gross 203,882.99  Disc -18,510.24  Returns -23,623.77  Net 161,748.98");
  console.log("(Current Revvo: Gross 204,427.70  Disc -18,548.23  Returns -17,925.49  Net 167,953.98)");
  console.log();
  console.log(`NOTE: Returns will only reach Shopify parity AFTER running`);
  console.log(`      migrate_post_cancel_refunds.js --apply (back-fills missing refund txns).`);
  process.exit(0);
})();

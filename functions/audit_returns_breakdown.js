const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const ms = new Date(2026, 3, 1), me = new Date(2026, 4, 1);

  const snap = await db.collection("transactions").where("user_id","==",uid).where("category_id","==","cat_sales_revenue").get();
  const buckets = { reversal: 0, refundPer: 0, refundLegacy: 0, other: 0 };
  const countBuckets = { reversal: 0, refundPer: 0, refundLegacy: 0, other: 0 };
  const others = [];
  let totalNegApril = 0;
  for (const d of snap.docs) {
    const t = d.data();
    if (t.exclude_from_pl) continue;
    const amt = Number(t.amount) || 0;
    if (amt >= 0) continue;
    const dt = t.date_time && t.date_time.toDate ? t.date_time.toDate() : null;
    if (!dt || dt < ms || dt >= me) continue;
    totalNegApril += amt;
    const id = d.id;
    if (id.endsWith("_reversal")) { buckets.reversal += amt; countBuckets.reversal++; }
    else if (id.startsWith("sale_refund_") && id.split("_").length > 3) { buckets.refundPer += amt; countBuckets.refundPer++; }
    else if (id.startsWith("sale_refund_")) { buckets.refundLegacy += amt; countBuckets.refundLegacy++; }
    else { buckets.other += amt; countBuckets.other++; others.push({ id, amt, title: t.title }); }
  }
  console.log("April 2026 returns breakdown (negative cat_sales_revenue txns):");
  console.log(`  Cancellation reversals: ${countBuckets.reversal} txns totaling ${buckets.reversal.toFixed(2)}`);
  console.log(`  Per-refund (new format): ${countBuckets.refundPer} txns totaling ${buckets.refundPer.toFixed(2)}`);
  console.log(`  Legacy single refund docs: ${countBuckets.refundLegacy} txns totaling ${buckets.refundLegacy.toFixed(2)}`);
  console.log(`  Other negative sales revenue: ${countBuckets.other} txns totaling ${buckets.other.toFixed(2)}`);
  console.log(`  TOTAL Returns: ${totalNegApril.toFixed(2)}`);
  if (others.length > 0) {
    console.log("Other txns:");
    others.slice(0, 20).forEach(o => console.log("  ", JSON.stringify(o)));
  }
  process.exit(0);
})();

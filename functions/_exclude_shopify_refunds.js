const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({ credential: admin.credential.cert(require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const COMMIT = process.argv.includes("--commit");

// Shopify refunds are already deducted from net revenue (Shopify reports net),
// so the separate cat_refunds rows double-count. Exclude them from the P&L
// (keep the record; just flag exclude_from_pl). Manual refunds are left intact.
function isShopifyRefund(x) {
  const txt = ((x.title || "") + " " + (x.note || "")).toLowerCase();
  return txt.includes("shopify") || txt.includes("backfill") || txt.includes("#");
}

async function main() {
  const snap = await db.collection("transactions").where("user_id", "==", UID).get();
  const targets = [];
  snap.docs.forEach(d => {
    const x = d.data();
    if (x.category_id !== "cat_refunds") return;
    if (x.exclude_from_pl) return; // already excluded
    if (!isShopifyRefund(x)) return; // leave manual refunds as legit deductions
    targets.push({ id: d.id, amount: x.amount || 0 });
  });
  const total = targets.reduce((s, t) => s + t.amount, 0);
  console.log(`Shopify refunds to exclude from P&L: ${targets.length}, total ${total.toFixed(2)}`);

  if (!COMMIT) { console.log("DRY RUN — re-run with --commit to apply."); process.exit(0); }

  let batch = db.batch(), n = 0;
  for (const t of targets) {
    batch.update(db.collection("transactions").doc(t.id), { exclude_from_pl: true });
    if (++n % 450 === 0) { await batch.commit(); batch = db.batch(); }
  }
  await batch.commit();
  console.log(`Flagged ${targets.length} Shopify refund docs as exclude_from_pl=true.`);
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });

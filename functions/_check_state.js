/** Assess current state after partial migration: per-cancelled-order net consistency + monthly returns. */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const r2 = n => Math.round(n * 100) / 100;
function cairoMonth(d) {
  const p = new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo", year: "numeric", month: "2-digit" }).formatToParts(d);
  return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}`;
}
async function main() {
  const salesSnap = await db.collection("sales").where("user_id", "==", UID).get();
  const cancelledSaleIds = new Set();
  salesSnap.docs.forEach(d => { if (d.data().order_status === 4) cancelledSaleIds.add(d.id); });

  const txnSnap = await db.collection("transactions").where("user_id", "==", UID).where("category_id", "==", "cat_sales_revenue").get();
  // group by sale
  const bySale = {};
  const monthlyReturns = {}; // month -> sum |neg| (excl open-return excluded)
  const monthlyReturnsInclOpen = {};
  txnSnap.docs.forEach(d => {
    const t = d.data();
    const sid = t.sale_id || "none";
    (bySale[sid] = bySale[sid] || []).push({ id: d.id, amt: Number(t.amount)||0, excl: !!t.exclude_from_pl, date: t.date_time?.toDate?.() });
    const amt = Number(t.amount) || 0;
    if (amt < 0 && t.date_time?.toDate) {
      const m = cairoMonth(t.date_time.toDate());
      monthlyReturnsInclOpen[m] = (monthlyReturnsInclOpen[m]||0) + Math.abs(amt);
      if (!t.exclude_from_pl) monthlyReturns[m] = (monthlyReturns[m]||0) + Math.abs(amt);
    }
  });

  // Consistency: cancelled order net (excl excluded txns) should be 0
  let bad = [];
  for (const sid of cancelledSaleIds) {
    const txns = bySale[sid] || [];
    let net = 0; for (const t of txns) if (!t.excl) net += t.amt;
    if (Math.abs(r2(net)) > 0.01) bad.push({ sid, net: r2(net), n: txns.length });
  }
  bad.sort((a,b)=>Math.abs(b.net)-Math.abs(a.net));
  console.log(`\n=== Cancelled orders with non-zero net (half-done / inconsistent): ${bad.length} ===`);
  bad.slice(0,30).forEach(b => console.log(`  ${b.sid}  net=${b.net}  txns=${b.n}`));
  const totalBad = bad.reduce((s,b)=>s+b.net,0);
  console.log(`  total net of inconsistent cancelled orders: ${r2(totalBad)}`);

  console.log(`\n=== Monthly returns (cat_sales_revenue negatives) ===`);
  Object.keys(monthlyReturns).sort().forEach(m => {
    console.log(`  ${m}: inPL=${r2(monthlyReturns[m]||0)}  inclOpen=${r2(monthlyReturnsInclOpen[m]||0)}`);
  });
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });

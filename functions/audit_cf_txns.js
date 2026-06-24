const admin = require("firebase-admin");
const path = require("path");
const SA_PATH = path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(require(SA_PATH)) });
const db = admin.firestore();
const USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";

const saleTxnCats = new Set(["cat_sales_revenue", "cat_cogs", "cat_shipping"]);

async function main() {
  const txnSnap = await db.collection("transactions").where("user_id", "==", USER_ID).get();
  console.log(`Total transactions: ${txnSnap.size}\n`);

  const byCategory = {};
  const bostaDaily = [];
  const negSaleLinked = [];
  const posSaleLinked = [];

  for (const doc of txnSnap.docs) {
    const d = doc.data();
    const catId = d.category_id || "NO_CATEGORY";
    const amt = Number(d.amount) || 0;
    const hasSaleId = !!d.sale_id;
    const excludeFromPL = d.exclude_from_pl === true;
    const txnId = d.id || doc.id;

    if (!byCategory[catId]) {
      byCategory[catId] = { count: 0, sum: 0, withSaleId: 0, withExcludeFromPL: 0, samples: [] };
    }
    byCategory[catId].count++;
    byCategory[catId].sum += amt;
    if (hasSaleId) byCategory[catId].withSaleId++;
    if (excludeFromPL) byCategory[catId].withExcludeFromPL++;
    if (byCategory[catId].samples.length < 2) byCategory[catId].samples.push(txnId);

    if (txnId.startsWith("bosta_est_daily_") || txnId.startsWith("bosta_rec_daily_")) {
      bostaDaily.push({ id: txnId, cat: catId, amt, saleId: d.sale_id, excludeFromPL });
    }
    if (hasSaleId && saleTxnCats.has(catId) && amt < 0) {
      negSaleLinked.push({ id: txnId, cat: catId, amt, saleId: d.sale_id, title: d.title });
    }
    if (hasSaleId && saleTxnCats.has(catId) && amt >= 0) {
      posSaleLinked.push({ id: txnId, cat: catId, amt, saleId: d.sale_id, title: d.title });
    }
  }

  console.log("=== BY CATEGORY ===\n");
  for (const [cat, s] of Object.entries(byCategory).sort((a, b) => b[1].count - a[1].count)) {
    console.log(`${cat}: count=${s.count} sum=${s.sum.toFixed(2)} withSaleId=${s.withSaleId} excludeFromPL=${s.withExcludeFromPL} samples=[${s.samples.join(", ")}]`);
  }

  console.log(`\n=== BOSTA DAILY TXNS (${bostaDaily.length}) ===\n`);
  for (const t of bostaDaily) console.log(`  ${t.id} | ${t.cat} | amt=${t.amt} | excludeFromPL=${t.excludeFromPL}`);

  console.log(`\n=== NEGATIVE SALE-LINKED ACCRUAL (${negSaleLinked.length}) ===`);
  console.log(`  Total value: ${negSaleLinked.reduce((s, t) => s + t.amt, 0).toFixed(2)}\n`);
  for (const t of negSaleLinked.slice(0, 10)) console.log(`  ${t.id} | ${t.cat} | amt=${t.amt} | "${t.title}"`);
  if (negSaleLinked.length > 10) console.log(`  ... and ${negSaleLinked.length - 10} more`);

  console.log(`\n=== POSITIVE SALE-LINKED ACCRUAL (${posSaleLinked.length}) ===`);
  console.log(`  Total value: ${posSaleLinked.reduce((s, t) => s + t.amt, 0).toFixed(2)}\n`);
  for (const t of posSaleLinked.slice(0, 5)) console.log(`  ${t.id} | ${t.cat} | amt=${t.amt}`);
  if (posSaleLinked.length > 5) console.log(`  ... and ${posSaleLinked.length - 5} more`);

  // Simulate CF engine filter
  let cfUserCash = 0, cfUserExcluded = 0;
  for (const doc of txnSnap.docs) {
    const d = doc.data();
    const catId = d.category_id || "";
    const amt = Number(d.amount) || 0;
    const txnId = d.id || doc.id;
    const isIncome = amt > 0;

    // isCfUserCashTransaction logic
    if (d.sale_id && saleTxnCats.has(catId) && amt >= 0) { cfUserExcluded += amt; continue; }
    if (txnId.startsWith("bosta_est_daily_") || txnId.startsWith("bosta_rec_daily_")) { cfUserExcluded += amt; continue; }
    if (catId === "cat_supplier_payment") { cfUserCash += (isIncome ? Math.abs(amt) : -Math.abs(amt)); continue; }
    const plExcluded = ["cat_investments","cat_loan_received","cat_loan_repayment","cat_equity_injection","cat_owner_withdrawal"];
    if (plExcluded.includes(catId)) { cfUserCash += (isIncome ? Math.abs(amt) : -Math.abs(amt)); continue; }
    if (d.exclude_from_pl === true) { cfUserExcluded += amt; continue; }
    cfUserCash += (isIncome ? Math.abs(amt) : -Math.abs(amt));
  }

  console.log(`\n=== CF ENGINE SIMULATION ===`);
  console.log(`  txnCashFlow (isCfUserCashTransaction): ${cfUserCash.toFixed(2)}`);
  console.log(`  Excluded txn total: ${cfUserExcluded.toFixed(2)}`);
  console.log(`  + cashouts (230428.64) = ${(cfUserCash + 230428.64).toFixed(2)}`);
  console.log(`  + openingCash (user setting) = final Cash & Bank`);
}

main().catch(console.error);

const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const ms = new Date(2026, 3, 1), me = new Date(2026, 4, 1);

  // All cancelled sales that were cancelled in April
  const salesSnap = await db.collection("sales").where("user_id","==",uid).where("order_status","==",4).get();
  let inPeriod = 0, mismatched = 0, matchedAmt = 0, mismatchedAmt = 0;
  const details = [];

  for (const s of salesSnap.docs) {
    const d = s.data();
    // cancel date: prefer shopify cancelled_at stored, else updated_at
    // Sales might store cancelled_at; but easiest is to look at reversal txn date
    const revSnap = await db.collection("transactions").doc(`sale_rev_${s.id}_reversal`).get();
    if (!revSnap.exists) continue;
    const rev = revSnap.data();
    const revDate = rev.date_time.toDate();
    const saleDate = d.date ? d.date.toDate() : null;
    const updated = d.updated_at ? d.updated_at.toDate() : null;

    // If reversal is in April but order (created) is pre-April, it means reversal was dated at order date → NOT in April
    // We want to find orders where cancellation happened in April (updated_at in April) but reversal is NOT in April
    const cancelledInApril = updated && updated >= ms && updated < me;
    if (!cancelledInApril) continue;
    inPeriod++;
    const revInApril = revDate >= ms && revDate < me;
    if (!revInApril) {
      mismatched++;
      mismatchedAmt += Math.abs(Number(rev.amount) || 0);
      if (details.length < 20) details.push({ saleId: s.id, orderNum: d.external_order_number || d.order_number, saleDate: saleDate?.toISOString().slice(0,10), updatedAt: updated.toISOString().slice(0,10), revDate: revDate.toISOString().slice(0,10), revAmt: rev.amount });
    } else {
      matchedAmt += Math.abs(Number(rev.amount) || 0);
    }
  }
  console.log(`Cancelled in April (by updated_at): ${inPeriod}`);
  console.log(`Reversal NOT dated in April: ${mismatched} (total abs amount: ${mismatchedAmt.toFixed(2)})`);
  console.log(`Reversal dated in April: ${inPeriod - mismatched} (total abs amount: ${matchedAmt.toFixed(2)})`);
  console.log("Samples (cancelled in April but reversal dated elsewhere):");
  details.forEach(x => console.log("  ", JSON.stringify(x)));
  process.exit(0);
})();

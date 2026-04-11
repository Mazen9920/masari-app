const a = require("firebase-admin");
a.initializeApp({ credential: a.credential.cert(require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")) });
const db = a.firestore();
const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

(async () => {
  const txns = await db.collection("transactions").where("user_id", "==", uid).where("payment_method", "==", "bosta").get();
  const daily = txns.docs.filter(d => d.id.startsWith("bosta_daily_"));
  const est = txns.docs.filter(d => d.id.startsWith("bosta_est_daily_"));
  const rec = txns.docs.filter(d => d.id.startsWith("bosta_rec_daily_"));
  const estTotal = est.reduce((s, d) => s + Math.abs(Number(d.data().amount) || 0), 0);

  console.log("=== Verification ===");
  console.log("bosta_daily_ remaining:", daily.length);
  console.log("bosta_est_daily_ count:", est.length);
  console.log("bosta_rec_daily_ count:", rec.length);
  console.log("Estimate total:", Math.round(estTotal * 100) / 100, "EGP");

  if (est.length > 0) {
    const s = est[0].data();
    console.log("\nSample est txn:", est[0].id);
    console.log("  is_estimate:", s.is_estimate);
    console.log("  is_reconciliation:", s.is_reconciliation);
    console.log("  amount:", s.amount);
    console.log("  shipments:", s.bosta_shipment_count);
  }

  const conn = await db.doc("bosta_connections/" + uid).get();
  const cd = conn.data();
  console.log("\nConnection doc:");
  console.log("  average_bosta_fee:", cd.average_bosta_fee);
  console.log("  total_settled_fees:", cd.total_settled_fees);
  console.log("  total_settled_count:", cd.total_settled_count);

  const sh = await db.collection("bosta_shipments").where("user_id", "==", uid).where("estimate_recorded", "==", true).limit(1).get();
  if (sh.docs.length > 0) {
    const s = sh.docs[0].data();
    console.log("\nSample shipment:", sh.docs[0].id);
    console.log("  estimated_fee:", s.estimated_fee);
    console.log("  bosta_created_at:", s.bosta_created_at && s.bosta_created_at.toDate().toISOString());
    console.log("  estimate_recorded:", s.estimate_recorded);
    console.log("  estimate_transaction_id:", s.estimate_transaction_id);
    console.log("  reconciled:", s.reconciled);
  }

  process.exit(0);
})();

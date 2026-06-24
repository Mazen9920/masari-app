const admin = require("firebase-admin");
const sa = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const CUTOFF = new Date("2025-03-01");

(async () => {
  // 1) Matched shipments breakdown
  const matchedSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", UID)
    .where("matched", "==", true)
    .get();

  let paid = 0, pending = 0, rto = 0, returned = 0, noSaleId = 0;
  const pendingSaleIds = [];

  for (const d of matchedSnap.docs) {
    const data = d.data();
    if (data.cashout_status === "paid") { paid++; continue; }
    const state = data.state || 0;
    if (state === 60) { rto++; continue; }
    if (state === 46) { returned++; continue; }
    if (!data.sale_id) { noSaleId++; continue; }
    pending++;
    pendingSaleIds.push(data.sale_id);
  }

  console.log("=== MATCHED SHIPMENTS ===");
  console.log("Total matched:", matchedSnap.size);
  console.log("Paid:", paid);
  console.log("RTO:", rto, "Returned:", returned);
  console.log("No sale_id:", noSaleId);
  console.log("Pending (should be AR):", pending);
  console.log("Sample pending sale IDs:", pendingSaleIds.slice(0, 5));

  // 2) All shipments — non-matched
  const allSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", UID).get();
  let notMatched = 0;
  for (const d of allSnap.docs) {
    if (!d.data().matched) notMatched++;
  }
  console.log("\n=== ALL SHIPMENTS ===");
  console.log("Total:", allSnap.size);
  console.log("Not matched to sale:", notMatched);

  // 3) COD sales after cutoff
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", UID)
    .where("payment_method", "==", "Cash on Delivery (COD)")
    .get();

  let codTotal = 0, codAfterCutoff = 0, codCancelled = 0, codActive = 0;
  const activeCodSaleIds = new Set();

  for (const d of salesSnap.docs) {
    codTotal++;
    const data = d.data();
    const saleDate = data.date && data.date.toDate ? data.date.toDate() : new Date(data.date);
    if (saleDate < CUTOFF) continue;
    codAfterCutoff++;
    if (data.order_status === "cancelled") { codCancelled++; continue; }
    codActive++;
    activeCodSaleIds.add(d.id);
  }

  console.log("\n=== COD SALES ===");
  console.log("Total COD:", codTotal);
  console.log("After cutoff:", codAfterCutoff);
  console.log("Cancelled after cutoff:", codCancelled);
  console.log("Active after cutoff (potential AR):", codActive);

  // 4) Which of those active COD sales have NO paid shipment?
  // Build map: saleId -> best cashout_status
  const saleShipmentStatus = {};
  for (const d of allSnap.docs) {
    const data = d.data();
    const sid = data.sale_id;
    if (!sid) continue;
    const st = data.cashout_status || "pending";
    if (!saleShipmentStatus[sid] || st === "paid") {
      saleShipmentStatus[sid] = st;
    }
  }

  let arFromUnpaid = 0, arCountUnpaid = 0;
  let arFromNoShipment = 0, arCountNoShipment = 0;

  for (const saleId of activeCodSaleIds) {
    const status = saleShipmentStatus[saleId];
    if (status === "paid") continue; // Cashout received

    // Get sale total
    const saleDoc = await db.collection("sales").doc(saleId).get();
    const saleData = saleDoc.data();
    const total = Number(saleData.total) || 0;
    if (total <= 0) continue;

    // Check for RTO
    let isRto = false;
    for (const d of allSnap.docs) {
      if (d.data().sale_id === saleId) {
        const state = d.data().state || 0;
        if (state === 60 || state === 46) { isRto = true; break; }
      }
    }
    if (isRto) continue;

    if (!status) {
      // No shipment at all
      arCountNoShipment++;
      arFromNoShipment += total;
    } else {
      // Has shipment but not paid
      arCountUnpaid++;
      arFromUnpaid += total;
    }
  }

  console.log("\n=== CORRECT AR CALCULATION ===");
  console.log("COD with unpaid shipment:", arCountUnpaid, "total:", arFromUnpaid);
  console.log("COD with no shipment:", arCountNoShipment, "total:", arFromNoShipment);
  console.log("TOTAL AR:", arFromUnpaid + arFromNoShipment);

  // 5) Connection doc
  const conn = await db.collection("bosta_connections").doc(UID).get();
  const cd = conn.data();
  console.log("\n=== CONNECTION SUMMARY ===");
  console.log("cf_total_cashouts:", cd.cf_total_cashouts);
  console.log("cf_pending_ar:", cd.cf_pending_ar);
  console.log("cf_pending_ar_count:", cd.cf_pending_ar_count);
  console.log("cf_ar_cutoff_date:", cd.cf_ar_cutoff_date && cd.cf_ar_cutoff_date.toDate().toISOString());

  process.exit(0);
})();

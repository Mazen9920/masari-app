const admin = require("firebase-admin");
const sa = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";

(async () => {
  // Get all shipments
  const allSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", UID).get();

  // Get matched + pending (non-paid, non-RTO)
  const pendingSaleIds = new Set();
  for (const d of allSnap.docs) {
    const data = d.data();
    if (!data.matched) continue;
    if (data.cashout_status === "paid") continue;
    if (data.state === 60 || data.state === 46) continue;
    if (data.sale_id) pendingSaleIds.add(data.sale_id);
  }

  console.log("Unique pending sale IDs:", pendingSaleIds.size);

  // Check what payment methods those sales have
  const saleIds = [...pendingSaleIds];
  let codCount = 0, paymobCount = 0, otherCount = 0;
  let codArTotal = 0;

  for (let i = 0; i < saleIds.length; i += 10) {
    const chunk = saleIds.slice(i, i + 10);
    const snap = await db.collection("sales")
      .where(admin.firestore.FieldPath.documentId(), "in", chunk)
      .get();

    for (const s of snap.docs) {
      const data = s.data();
      const pm = data.payment_method || "unknown";
      const total = Number(data.total) || 0;
      if (pm.includes("COD")) {
        codCount++;
        codArTotal += total;
        console.log("  COD pending:", s.id, "total:", total, "status:", data.order_status);
      } else if (pm.includes("Paymob")) {
        paymobCount++;
      } else {
        otherCount++;
        console.log("  Other:", s.id, "method:", pm, "total:", total);
      }
    }
  }

  console.log("\nPending shipments' sales by payment method:");
  console.log("COD:", codCount, "AR total:", codArTotal);
  console.log("Paymob:", paymobCount);
  console.log("Other:", otherCount);

  // Now flip the approach: start from COD sales and check their shipment status
  console.log("\n=== APPROACH 2: Start from COD sales ===");
  const codSalesSnap = await db.collection("sales")
    .where("user_id", "==", UID)
    .where("payment_method", "==", "Cash on Delivery (COD)")
    .get();

  // Build saleId -> [shipment statuses] map
  const saleToShipments = {};
  for (const d of allSnap.docs) {
    const data = d.data();
    if (!data.sale_id) continue;
    if (!saleToShipments[data.sale_id]) saleToShipments[data.sale_id] = [];
    saleToShipments[data.sale_id].push({
      cashout_status: data.cashout_status,
      state: data.state,
    });
  }

  let withPaidShipment = 0, withPendingOnly = 0, withNoShipment = 0, withRtoOnly = 0;
  let arShouldBe = 0;
  const CUTOFF = new Date("2025-03-01");

  for (const d of codSalesSnap.docs) {
    const data = d.data();
    if (data.order_status === "cancelled") continue;
    const total = Number(data.total) || 0;
    if (total <= 0) continue;
    const saleDate = data.date && data.date.toDate ? data.date.toDate() : new Date(data.date);
    if (saleDate < CUTOFF) continue;

    const shipments = saleToShipments[d.id] || [];

    if (shipments.length === 0) {
      withNoShipment++;
      arShouldBe += total;
      continue;
    }

    const hasPaid = shipments.some(s => s.cashout_status === "paid");
    const allRto = shipments.every(s => s.state === 60 || s.state === 46);

    if (allRto) {
      withRtoOnly++;
    } else if (hasPaid) {
      withPaidShipment++;
    } else {
      withPendingOnly++;
      arShouldBe += total;
      console.log("  AR:", d.id, "total:", total, "shipments:", JSON.stringify(shipments));
    }
  }

  console.log("\nCOD sales (active, after cutoff, total>0):");
  console.log("With paid shipment:", withPaidShipment);
  console.log("With pending-only shipment:", withPendingOnly);
  console.log("With no shipment:", withNoShipment);
  console.log("With RTO-only:", withRtoOnly);
  console.log("\nCORRECT AR SHOULD BE:", arShouldBe);

  process.exit(0);
})();

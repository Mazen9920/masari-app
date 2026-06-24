const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();
const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

async function main() {
  // 1. Check specific orders user mentioned
  console.log("=== Checking orders 19435, 19197 ===");
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "in", [19435, 19197])
    .get();
  
  for (const doc of salesSnap.docs) {
    const d = doc.data();
    console.log(`Sale ${doc.id}: order=#${d.shopify_order_number} status=${d.order_status} payment=${d.payment_status} amount=${d.amount_paid} tracking=${d.tracking_number || "none"} customer=${d.customer_name}`);
  }

  // 2. Find ALL bosta_shipments matched=true with state 60 or 46
  const shipSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", uid)
    .where("matched", "==", true)
    .get();
  
  const rtoShips = shipSnap.docs.filter(d => {
    const st = d.data().state;
    return st === 60 || st === 46;
  });
  
  console.log(`\nTotal RTO/Returned shipments (matched=true): ${rtoShips.length}`);
  
  // 3. For each RTO shipment, load the linked sale and check for mismatches
  let falsePositives = [];
  let truePositives = [];
  let noSale = [];
  
  for (const shipDoc of rtoShips) {
    const ship = shipDoc.data();
    const saleId = ship.sale_id;
    
    if (!saleId) {
      noSale.push({ shipId: shipDoc.id, tracking: ship.tracking_number, state: ship.state });
      continue;
    }
    
    const saleDoc = await db.collection("sales").doc(saleId).get();
    if (!saleDoc.exists) {
      noSale.push({ shipId: shipDoc.id, tracking: ship.tracking_number, state: ship.state, saleId });
      continue;
    }
    
    const sale = saleDoc.data();
    const saleTracking = sale.tracking_number || "";
    const bostaTracking = ship.tracking_number || "";
    
    // A shipment is a TRUE RTO only if the sale's tracking matches the bosta tracking
    // OR if the sale has no other tracking (meaning this IS the shipment for that order)
    const trackingMatch = !saleTracking || !bostaTracking || saleTracking === bostaTracking;
    
    // Also check: did the order get RE-SHIPPED with a different tracking?
    // If sale has a different tracking number, the RTO shipment was replaced
    const isReplaced = saleTracking && bostaTracking && saleTracking !== bostaTracking;
    
    const entry = {
      shipId: shipDoc.id,
      bostaTracking,
      bostaState: ship.state === 60 ? "RTO" : "Returned",
      saleId,
      orderNum: sale.shopify_order_number,
      saleTracking,
      orderStatus: sale.order_status,
      paymentStatus: sale.payment_status,
      amount: sale.amount_paid,
      customer: sale.customer_name,
      trackingMatch,
      isReplaced,
    };
    
    if (isReplaced) {
      falsePositives.push(entry);
    } else {
      truePositives.push(entry);
    }
  }
  
  console.log(`\nTRUE RTOs (tracking matches or no tracking): ${truePositives.length}`);
  console.log(`FALSE RTOs (sale has different tracking = re-shipped): ${falsePositives.length}`);
  console.log(`No sale linked: ${noSale.length}`);
  
  if (falsePositives.length > 0) {
    console.log("\n=== FALSE POSITIVES (Re-shipped orders showing as RTO) ===");
    for (const fp of falsePositives) {
      console.log(`  #${fp.orderNum} ${fp.customer} | bosta=${fp.bostaTracking}(${fp.bostaState}) sale_tracking=${fp.saleTracking} | order_status=${fp.orderStatus} amount=${fp.amount}`);
    }
  }
  
  // 4. Also check: are there orders where the same sale_id has MULTIPLE bosta shipments?
  const saleIdCounts = {};
  for (const shipDoc of rtoShips) {
    const sid = shipDoc.data().sale_id;
    if (sid) saleIdCounts[sid] = (saleIdCounts[sid] || 0) + 1;
  }
  const dups = Object.entries(saleIdCounts).filter(([_, c]) => c > 1);
  if (dups.length > 0) {
    console.log(`\n=== Sales with MULTIPLE RTO shipments ===`);
    for (const [sid, count] of dups) {
      console.log(`  sale_id=${sid} count=${count}`);
    }
  }

  // 5. How many of the "true" RTOs have order_status != 4 (not cancelled)?
  const uncancelled = truePositives.filter(t => t.orderStatus !== 4);
  console.log(`\nTrue RTOs NOT cancelled in Shopify: ${uncancelled.length}`);
  for (const u of uncancelled) {
    console.log(`  #${u.orderNum} ${u.customer} amount=${u.amount} order_status=${u.orderStatus} payment=${u.paymentStatus}`);
  }
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });

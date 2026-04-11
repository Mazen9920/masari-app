#!/usr/bin/env node
/**
 * Re-link unmatched Bosta shipments to their Revvo sales.
 *
 * The Bosta businessReference format is  bd3cf0-3:#1319625
 * where the number after :# is  13 + shopify_order_number (e.g. 19625).
 * Some shipments were synced before the matching logic was correct.
 *
 * This script:
 *  1. Loads all sales into a byOrderNumber map
 *  2. For each unlinked shipment, tries to match via 2-char prefix strip
 *  3. Updates matched shipments (matched=true, sale_id=...)
 *  4. Updates matched sales (bosta_delivery_id, bosta_tracking_number)
 */
const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();
const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

async function main() {
  // Build sales lookup
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", uid)
    .select("shopify_order_number", "bosta_delivery_id")
    .get();

  const byOrderNumber = new Map();
  for (const doc of salesSnap.docs) {
    const num = String(doc.data().shopify_order_number);
    if (num) byOrderNumber.set(num, doc.id);
  }
  console.log("Sales loaded:", byOrderNumber.size);

  // Get all unlinked shipments
  const shipSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", uid)
    .where("matched", "==", false)
    .get();
  console.log("Unlinked shipments:", shipSnap.size);

  let linked = 0;
  let noSale = 0;
  let noRef = 0;
  let batch = db.batch();
  let ops = 0;

  for (const doc of shipSnap.docs) {
    const data = doc.data();
    const bizRef = data.business_reference;
    if (!bizRef) { noRef++; continue; }

    const m = bizRef.match(/#(\d+)/);
    if (!m) { noRef++; continue; }

    let rawRef = m[1];

    // Try exact match first
    let saleId = byOrderNumber.get(rawRef) || null;

    // Try stripping 1-4 char prefix (handles the "13" prefix)
    if (!saleId && rawRef.length > 4) {
      for (let prefixLen = 1; prefixLen <= 4; prefixLen++) {
        const stripped = rawRef.substring(prefixLen);
        if (stripped.length < 3) break;
        saleId = byOrderNumber.get(stripped) || null;
        if (saleId) {
          rawRef = stripped;
          break;
        }
      }
    }

    if (!saleId) { noSale++; continue; }

    // Update shipment
    batch.update(doc.ref, {
      matched: true,
      sale_id: saleId,
    });
    ops++;

    // Update sale with bosta delivery info
    const saleRef = db.doc(`sales/${saleId}`);
    batch.update(saleRef, {
      bosta_delivery_id: data.bosta_delivery_id || doc.id,
      bosta_tracking_number: data.tracking_number,
    });
    ops++;

    linked++;
    console.log(`  Linked #${rawRef} → sale ${saleId.slice(0, 20)}...`);

    if (ops >= 490) {
      await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0) {
    await batch.commit();
  }

  console.log("\n=== Re-link Complete ===");
  console.log(`Linked: ${linked}`);
  console.log(`No sale in Revvo: ${noSale}`);
  console.log(`No reference: ${noRef}`);
}

main().then(() => process.exit(0)).catch(e => { console.error("Error:", e); process.exit(1); });

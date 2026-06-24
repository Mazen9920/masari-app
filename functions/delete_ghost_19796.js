// Delete ghost Revvo sale 19796 (exists in Revvo but not in Shopify)
const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();

(async () => {
  const saleId = "shopify_EGYQnP7ughdUtTbn04UwUET534i1_7162721730880";
  const saleRef = db.collection("sales").doc(saleId);
  const saleSnap = await saleRef.get();
  if (!saleSnap.exists) { console.log("Sale not found, nothing to delete."); process.exit(0); }
  console.log("Sale found:", saleSnap.data().shopify_order_number || saleSnap.data().order_number);

  const txnSnap = await db.collection("transactions").where("sale_id", "==", saleId).get();
  console.log(`Linked txns: ${txnSnap.size}`);
  for (const t of txnSnap.docs) {
    console.log(`  - ${t.id}  cat=${t.data().category_id}  amt=${t.data().amount}`);
  }

  const batch = db.batch();
  for (const t of txnSnap.docs) batch.delete(t.ref);
  batch.delete(saleRef);
  await batch.commit();
  console.log("Deleted.");
  process.exit(0);
})();

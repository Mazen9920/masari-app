const admin = require("firebase-admin");
admin.initializeApp({credential: admin.credential.cert(require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))});
const db = admin.firestore();

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  
  // Check a few regular sales
  const snap = await db.collection("sales").where("user_id", "==", uid).limit(3).get();
  console.log("Sample sales:");
  snap.docs.forEach(d => {
    const data = d.data();
    console.log(`  ${d.id}: status=${data.status} order_status=${data.order_status} num=${data.shopify_order_number}`);
  });
  
  // Check known cancelled order from migration
  const cancelledIds = [
    "48defe8d-9129-436d-9eed-e0dfbf44920f", // #19466
    "90a89411-5dbf-4bde-b8f0-b62763fe60b5", // #19475
  ];
  console.log("\nKnown cancelled sales (from migration):");
  for (const id of cancelledIds) {
    const d = await db.collection("sales").doc(id).get();
    if (d.exists) {
      const data = d.data();
      console.log(`  ${d.id}: status=${data.status} order_status=${data.order_status} cancelled_at=${data.cancelled_at} num=${data.shopify_order_number}`);
    }
  }

  // Check webhook-created cancelled orders
  const webhookCancelled = [
    "shopify_EGYQnP7ughdUtTbn04UwUET534i1_7087282651456", // #19293
    "shopify_EGYQnP7ughdUtTbn04UwUET534i1_7111173046592", // #19563
  ];
  console.log("\nWebhook-created cancelled sales:");
  for (const id of webhookCancelled) {
    const d = await db.collection("sales").doc(id).get();
    if (d.exists) {
      const data = d.data();
      console.log(`  ${d.id}: status=${data.status} order_status=${data.order_status} cancelled_at=${data.cancelled_at} num=${data.shopify_order_number}`);
    }
  }

  process.exit(0);
})();

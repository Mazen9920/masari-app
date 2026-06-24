const admin = require("firebase-admin");
admin.initializeApp({ credential: admin.credential.cert(require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")) });
const db = admin.firestore();
(async () => {
  const s = await db.collection("sales").doc("adde5cb9-8601-4264-8792-e5430b6735f3").get();
  const data = s.data();
  console.log("Sale keys:", Object.keys(data).sort());
  console.log("First item:", JSON.stringify(data.items[0], null, 2));
  console.log("subtotal:", data.subtotal);
  console.log("total:", data.total);
  console.log("discount_amount:", data.discount_amount);
  console.log("tax_amount:", data.tax_amount);
  console.log("shipping_cost:", data.shipping_cost);
  process.exit(0);
})();

const admin = require("firebase-admin");
const sa = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

(async () => {
  const snap = await db.collection("sales")
    .where("user_id", "==", "EGYQnP7ughdUtTbn04UwUET534i1")
    .where("payment_method", "==", "Cash on Delivery (COD)")
    .limit(3)
    .get();

  for (const d of snap.docs) {
    const data = d.data();
    console.log("Sale:", d.id);
    console.log("Keys:", Object.keys(data).sort().join(", "));
    for (const k of Object.keys(data).sort()) {
      const v = data[k];
      if (typeof v === "number" || /total|amount|price|cost|paid|outstanding|subtotal/i.test(k)) {
        console.log("  ", k, "=", v);
      }
    }
    console.log("  order_status:", data.order_status);
    console.log("  payment_method:", data.payment_method);
    console.log("---");
  }
  process.exit(0);
})();

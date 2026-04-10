const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const snap = await db.collection("sales").where("user_id", "==", uid).get();
  
  const docIds = snap.docs.map(d => d.id);
  const shopifyIdDocs = docIds.filter(id => id.startsWith("shopify_"));
  const uuidDocs = docIds.filter(id => !id.startsWith("shopify_"));
  
  console.log("Total sales:", docIds.length);
  console.log("Shopify-ID docs:", shopifyIdDocs.length);
  console.log("UUID docs:", uuidDocs.length);
  
  if (shopifyIdDocs.length > 0) {
    console.log("Sample shopify doc IDs:", shopifyIdDocs.slice(0, 5));
  }
  
  // Check shopify fields on a UUID doc
  const uuidDoc = snap.docs.find(d => !d.id.startsWith("shopify_"));
  if (uuidDoc) {
    const data = uuidDoc.data();
    console.log("\nUUID doc fields (shopify-related):");
    Object.keys(data).filter(k => k.toLowerCase().includes("shopify") || k === "source" || k === "order_number").sort().forEach(k => {
      console.log(`  ${k}:`, data[k]);
    });
  }
  
  // Check a shopify doc
  const sDoc = snap.docs.find(d => d.id.startsWith("shopify_"));
  if (sDoc) {
    const data = sDoc.data();
    console.log("\nShopify doc fields (shopify-related):");
    Object.keys(data).filter(k => k.toLowerCase().includes("shopify") || k === "source" || k === "order_number").sort().forEach(k => {
      console.log(`  ${k}:`, data[k]);
    });
  }
  
  // Build order_number to Shopify ID mapping
  console.log("\nOrder number mapping (first 5):");
  snap.docs.slice(0, 10).forEach(d => {
    const data = d.data();
    console.log(`  docId=${d.id.substring(0, 30)}... orderNum=${data.shopify_order_number || data.order_number}`);
  });
  
  process.exit(0);
}

main().catch(console.error);

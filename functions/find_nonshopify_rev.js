const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const TARGET = process.argv[2] || "2026-05";
function cairoMonth(d){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit"}).formatToParts(new Date(d));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}`;}
(async()=>{
  const snap = await db.collection("transactions").where("user_id","==",UID).get();
  let nonShopify=0, count=0;
  for(const doc of snap.docs){
    const t=doc.data();
    if(t.category_id!=="cat_sales_revenue") continue;
    const dt=t.date_time?.toDate?.(); if(!dt) continue;
    if(cairoMonth(dt.toISOString())!==TARGET) continue;
    const sid=t.sale_id||"";
    if(!sid || !String(sid).startsWith("shopify_")){
      nonShopify += Number(t.amount)||0; count++;
      console.log(`${doc.id} | sale_id=${sid||"(none)"} | amt=${t.amount} | ${dt.toISOString()} | ${t.title}`);
    }
  }
  console.log(`\nNon-Shopify cat_sales_revenue in ${TARGET}: count=${count} total=${Math.round(nonShopify*100)/100}`);
  process.exit(0);
})();

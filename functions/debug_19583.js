const admin=require("firebase-admin"),crypto=require("crypto"),path=require("path");
admin.initializeApp({credential:admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")))});
const EK="9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(e,k){const[i,t,d]=e.split(":");const kb=Buffer.from(k,"hex");const iv=Buffer.from(i,"base64");const tg=Buffer.from(t,"base64");const da=Buffer.from(d,"base64");const c=crypto.createDecipheriv("aes-256-gcm",kb,iv);c.setAuthTag(tg);return c.update(da).toString("utf8")+c.final("utf8");}
const db=admin.firestore(),UID="EGYQnP7ughdUtTbn04UwUET534i1";
(async()=>{
const cn=(await db.collection("shopify_connections").doc(UID).get()).data();
const tk=decrypt(cn.access_token,EK);
const r=await fetch("https://"+cn.shop_domain+"/admin/api/2024-01/orders/7112654225728.json",{headers:{"X-Shopify-Access-Token":tk}});
const j=await r.json();
const o=j.order;
console.log("subtotal_price:",o.subtotal_price);
console.log("total_discounts:",o.total_discounts);
console.log("total_price:",o.total_price);
let gross=0;
for(const li of o.line_items){
  const p=Number(li.price),q=Number(li.quantity);
  gross+=p*q;
  console.log("  item:",li.title,"price="+li.price,"qty="+li.quantity,"discounts:",JSON.stringify(li.discount_allocations));
}
console.log("gross (sum price*qty):",gross);
for(const sl of(o.shipping_lines||[])){
  console.log("shipping: price="+sl.price+" discounted_price="+sl.discounted_price);
  console.log("  discount_allocations:",JSON.stringify(sl.discount_allocations));
}
const salesSnap=await db.collection("sales").where("external_order_id","==","7112654225728").where("user_id","==",UID).limit(1).get();
if(salesSnap.docs.length>0){
  const s=salesSnap.docs[0].data();
  console.log("\nRevvo sale:");
  console.log("  shipping_cost:",s.shipping_cost);
  console.log("  discount_amount:",s.discount_amount);
  let revSubtotal=0;
  for(const item of(s.items||[])){revSubtotal+=Number(item.unit_price)*Number(item.quantity);}
  console.log("  items subtotal:",revSubtotal);
  const revTxn=await db.collection("transactions").doc("sale_rev_"+salesSnap.docs[0].id).get();
  if(revTxn.exists)console.log("  revenue txn:",revTxn.data().amount);
}
process.exit(0);})();

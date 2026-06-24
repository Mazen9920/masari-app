/** Inspect Shopify discount structure for specific June orders to locate the missing 95/99. */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const TARGETS = new Set(["21492","21728","21717","21697","21590","21553","21499","21426","21200"]);
function decrypt(enc, key){const[a,b,c]=enc.split(":");const k=Buffer.from(key,"hex");const d=crypto.createDecipheriv("aes-256-gcm",k,Buffer.from(a,"base64"));d.setAuthTag(Buffer.from(b,"base64"));return d.update(Buffer.from(c,"base64")).toString("utf8")+d.final("utf8");}
async function main(){
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token,ENCRYPTION_KEY); const shop=conn.shop_domain;
  let orders=[]; let url=`https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2026-06-01T00:00:00Z`;
  while(url){const res=await fetch(url,{headers:{"X-Shopify-Access-Token":token}});const j=await res.json();orders=orders.concat(j.orders||[]);const link=res.headers.get("link")||"";const m=link.match(/<([^>]+)>;\s*rel="next"/);url=m?m[1]:null;}
  for(const o of orders){
    const num=String(o.order_number||o.name||"").replace("#","");
    if(!TARGETS.has(num)) continue;
    console.log(`\n=== #${num} (id ${o.id}) ===`);
    console.log(`  total_discounts=${o.total_discounts} subtotal_price=${o.subtotal_price} total_price=${o.total_price} total_line_items_price=${o.total_line_items_price}`);
    console.log(`  discount_codes=${JSON.stringify(o.discount_codes)}`);
    console.log(`  discount_applications=${JSON.stringify((o.discount_applications||[]).map(d=>({type:d.type,target:d.target_type,target_sel:d.target_selection,value_type:d.value_type,value:d.value,title:d.title,code:d.code})))}`);
    console.log(`  shipping_lines=${JSON.stringify((o.shipping_lines||[]).map(s=>({price:s.price,disc:s.discounted_price,alloc:s.discount_allocations})))}`);
    console.log(`  line_items disc=${JSON.stringify((o.line_items||[]).map(li=>({price:li.price,qty:li.quantity,total_discount:li.total_discount,alloc:li.discount_allocations})))}`);
  }
  process.exit(0);
}
main().catch(e=>{console.error(e);process.exit(1);});

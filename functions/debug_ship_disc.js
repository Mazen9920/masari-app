const admin=require("firebase-admin"),crypto=require("crypto"),path=require("path");
admin.initializeApp({credential:admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")))});
const EK="9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(e,k){const[i,t,d]=e.split(":");const kb=Buffer.from(k,"hex");const iv=Buffer.from(i,"base64");const tg=Buffer.from(t,"base64");const da=Buffer.from(d,"base64");const c=crypto.createDecipheriv("aes-256-gcm",kb,iv);c.setAuthTag(tg);return c.update(da).toString("utf8")+c.final("utf8");}
const db=admin.firestore(),UID="EGYQnP7ughdUtTbn04UwUET534i1";
const r2=n=>Math.round(n*100)/100;
(async()=>{
const cn=(await db.collection("shopify_connections").doc(UID).get()).data();
const tk=decrypt(cn.access_token,EK);
let all=[],url="https://"+cn.shop_domain+"/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2026-04-01T00:00:00%2B02:00&created_at_max=2026-04-30T23:59:59%2B02:00";
const r=await fetch(url,{headers:{"X-Shopify-Access-Token":tk}});
const j=await r.json();
all=j.orders||[];

const salesSnap=await db.collection("sales").where("user_id","==",UID).get();
const orderToSale={};
for(const doc of salesSnap.docs){const s=doc.data();if(s.external_order_id)orderToSale[s.external_order_id]=doc.id;}

const revSnap=await db.collection("transactions").where("user_id","==",UID).where("category_id","==","cat_sales_revenue").get();
const revBySale={};
for(const d of revSnap.docs){const t=d.data();revBySale[t.sale_id]=(revBySale[t.sale_id]||0)+(Number(t.amount)||0);}

let found=0;
for(const o of all){
  let sd=0;
  for(const sl of(o.shipping_lines||[])){sd+=(Number(sl.price)||0)-(Number(sl.discounted_price||sl.price)||0);}
  if(sd<=0)continue;
  const sid=orderToSale[String(o.id)];
  if(!sid){console.log("#"+o.order_number+": shipping discount="+sd+" but NOT in Revvo");continue;}
  let gross=0;
  for(const li of(o.line_items||[]))gross+=(Number(li.price)||0)*(Number(li.quantity)||0);
  const disc=Number(o.total_discounts)||0;
  const shopifyNet=r2(gross-disc);
  const revvoNet=r2(revBySale[sid]||0);
  console.log("#"+o.order_number+": gross="+gross+" disc="+disc+" shipDisc="+sd+" cancelled="+!!o.cancelled_at);
  console.log("  shopifyNet="+shopifyNet+" revvoNet="+revvoNet+" gap="+(revvoNet-shopifyNet));
  console.log("  subtotal_price="+o.subtotal_price);
  found++;
  if(found>=5)break;
}
if(!found)console.log("No April orders with shipping discount found in Revvo");
process.exit(0);})();

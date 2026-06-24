const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const TARGET = process.argv[2] || "2026-06";
function decrypt(enc){const[a,b,c]=enc.split(":");const d=crypto.createDecipheriv("aes-256-gcm",Buffer.from(KEY,"hex"),Buffer.from(a,"base64"));d.setAuthTag(Buffer.from(b,"base64"));return d.update(Buffer.from(c,"base64")).toString("utf8")+d.final("utf8");}
const r2=n=>Math.round(n*100)/100;
const fmt=n=>r2(n).toLocaleString("en",{minimumFractionDigits:2,maximumFractionDigits:2});
function cairoMonth(s){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit"}).formatToParts(new Date(s));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}`;}
(async()=>{
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token); const shop=conn.shop_domain;
  let orders=[]; let url=`https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while(url){const res=await fetch(url,{headers:{"X-Shopify-Access-Token":token}});const j=await res.json();orders=orders.concat(j.orders||[]);const l=res.headers.get("link")||"";const m=l.match(/<([^>]+)>;\s*rel="next"/);url=m?m[1]:null;await new Promise(r=>setTimeout(r,200));}

  // Variant A: returns attributed by ORDER created month (Shopify "by order date")
  let grossA=0,discA=0,retA=0,shipA=0,shipRefA=0;
  // Variant B: sum of total_price / current_total_price for orders created this month
  let sumTotalPrice=0, sumCurrentTotalPrice=0;
  for(const o of orders){
    const cm=cairoMonth(o.created_at);
    if(cm===TARGET){
      for(const li of o.line_items||[]) grossA+=(Number(li.price)||0)*(Number(li.quantity)||0);
      let sd=0; for(const sl of o.shipping_lines||[]){const g=Number(sl.price)||0,n=Number(sl.discounted_price??sl.price)||0;shipA+=n;sd+=g-n;}
      discA+=((Number(o.total_discounts)||0)-sd);
      sumTotalPrice+=Number(o.total_price)||0;
      sumCurrentTotalPrice+=Number(o.current_total_price)||0;
      // returns by order date = all refunds on this order
      for(const rf of o.refunds||[]){
        for(const ri of rf.refund_line_items||[]) retA+=Number(ri.subtotal)||0;
        for(const adj of rf.order_adjustments||[]) if(adj.kind==="shipping_refund") shipRefA+=Math.abs(Number(adj.amount)||0);
      }
    }
  }
  const totalA=r2((grossA-discA-retA)+(shipA-shipRefA));
  console.log(`\n${TARGET} Total sales — more variants (target ~336k):`);
  console.log(`  (A) Returns by ORDER date:                 ${fmt(totalA)}  (gross ${fmt(grossA)} disc ${fmt(discA)} ret ${fmt(retA)} ship ${fmt(shipA-shipRefA)})`);
  console.log(`  (B) Σ total_price (orders created ${TARGET}):     ${fmt(sumTotalPrice)}`);
  console.log(`  (C) Σ current_total_price (after refunds):  ${fmt(sumCurrentTotalPrice)}`);
  process.exit(0);
})();

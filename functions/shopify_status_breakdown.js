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

  // Net (gross-disc) attributed to order create month, minus refunds attributed to refund month
  // Bucket by financial_status, cancelled, test
  const byStatus={}; let cancelledNet=0, testNet=0, unpaidNet=0;
  let totalNet=0, totalShip=0;
  // Precompute per-order createMonth net and refund-month returns
  for(const o of orders){
    const cm=cairoMonth(o.created_at);
    let oNet=0, oShip=0;
    if(cm===TARGET){
      for(const li of o.line_items||[]) oNet+=(Number(li.price)||0)*(Number(li.quantity)||0);
      let sd=0; for(const sl of o.shipping_lines||[]){const g=Number(sl.price)||0,n=Number(sl.discounted_price??sl.price)||0;oShip+=n;sd+=g-n;}
      oNet-=((Number(o.total_discounts)||0)-sd);
    }
    let oRet=0, oShipRef=0;
    for(const rf of o.refunds||[]){ if(cairoMonth(rf.created_at||o.created_at)!==TARGET) continue;
      for(const ri of rf.refund_line_items||[]) oRet+=Number(ri.subtotal)||0;
      for(const adj of rf.order_adjustments||[]) if(adj.kind==="shipping_refund") oShipRef+=Math.abs(Number(adj.amount)||0);
    }
    const net=oNet-oRet; const ship=oShip-oShipRef;
    totalNet+=net; totalShip+=ship;
    const fs=o.financial_status||"unknown";
    byStatus[fs]=(byStatus[fs]||0)+net+ship;
    if(o.cancelled_at && cm===TARGET) cancelledNet+=oNet+oShip; // gross of cancelled created this month
    if(o.test) testNet+=net+ship;
    if((fs==="pending"||fs==="unpaid"||fs==="partially_paid") ) unpaidNet+=net+ship;
  }
  console.log(`\n${TARGET}  Total (Net+Ship) = ${fmt(totalNet+totalShip)}  (Net ${fmt(totalNet)} + Ship ${fmt(totalShip)})`);
  console.log(`\nBy financial_status (Net+Ship attributed):`);
  for(const [k,v] of Object.entries(byStatus).sort((a,b)=>b[1]-a[1])) console.log(`  ${k.padEnd(18)} ${fmt(v)}`);
  console.log(`\nCancelled orders gross (created ${TARGET}): ${fmt(cancelledNet)}`);
  console.log(`Test orders Net+Ship: ${fmt(testNet)}`);
  console.log(`Unpaid/pending/partial Net+Ship: ${fmt(unpaidNet)}`);
  console.log(`\nTotal MINUS unpaid/pending = ${fmt(totalNet+totalShip-unpaidNet)}`);
  process.exit(0);
})();

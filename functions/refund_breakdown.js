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
function cairoDay(s){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date(s));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}-${p.find(x=>x.type==="day").value}`;}
function cairoMonth(s){return cairoDay(s).slice(0,7);}
(async()=>{
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token); const shop=conn.shop_domain;
  let orders=[]; let url=`https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while(url){const res=await fetch(url,{headers:{"X-Shopify-Access-Token":token}});const j=await res.json();orders=orders.concat(j.orders||[]);const l=res.headers.get("link")||"";const m=l.match(/<([^>]+)>;\s*rel="next"/);url=m?m[1]:null;await new Promise(r=>setTimeout(r,200));}

  let lineItemReturns=0;   // Σ refund_line_items.subtotal
  let lineItemTax=0;
  let totalDiscountAdj=0;  // order_adjustments kind != shipping_refund (refund_discrepancy etc.)
  let shipRefundAdj=0;     // order_adjustments kind == shipping_refund
  const adjKinds={};
  let refundTxnTotal=0;    // Σ refund.transactions amount (actual money)
  const perDay={};
  for(const o of orders){
    for(const rf of o.refunds||[]){
      const rm=cairoMonth(rf.created_at||o.created_at);
      if(rm!==TARGET) continue;
      const day=cairoDay(rf.created_at||o.created_at);
      let liSub=0;
      for(const ri of rf.refund_line_items||[]){ liSub+=Number(ri.subtotal)||0; lineItemTax+=Number(ri.total_tax)||0; }
      lineItemReturns+=liSub;
      perDay[day]=(perDay[day]||0)+liSub;
      for(const adj of rf.order_adjustments||[]){
        const k=adj.kind||"?"; const amt=Math.abs(Number(adj.amount)||0);
        adjKinds[k]=(adjKinds[k]||0)+amt;
        if(k==="shipping_refund") shipRefundAdj+=amt; else totalDiscountAdj+=amt;
      }
      for(const tx of rf.transactions||[]){ if(tx.kind==="refund") refundTxnTotal+=Number(tx.amount)||0; }
    }
  }
  console.log(`\n${TARGET} REFUND breakdown from Orders API:`);
  console.log(`  Σ refund_line_items.subtotal (Revvo Returns): ${fmt(lineItemReturns)}`);
  console.log(`  Σ refund_line_items.total_tax:                ${fmt(lineItemTax)}`);
  console.log(`  order_adjustments by kind:`);
  for(const [k,v] of Object.entries(adjKinds)) console.log(`      ${k.padEnd(20)} ${fmt(v)}`);
  console.log(`  Σ refund.transactions(refund) actual money:   ${fmt(refundTxnTotal)}`);
  console.log(`\n  CSV Shopify Returns target: 97,309.20  (diff vs lineItems = ${fmt(97309.20-lineItemReturns)})`);
  console.log(`  CSV Shopify Shipping refunds: 8,198.00 (52,524 gross - 44,326)  vs API shipping_refund ${fmt(shipRefundAdj)} (diff ${fmt(8198-shipRefundAdj)})`);
  console.log(`\n  Returns + non-ship adjustments = ${fmt(lineItemReturns+totalDiscountAdj)}`);
  console.log(`\nPer-day line-item returns (compare to CSV):`);
  for(const d of Object.keys(perDay).sort()) console.log(`  ${d}  ${fmt(perDay[d])}`);
  process.exit(0);
})();

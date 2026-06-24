const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const DAYS = (process.argv[2]||"2026-06-07,2026-06-13,2026-06-18").split(",");
function decrypt(enc){const[a,b,c]=enc.split(":");const d=crypto.createDecipheriv("aes-256-gcm",Buffer.from(KEY,"hex"),Buffer.from(a,"base64"));d.setAuthTag(Buffer.from(b,"base64"));return d.update(Buffer.from(c,"base64")).toString("utf8")+d.final("utf8");}
const r2=n=>Math.round(n*100)/100;
const fmt=n=>r2(n).toLocaleString("en",{minimumFractionDigits:2,maximumFractionDigits:2});
function cairoDay(s){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date(s));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}-${p.find(x=>x.type==="day").value}`;}
(async()=>{
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token); const shop=conn.shop_domain;
  let orders=[]; let url=`https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while(url){const res=await fetch(url,{headers:{"X-Shopify-Access-Token":token}});const j=await res.json();orders=orders.concat(j.orders||[]);const l=res.headers.get("link")||"";const m=l.match(/<([^>]+)>;\s*rel="next"/);url=m?m[1]:null;await new Promise(r=>setTimeout(r,200));}

  for(const o of orders){
    for(const rf of o.refunds||[]){
      const day=cairoDay(rf.created_at||o.created_at);
      if(!DAYS.includes(day)) continue;
      let liSub=0; for(const ri of rf.refund_line_items||[]) liSub+=Number(ri.subtotal)||0;
      let txn=0; for(const tx of rf.transactions||[]) if(tx.kind==="refund") txn+=Number(tx.amount)||0;
      const adjs=(rf.order_adjustments||[]).map(a=>`${a.kind}:${a.amount}`).join(",");
      console.log(`#${o.order_number} ${day} cancelled_at=${o.cancelled_at?cairoDay(o.cancelled_at):"-"} fin=${o.financial_status}`);
      console.log(`   refund_line_items.subtotal=${fmt(liSub)}  refundTxn=${fmt(txn)}  adjustments=[${adjs}]  refundNote="${rf.note||""}"`);
      console.log(`   order: total_price=${o.total_price} current_total_price=${o.current_total_price} subtotal=${o.subtotal_price} current_subtotal=${o.current_subtotal_price} total_discounts=${o.total_discounts}`);
      console.log(`   line_items: ${(o.line_items||[]).map(li=>`${li.title}:${li.quantity}x${li.price}(fulfillable=${li.fulfillable_quantity})`).join(" | ")}`);
    }
  }
  process.exit(0);
})();

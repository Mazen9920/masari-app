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

  // Detect order edits: original total_line_items_price vs current sum of line_items.
  // Shopify keeps `current_subtotal_price` (after edits/refunds) and the order
  // also reports each line_item current quantity. The ORIGINAL subtotal at
  // creation = subtotal_price ONLY if never edited. When edited, Shopify updates
  // current_* fields. We compare gross of current line items vs current_subtotal.
  let editTotal=0; const edited=[];
  for(const o of orders){
    if(cairoMonth(o.created_at)!==TARGET) continue;
    if(o.cancelled_at) continue; // skip cancellations (counted as returns already)
    // Sum current line items gross (price*current_quantity) - their discounts
    let curGross=0;
    for(const li of o.line_items||[]){
      const q = (li.current_quantity!==undefined? Number(li.current_quantity): Number(li.quantity))||0;
      curGross += (Number(li.price)||0)*q;
    }
    const origGross = (o.line_items||[]).reduce((a,li)=>a+(Number(li.price)||0)*(Number(li.quantity)||0),0);
    const removed = r2(origGross - curGross);
    if(Math.abs(removed)>0.01){ edited.push({num:o.order_number, removed, origGross:r2(origGross), curGross:r2(curGross)}); editTotal+=removed; }
  }
  edited.sort((a,b)=>b.removed-a.removed);
  for(const e of edited) console.log(`#${e.num}  removed=${fmt(e.removed)}  (orig ${fmt(e.origGross)} -> cur ${fmt(e.curGross)})`);
  console.log(`\nEdited orders (items removed, non-cancelled): ${edited.length}  total removed = ${fmt(editTotal)}`);
  console.log(`Target extra returns to explain: 5,118.10`);
  process.exit(0);
})();

const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(enc){const[a,b,c]=enc.split(":");const d=crypto.createDecipheriv("aes-256-gcm",Buffer.from(KEY,"hex"),Buffer.from(a,"base64"));d.setAuthTag(Buffer.from(b,"base64"));return d.update(Buffer.from(c,"base64")).toString("utf8")+d.final("utf8");}
const r2=n=>Math.round(n*100)/100;
const fmt=n=>r2(n).toLocaleString("en",{minimumFractionDigits:2,maximumFractionDigits:2});
function cairoDay(s){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date(s));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}-${p.find(x=>x.type==="day").value}`;}
(async()=>{
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token); const shop=conn.shop_domain;
  const gql = async (query)=>{
    const res = await fetch(`https://${shop}/admin/api/2024-07/graphql.json`,{
      method:"POST", headers:{"X-Shopify-Access-Token":token,"Content-Type":"application/json"}, body:JSON.stringify({query})
    });
    return res.json();
  };
  let after=null, pages=0; const byDay={}; let count=0;
  do{
    const q=`{ orders(first:40, query:"updated_at:>=2026-06-05"${after?`, after:\"${after}\"`:""}) {
      pageInfo{hasNextPage endCursor}
      edges{ node{ name createdAt
        returns(first:10){ edges{ node{ name status createdAt
          returnLineItems(first:20){ edges{ node{ ... on ReturnLineItem { quantity
            fulfillmentLineItem{ lineItem{ discountedUnitPriceSet{shopMoney{amount}} } } } } } } } } }
      } }
    } }`;
    const j=await gql(q);
    if(j.errors){ console.log("GraphQL errors:", JSON.stringify(j.errors).slice(0,500)); break; }
    const c=j.data?.orders; if(!c) { console.log("resp:",JSON.stringify(j).slice(0,300)); break; }
    for(const e of c.edges){
      for(const re of e.node.returns.edges){
        const rn=re.node; const d=cairoDay(rn.createdAt); count++;
        let val=0; for(const li of rn.returnLineItems.edges){ const n=li.node; val+=Number(n.fulfillmentLineItem?.lineItem?.discountedUnitPriceSet?.shopMoney?.amount||0)*(n.quantity||0); }
        byDay[d]=(byDay[d]||0)+val;
        if(["2026-06-07","2026-06-13","2026-06-18"].includes(d)) console.log(`  ${d} ${e.node.name} return ${rn.name} status=${rn.status} value=${fmt(val)}`);
      }
    }
    after=c.pageInfo.hasNextPage?c.pageInfo.endCursor:null; pages++;
    await new Promise(r=>setTimeout(r,250));
  } while(after && pages<60);
  console.log(`\nTotal RMA returns found: ${count}`);
  for(const d of Object.keys(byDay).sort()) console.log(`  ${d}: ${fmt(byDay[d])}`);
  process.exit(0);
})();

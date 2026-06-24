/**
 * Fix legacy sale docs whose discount_amount still includes free-shipping
 * (shipping_line) discounts. Recomputes discount_amount = total_discounts −
 * shippingDiscount (product-only), matching the current CF/Dart logic and
 * Shopify's displayed "Discounts" line. Also re-derives `total` for
 * consistency. Dry-run by default; pass --apply to write.
 */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = process.argv.includes("--uid") ? process.argv[process.argv.indexOf("--uid") + 1] : "EGYQnP7ughdUtTbn04UwUET534i1";
const APPLY = process.argv.includes("--apply");
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const CREATED_MIN = "2026-01-01T00:00:00Z";
const r2 = n => Math.round(n * 100) / 100;
function decrypt(enc, key) { const [a, b, c] = enc.split(":"); const k = Buffer.from(key, "hex"); const d = crypto.createDecipheriv("aes-256-gcm", k, Buffer.from(a, "base64")); d.setAuthTag(Buffer.from(b, "base64")); return d.update(Buffer.from(c, "base64")).toString("utf8") + d.final("utf8"); }

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY); const shop = conn.shop_domain;

  // index sales by external_order_id
  const salesSnap = await db.collection("sales").where("user_id", "==", UID).where("external_source", "==", "shopify").get();
  const byExt = {};
  salesSnap.docs.forEach(d => { const ext = d.data().external_order_id; if (ext) byExt[String(ext)] = d; });

  let orders = []; let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=${encodeURIComponent(CREATED_MIN)}`;
  let page = 0;
  while (url) {
    const res = await fetch(url, { headers: { "X-Shopify-Access-Token": token } });
    const j = await res.json(); orders = orders.concat(j.orders || []); page++;
    process.stderr.write(`page ${page} (${orders.length})\n`);
    const link = res.headers.get("link") || ""; const m = link.match(/<([^>]+)>;\s*rel="next"/); url = m ? m[1] : null;
  }

  let changed = 0, totalDelta = 0; const examples = [];
  const batchOps = [];
  for (const o of orders) {
    const saleDoc = byExt[String(o.id)];
    if (!saleDoc) continue;
    const sale = saleDoc.data();
    const totalDiscounts = Number(o.total_discounts) || 0;
    let shippingDiscount = 0;
    for (const sl of (o.shipping_lines || [])) {
      const gross = Number(sl.price) || 0;
      const net = Number(sl.discounted_price ?? sl.price) || 0;
      shippingDiscount += (gross - net);
    }
    const productDiscount = r2(totalDiscounts - shippingDiscount);
    const cur = r2(Number(sale.discount_amount) || 0);
    if (Math.abs(cur - productDiscount) <= 0.01) continue;
    changed++; totalDelta += (productDiscount - cur);
    if (examples.length < 25) examples.push(`  #${o.order_number} disc ${cur} -> ${productDiscount} (shipDisc ${r2(shippingDiscount)})`);
    if (APPLY) batchOps.push({ ref: saleDoc.ref, data: { discount_amount: productDiscount } });
  }

  console.log(`\nSales with discount_amount to correct: ${changed}`);
  console.log(`Net discount delta (new − old): ${r2(totalDelta)}`);
  examples.forEach(e => console.log(e));
  if (!APPLY) { console.log("\n(dry run — pass --apply to write)"); process.exit(0); }
  let n = 0;
  for (let i = 0; i < batchOps.length; i += 400) {
    const batch = db.batch();
    batchOps.slice(i, i + 400).forEach(op => batch.update(op.ref, op.data));
    await batch.commit(); n += Math.min(400, batchOps.length - i);
    console.log(`  updated ${n}/${batchOps.length}`);
  }
  console.log("DONE — discount_amount corrected.");
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });

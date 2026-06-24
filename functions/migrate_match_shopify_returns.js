/**
 * migrate_match_shopify_returns.js
 *
 * Brings Revvo's Sales → Returns in line with Shopify's Sales report by
 * fixing three classes of historical data issues (see shopify_revenue_audit.md
 * "June 2026 reconciliation"):
 *
 *   ① OPEN RMA returns  — `sale_return_{saleId}_{returnId}` txns (note
 *      "Return (open)") have NO Shopify refund yet. Shopify Net Sales does
 *      not deduct them, so set exclude_from_pl=true (track but don't reduce
 *      net sales until a refund is issued).
 *
 *   ② CANCEL+REFUND double-count — a cancelled order has BOTH a full
 *      `sale_rev_{saleId}_reversal` AND a `sale_refund_{saleId}_*`, deducting
 *      revenue twice. Recompute reversal = -max(0, origRev - Σrefunds) so the
 *      order nets to (original - refunded) and the return is counted once.
 *
 *   ③ MIS-DATED reversal / missing refund — a cancelled order whose Shopify
 *      refund exists but Revvo only has a reversal dated to the ORIGINAL
 *      month. Create the missing `sale_refund_*` at refund.created_at (so the
 *      return lands in the refund's month, like Shopify) and recompute the
 *      reversal (usually → 0).
 *
 * Usage:
 *   node migrate_match_shopify_returns.js                # DRY RUN
 *   node migrate_match_shopify_returns.js --apply
 *   node migrate_match_shopify_returns.js --apply --uid <UID>
 */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))
  ),
});
const db = admin.firestore();

const APPLY = process.argv.includes("--apply");
const uidArg = process.argv.indexOf("--uid");
const UID = uidArg !== -1 ? process.argv[uidArg + 1] : "EGYQnP7ughdUtTbn04UwUET534i1";
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const CREATED_MIN = "2026-01-01T00:00:00Z";

const r2 = n => Math.round(n * 100) / 100;
function decrypt(enc, key) {
  const [iv, tag, data] = enc.split(":");
  const d = crypto.createDecipheriv("aes-256-gcm", Buffer.from(key, "hex"), Buffer.from(iv, "base64"));
  d.setAuthTag(Buffer.from(tag, "base64"));
  return d.update(Buffer.from(data, "base64")).toString("utf8") + d.final("utf8");
}
const ts = dateStr => admin.firestore.Timestamp.fromDate(new Date(dateStr));

async function fetchAllOrders(shop, token) {
  let orders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=${encodeURIComponent(CREATED_MIN)}`;
  while (url) {
    const res = await fetch(url, { headers: { "X-Shopify-Access-Token": token } });
    const j = await res.json();
    orders = orders.concat(j.orders || []);
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise(r => setTimeout(r, 150));
  }
  return orders;
}

async function main() {
  console.log(`\n=== migrate_match_shopify_returns ${APPLY ? "(APPLY)" : "(DRY RUN)"} uid=${UID} ===\n`);
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  if (!conn?.access_token || !conn?.shop_domain) { console.log("No Shopify connection"); process.exit(1); }
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  const shop = conn.shop_domain;

  const orders = await fetchAllOrders(shop, token);
  console.log(`Fetched ${orders.length} Shopify orders\n`);

  // sales by external_order_id
  const salesSnap = await db.collection("sales").where("user_id", "==", UID).get();
  const saleByExt = {};
  salesSnap.docs.forEach(d => {
    const s = d.data();
    if (s.external_order_id) saleByExt[String(s.external_order_id)] = { id: d.id, data: s };
  });
  const txnCol = db.collection("transactions");

  const stats = {
    openReturnsExcluded: 0, openReturnsValue: 0,
    refundsCreated: 0, refundsValue: 0,
    shipRefundsCreated: 0,
    revReversalsFixed: 0, revReversalDelta: 0,
    shipReversalsFixed: 0,
    reversalsRedated: 0,
  };

  // ── ① Exclude all open RMA return txns ──
  const returnSnap = await txnCol.where("user_id", "==", UID).where("category_id", "==", "cat_sales_revenue").get();
  for (const doc of returnSnap.docs) {
    if (!/^sale_return_.*_/.test(doc.id)) continue;
    if (doc.data().exclude_from_pl === true) continue;
    stats.openReturnsExcluded++;
    stats.openReturnsValue += Math.abs(Number(doc.data().amount) || 0);
    if (APPLY) await doc.ref.update({ exclude_from_pl: true, updated_at: admin.firestore.Timestamp.now() });
  }

  // ── ②/③ Per cancelled order: ensure refunds + recompute reversals ──
  for (const o of orders) {
    const sale = saleByExt[String(o.id)];
    if (!sale) continue;
    const isCancelled = !!o.cancelled_at || sale.data.order_status === 4;
    const refunds = o.refunds || [];
    if (!isCancelled && refunds.length === 0) continue;
    const saleId = sale.id;

    // GUARD: only book returns for orders that actually have recorded
    // revenue in Revvo. Orders before the import range (origRev=0) have
    // no sale_rev txn — creating a refund there would be a phantom
    // net-new deduction. Skip those entirely.
    const revProbe = await txnCol.doc(`sale_rev_${saleId}`).get();
    const hasRecordedRevenue = revProbe.exists &&
      Math.abs(Number(revProbe.data().amount) || 0) > 0;
    if (!hasRecordedRevenue) continue;

    // Create missing post-cancellation refund txns (only for cancelled orders)
    if (isCancelled) {
      for (const rf of refunds) {
        const rid = String(rf.id || "");
        if (!rid) continue;
        let prod = 0, qty = 0;
        for (const ri of (rf.refund_line_items || [])) { prod += Number(ri.subtotal) || 0; qty += Number(ri.quantity) || 0; }
        let ship = 0;
        for (const adj of (rf.order_adjustments || [])) if (adj.kind === "shipping_refund") ship += Math.abs(Number(adj.amount) || 0);
        prod = r2(prod); ship = r2(ship);
        const refundDate = rf.created_at || o.created_at;

        if (prod > 0) {
          const refundTxnId = `sale_refund_${saleId}_${rid}`;
          const ex = await txnCol.doc(refundTxnId).get();
          if (!ex.exists) {
            stats.refundsCreated++; stats.refundsValue += prod;
            console.log(`  + refund #${o.order_number} ${refundTxnId} -${prod} @ ${refundDate}`);
            if (APPLY) await txnCol.doc(refundTxnId).set({
              id: refundTxnId, user_id: UID,
              title: `Refund — #${o.order_number || o.name || ""} — Shopify`,
              amount: -prod, date_time: ts(refundDate), category_id: "cat_sales_revenue",
              note: `Refund issued after cancellation (${qty} items)`,
              payment_method: "shopify", sale_id: saleId, shopify_refund_id: rid,
              exclude_from_pl: false, created_at: admin.firestore.Timestamp.now(),
            });
          }
        }
        if (ship > 0) {
          const shipRefundId = `sale_ship_refund_${saleId}_${rid}`;
          const ex = await txnCol.doc(shipRefundId).get();
          if (!ex.exists) {
            stats.shipRefundsCreated++;
            if (APPLY) await txnCol.doc(shipRefundId).set({
              id: shipRefundId, user_id: UID,
              title: `Shipping Refund — #${o.order_number || o.name || ""} — Shopify`,
              amount: -ship, date_time: ts(refundDate), category_id: "cat_shipping",
              note: `Refund issued after cancellation (${qty} items)`,
              payment_method: "shopify", sale_id: saleId, shopify_refund_id: rid,
              exclude_from_pl: false, created_at: admin.firestore.Timestamp.now(),
            });
          }
        }
      }
    }

    if (!isCancelled) continue;

    // Recompute revenue reversal from full refund set
    const revSnap = await txnCol.where("sale_id", "==", saleId).where("category_id", "==", "cat_sales_revenue").get();
    let origRev = 0, refundedRev = 0;
    revSnap.docs.forEach(d => {
      const amt = Number(d.data().amount) || 0;
      if (d.id === `sale_rev_${saleId}`) origRev = Math.abs(amt);
      else if (d.id.startsWith(`sale_refund_${saleId}_`) && !d.data().exclude_from_pl) refundedRev += Math.abs(amt);
    });
    // include refunds we are about to create in dry-run accounting
    if (!APPLY) {
      for (const rf of refunds) {
        const rid = String(rf.id || "");
        const exists = revSnap.docs.some(d => d.id === `sale_refund_${saleId}_${rid}`);
        if (!exists) { let p = 0; for (const ri of (rf.refund_line_items || [])) p += Number(ri.subtotal) || 0; refundedRev += r2(p); }
      }
    }
    if (origRev > 0) {
      const revRevRef = txnCol.doc(`sale_rev_${saleId}_reversal`);
      const revRevSnap = await revRevRef.get();
      if (revRevSnap.exists) {
        const target = r2(Math.max(0, origRev - refundedRev));
        const newAmount = target > 0 ? -target : 0;
        const cur = Number(revRevSnap.data().amount) || 0;
        const reDate = o.cancelled_at ? ts(o.cancelled_at) : revRevSnap.data().date_time;
        const curDate = revRevSnap.data().date_time;
        const needAmt = cur !== newAmount;
        const needDate = o.cancelled_at && curDate && curDate.toDate &&
          curDate.toDate().getTime() !== new Date(o.cancelled_at).getTime();
        if (needAmt || needDate) {
          if (needAmt) { stats.revReversalsFixed++; stats.revReversalDelta += (newAmount - cur); console.log(`  ~ rev reversal #${o.order_number} ${cur} -> ${newAmount} (origRev=${origRev} refunded=${r2(refundedRev)})`); }
          if (needDate) { stats.reversalsRedated++; }
          if (APPLY) await revRevRef.update({
            amount: newAmount, date_time: reDate,
            note: refundedRev > 0 ? "Auto-reversal — Shopify order cancelled (adjusted for post-cancellation refunds)" : "Auto-reversal — Shopify order cancelled",
            updated_at: admin.firestore.Timestamp.now(),
          });
        }
      }
    }

    // Recompute shipping reversal
    const shipSnap = await txnCol.where("sale_id", "==", saleId).where("category_id", "==", "cat_shipping").get();
    let origShip = 0, refundedShip = 0;
    shipSnap.docs.forEach(d => {
      const amt = Number(d.data().amount) || 0;
      if (d.id === `sale_ship_${saleId}`) origShip = Math.abs(amt);
      else if (d.id.startsWith(`sale_ship_refund_${saleId}_`) && !d.data().exclude_from_pl) refundedShip += Math.abs(amt);
    });
    if (origShip > 0) {
      const shipRevRef = txnCol.doc(`sale_ship_${saleId}_reversal`);
      const shipRevSnap = await shipRevRef.get();
      if (shipRevSnap.exists) {
        const target = r2(Math.max(0, origShip - refundedShip));
        const newAmount = target > 0 ? -target : 0;
        const cur = Number(shipRevSnap.data().amount) || 0;
        if (cur !== newAmount) {
          stats.shipReversalsFixed++;
          if (APPLY) await shipRevRef.update({
            amount: newAmount, date_time: o.cancelled_at ? ts(o.cancelled_at) : shipRevSnap.data().date_time,
            note: refundedShip > 0 ? "Auto-reversal — Shopify order cancelled (adjusted for post-cancellation shipping refund)" : "Auto-reversal — Shopify order cancelled",
            updated_at: admin.firestore.Timestamp.now(),
          });
        }
      }
    }
  }

  console.log(`\n── SUMMARY ${APPLY ? "(APPLIED)" : "(dry run)"} ──`);
  console.log(`① open returns excluded:      ${stats.openReturnsExcluded}  (value ${r2(stats.openReturnsValue)})`);
  console.log(`③ refund txns created:        ${stats.refundsCreated}  (value ${r2(stats.refundsValue)})`);
  console.log(`   ship refund txns created:  ${stats.shipRefundsCreated}`);
  console.log(`② rev reversals recomputed:   ${stats.revReversalsFixed}  (Δ ${r2(stats.revReversalDelta)})`);
  console.log(`   ship reversals recomputed: ${stats.shipReversalsFixed}`);
  console.log(`   reversals re-dated:        ${stats.reversalsRedated}`);
  if (!APPLY) console.log(`\nRe-run with --apply to write changes.`);
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });

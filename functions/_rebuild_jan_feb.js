/**
 * Rebuild Jan+Feb from xlsm-accurate data (fixes returns-ignored revenue).
 * DRY RUN by default; --commit to apply.
 *
 * Deletes today-imported (created_at >= 2026-06-22) transactions dated
 * 2026-01-01..2026-02-28 EXCEPT cat_bosta_cashout (cash receipts kept), then
 * writes rows from rebuild_jan_feb.json (sales Jan1-Feb14 + expenses Jan+Feb).
 * Revvo's live Feb15+ Shopify sync (created earlier) is never touched.
 */
const fs = require('fs');
const crypto = require('crypto');
const admin = require('firebase-admin');

const SA = '/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json';
const JSON_PATH = '/Users/mazen/Downloads/rebuild_jan_feb.json';
const UID = 'EGYQnP7ughdUtTbn04UwUET534i1';
const COMMIT = process.argv.includes('--commit');
const TODAY = new Date('2026-06-22T00:00:00Z');

admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
const db = admin.firestore();

async function main() {
  const data = JSON.parse(fs.readFileSync(JSON_PATH, 'utf8'));
  const rows = [...data.sales, ...data.expenses];

  // ── Identify rows to DELETE ──
  const snap = await db.collection('transactions').where('user_id', '==', UID).get();
  const toDelete = [];
  snap.docs.forEach(d => {
    const x = d.data();
    let ca = null, dt = null;
    try { ca = x.created_at.toDate(); } catch (e) {}
    try { dt = x.date_time.toDate(); } catch (e) {}
    if (!ca || !dt) return;
    const day = dt.toISOString().slice(0, 10);
    if (ca >= TODAY && day >= '2026-01-01' && day <= '2026-02-28' && x.category_id !== 'cat_bosta_cashout') {
      toDelete.push(d.ref);
    }
  });

  // ── Build new docs ──
  const docs = rows.map(r => {
    const dt = new Date(r.date + 'T12:00:00+02:00');
    return {
      id: crypto.randomUUID(), user_id: UID, title: r.title,
      amount: Math.round(r.amount * 100) / 100,
      date_time: admin.firestore.Timestamp.fromDate(dt),
      category_id: r.category_id, note: r.note || null,
      payment_method: r.category_id === 'cat_sales_revenue' || r.category_id === 'cat_cogs' ? 'Cash' : 'Bank',
      supplier_id: null, sale_id: null,
      exclude_from_pl: !!r.exclude_from_pl,
      is_estimate: false, is_reconciliation: false,
      created_at: admin.firestore.Timestamp.now(),
    };
  });

  console.log('=== REBUILD JAN+FEB —', COMMIT ? 'COMMIT' : 'DRY RUN', '===');
  console.log('Rows to DELETE (today-imported Jan1-Feb28, excl bosta):', toDelete.length);
  console.log('Rows to WRITE from xlsm:', docs.length,
    '(sales', data.sales.length, '+ expenses', data.expenses.length, ')');

  if (!COMMIT) { console.log('\nDRY RUN — nothing changed. Add --commit to apply.'); process.exit(0); }

  let del = 0;
  for (let i = 0; i < toDelete.length; i += 450) {
    const b = db.batch();
    toDelete.slice(i, i + 450).forEach(ref => b.delete(ref));
    await b.commit(); del += Math.min(450, toDelete.length - i);
    console.log('  deleted', del, '/', toDelete.length);
  }
  let wr = 0;
  const col = db.collection('transactions');
  for (let i = 0; i < docs.length; i += 450) {
    const b = db.batch();
    docs.slice(i, i + 450).forEach(d => b.set(col.doc(d.id), d));
    await b.commit(); wr += Math.min(450, docs.length - i);
    console.log('  wrote', wr, '/', docs.length);
  }
  console.log('\nDONE. Deleted', del, 'wrote', wr);
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });

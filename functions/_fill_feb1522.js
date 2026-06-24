/**
 * Fill Feb 15-22 sales/COGS from xlsm (Revvo's sync missed this window).
 * Deletes existing Feb15-22 cat_sales_revenue/cat_cogs/cat_shipping rows (the
 * ~23 stray sync rows), then writes xlsm rows from feb1522.json.
 * DRY RUN by default; --commit to apply.
 */
const fs = require('fs');
const crypto = require('crypto');
const admin = require('firebase-admin');
const SA = '/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json';
const UID = 'EGYQnP7ughdUtTbn04UwUET534i1';
const COMMIT = process.argv.includes('--commit');
admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
const db = admin.firestore();
const SALECATS = new Set(['cat_sales_revenue', 'cat_cogs', 'cat_shipping']);

async function main() {
  const data = JSON.parse(fs.readFileSync('/Users/mazen/Downloads/feb1522.json', 'utf8'));
  const snap = await db.collection('transactions').where('user_id', '==', UID).get();
  const toDelete = [];
  snap.docs.forEach(d => {
    const x = d.data(); let dt; try { dt = x.date_time.toDate(); } catch (e) { return; }
    const day = dt.toISOString().slice(0, 10);
    if (day >= '2026-02-15' && day <= '2026-02-22' && SALECATS.has(x.category_id)) toDelete.push({ ref: d.ref, t: x.title, a: x.amount });
  });
  const docs = data.sales.map(r => {
    const dt = new Date(r.date + 'T12:00:00+02:00');
    return {
      id: crypto.randomUUID(), user_id: UID, title: r.title, amount: Math.round(r.amount * 100) / 100,
      date_time: admin.firestore.Timestamp.fromDate(dt), category_id: r.category_id, note: r.note || null,
      payment_method: 'Cash', supplier_id: null, sale_id: null, exclude_from_pl: false,
      is_estimate: false, is_reconciliation: false, created_at: admin.firestore.Timestamp.now(),
    };
  });
  console.log('=== FEB 15-22 FILL —', COMMIT ? 'COMMIT' : 'DRY RUN', '===');
  console.log('Existing Feb15-22 sale rows to DELETE:', toDelete.length);
  toDelete.forEach(x => console.log('   -', x.t, x.a));
  console.log('xlsm rows to WRITE:', docs.length);
  if (!COMMIT) { console.log('\nDRY RUN — add --commit to apply.'); process.exit(0); }
  let del = 0;
  for (let i = 0; i < toDelete.length; i += 450) {
    const b = db.batch(); toDelete.slice(i, i + 450).forEach(x => b.delete(x.ref)); await b.commit();
    del += Math.min(450, toDelete.length - i);
  }
  let wr = 0; const col = db.collection('transactions');
  for (let i = 0; i < docs.length; i += 450) {
    const b = db.batch(); docs.slice(i, i + 450).forEach(d => b.set(col.doc(d.id), d)); await b.commit();
    wr += Math.min(450, docs.length - i); console.log('  wrote', wr, '/', docs.length);
  }
  console.log('\nDONE. Deleted', del, 'wrote', wr);
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });

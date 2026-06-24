/**
 * Match the finance sheet's P&L exactly for Jan + Feb.
 * Jan: delete today-added cat_shipping (revert to net 145).
 * Feb: delete ALL Feb transactions except cat_bosta_cashout (cash receipts),
 *      then write full Feb from xlsm (feb_full.json) -> net 76,445.
 * DRY RUN by default; --commit to apply.
 */
const fs = require('fs');
const crypto = require('crypto');
const admin = require('firebase-admin');
const SA = '/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json';
const UID = 'EGYQnP7ughdUtTbn04UwUET534i1';
const COMMIT = process.argv.includes('--commit');
const TODAY = new Date('2026-06-22T00:00:00Z');
admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
const db = admin.firestore();

async function main() {
  const feb = JSON.parse(fs.readFileSync('/Users/mazen/Downloads/feb_full.json', 'utf8'));
  const rows = [...feb.sales, ...feb.expenses];
  const snap = await db.collection('transactions').where('user_id', '==', UID).get();

  const delJanShip = [], delFeb = [];
  snap.docs.forEach(d => {
    const x = d.data();
    let dt, ca; try { dt = x.date_time.toDate(); ca = x.created_at.toDate(); } catch (e) { return; }
    const day = dt.toISOString().slice(0, 10);
    // Jan shipping added today
    if (day >= '2026-01-01' && day <= '2026-01-31' && x.category_id === 'cat_shipping' && ca >= TODAY) delJanShip.push(d.ref);
    // ALL Feb except bosta cashout
    if (day >= '2026-02-01' && day <= '2026-02-28' && x.category_id !== 'cat_bosta_cashout') delFeb.push(d.ref);
  });

  const docs = rows.map(r => {
    const dt = new Date(r.date + 'T12:00:00+02:00');
    return {
      id: crypto.randomUUID(), user_id: UID, title: r.title, amount: Math.round(r.amount * 100) / 100,
      date_time: admin.firestore.Timestamp.fromDate(dt), category_id: r.category_id, note: r.note || null,
      payment_method: r.category_id === 'cat_sales_revenue' || r.category_id === 'cat_cogs' ? 'Cash' : 'Bank',
      supplier_id: null, sale_id: null, exclude_from_pl: !!r.exclude_from_pl,
      is_estimate: false, is_reconciliation: false, created_at: admin.firestore.Timestamp.now(),
    };
  });

  console.log('=== MATCH SHEET (Jan 145 / Feb 76445) —', COMMIT ? 'COMMIT' : 'DRY RUN', '===');
  console.log('Jan cat_shipping to DELETE:', delJanShip.length);
  console.log('Feb rows to DELETE (all except bosta_cashout):', delFeb.length);
  console.log('Feb rows to WRITE from xlsm:', docs.length, '(sales', feb.sales.length, '+ expenses', feb.expenses.length, ')');
  if (!COMMIT) { console.log('\nDRY RUN — add --commit to apply.'); process.exit(0); }

  const allDel = [...delJanShip, ...delFeb];
  let del = 0;
  for (let i = 0; i < allDel.length; i += 450) { const b = db.batch(); allDel.slice(i, i + 450).forEach(r => b.delete(r)); await b.commit(); del += Math.min(450, allDel.length - i); console.log('  deleted', del, '/', allDel.length); }
  let wr = 0; const col = db.collection('transactions');
  for (let i = 0; i < docs.length; i += 450) { const b = db.batch(); docs.slice(i, i + 450).forEach(d => b.set(col.doc(d.id), d)); await b.commit(); wr += Math.min(450, docs.length - i); console.log('  wrote', wr, '/', docs.length); }
  console.log('\nDONE. Deleted', del, 'wrote', wr);
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });

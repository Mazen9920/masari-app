/**
 * Revvo historical backfill importer (Jan–Mar 2026 gap).
 *
 * DRY RUN by default. Pass --commit to actually write.
 * Flags:
 *   --commit              actually write transactions to Firestore
 *   --skip-feb-overlap    do NOT import Shopify sales/cogs/shipping dated
 *                         2026-02-15..2026-02-22 (avoids the 23 partial rows
 *                         already in Revvo). Recommended unless you first
 *                         delete those partial rows.
 *   --link-suppliers      set supplier_id on cat_supplier_payment rows (will
 *                         affect current supplier balances — off by default).
 *
 * Reads: ~/Downloads/revvo_transactions (1).csv
 */
const fs = require('fs');
const crypto = require('crypto');
const admin = require('firebase-admin');

const SA = '/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json';
const CSV = '/Users/mazen/Downloads/revvo_transactions (1).csv';
const UID = 'EGYQnP7ughdUtTbn04UwUET534i1';

const COMMIT = process.argv.includes('--commit');
const SKIP_FEB_OVERLAP = process.argv.includes('--skip-feb-overlap');
const LINK_SUPPLIERS = process.argv.includes('--link-suppliers');

admin.initializeApp({ credential: admin.credential.cert(require(SA)) });
const db = admin.firestore();

function parseCSV(line) {
  const out = [];
  let cur = '';
  let q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"') { q = !q; continue; }
    if (c === ',' && !q) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  out.push(cur);
  return out;
}

const SHOPIFY_CATS = new Set(['cat_sales_revenue', 'cat_cogs', 'cat_shipping']);

async function main() {
  const raw = fs.readFileSync(CSV, 'utf8');
  const lines = raw.split(/\r?\n/).filter(l => l.trim().length);
  const header = lines[0].split(',').map(h => h.trim());
  const idx = {};
  header.forEach((h, i) => (idx[h] = i));

  // supplier name -> id map (existing suppliers)
  const supSnap = await db.collection('suppliers').where('user_id', '==', UID).get();
  const supByName = {};
  supSnap.docs.forEach(d => {
    const n = (d.data().name || '').trim().toLowerCase();
    if (n) supByName[n] = d.id;
  });

  const docs = [];
  const stats = {
    considered: 0,
    skippedAction: 0,
    skippedFebOverlap: 0,
    byCategory: {},
    byMonth: {},
    supplierPaymentRows: 0,
    supplierLinked: 0,
    supplierUnmatched: new Set(),
    cashIncome: 0,
  };

  for (let i = 1; i < lines.length; i++) {
    const f = parseCSV(lines[i]);
    const action = f[idx.action];
    if (action !== 'import') { stats.skippedAction++; continue; }
    stats.considered++;

    const date = f[idx.date];
    const amount = parseFloat(f[idx.amount]);
    const category_id = f[idx.category_id];
    // Supplier payments are inventory purchases (COGS hits P&L per-sale), so they
    // must be excluded from P&L. cat_supplier_payment is NOT in plExcludedCats,
    // so Revvo relies on the per-row exclude_from_pl flag — force it true here.
    const exclude = f[idx.exclude_from_pl] === 'true' || category_id === 'cat_supplier_payment';
    const title = f[idx.title] || '';
    const note = f[idx.note] || null;
    const payment = f[idx.payment_method] || 'Cash';
    const supplierName = (f[idx.supplier_name] || '').trim();

    // Feb 15-22 Shopify overlap guard
    if (SHOPIFY_CATS.has(category_id) && date >= '2026-02-15' && date <= '2026-02-22') {
      if (SKIP_FEB_OVERLAP) { stats.skippedFebOverlap++; continue; }
    }

    let supplier_id = null;
    if (category_id === 'cat_supplier_payment') {
      stats.supplierPaymentRows++;
      if (LINK_SUPPLIERS && supplierName) {
        const sid = supByName[supplierName.toLowerCase()];
        if (sid) { supplier_id = sid; stats.supplierLinked++; }
        else stats.supplierUnmatched.add(supplierName);
      } else if (supplierName) {
        stats.supplierUnmatched.add(supplierName);
      }
    }
    if (title === 'Cash Income') stats.cashIncome++;

    // build date_time at noon local (UTC+2) to keep calendar day stable
    const dt = new Date(date + 'T12:00:00+02:00');

    const doc = {
      id: crypto.randomUUID(),
      user_id: UID,
      title: title,
      amount: Math.round(amount * 100) / 100,
      date_time: admin.firestore.Timestamp.fromDate(dt),
      category_id: category_id,
      note: note,
      payment_method: payment,
      supplier_id: supplier_id,
      sale_id: null,
      exclude_from_pl: exclude,
      is_estimate: false,
      is_reconciliation: false,
      created_at: admin.firestore.Timestamp.now(),
    };
    docs.push(doc);

    stats.byCategory[category_id] = (stats.byCategory[category_id] || 0) + 1;
    const m = date.slice(0, 7);
    stats.byMonth[m] = (stats.byMonth[m] || 0) + 1;
  }

  // ── Report ──
  console.log('=== REVVO HISTORICAL IMPORT —', COMMIT ? 'COMMIT' : 'DRY RUN', '===\n');
  console.log('Rows with action=import considered:', stats.considered);
  console.log('Rows skipped (action!=import):', stats.skippedAction);
  console.log('Skipped Feb15-22 Shopify overlap:', stats.skippedFebOverlap, SKIP_FEB_OVERLAP ? '' : '(guard OFF — included)');
  console.log('Docs to write:', docs.length);
  console.log('\nBy month:', JSON.stringify(stats.byMonth));
  console.log('\nBy category:');
  Object.entries(stats.byCategory).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log('  ', k, v));
  console.log('\nSupplier-payment rows:', stats.supplierPaymentRows,
    '| linked to supplier_id:', stats.supplierLinked,
    '| link mode:', LINK_SUPPLIERS ? 'ON' : 'OFF (supplier_id=null)');
  if (stats.supplierUnmatched.size) console.log('  unmatched/unlinked supplier names:', [...stats.supplierUnmatched].join(' | '));
  console.log('Cash Income (AR settlement) rows:', stats.cashIncome);

  // sample
  console.log('\nSample docs:');
  docs.slice(0, 3).forEach(d => console.log('  ', JSON.stringify({ ...d, date_time: d.date_time.toDate().toISOString().slice(0, 10), created_at: undefined })));

  if (!COMMIT) {
    console.log('\nDRY RUN — nothing written. Re-run with --commit to write.');
    process.exit(0);
  }

  // ── Commit in batches of 500 ──
  const col = db.collection('transactions');
  let written = 0;
  for (let i = 0; i < docs.length; i += 500) {
    const batch = db.batch();
    for (const d of docs.slice(i, i + 500)) batch.set(col.doc(d.id), d);
    await batch.commit();
    written += Math.min(500, docs.length - i);
    console.log('  committed', written, '/', docs.length);
  }
  console.log('\nDONE. Wrote', written, 'transactions.');
  process.exit(0);
}

main().catch(e => { console.error(e); process.exit(1); });

const fs = require('fs');
const path = process.argv[2] || '/Users/mazen/Downloads/revvo_transactions (1).csv';
const raw = fs.readFileSync(path, 'utf8');
const lines = raw.split(/\r?\n/).filter(l => l.trim().length);
const header = lines[0].split(',').map(h => h.trim());

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

const idx = {};
header.forEach((h, i) => (idx[h] = i));
console.log('HEADER:', header.join(' | '));
console.log('Total data rows:', lines.length - 1);

let nImport = 0, nSkip = 0, nReview = 0, other = 0;
const catCount = {};
const actByKind = { shopify: {}, manual: {} };
const suppliers = new Set();
let minDate = null, maxDate = null;
let cashIncomeCount = 0, cashIncomeBad = 0;
const monthImport = {};
let badAmount = 0, badDate = 0;

for (let i = 1; i < lines.length; i++) {
  const f = parseCSV(lines[i]);
  const date = f[idx.date];
  const amt = parseFloat(f[idx.amount]);
  const cat = f[idx.category_id];
  const excl = f[idx.exclude_from_pl];
  const act = f[idx.action];
  const title = f[idx.title] || '';
  const supp = f[idx.supplier_name] || '';
  if (!date) { badDate++; continue; }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) badDate++;
  if (isNaN(amt)) badAmount++;
  if (!minDate || date < minDate) minDate = date;
  if (!maxDate || date > maxDate) maxDate = date;
  if (act === 'import') nImport++;
  else if (act === 'skip') nSkip++;
  else if (act === 'review') nReview++;
  else other++;
  catCount[cat] = (catCount[cat] || 0) + 1;
  if (supp.trim()) suppliers.add(supp.trim());
  const kind = cat === 'cat_sales_revenue' || cat === 'cat_cogs' ? 'shopify' : 'manual';
  actByKind[kind][act] = (actByKind[kind][act] || 0) + 1;
  if (act === 'import') {
    const m = date.slice(0, 7);
    monthImport[m] = (monthImport[m] || 0) + 1;
  }
  if (title === 'Cash Income') {
    cashIncomeCount++;
    if (cat !== 'cat_bosta_cashout' || excl !== 'true') cashIncomeBad++;
  }
}

console.log('\nactions: import', nImport, 'skip', nSkip, 'review', nReview, 'other', other);
console.log('date range:', minDate, '->', maxDate);
console.log('bad dates:', badDate, 'bad amounts:', badAmount);
console.log('\naction by kind:', JSON.stringify(actByKind));
console.log('\nIMPORT rows by month:', JSON.stringify(monthImport, null, 0));
console.log('\nCash Income rows:', cashIncomeCount, 'misclassified:', cashIncomeBad);
console.log('\nsuppliers (' + suppliers.size + '):', [...suppliers].join(' | '));
console.log('\ncategory counts:');
Object.entries(catCount).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log('  ', k, v));

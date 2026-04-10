process.env.GOOGLE_APPLICATION_CREDENTIALS = '/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json';
const admin = require('firebase-admin');
if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();
const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';
const Timestamp = admin.firestore.Timestamp;

const excluded = new Set([
  'cat_investments', 'cat_loan_received', 'cat_loan_repayment',
  'cat_equity_injection', 'cat_owner_withdrawal'
]);

async function calc(name, start, end, allTxns) {
  const txns = allTxns.filter(t => {
    if (t.excl || excluded.has(t.cat)) return false;
    return t.dt >= start && t.dt <= end;
  });

  let oldR = 0, oldE = 0, newR = 0, newE = 0;
  let sr = 0, cg = 0, sh = 0, op = 0;
  let cgR = 0, cgN = 0, shR = 0, shN = 0, slR = 0, slN = 0;

  for (const t of txns) {
    const a = Math.abs(t.amount);
    // OLD logic (original)
    if (t.amount > 0) oldR += a;
    else if (t.cat === 'cat_sales_revenue') oldR -= a;
    else oldE += a;
    // NEW logic (current code)
    if (t.cat === 'cat_cogs') newE -= t.amount;
    else if (t.cat === 'cat_sales_revenue' || t.cat === 'cat_shipping') newR += t.amount;
    else if (t.amount > 0) newR += a;
    else newE += a;
    // P&L detail
    if (t.cat === 'cat_sales_revenue') sr += t.amount;
    else if (t.cat === 'cat_cogs') cg += -t.amount;
    else if (t.cat === 'cat_shipping') sh += t.amount;
    else if (t.amount > 0) sh += a;
    else op += a;
    // Reversals
    if (t.cat === 'cat_cogs') { if (t.amount > 0) cgR += t.amount; else cgN += a; }
    if (t.cat === 'cat_shipping') { if (t.amount < 0) shR += a; else shN += t.amount; }
    if (t.cat === 'cat_sales_revenue') { if (t.amount < 0) slR += a; else slN += t.amount; }
  }

  console.log('=== ' + name + ' (' + start.toLocaleDateString() + ' - ' + end.toLocaleDateString() + ') ===');
  console.log('Txns:', txns.length);
  console.log('OLD:  Rev=' + oldR.toFixed(0) + ', Exp=' + oldE.toFixed(0));
  console.log('NEW:  Rev=' + newR.toFixed(0) + ', Exp=' + newE.toFixed(0));
  console.log('P&L:  SalesRev=' + sr.toFixed(0) + ', COGS=' + cg.toFixed(0) + ', Ship/Other=' + sh.toFixed(0) + ', OpEx=' + op.toFixed(0));
  console.log('      TotalRev=' + (sr + sh).toFixed(0) + ', NetProfit=' + (sr - cg + sh - op).toFixed(0));
  console.log('Reversals: COGS(cost=' + cgN.toFixed(0) + ',rev=' + cgR.toFixed(0) + ') Sales(inc=' + slN.toFixed(0) + ',ref=' + slR.toFixed(0) + ') Ship(inc=' + shN.toFixed(0) + ',rev=' + shR.toFixed(0) + ')');
  console.log('');
}

(async () => {
  // Fetch all transactions once
  const snap = await db.collection('transactions').where('user_id', '==', uid).get();
  const allTxns = snap.docs.map(d => {
    const r = d.data();
    return {
      id: d.id,
      amount: r.amount,
      cat: r.category_id,
      excl: r.exclude_from_pl || false,
      dt: r.date_time && r.date_time.toDate ? r.date_time.toDate() : null,
    };
  }).filter(t => t.dt !== null);
  console.log('Total transactions loaded:', allTxns.length);
  console.log('');

  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const yesterday = new Date(today.getTime() - 86400000);
  const yesterdayEnd = new Date(today.getTime() - 1);
  const l7Start = new Date(today.getTime() - 6 * 86400000);
  const mtdStart = new Date(now.getFullYear(), now.getMonth(), 1);

  console.log('Current time:', now.toString());
  console.log('');

  await calc('Today', today, now, allTxns);
  await calc('Yesterday', yesterday, yesterdayEnd, allTxns);
  await calc('Last 7 Days', l7Start, now, allTxns);
  await calc('Month to Date', mtdStart, now, allTxns);
  process.exit();
})();

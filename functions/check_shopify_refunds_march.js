// Check refund amounts on March Shopify orders
const admin = require('firebase-admin');
const { onRequest } = require('firebase-functions/v2/https');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  // Get user's Shopify connection
  const connSnap = await db.collection('shopify_connections')
    .where('user_id', '==', uid)
    .limit(1)
    .get();

  if (connSnap.empty) { console.log('No connection found'); process.exit(1); }
  const conn = connSnap.docs[0].data();
  const shop = conn.shop_domain;
  const token = conn.access_token;

  // Fetch March orders with refund data
  const marchStart = '2026-03-01T00:00:00Z';
  const marchEnd   = '2026-04-01T00:00:00Z';

  let allOrders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&created_at_min=${encodeURIComponent(marchStart)}&created_at_max=${encodeURIComponent(marchEnd)}&limit=250`;

  console.log('Shop:', shop);
  console.log('Fetching from:', url.split('?')[0]);

  while (url && allOrders.length < 5000) {
    const resp = await fetch(url, { headers: { 'X-Shopify-Access-Token': token } });
    if (!resp.ok) {
      console.log('API error:', resp.status, await resp.text());
      break;
    }
    const data = await resp.json();
    console.log('Page orders:', (data.orders || []).length);
    allOrders = allOrders.concat(data.orders || []);

    // Pagination
    const link = resp.headers.get('link') || '';
    const next = link.match(/<([^>]+)>;\s*rel="next"/);
    url = next ? next[1] : null;
  }

  console.log(`Fetched ${allOrders.length} March orders from Shopify`);

  let totalRefundAmount = 0;
  let ordersWithRefunds = 0;
  let partialRefundOrders = [];

  for (const order of allOrders) {
    const refunds = order.refunds || [];
    if (refunds.length === 0) continue;

    let orderRefundTotal = 0;
    for (const refund of refunds) {
      // Sum refund line items (product refunds)
      const refundLineItems = refund.refund_line_items || [];
      for (const rli of refundLineItems) {
        orderRefundTotal += Number(rli.subtotal) || 0;
      }
    }

    if (orderRefundTotal > 0) {
      ordersWithRefunds++;
      totalRefundAmount += orderRefundTotal;

      // Check if order is NOT cancelled
      if (!order.cancelled_at) {
        partialRefundOrders.push({
          orderNum: order.order_number,
          financialStatus: order.financial_status,
          refundAmount: orderRefundTotal,
          cancelled: !!order.cancelled_at,
        });
      }
    }
  }

  console.log(`\nOrders with refunds: ${ordersWithRefunds}`);
  console.log(`Total refund amount (product): ${totalRefundAmount.toFixed(2)}`);
  console.log(`\nNon-cancelled orders with partial refunds: ${partialRefundOrders.length}`);

  let partialTotal = 0;
  for (const o of partialRefundOrders) {
    partialTotal += o.refundAmount;
  }
  console.log(`Partial refund total: ${partialTotal.toFixed(2)}`);

  if (partialRefundOrders.length > 0) {
    console.log('\nFirst 15:');
    for (const o of partialRefundOrders.slice(0, 15)) {
      console.log(`  #${o.orderNum}: refund=${o.refundAmount.toFixed(2)} (status: ${o.financialStatus})`);
    }
  }

  // Also check: cancelled order refunds (should already have reversals)
  let cancelledRefundTotal = 0;
  let cancelledRefundCount = 0;
  for (const order of allOrders) {
    if (!order.cancelled_at) continue;
    const refunds = order.refunds || [];
    for (const refund of refunds) {
      for (const rli of (refund.refund_line_items || [])) {
        cancelledRefundTotal += Number(rli.subtotal) || 0;
      }
    }
    if (refunds.length > 0) cancelledRefundCount++;
  }
  console.log(`\nCancelled orders with refunds: ${cancelledRefundCount}, total: ${cancelledRefundTotal.toFixed(2)}`);

  process.exit(0);
})();

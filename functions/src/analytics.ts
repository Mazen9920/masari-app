/**
 * Analytics Cloud Functions — revenue, subscription, and daily metrics
 */

import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {getFirestore, Timestamp, FieldValue} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";

const db = () => getFirestore();

/** Verify admin claim */
function assertAdmin(request: CallableRequest) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  if (!(request.auth.token as Record<string, unknown>).admin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

// ────────────────────────────────────────────────────────────────────────────
// getRevenueMetrics — aggregates payment_logs for MRR/ARR/churn/revenue
// ────────────────────────────────────────────────────────────────────────────
export const getRevenueMetrics = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    assertAdmin(request);

    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const startOfPrevMonth = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    const endOfPrevMonth = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
    const twelveMonthsAgo = new Date(now.getFullYear() - 1, now.getMonth(), 1);

    // ── All successful payments in last 12 months ──
    const paymentsSnap = await db()
      .collection("payment_logs")
      .where("success", "==", true)
      .where("created_at", ">=", Timestamp.fromDate(twelveMonthsAgo))
      .orderBy("created_at", "asc")
      .get();

    // ── Current month revenue ──
    let currentMonthRevenue = 0;
    let prevMonthRevenue = 0;
    let totalRevenue = 0;
    const revenueByPlan: Record<string, number> = {};
    const monthlyRevenue: Record<string, number> = {}; // "YYYY-MM" → cents

    for (const doc of paymentsSnap.docs) {
      const d = doc.data();
      const cents = d.amount_cents ?? 0;
      const plan = d.plan ?? "unknown";
      const createdAt = d.created_at?.toDate?.() ??
        (typeof d.created_at === "string" ? new Date(d.created_at) : null);
      if (!createdAt) continue;

      totalRevenue += cents;
      revenueByPlan[plan] = (revenueByPlan[plan] ?? 0) + cents;

      // Monthly bucket
      const key = `${createdAt.getFullYear()}-${String(createdAt.getMonth() + 1).padStart(2, "0")}`;
      monthlyRevenue[key] = (monthlyRevenue[key] ?? 0) + cents;

      if (createdAt >= startOfMonth) {
        currentMonthRevenue += cents;
      } else if (createdAt >= startOfPrevMonth && createdAt <= endOfPrevMonth) {
        prevMonthRevenue += cents;
      }
    }

    // ── MRR = current month revenue (simplification: recurring revenue this month) ──
    const mrr = currentMonthRevenue;
    const arr = mrr * 12;
    const mrrGrowthPct = prevMonthRevenue > 0
      ? ((currentMonthRevenue - prevMonthRevenue) / prevMonthRevenue) * 100
      : 0;

    // ── Failed payment count this month ──
    const failedSnap = await db()
      .collection("payment_logs")
      .where("success", "==", false)
      .where("created_at", ">=", Timestamp.fromDate(startOfMonth))
      .count()
      .get();
    const failedPaymentsThisMonth = failedSnap.data().count;

    // ── Build 12-month trend ──
    const mrrTrend: Array<{month: string; revenue: number}> = [];
    for (let i = 11; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
      const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      mrrTrend.push({month: key, revenue: (monthlyRevenue[key] ?? 0) / 100});
    }

    // ── Revenue by plan (top-level) ──
    const planBreakdown = Object.entries(revenueByPlan).map(([plan, cents]) => ({
      plan,
      revenue: cents / 100,
    }));

    return {
      mrr: mrr / 100,
      arr: arr / 100,
      totalRevenue: totalRevenue / 100,
      mrrGrowthPct: Math.round(mrrGrowthPct * 10) / 10,
      currentMonthRevenue: currentMonthRevenue / 100,
      prevMonthRevenue: prevMonthRevenue / 100,
      failedPaymentsThisMonth,
      mrrTrend,
      planBreakdown,
    };
  }
);

// ────────────────────────────────────────────────────────────────────────────
// getSubscriptionMetrics — subscriber counts, churn, conversion
// ────────────────────────────────────────────────────────────────────────────
export const getSubscriptionMetrics = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    assertAdmin(request);

    // ── Count by tier ──
    const [launchSnap, growthSnap, proSnap] = await Promise.all([
      db().collection("users").where("subscription_tier", "==", "launch").count().get(),
      db().collection("users").where("subscription_tier", "==", "growth").count().get(),
      db().collection("users").where("subscription_tier", "==", "pro").count().get(),
    ]);

    const launchCount = launchSnap.data().count;
    const growthCount = growthSnap.data().count;
    const proCount = proSnap.data().count;
    const totalUsers = launchCount + growthCount + proCount;
    const paidSubscribers = growthCount + proCount;

    // ── Count by status ──
    const [activeSnap, expiredSnap, cancelledSnap, graceSnap] = await Promise.all([
      db().collection("users").where("subscription_status", "==", "active").count().get(),
      db().collection("users").where("subscription_status", "==", "expired").count().get(),
      db().collection("users").where("subscription_status", "==", "cancelled").count().get(),
      db().collection("users").where("subscription_status", "==", "grace_period").count().get(),
    ]);

    const activeCount = activeSnap.data().count;
    const expiredCount = expiredSnap.data().count;
    const cancelledCount = cancelledSnap.data().count;
    const graceCount = graceSnap.data().count;

    // ── Churn rate = (expired + cancelled this month) / (active at start of month + new this month) ──
    // Simplified: expired+cancelled / total paid ever attempted
    const churnRate = paidSubscribers + expiredCount + cancelledCount > 0
      ? ((expiredCount + cancelledCount) / (paidSubscribers + expiredCount + cancelledCount)) * 100
      : 0;

    // ── Conversion rate = paid / total ──
    const conversionRate = totalUsers > 0
      ? (paidSubscribers / totalUsers) * 100
      : 0;

    // ── Renewal rate: renewals vs total successful payments this month ──
    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    const [renewalSnap, totalPaymentsSnap] = await Promise.all([
      db().collection("payment_logs")
        .where("success", "==", true)
        .where("is_renewal", "==", true)
        .where("created_at", ">=", Timestamp.fromDate(startOfMonth))
        .count().get(),
      db().collection("payment_logs")
        .where("success", "==", true)
        .where("created_at", ">=", Timestamp.fromDate(startOfMonth))
        .count().get(),
    ]);

    const renewalCount = renewalSnap.data().count;
    const totalPaymentsCount = totalPaymentsSnap.data().count;
    const renewalRate = totalPaymentsCount > 0
      ? (renewalCount / totalPaymentsCount) * 100
      : 0;

    // ── Subscriber growth: last 12 months from admin_metrics ──
    const twelveMonthsAgo = new Date(now.getFullYear(), now.getMonth() - 11, 1);
    const metricsSnap = await db()
      .collection("admin_metrics")
      .where("date", ">=", twelveMonthsAgo.toISOString().split("T")[0])
      .orderBy("date", "asc")
      .get();

    const subscriberTrend = metricsSnap.docs.map((doc) => {
      const md = doc.data();
      return {
        date: md.date,
        totalUsers: md.total_users ?? 0,
        paidSubscribers: md.paid_subscribers ?? 0,
        growthCount: md.growth_count ?? 0,
        proCount: md.pro_count ?? 0,
      };
    });

    return {
      totalUsers,
      paidSubscribers,
      tierBreakdown: {
        launch: launchCount,
        growth: growthCount,
        pro: proCount,
      },
      statusBreakdown: {
        active: activeCount,
        expired: expiredCount,
        cancelled: cancelledCount,
        grace_period: graceCount,
      },
      churnRate: Math.round(churnRate * 10) / 10,
      conversionRate: Math.round(conversionRate * 10) / 10,
      renewalRate: Math.round(renewalRate * 10) / 10,
      subscriberTrend,
    };
  }
);

// ────────────────────────────────────────────────────────────────────────────
// computeDailyMetrics — scheduled at 04:00 UTC, stores daily snapshot
// ────────────────────────────────────────────────────────────────────────────
export const computeDailyMetrics = onSchedule(
  {
    schedule: "0 4 * * *",
    timeZone: "UTC",
    region: "us-central1",
    maxInstances: 1,
    timeoutSeconds: 120,
  },
  async () => {
    const now = new Date();
    const dateKey = now.toISOString().split("T")[0]; // "YYYY-MM-DD"
    const startOfDay = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const startOfPrevDay = new Date(startOfDay.getTime() - 86400000);

    // ── User counts by tier ──
    const [totalSnap, launchSnap, growthSnap, proSnap] = await Promise.all([
      db().collection("users").count().get(),
      db().collection("users").where("subscription_tier", "==", "launch").count().get(),
      db().collection("users").where("subscription_tier", "==", "growth").count().get(),
      db().collection("users").where("subscription_tier", "==", "pro").count().get(),
    ]);

    const totalUsers = totalSnap.data().count;
    const launchCount = launchSnap.data().count;
    const growthCount = growthSnap.data().count;
    const proCount = proSnap.data().count;

    // ── Status counts ──
    const [activeSnap, expiredSnap, cancelledSnap, graceSnap] = await Promise.all([
      db().collection("users").where("subscription_status", "==", "active").count().get(),
      db().collection("users").where("subscription_status", "==", "expired").count().get(),
      db().collection("users").where("subscription_status", "==", "cancelled").count().get(),
      db().collection("users").where("subscription_status", "==", "grace_period").count().get(),
    ]);

    // ── Revenue yesterday ──
    const yesterdayPaymentsSnap = await db()
      .collection("payment_logs")
      .where("success", "==", true)
      .where("created_at", ">=", Timestamp.fromDate(startOfPrevDay))
      .where("created_at", "<", Timestamp.fromDate(startOfDay))
      .get();

    let dailyRevenueCents = 0;
    let dailyPaymentCount = 0;
    let dailyRenewalCount = 0;
    for (const doc of yesterdayPaymentsSnap.docs) {
      const d = doc.data();
      dailyRevenueCents += d.amount_cents ?? 0;
      dailyPaymentCount++;
      if (d.is_renewal) dailyRenewalCount++;
    }

    // ── New signups yesterday ──
    const newUsersSnap = await db()
      .collection("users")
      .where("created_at", ">=", Timestamp.fromDate(startOfPrevDay))
      .where("created_at", "<", Timestamp.fromDate(startOfDay))
      .count()
      .get();

    const snapshot = {
      date: dateKey,
      total_users: totalUsers,
      launch_count: launchCount,
      growth_count: growthCount,
      pro_count: proCount,
      paid_subscribers: growthCount + proCount,
      active_count: activeSnap.data().count,
      expired_count: expiredSnap.data().count,
      cancelled_count: cancelledSnap.data().count,
      grace_period_count: graceSnap.data().count,
      daily_revenue_cents: dailyRevenueCents,
      daily_revenue: dailyRevenueCents / 100,
      daily_payment_count: dailyPaymentCount,
      daily_renewal_count: dailyRenewalCount,
      new_users: newUsersSnap.data().count,
      computed_at: FieldValue.serverTimestamp(),
    };

    await db().collection("admin_metrics").doc(dateKey).set(snapshot);

    logger.info("computeDailyMetrics complete", snapshot);
  }
);

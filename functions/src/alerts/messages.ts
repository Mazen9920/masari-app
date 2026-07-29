/**
 * messages.ts — bilingual (en/ar) push-notification templates.
 *
 * Every smart alert has one entry here, written in BOTH languages; the send
 * path picks by `users/{uid}.locale` (synced by the app, default "en").
 * Templates use `{token}` placeholders filled from a params map, so callers
 * never concatenate copy — adding a language or rewording never touches
 * alert logic.
 */

export type AlertLocale = "en" | "ar";

export interface AlertMessage {
  title: string;
  body: string;
}

type Template = {en: AlertMessage; ar: AlertMessage};

/** Replaces `{key}` tokens; unknown tokens are left visible (easier to spot). */
function fill(text: string, params: Record<string, string>): string {
  return text.replace(/\{(\w+)\}/g, (m, k: string) => params[k] ?? m);
}

const TEMPLATES: Record<string, Template> = {
  low_stock: {
    en: {
      title: "Low stock",
      body: "{count} item(s) at or below reorder point — worst: {worst} ({stock} left)",
    },
    ar: {
      title: "المخزون منخفض",
      body: "{count} منتج وصل لحد إعادة الطلب — الأقل: {worst} (متبقي {stock})",
    },
  },
  stockout_forecast: {
    en: {
      title: "Order now — stockout ahead",
      body: "{worst} runs out in ~{days} days but {supplier} needs {lead} days. {count} item(s) at risk.",
    },
    ar: {
      title: "اطلب الآن — المخزون سينفد",
      body: "{worst} سينفد خلال ~{days} يوم بينما {supplier} يحتاج {lead} يوم للتوريد. {count} منتج في خطر.",
    },
  },
  cash_crunch: {
    en: {
      title: "Cash crunch ahead",
      body: "Next 14 days: {obligations} EGP due vs {available} EGP available — short by {gap} EGP.",
    },
    ar: {
      title: "ضغط على السيولة",
      body: "خلال 14 يوم: مستحقات {obligations} ج.م مقابل {available} ج.م متاحة — عجز {gap} ج.م.",
    },
  },
  payout_overdue: {
    en: {
      title: "Bosta payout overdue",
      body: "{pending} EGP awaiting cashout — last payout was {days} days ago.",
    },
    ar: {
      title: "تأخر تحويل بوسطة",
      body: "{pending} ج.م في انتظار التحصيل — آخر تحويل كان منذ {days} يوم.",
    },
  },
  rto_spike: {
    en: {
      title: "Delivery refusals spiking",
      body: "{count} refused/returned this week — {rate}% vs your usual {baseline}%.",
    },
    ar: {
      title: "ارتفاع في مرتجعات الشحن",
      body: "{count} طلب مرفوض/مرتجع هذا الأسبوع — {rate}% مقابل معدلك المعتاد {baseline}%.",
    },
  },
  repeat_refuser: {
    en: {
      title: "⚠ Repeat refuser ordered again",
      body: "Customer {phone} refused delivery {count}× before (last {last}). Confirm by phone before shipping.",
    },
    ar: {
      title: "⚠ عميل سبق أن رفض الاستلام",
      body: "العميل {phone} رفض الاستلام {count} مرة من قبل (آخرها {last}). أكد هاتفياً قبل الشحن.",
    },
  },
  accrued_due: {
    en: {
      title: "Accrued expenses due",
      body: "{count} accrual(s) need payment — {total} EGP ({worst} is {status}).",
    },
    ar: {
      title: "مصروفات مستحقة",
      body: "{count} التزام يحتاج سداد — {total} ج.م ({worst} {status}).",
    },
  },
  gateway_overdue: {
    en: {
      title: "Gateway payout overdue",
      body: "{name} holds {pending} EGP — {days} days since last settlement (cycle: {cycle}d).",
    },
    ar: {
      title: "تأخر تسوية بوابة الدفع",
      body: "{name} تحتفظ بـ {pending} ج.م — مرّ {days} يوم على آخر تسوية (الدورة: {cycle} يوم).",
    },
  },
  salary_unpaid: {
    en: {
      title: "Salaries not fully paid",
      body: "{count} employee(s) still owed {total} EGP for {month}.",
    },
    ar: {
      title: "رواتب لم تُسدد بالكامل",
      body: "{count} موظف ما زال مستحقاً {total} ج.م عن شهر {month}.",
    },
  },
  supplier_due: {
    en: {
      title: "Supplier payments owed",
      body: "{count} supplier(s) owed {total} EGP for goods already received — largest: {worst}.",
    },
    ar: {
      title: "مستحقات موردين",
      body: "{count} مورد مستحق لهم {total} ج.م عن بضاعة تم استلامها — الأكبر: {worst}.",
    },
  },
  no_orders: {
    en: {
      title: "No orders in {hours}h",
      body: "Usually an order lands every ~{median}h. Check the store and checkout.",
    },
    ar: {
      title: "لا طلبات منذ {hours} ساعة",
      body: "المعتاد طلب كل ~{median} ساعة. راجع المتجر وصفحة الدفع.",
    },
  },
  margin_erosion: {
    en: {
      title: "Cost jump on {product}",
      body: "New batch costs {newCost} EGP/unit vs {oldCost} before (+{pct}%). Margin at current price: {margin}%.",
    },
    ar: {
      title: "ارتفاع تكلفة {product}",
      body: "الدفعة الجديدة بتكلفة {newCost} ج.م/وحدة مقابل {oldCost} سابقاً (+{pct}%). الهامش بالسعر الحالي: {margin}%.",
    },
  },
  cashout_gap: {
    en: {
      title: "Cashout doesn't match",
      body: "Bosta paid {actual} EGP but ~{expected} EGP was expected — gap {gap} EGP.",
    },
    ar: {
      title: "تحويل بوسطة غير مطابق",
      body: "بوسطة حولت {actual} ج.م بينما المتوقع ~{expected} ج.م — فرق {gap} ج.م.",
    },
  },
  dead_capital: {
    en: {
      title: "Money sitting in dead stock",
      body: "{total} EGP tied up in {count} product(s) with no sales for 30 days — top: {worst}.",
    },
    ar: {
      title: "رأس مال راكد في المخزون",
      body: "{total} ج.م محتجزة في {count} منتج بدون مبيعات منذ 30 يوم — الأعلى: {worst}.",
    },
  },
  vip_customer: {
    en: {
      title: "VIP customer 🎉",
      body: "{name} just placed order #{n} — a personal thank-you goes a long way.",
    },
    ar: {
      title: "عميل مميز 🎉",
      body: "{name} أتم طلبه رقم {n} — رسالة شكر شخصية تصنع فرقاً.",
    },
  },
  weekly_digest: {
    en: {
      title: "Your week at {business}",
      body: "Revenue {revenue} EGP ({trend}% WoW) · {orders} orders · {extra}",
    },
    ar: {
      title: "أسبوعك في {business}",
      body: "الإيراد {revenue} ج.م ({trend}% عن الأسبوع الماضي) · {orders} طلب · {extra}",
    },
  },
  integrity_nudge: {
    en: {
      title: "Books need attention",
      body: "{count} data issue(s): {summary}",
    },
    ar: {
      title: "الدفاتر تحتاج مراجعة",
      body: "{count} ملاحظة على البيانات: {summary}",
    },
  },
};

/**
 * Builds the localized message for [type]. Unknown types fall back to a plain
 * English envelope so a send never crashes on a missing template.
 */
export function alertMessage(
  type: string,
  locale: AlertLocale,
  params: Record<string, string>
): AlertMessage {
  const t = TEMPLATES[type];
  if (!t) {
    return {title: "Revvo", body: params.summary ?? type};
  }
  const m = t[locale] ?? t.en;
  return {title: fill(m.title, params), body: fill(m.body, params)};
}

/** Narrows an arbitrary stored locale to a supported one. */
export function toAlertLocale(raw: unknown): AlertLocale {
  return raw === "ar" ? "ar" : "en";
}

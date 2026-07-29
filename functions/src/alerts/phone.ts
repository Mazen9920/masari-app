/**
 * phone.ts — Egyptian mobile-number normalization for alert matching.
 *
 * Customer phones arrive in many spellings of the same number
 * (`+2010...`, `002010...`, `2010...`, `010...`, `10...`). The RTO index and
 * the repeat-refuser check must treat them as one identity, so everything is
 * canonicalized to the local `01XXXXXXXXX` form before use as a map key.
 */

/**
 * Normalizes [raw] to canonical `01XXXXXXXXX`, or returns null when the input
 * is not a plausible Egyptian mobile number (never index nulls).
 */
export function normalizeEgPhone(raw: string | null | undefined): string | null {
  if (!raw) return null;
  let d = raw.replace(/\D/g, "");
  if (d.startsWith("00")) d = d.substring(2); // 00201… → 201…
  if (d.length === 12 && d.startsWith("20")) d = d.substring(2); // 201… → 1…
  if (d.length === 10 && d.startsWith("1")) d = "0" + d; // 10… → 010…
  return /^01[0125]\d{8}$/.test(d) ? d : null;
}

/** Masks a canonical phone for notification bodies: 010****4567. */
export function maskPhone(phone: string): string {
  if (phone.length < 7) return phone;
  return phone.substring(0, 3) + "****" + phone.substring(phone.length - 4);
}

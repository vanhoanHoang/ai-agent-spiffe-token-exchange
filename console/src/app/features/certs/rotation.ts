/**
 * Rotation math for the live SVID panel — pure functions so the ticking UI
 * is testable without a clock. SPIRE renews an X.509-SVID at about the half
 * of its lifetime (lab config: 1h TTL → rotation ≈ every 30 min), so the
 * "rotation expected" moment is an ESTIMATE derived from the leaf's own
 * validity window, never a promise.
 */

export interface RotationView {
  /** ms until notAfter; negative = expired */
  readonly expiresInMs: number;
  /** ms until the estimated rotation (half-life); negative = due */
  readonly rotationInMs: number;
}

export function rotationView(nowMs: number, notBefore: string, notAfter: string): RotationView {
  const start = Date.parse(notBefore);
  const end = Date.parse(notAfter);
  const halfLife = start + (end - start) / 2;
  return { expiresInMs: end - nowMs, rotationInMs: halfLife - nowMs };
}

/** "41:23" / "1:02:41" — or "due" once the moment has passed. */
export function countdown(ms: number): string {
  if (ms <= 0) {
    return 'due';
  }
  const s = Math.floor(ms / 1000);
  const hh = Math.floor(s / 3600);
  const mm = Math.floor((s % 3600) / 60);
  const ss = s % 60;
  const pad = (n: number): string => String(n).padStart(2, '0');
  return hh > 0 ? `${hh}:${pad(mm)}:${pad(ss)}` : `${mm}:${pad(ss)}`;
}

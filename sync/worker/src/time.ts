import { CONFIRM_OVERLAP_WINDOW_SECONDS, OFFER_TTL_SECONDS } from "./constants.ts";

export function unixSeconds(nowMs = Date.now()): number {
  return Math.floor(nowMs / 1000);
}

export function offerExpiresAt(createdAt: number, ttl = OFFER_TTL_SECONDS): number {
  return createdAt + ttl;
}

export function isOfferExpired(expiresAt: number, now: number): boolean {
  return now >= expiresAt;
}

/** Both confirms must arrive within the window of the first. Inclusive. */
export function confirmOverlapOk(
  firstAt: number,
  secondAt: number,
  window = CONFIRM_OVERLAP_WINDOW_SECONDS,
): boolean {
  return secondAt - firstAt <= window;
}

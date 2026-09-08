import { describe, expect, it } from "vitest";
import { confirmOverlapOk, isOfferExpired, offerExpiresAt } from "../src/time.ts";
import { CONFIRM_OVERLAP_WINDOW_SECONDS, OFFER_TTL_SECONDS } from "../src/constants.ts";

describe("offer TTL", () => {
  it("expires at created + 120s from contract constants", () => {
    expect(OFFER_TTL_SECONDS).toBe(120);
    expect(offerExpiresAt(1_768_000_000)).toBe(1_768_000_120);
    expect(isOfferExpired(1_768_000_120, 1_768_000_119)).toBe(false);
    expect(isOfferExpired(1_768_000_120, 1_768_000_120)).toBe(true);
  });
});

describe("confirm overlap window", () => {
  it("accepts the second confirm within 15s of the first", () => {
    expect(CONFIRM_OVERLAP_WINDOW_SECONDS).toBe(15);
    expect(confirmOverlapOk(100, 115)).toBe(true);
    expect(confirmOverlapOk(100, 116)).toBe(false);
    expect(confirmOverlapOk(100, 100)).toBe(true);
  });
});

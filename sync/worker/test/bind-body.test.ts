import { describe, expect, it } from "vitest";
import { parseBind, parseHmacBody } from "../src/bind-body.ts";
import { HMAC_IPHONE, HMAC_MAC, S, X, Y } from "./contract-bytes.ts";

describe("parseBind", () => {
  it("accepts the golden iPhone and Mac payloads", () => {
    expect(parseBind({ role: "iphone", s: S, y: Y })).toEqual({ role: "iphone", s: S, y: Y });
    expect(parseBind({ role: "mac", s: S, x: X })).toEqual({ role: "mac", s: S, x: X });
  });

  it("rejects missing fields, bad UUIDs, and unknown roles", () => {
    expect(parseBind(null)).toBeNull();
    expect(parseBind([])).toBeNull();
    expect(parseBind({ role: "iphone", s: S })).toBeNull();
    expect(parseBind({ role: "iphone", s: "NOT-A-UUID", y: Y })).toBeNull();
    expect(parseBind({ role: "mac", s: S, x: "short" })).toBeNull();
    expect(parseBind({ role: "watch", s: S, y: Y })).toBeNull();
  });
});

describe("parseHmacBody", () => {
  it("accepts golden 32-byte HMACs and rejects malformed ones", () => {
    expect(parseHmacBody({ hmac: HMAC_IPHONE })).toBe(HMAC_IPHONE);
    expect(parseHmacBody({ hmac: HMAC_MAC })).toBe(HMAC_MAC);
    expect(parseHmacBody({})).toBe("missing");
    expect(parseHmacBody({ hmac: 1 })).toBe("missing");
    expect(parseHmacBody({ hmac: "short" })).toBe("bad");
    expect(parseHmacBody({ hmac: `${HMAC_IPHONE}=` })).toBe("bad");
  });
});

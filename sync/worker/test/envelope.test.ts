import { describe, expect, it } from "vitest";
import { encodeB64u } from "../src/b64.ts";
import { parseEnvelope } from "../src/envelope.ts";
import { SNAP } from "./contract-bytes.ts";

describe("parseEnvelope", () => {
  it("accepts the golden snap envelope as opaque fields", () => {
    const parsed = parseEnvelope(SNAP, "snap");
    expect(parsed.ok).toBe(true);
    if (parsed.ok) expect(parsed.envelope).toEqual(SNAP);
  });

  it("rejects kind mismatch, padded nonce, short ct, and non-integer rev", () => {
    expect(parseEnvelope({ ...SNAP, kind: "cmd" }, "snap").ok).toBe(false);
    expect(parseEnvelope({ ...SNAP, n: `${SNAP.n}=` }, "snap").ok).toBe(false);
    expect(parseEnvelope({ ...SNAP, ct: encodeB64u(new Uint8Array(15)) }, "snap").ok).toBe(false);
    expect(parseEnvelope({ ...SNAP, rev: 1.5 }, "snap").ok).toBe(false);
    expect(parseEnvelope({ ...SNAP, rev: -1 }, "snap").ok).toBe(false);
    expect(parseEnvelope({ ...SNAP, n: "short" }, "snap").ok).toBe(false);
    expect(parseEnvelope(null, "snap").ok).toBe(false);
  });

  it("does not JSON.parse ct even when decoded bytes are JSON", () => {
    const plaintext = new TextEncoder().encode('{"title":"週次レポート","pad":"********"}');
    const ct = encodeB64u(plaintext);
    const original = JSON.parse;
    let parsedTitle = false;
    JSON.parse = ((text: string, reviver?: (this: unknown, key: string, value: unknown) => unknown) => {
      if (typeof text === "string" && text.includes("週次レポート")) parsedTitle = true;
      return original(text, reviver);
    }) as typeof JSON.parse;
    try {
      const parsed = parseEnvelope({ rev: 1, kind: "cmd", n: SNAP.n, ct }, "cmd");
      expect(parsed.ok).toBe(true);
      if (parsed.ok) expect(parsed.envelope.ct).toBe(ct);
      expect(parsedTitle).toBe(false);
    } finally {
      JSON.parse = original;
    }
  });
});

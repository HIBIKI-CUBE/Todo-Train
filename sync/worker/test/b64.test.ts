import { describe, expect, it } from "vitest";
import { decodeB64u, encodeB64u, isB64uBytes } from "../src/b64.ts";
import { X } from "./contract-bytes.ts";

describe("unpadded base64url", () => {
  it("round-trips 12 / 32 / 48 byte values", () => {
    for (const n of [12, 32, 48]) {
      const bytes = crypto.getRandomValues(new Uint8Array(n));
      const encoded = encodeB64u(bytes);
      expect(encoded.includes("=")).toBe(false);
      expect(decodeB64u(encoded)).toEqual(bytes);
    }
  });

  it("rejects padding, empty strings, and non-base64url alphabets", () => {
    expect(decodeB64u("")).toBeNull();
    expect(decodeB64u(`${X}=`)).toBeNull();
    expect(decodeB64u("abc+def/ghi")).toBeNull();
    expect(isB64uBytes(X, 32)).toBe(true);
    expect(isB64uBytes(X, 31)).toBe(false);
  });

  it("decodes the golden X25519 pub to 32 bytes", () => {
    expect(decodeB64u(X)?.byteLength).toBe(32);
  });
});

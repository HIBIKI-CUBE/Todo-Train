import { describe, expect, it } from "vitest";
import { isPub32, isUuid } from "../src/ids.ts";
import { S, X } from "./contract-bytes.ts";

describe("ids", () => {
  it("accepts lowercase canonical UUIDs only", () => {
    expect(isUuid(S)).toBe(true);
    expect(isUuid(S.toUpperCase())).toBe(false);
    expect(isUuid("not-a-uuid")).toBe(false);
  });

  it("treats the golden X as a 32-byte public key", () => {
    expect(isPub32(X)).toBe(true);
  });
});

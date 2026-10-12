import { describe, expect, it } from "vitest";
import { CONTRACT, MIN_READABLE } from "../src/contract-version.ts";

describe("contract version", () => {
  it("imports positive versions from version.json", () => {
    expect(Number.isInteger(CONTRACT)).toBe(true);
    expect(Number.isInteger(MIN_READABLE)).toBe(true);
    expect(CONTRACT).toBeGreaterThan(0);
    expect(MIN_READABLE).toBeGreaterThan(0);
    expect(MIN_READABLE).toBeLessThanOrEqual(CONTRACT);
  });
});

import { describe, expect, it } from "vitest";
import { SNAP, SNAP_TITLE } from "./contract-bytes.ts";
import { readPairingState } from "./do.ts";
import { pairedClient, requestAuth } from "./http.ts";

describe("ciphertext opacity", () => {
  it("never logs or stores the snap plaintext title", async () => {
    const logs: string[] = [];
    const originalLog = console.log;
    const originalInfo = console.info;
    const originalWarn = console.warn;
    const originalError = console.error;
    const originalParse = JSON.parse;
    let parsedTitle = false;
    const capture = (...args: unknown[]) => {
      logs.push(args.map((a) => String(a)).join(" "));
    };
    console.log = capture;
    console.info = capture;
    console.warn = capture;
    console.error = capture;
    JSON.parse = ((text: string, reviver?: (this: unknown, key: string, value: unknown) => unknown) => {
      if (typeof text === "string" && text.includes(SNAP_TITLE)) parsedTitle = true;
      return originalParse(text, reviver);
    }) as typeof JSON.parse;
    try {
      const client = await pairedClient();
      await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
      await requestAuth("/v1/snap", "GET", client.writeToken);
      const stored = await readPairingState(client.pairingId);
      const dumped = JSON.stringify(stored);
      expect(dumped).not.toContain(SNAP_TITLE);
      expect(logs.join("\n")).not.toContain(SNAP_TITLE);
      expect(parsedTitle).toBe(false);
      expect(stored?.snap?.ct).toBe(SNAP.ct);
      expect(stored?.snap).not.toHaveProperty("title");
    } finally {
      console.log = originalLog;
      console.info = originalInfo;
      console.warn = originalWarn;
      console.error = originalError;
      JSON.parse = originalParse;
    }
  });
});

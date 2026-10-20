import { describe, expect, it } from "vitest";
import { CONTRACT, MIN_READABLE } from "../src/contract-version.ts";
import { contractRange, parseContractHeader } from "../src/contract-range.ts";
import { encodeHello, parseHello } from "../src/ws-frame.ts";
import { SNAP } from "./contract-bytes.ts";
import { pairedClient, request, requestAuth } from "./http.ts";
import { envelope, openWs } from "./ws-util.ts";

describe("contract range", () => {
  it("treats a missing header as v3 and rejects a broken header", () => {
    expect(parseContractHeader(undefined)).toEqual({
      ok: true,
      announcement: { contract: 3, minReadable: 3 },
    });
    expect(parseContractHeader("nope").ok).toBe(false);
    expect(contractRange(
      { contract: 4, minReadable: 3 },
      { contract: 3, minReadable: 3 },
    )).toBe("ok");
    expect(contractRange(
      { contract: 4, minReadable: 3 },
      { contract: 2, minReadable: 2 },
    )).toBe("peerTooOld");
    expect(contractRange(
      { contract: 4, minReadable: 3 },
      { contract: 4, minReadable: 5 },
    )).toBe("selfTooOld");
  });

  it("keeps an installed contract-4 client inside the range", () => {
    expect(MIN_READABLE).toBeLessThanOrEqual(4);
    expect(contractRange(
      { contract: CONTRACT, minReadable: MIN_READABLE },
      { contract: 4, minReadable: 3 },
    )).toBe("ok");
  });

  it("queues a command from an installed v4 client and from the current contract", async () => {
    const client = await pairedClient();
    const headers = ["4;min=3", `${CONTRACT};min=${MIN_READABLE}`];
    for (const [index, header] of headers.entries()) {
      const queued = await request("/v1/cmd", {
        method: "POST",
        headers: {
          authorization: `Bearer ${client.writeToken}`,
          "content-type": "application/json",
          "X-TT-Contract": header,
        },
        body: JSON.stringify(envelope("cmd", 7 + index)),
      });
      expect(queued.status).toBe(201);
    }
  });

  it("accepts a peer that does not announce and still queues the command", async () => {
    const client = await pairedClient();
    const queued = await requestAuth("/v1/cmd", "POST", client.writeToken, envelope("cmd", 1));
    expect(queued.status).toBe(201);
  });

  it("returns 426 for a command outside the range and still serves the snap", async () => {
    const client = await pairedClient();
    await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    const denied = await request("/v1/cmd", {
      method: "POST",
      headers: {
        authorization: `Bearer ${client.writeToken}`,
        "content-type": "application/json",
        "X-TT-Contract": "2;min=2",
      },
      body: JSON.stringify(envelope("cmd", 2)),
    });
    expect(denied.status).toBe(426);
    expect(denied.body).toEqual({
      error: "contractRange",
      contract: CONTRACT,
      minReadable: MIN_READABLE,
    });
    expect(denied.raw.headers.get("X-TT-Contract")).toBe(`${CONTRACT};min=${MIN_READABLE}`);

    const snap = await request("/v1/snap", {
      headers: {
        authorization: `Bearer ${client.writeToken}`,
        "X-TT-Contract": "2;min=2",
      },
    });
    expect(snap.status).toBe(200);
    const listed = await requestAuth("/v1/cmd", "GET", client.writeToken);
    expect(listed.body).toEqual({ items: [] });
  });

  it("answers hello with its own version and keeps forwarding snaps", async () => {
    const client = await pairedClient();
    const { ws, next } = await openWs(client.writeToken);
    ws.send(encodeHello(4, 3));
    expect(await next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });
    expect(parseHello(JSON.stringify({ t: "hello" }))).toEqual({ contract: 3, minReadable: 3 });

    await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    const snapFrame = await next();
    expect(snapFrame).toMatchObject({ t: "snap", envelope: { rev: 42, kind: "snap" } });
    ws.close(1000, "done");
  });
});

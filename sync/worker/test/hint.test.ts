import { describe, expect, it } from "vitest";
import { SNAP, SNAP_TITLE } from "./contract-bytes.ts";
import { envelope } from "./ws-util.ts";
import { createOffer, pairedClient, request, requestAuth } from "./http.ts";

describe("public hint", () => {
  it("returns zeroes for a confirmed pairing with no snap", async () => {
    const client = await pairedClient();
    const res = await request(`/v1/hint/${client.pairingId}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ snapRev: 0, ackRev: 0, cmdCount: 0 });
    expect(res.raw.headers.get("etag")).toBe('"0-0-0"');
    expect(res.raw.headers.get("cache-control")).toBe("public, max-age=5");
  });

  it("is unauthenticated and updates revs after snap/cmd/ack", async () => {
    const client = await pairedClient();
    await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    const afterSnap = await request(`/v1/hint/${client.pairingId}`);
    expect(afterSnap.body).toEqual({ snapRev: 42, ackRev: 0, cmdCount: 0 });
    expect(JSON.stringify(afterSnap.body)).not.toContain(SNAP_TITLE);
    expect(JSON.stringify(afterSnap.body)).not.toContain(SNAP.ct);

    await requestAuth("/v1/cmd", "POST", client.writeToken, envelope("cmd", 1));
    const afterCmd = await request(`/v1/hint/${client.pairingId}`);
    expect(afterCmd.body).toEqual({ snapRev: 42, ackRev: 0, cmdCount: 1 });

    await requestAuth("/v1/ack", "PUT", client.writeToken, envelope("ack", 1));
    const afterAck = await request(`/v1/hint/${client.pairingId}`);
    expect(afterAck.body).toEqual({ snapRev: 42, ackRev: 1, cmdCount: 0 });
  });

  it("returns 304 when If-None-Match matches", async () => {
    const client = await pairedClient();
    await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    const first = await request(`/v1/hint/${client.pairingId}`);
    const etag = first.raw.headers.get("etag");
    expect(etag).toBe('"42-0-0"');
    const again = await request(`/v1/hint/${client.pairingId}`, {
      headers: { "If-None-Match": etag ?? "" },
    });
    expect(again.status).toBe(304);
  });

  it("404s for an unconfirmed offer and a foreign uuid", async () => {
    const offer = await createOffer();
    const pending = await request(`/v1/hint/${offer.pairingId}`);
    expect(pending.status).toBe(404);
    expect(pending.body).toEqual({ error: "notFound" });

    const unknown = await request("/v1/hint/ffffffff-ffff-4fff-8fff-ffffffffffff");
    expect(unknown.status).toBe(404);
  });

  it("does not leak another pairing's revs", async () => {
    const a = await pairedClient();
    const b = await pairedClient();
    await requestAuth("/v1/snap", "PUT", a.writeToken, SNAP);
    const hintB = await request(`/v1/hint/${b.pairingId}`);
    expect(hintB.body).toEqual({ snapRev: 0, ackRev: 0, cmdCount: 0 });
    const hintA = await request(`/v1/hint/${a.pairingId}`);
    expect(hintA.body).toEqual({ snapRev: 42, ackRev: 0, cmdCount: 0 });
  });
});

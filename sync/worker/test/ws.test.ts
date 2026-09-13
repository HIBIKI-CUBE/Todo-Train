import { evictDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { ACK, CMD, SNAP } from "./contract-bytes.ts";
import { pairingStub } from "./do.ts";
import { pairedClient, request, requestAuth } from "./http.ts";
import { envelope, openWs } from "./ws-util.ts";

describe("websocket push", () => {
  it("pushes snap, cmd, and ack frames to a live connection", async () => {
    const client = await pairedClient();
    const { ws, next } = await openWs(client.writeToken);
    await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    expect(await next()).toEqual({ t: "snap", envelope: SNAP });
    await requestAuth("/v1/cmd", "POST", client.writeToken, CMD);
    expect(await next()).toEqual({ t: "cmd", envelope: CMD });
    await requestAuth("/v1/ack", "PUT", client.writeToken, ACK);
    expect(await next()).toEqual({ t: "ack", envelope: ACK });
    ws.close(1000, "done");
  });

  it("delivers the same snap to two connections on one pairing", async () => {
    const client = await pairedClient();
    const a = await openWs(client.writeToken);
    const b = await openWs(client.writeToken);
    await requestAuth("/v1/snap", "PUT", client.writeToken, envelope("snap", 3));
    const fa = await a.next();
    const fb = await b.next();
    expect(fa.t).toBe("snap");
    expect(fb).toEqual(fa);
    a.ws.close(1000, "done");
    b.ws.close(1000, "done");
  });

  it("keeps hibernated sockets and still pushes after eviction", async () => {
    const client = await pairedClient();
    const { ws, next } = await openWs(client.writeToken);
    await evictDurableObject(pairingStub(client.pairingId), { webSockets: "hibernate" });
    await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    expect(await next()).toEqual({ t: "snap", envelope: SNAP });
    ws.close(1000, "done");
  });

  it("rejects missing bearer, query tokens, and non-upgrade GETs", async () => {
    const noAuth = await request("/v1/ws", { headers: { upgrade: "websocket", connection: "Upgrade" } });
    expect(noAuth.status).toBe(401);
    const query = await request("/v1/ws?token=nope", { headers: { upgrade: "websocket", connection: "Upgrade" } });
    expect(query.status).toBe(401);
    const noUpgrade = await request("/v1/ws", { headers: { authorization: "Bearer x" } });
    expect(noUpgrade.status).toBe(400);
  });

  it("accepts X-Pairing-Id and rejects a foreign pairing", async () => {
    const a = await pairedClient();
    const b = await pairedClient();
    const { ws, next } = await openWs(a.writeToken, a.pairingId);
    await requestAuth("/v1/snap", "PUT", a.writeToken, SNAP, a.pairingId);
    expect(await next()).toEqual({ t: "snap", envelope: SNAP });
    ws.close(1000, "done");

    const foreign = await request("/v1/ws", {
      headers: {
        upgrade: "websocket",
        connection: "Upgrade",
        authorization: `Bearer ${a.writeToken}`,
        "X-Pairing-Id": b.pairingId,
      },
    });
    expect(foreign.status).toBe(401);
  });
});

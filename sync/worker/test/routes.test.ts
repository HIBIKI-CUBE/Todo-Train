import { runInDurableObject, SELF } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { CMD_FIFO_MAX } from "../src/constants.ts";
import { STATE_KEY, type PairingState } from "../src/pairing.ts";
import { ACK, CMD, HMAC_IPHONE, HMAC_MAC, S, SNAP, SNAP_TITLE, X, Y } from "./contract-bytes.ts";
import {
  bindBoth,
  createOffer,
  pairedClient,
  randomWriteToken,
  request,
  requestAuth,
  requestJson,
} from "./http.ts";

function pairingStub(pairingId: string) {
  return env.PAIRING.get(env.PAIRING.idFromName(pairingId)) as never;
}

async function readPairingState(pairingId: string): Promise<PairingState | undefined> {
  return runInDurableObject(pairingStub(pairingId), async (_instance, state: DurableObjectState) => {
    return state.storage.get<PairingState>(STATE_KEY);
  });
}

describe("offer + bind + confirm", () => {
  it("creates an offer from the golden X and returns TTL expiry", async () => {
    const before = Math.floor(Date.now() / 1000);
    const offer = await createOffer();
    expect(offer.offerId).toMatch(/^[0-9a-f-]{36}$/);
    expect(offer.pairingId).toMatch(/^[0-9a-f-]{36}$/);
    expect(offer.expiresAt).toBeGreaterThanOrEqual(before + 120);
    expect(offer.expiresAt).toBeLessThanOrEqual(before + 121);
  });

  it("rejects a malformed X", async () => {
    const res = await requestJson("/v1/offers", "POST", { x: "not-a-key" });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "invalid" });
  });

  it("does not bind on a single camera", async () => {
    const offer = await createOffer();
    const iphone = await requestJson(`/v1/offers/${offer.offerId}/bind`, "POST", {
      role: "iphone",
      s: S,
      y: Y,
    });
    expect(iphone.status).toBe(200);
    expect(iphone.body).toEqual({ bound: false });

    const confirm = await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", {
      hmac: HMAC_IPHONE,
    });
    expect(confirm.status).toBe(409);
    expect(confirm.body).toEqual({ error: "notBound" });
  });

  it("binds only after both optical reads, matching s and offer x", async () => {
    const offer = await createOffer();
    const { iphone, mac } = await bindBoth(offer.offerId);
    expect(iphone.body).toEqual({ bound: false });
    expect(mac.status).toBe(200);
    expect(mac.body).toEqual({
      bound: true,
      pairingId: offer.pairingId,
      s: S,
      x: X,
      y: Y,
    });
  });

  it("rejects a second bind of the same role with a different payload", async () => {
    const offer = await createOffer();
    await requestJson(`/v1/offers/${offer.offerId}/bind`, "POST", {
      role: "iphone",
      s: S,
      y: Y,
    });
    const otherY = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
    const res = await requestJson(`/v1/offers/${offer.offerId}/bind`, "POST", {
      role: "iphone",
      s: S,
      y: otherY,
    });
    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: "invalid" });
  });

  it("rejects Mac x that does not match the offer", async () => {
    const offer = await createOffer();
    await requestJson(`/v1/offers/${offer.offerId}/bind`, "POST", {
      role: "iphone",
      s: S,
      y: Y,
    });
    const res = await requestJson(`/v1/offers/${offer.offerId}/bind`, "POST", {
      role: "mac",
      s: S,
      x: Y,
    });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "invalid" });
  });

  it("confirms only when both HMACs arrive inside the window", async () => {
    const offer = await createOffer();
    await bindBoth(offer.offerId);
    const first = await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", {
      hmac: HMAC_IPHONE,
    });
    expect(first.body).toEqual({ confirmed: false });
    const second = await requestJson(`/v1/offers/${offer.offerId}/confirm-mac`, "POST", {
      hmac: HMAC_MAC,
    });
    expect(second.status).toBe(200);
    expect(second.body).toEqual({ confirmed: true, pairingId: offer.pairingId });
  });

  it("returns confirmWindow when the second HMAC is too late", async () => {
    const offer = await createOffer();
    await bindBoth(offer.offerId);
    await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", {
      hmac: HMAC_IPHONE,
    });
    const stub = pairingStub(offer.pairingId);
    await runInDurableObject(stub, async (_instance, state: DurableObjectState) => {
      const stored = await state.storage.get<PairingState>(STATE_KEY);
      if (!stored?.offer?.iphoneConfirm) throw new Error("missing first confirm");
      stored.offer.iphoneConfirm.at -= 20;
      await state.storage.put(STATE_KEY, stored);
    });
    const late = await requestJson(`/v1/offers/${offer.offerId}/confirm-mac`, "POST", {
      hmac: HMAC_MAC,
    });
    expect(late.status).toBe(410);
    expect(late.body).toEqual({ error: "confirmWindow" });
  });

  it("treats a same-role confirm with a different HMAC as hmacMismatch", async () => {
    const offer = await createOffer();
    await bindBoth(offer.offerId);
    await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", {
      hmac: HMAC_IPHONE,
    });
    const res = await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", {
      hmac: HMAC_MAC,
    });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "hmacMismatch" });
  });

  it("deletes an offer so later bind is notFound", async () => {
    const offer = await createOffer();
    const del = await request(`/v1/offers/${offer.offerId}`, { method: "DELETE" });
    expect(del.status).toBe(204);
    expect(del.body).toBeNull();
    const bind = await requestJson(`/v1/offers/${offer.offerId}/bind`, "POST", {
      role: "iphone",
      s: S,
      y: Y,
    });
    expect(bind.status).toBe(404);
    expect(bind.body).toEqual({ error: "notFound" });
  });
});

describe("snap / cmd / ack", () => {
  it("loads and returns the golden snap envelope without reading ct", async () => {
    const logs: string[] = [];
    const original = console.log;
    console.log = (...args: unknown[]) => {
      logs.push(args.map((a) => String(a)).join(" "));
    };
    try {
      const client = await pairedClient();
      expect(client.put.status).toBe(200);
      const put = await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
      expect(put.status).toBe(200);
      expect(put.body).toEqual({ rev: 42 });
      const got = await requestAuth("/v1/snap", "GET", client.writeToken);
      expect(got.status).toBe(200);
      expect(got.body).toEqual(SNAP);
      const stored = await readPairingState(client.pairingId);
      expect(JSON.stringify(stored)).not.toContain(SNAP_TITLE);
      expect(stored?.snap?.ct).toBe(SNAP.ct);
    } finally {
      console.log = original;
    }
    expect(logs.join("\n")).not.toContain(SNAP_TITLE);
  });

  it("rejects a non-monotonic snap rev", async () => {
    const client = await pairedClient();
    await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    const again = await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    expect(again.status).toBe(409);
    expect(again.body).toEqual({ error: "revConflict" });
  });

  it("queues opaque cmds up to fifo max and drops the matching rev on ack", async () => {
    const client = await pairedClient();
    const first = await requestAuth("/v1/cmd", "POST", client.writeToken, CMD);
    expect(first.status).toBe(201);
    expect(first.body).toEqual({ queued: true });
    for (let rev = 2; rev <= CMD_FIFO_MAX; rev++) {
      const res = await requestAuth("/v1/cmd", "POST", client.writeToken, { ...CMD, rev });
      expect(res.status).toBe(201);
    }
    const full = await requestAuth("/v1/cmd", "POST", client.writeToken, { ...CMD, rev: 9 });
    expect(full.status).toBe(409);
    expect(full.body).toEqual({ error: "fifoFull" });

    const pending = await requestAuth("/v1/cmd", "GET", client.writeToken);
    expect(pending.status).toBe(200);
    expect((pending.body as { items: unknown[] }).items).toHaveLength(CMD_FIFO_MAX);

    const ack = await requestAuth("/v1/ack", "PUT", client.writeToken, ACK);
    expect(ack.status).toBe(200);
    expect(ack.body).toEqual({ stored: true });

    const after = await requestAuth("/v1/cmd", "GET", client.writeToken);
    const items = (after.body as { items: Array<{ rev: number }> }).items;
    expect(items).toHaveLength(CMD_FIFO_MAX - 1);
    expect(items.every((item) => item.rev !== 1)).toBe(true);

    const gotAck = await requestAuth("/v1/ack", "GET", client.writeToken);
    expect(gotAck.body).toEqual(ACK);
  });

  it("returns 404 for snap and ack before anything is stored", async () => {
    const client = await pairedClient();
    const snap = await requestAuth("/v1/snap", "GET", client.writeToken);
    expect(snap.status).toBe(404);
    expect(snap.body).toEqual({ error: "notFound" });
    const ack = await requestAuth("/v1/ack", "GET", client.writeToken);
    expect(ack.status).toBe(404);
    const cmds = await requestAuth("/v1/cmd", "GET", client.writeToken);
    expect(cmds.body).toEqual({ items: [] });
  });

  it("rejects a missing or wrong bearer", async () => {
    const noAuth = await request("/v1/snap");
    expect(noAuth.status).toBe(401);
    expect(noAuth.body).toEqual({ error: "unauthorized" });
    await pairedClient();
    const bad = await requestAuth("/v1/snap", "GET", randomWriteToken());
    expect(bad.status).toBe(401);
    const malformed = await requestAuth("/v1/snap", "GET", "not-a-token");
    expect(malformed.status).toBe(401);
  });

  it("does not parse ct even when it is valid JSON text disguised as ciphertext shape", async () => {
    const client = await pairedClient();
    const put = await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    expect(put.status).toBe(200);
    await runInDurableObject(pairingStub(client.pairingId), async (_instance, state: DurableObjectState) => {
      const stored = await state.storage.get<PairingState>(STATE_KEY);
      const ct = stored?.snap?.ct;
      expect(typeof ct).toBe("string");
      expect(() => JSON.parse(ct!)).toThrow();
    });
  });
});

describe("websocket", () => {
  it("pushes t=snap to the open connection", async () => {
    const client = await pairedClient();
    const upgrade = await SELF.fetch("https://relay.test/v1/ws", {
      headers: {
        upgrade: "websocket",
        connection: "Upgrade",
        authorization: `Bearer ${client.writeToken}`,
      },
    });
    expect(upgrade.status).toBe(101);
    const ws = upgrade.webSocket;
    expect(ws).toBeDefined();
    ws!.accept();
    const got = new Promise<string>((resolve) => {
      ws!.addEventListener("message", (event) => resolve(String(event.data)));
    });
    await requestAuth("/v1/snap", "PUT", client.writeToken, SNAP);
    const frame = JSON.parse(await got) as { t: string; envelope: unknown };
    expect(frame.t).toBe("snap");
    expect(frame.envelope).toEqual(SNAP);
    ws!.close(1000, "done");
  });

  it("rejects WS without bearer", async () => {
    const res = await SELF.fetch("https://relay.test/v1/ws", {
      headers: { upgrade: "websocket", connection: "Upgrade" },
    });
    expect(res.status).toBe(401);
  });
});

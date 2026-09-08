import { describe, expect, it } from "vitest";
import { ACK, CMD, HMAC_IPHONE, HMAC_MAC, S, S_OTHER, SNAP, X, Y } from "./contract-bytes.ts";
import { patchPairingState } from "./do.ts";
import {
  bindBoth,
  bindIphone,
  bindMac,
  confirmBoth,
  createOffer,
  pairedClient,
  randomWriteToken,
  request,
  requestAuth,
  requestJson,
  tokenHash,
} from "./http.ts";
import { envelope } from "./ws-util.ts";

describe("bind idempotency and matching", () => {
  it("is a no-op when the same role repeats the same payload", async () => {
    const offer = await createOffer();
    const first = await bindIphone(offer.offerId);
    const again = await bindIphone(offer.offerId);
    expect(first.body).toEqual({ bound: false });
    expect(again.body).toEqual({ bound: false });
    const mac = await bindMac(offer.offerId);
    expect(mac.body).toMatchObject({ bound: true, pairingId: offer.pairingId });
    const iphoneAgain = await bindIphone(offer.offerId);
    expect(iphoneAgain.body).toMatchObject({ bound: true, pairingId: offer.pairingId, s: S, x: X, y: Y });
  });

  it("binds when Mac reports first, then iPhone", async () => {
    const offer = await createOffer();
    const mac = await bindMac(offer.offerId);
    expect(mac.body).toEqual({ bound: false });
    const iphone = await bindIphone(offer.offerId);
    expect(iphone.body).toMatchObject({ bound: true, pairingId: offer.pairingId, s: S, y: Y, x: X });
  });

  it("rejects mismatched s between the two cameras", async () => {
    const offer = await createOffer();
    await bindIphone(offer.offerId, S);
    const res = await bindMac(offer.offerId, S_OTHER);
    expect(res.status).toBe(409);
    expect(res.body).toEqual({ error: "invalid" });
  });
});

describe("confirm idempotency and order", () => {
  it("confirms Mac-first then iPhone, and retries are successBoth", async () => {
    const offer = await createOffer();
    await bindBoth(offer.offerId);
    const mac = await requestJson(`/v1/offers/${offer.offerId}/confirm-mac`, "POST", { hmac: HMAC_MAC });
    expect(mac.body).toEqual({ confirmed: false });
    const iphone = await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", { hmac: HMAC_IPHONE });
    expect(iphone.body).toEqual({ confirmed: true, pairingId: offer.pairingId });
    const retry = await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", { hmac: HMAC_IPHONE });
    expect(retry.body).toEqual({ confirmed: true, pairingId: offer.pairingId });
  });

  it("returns hmacMismatch for a well-shaped but short HMAC", async () => {
    const offer = await createOffer();
    await bindBoth(offer.offerId);
    const res = await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", { hmac: "short" });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "hmacMismatch" });
  });
});

describe("offer expiry and delete", () => {
  it("returns expired then notFound after TTL elapses", async () => {
    const offer = await createOffer();
    await patchPairingState(offer.pairingId, (stored) => {
      if (!stored.offer) throw new Error("missing offer");
      stored.offer.expiresAt = 1;
    });
    const bind = await bindIphone(offer.offerId);
    expect(bind.status).toBe(410);
    expect(bind.body).toEqual({ error: "expired" });
    const again = await bindIphone(offer.offerId);
    expect(again.status).toBe(404);
  });

  it("returns 404 for a second DELETE and for unknown ids", async () => {
    const offer = await createOffer();
    expect((await request(`/v1/offers/${offer.offerId}`, { method: "DELETE" })).status).toBe(204);
    expect((await request(`/v1/offers/${offer.offerId}`, { method: "DELETE" })).status).toBe(404);
    expect((await request("/v1/offers/00000000-0000-4000-8000-000000000000", { method: "DELETE" })).status).toBe(404);
  });
});

describe("tokenHash registration", () => {
  it("404s before confirm, stores once, then mismatches a different hash", async () => {
    const offer = await createOffer();
    const hash = await tokenHash(randomWriteToken());
    const early = await requestJson(`/v1/pairings/${offer.pairingId}`, "PUT", { tokenHash: hash });
    expect(early.status).toBe(404);

    await bindBoth(offer.offerId);
    await confirmBoth(offer.offerId);

    const first = await requestJson(`/v1/pairings/${offer.pairingId}`, "PUT", { tokenHash: hash });
    expect(first.status).toBe(200);
    expect(first.body).toEqual({ pairingId: offer.pairingId });
    const again = await requestJson(`/v1/pairings/${offer.pairingId}`, "PUT", { tokenHash: hash });
    expect(again.status).toBe(200);

    const other = await tokenHash(randomWriteToken());
    const clash = await requestJson(`/v1/pairings/${offer.pairingId}`, "PUT", { tokenHash: other });
    expect(clash.status).toBe(409);
    expect(clash.body).toEqual({ error: "tokenHashMismatch" });
  });

  it("does not authorize snap until tokenHash is registered", async () => {
    const offer = await createOffer();
    await bindBoth(offer.offerId);
    await confirmBoth(offer.offerId);
    const token = randomWriteToken();
    const snap = await requestAuth("/v1/snap", "GET", token);
    expect(snap.status).toBe(401);
  });
});

describe("full pairing journey", () => {
  it("goes offer → both binds → both confirms → tokenHash → snap/cmd/ack", async () => {
    const offer = await createOffer();
    expect((await bindIphone(offer.offerId)).body).toEqual({ bound: false });
    expect((await bindMac(offer.offerId)).body).toMatchObject({ bound: true });
    const waiting = await requestJson(`/v1/offers/${offer.offerId}/confirm-iphone`, "POST", { hmac: HMAC_IPHONE });
    expect(waiting.body).toEqual({ confirmed: false });
    const done = await requestJson(`/v1/offers/${offer.offerId}/confirm-mac`, "POST", { hmac: HMAC_MAC });
    expect(done.body).toEqual({ confirmed: true, pairingId: offer.pairingId });

    const writeToken = randomWriteToken();
    const put = await requestJson(`/v1/pairings/${offer.pairingId}`, "PUT", {
      tokenHash: await tokenHash(writeToken),
    });
    expect(put.status).toBe(200);

    expect((await requestAuth("/v1/snap", "PUT", writeToken, SNAP)).body).toEqual({ rev: 42 });
    expect((await requestAuth("/v1/snap", "GET", writeToken)).body).toEqual(SNAP);
    expect((await requestAuth("/v1/cmd", "POST", writeToken, CMD)).body).toEqual({ queued: true });
    expect((await requestAuth("/v1/cmd", "GET", writeToken)).body).toEqual({ items: [CMD] });
    expect((await requestAuth("/v1/ack", "PUT", writeToken, ACK)).body).toEqual({ stored: true });
    expect((await requestAuth("/v1/cmd", "GET", writeToken)).body).toEqual({ items: [] });
    expect((await requestAuth("/v1/ack", "GET", writeToken)).body).toEqual(ACK);
  });
});

describe("envelope validation on the wire", () => {
  it("rejects the wrong kind, padded n, and a non-monotonic smaller rev", async () => {
    const client = await pairedClient();
    const wrongKind = await requestAuth("/v1/snap", "PUT", client.writeToken, { ...SNAP, kind: "cmd" });
    expect(wrongKind.status).toBe(400);
    const padded = await requestAuth("/v1/snap", "PUT", client.writeToken, { ...SNAP, n: `${SNAP.n}=` });
    expect(padded.status).toBe(400);
    const first = await requestAuth("/v1/snap", "PUT", client.writeToken, envelope("snap", 0));
    expect(first.status).toBe(200);
    const next = await requestAuth("/v1/snap", "PUT", client.writeToken, envelope("snap", 7));
    expect(next.status).toBe(200);
    const back = await requestAuth("/v1/snap", "PUT", client.writeToken, envelope("snap", 7));
    expect(back.status).toBe(409);
    expect(back.body).toEqual({ error: "revConflict" });
  });

  it("keeps FIFO oldest-first and frees a slot after matching ack", async () => {
    const client = await pairedClient();
    await requestAuth("/v1/cmd", "POST", client.writeToken, envelope("cmd", 5));
    await requestAuth("/v1/cmd", "POST", client.writeToken, envelope("cmd", 2));
    const pending = await requestAuth("/v1/cmd", "GET", client.writeToken);
    expect((pending.body as { items: Array<{ rev: number }> }).items.map((i) => i.rev)).toEqual([5, 2]);

    await requestAuth("/v1/ack", "PUT", client.writeToken, envelope("ack", 5));
    const after = await requestAuth("/v1/cmd", "GET", client.writeToken);
    expect((after.body as { items: Array<{ rev: number }> }).items.map((i) => i.rev)).toEqual([2]);

    const secondAck = await requestAuth("/v1/ack", "PUT", client.writeToken, envelope("ack", 9, ACK.ct));
    expect(secondAck.status).toBe(200);
    const latest = await requestAuth("/v1/ack", "GET", client.writeToken);
    expect((latest.body as { rev: number }).rev).toBe(9);
  });

  it("rejects cmd/ack kind mismatches", async () => {
    const client = await pairedClient();
    expect((await requestAuth("/v1/cmd", "POST", client.writeToken, SNAP)).status).toBe(400);
    expect((await requestAuth("/v1/ack", "PUT", client.writeToken, CMD)).status).toBe(400);
  });
});

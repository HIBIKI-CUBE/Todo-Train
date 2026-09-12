import { DurableObject } from "cloudflare:workers";
import { parseBind, parseHmacBody } from "./bind-body.ts";
import { CMD_FIFO_MAX } from "./constants.ts";
import type { WireEnvelope } from "./envelope.ts";
import { parseEnvelope } from "./envelope.ts";
import { isPub32, isTokenHash32, isUuid } from "./ids.ts";
import { jsonError, jsonOk, type RpcResult } from "./result.ts";
import { confirmOverlapOk, isOfferExpired, offerExpiresAt } from "./time.ts";
import { encodeWsFrame } from "./ws-frame.ts";

// 永続するのは ciphertext とメタだけ。ct / hmac / token をログに出さない。

type BindIphone = { s: string; y: string };
type BindMac = { s: string; x: string };
type ConfirmSlot = { hmac: string; at: number };

type OfferState = {
  offerId: string;
  x: string;
  expiresAt: number;
  iphone: BindIphone | null;
  mac: BindMac | null;
  iphoneConfirm: ConfirmSlot | null;
  macConfirm: ConfirmSlot | null;
  confirmed: boolean;
};

type PairingState = {
  pairingId: string;
  offer: OfferState | null;
  confirmed: boolean;
  tokenHash: string | null;
  snap: WireEnvelope | null;
  cmds: WireEnvelope[];
  ack: WireEnvelope | null;
};

const STATE_KEY = "state";

function emptyState(pairingId: string): PairingState {
  return {
    pairingId,
    offer: null,
    confirmed: false,
    tokenHash: null,
    snap: null,
    cmds: [],
    ack: null,
  };
}

function bothBound(offer: OfferState): boolean {
  return offer.iphone !== null && offer.mac !== null;
}

function boundBody(pairingId: string, offer: OfferState) {
  return {
    bound: true,
    pairingId,
    s: offer.iphone!.s,
    x: offer.x,
    y: offer.iphone!.y,
  };
}

function confirmBothBody(pairingId: string) {
  return { confirmed: true, pairingId };
}

export class PairingDurableObject extends DurableObject<unknown> {
  private async load(): Promise<PairingState | null> {
    return (await this.ctx.storage.get<PairingState>(STATE_KEY)) ?? null;
  }

  private async save(state: PairingState): Promise<void> {
    await this.ctx.storage.put(STATE_KEY, state);
  }

  async createOffer(input: { pairingId: string; offerId: string; x: string; now: number }): Promise<RpcResult> {
    if (!isUuid(input.pairingId) || !isUuid(input.offerId) || !isPub32(input.x)) {
      return jsonError(400, "invalid");
    }
    const existing = await this.load();
    if (existing) return jsonError(409, "invalid");
    const expiresAt = offerExpiresAt(input.now);
    const state: PairingState = {
      ...emptyState(input.pairingId),
      offer: {
        offerId: input.offerId,
        x: input.x,
        expiresAt,
        iphone: null,
        mac: null,
        iphoneConfirm: null,
        macConfirm: null,
        confirmed: false,
      },
    };
    await this.save(state);
    return jsonOk(201, {
      offerId: input.offerId,
      pairingId: input.pairingId,
      expiresAt,
    });
  }

  async bind(input: { body: unknown; now: number }): Promise<RpcResult> {
    const state = await this.load();
    if (!state?.offer) return jsonError(404, "notFound");
    const offer = state.offer;
    if (isOfferExpired(offer.expiresAt, input.now) && !offer.confirmed) {
      return { ...jsonError(410, "expired"), dropOffer: true };
    }
    const parsed = parseBind(input.body);
    if (!parsed) return jsonError(400, "invalid");

    if (parsed.role === "iphone") {
      if (offer.iphone) {
        if (offer.iphone.s === parsed.s && offer.iphone.y === parsed.y) {
          return bothBound(offer)
            ? jsonOk(200, boundBody(state.pairingId, offer))
            : jsonOk(200, { bound: false });
        }
        return jsonError(409, "invalid");
      }
      if (offer.mac && offer.mac.s !== parsed.s) return jsonError(409, "invalid");
      offer.iphone = { s: parsed.s, y: parsed.y };
    } else {
      if (parsed.x !== offer.x) return jsonError(400, "invalid");
      if (offer.mac) {
        if (offer.mac.s === parsed.s && offer.mac.x === parsed.x) {
          return bothBound(offer)
            ? jsonOk(200, boundBody(state.pairingId, offer))
            : jsonOk(200, { bound: false });
        }
        return jsonError(409, "invalid");
      }
      if (offer.iphone && offer.iphone.s !== parsed.s) return jsonError(409, "invalid");
      offer.mac = { s: parsed.s, x: parsed.x };
    }

    await this.save(state);
    if (bothBound(offer)) return jsonOk(200, boundBody(state.pairingId, offer));
    return jsonOk(200, { bound: false });
  }

  async confirm(input: { role: "iphone" | "mac"; body: unknown; now: number }): Promise<RpcResult> {
    const state = await this.load();
    if (!state?.offer) return jsonError(404, "notFound");
    const offer = state.offer;
    if (offer.confirmed) {
      return jsonOk(200, confirmBothBody(state.pairingId));
    }
    if (isOfferExpired(offer.expiresAt, input.now)) {
      return { ...jsonError(410, "confirmWindow"), dropOffer: true };
    }
    if (!bothBound(offer)) return jsonError(409, "notBound");

    const hmac = parseHmacBody(input.body);
    if (hmac === "missing") return jsonError(400, "invalid");
    if (hmac === "bad") return jsonError(401, "hmacMismatch");

    const slot = input.role === "iphone" ? offer.iphoneConfirm : offer.macConfirm;
    if (slot) {
      if (slot.hmac !== hmac) return jsonError(401, "hmacMismatch");
      if (offer.iphoneConfirm && offer.macConfirm) {
        return jsonOk(200, confirmBothBody(state.pairingId));
      }
      return jsonOk(200, { confirmed: false });
    }

    const first = offer.iphoneConfirm ?? offer.macConfirm;
    if (first && !confirmOverlapOk(first.at, input.now)) {
      return jsonError(410, "confirmWindow");
    }

    const next: ConfirmSlot = { hmac, at: input.now };
    if (input.role === "iphone") offer.iphoneConfirm = next;
    else offer.macConfirm = next;

    if (offer.iphoneConfirm && offer.macConfirm) {
      offer.confirmed = true;
      state.confirmed = true;
      await this.save(state);
      return jsonOk(200, confirmBothBody(state.pairingId));
    }

    await this.save(state);
    return jsonOk(200, { confirmed: false });
  }

  async deleteOffer(): Promise<RpcResult> {
    const state = await this.load();
    if (!state?.offer) return jsonError(404, "notFound");
    state.offer = null;
    await this.save(state);
    return { status: 204, body: null, dropOffer: true };
  }

  async putTokenHash(tokenHash: string): Promise<RpcResult> {
    if (!isTokenHash32(tokenHash)) return jsonError(400, "invalid");
    const state = await this.load();
    if (!state?.confirmed) return jsonError(404, "notFound");
    if (state.tokenHash === null) {
      state.tokenHash = tokenHash;
      await this.save(state);
      return { ...jsonOk(200, { pairingId: state.pairingId }), registerTokenHash: tokenHash };
    }
    if (state.tokenHash !== tokenHash) return jsonError(409, "tokenHashMismatch");
    return { ...jsonOk(200, { pairingId: state.pairingId }), registerTokenHash: tokenHash };
  }

  async getSnap(tokenHash: string): Promise<RpcResult> {
    const state = await this.requirePaired(tokenHash);
    if ("status" in state) return state;
    if (!state.snap) return jsonError(404, "notFound");
    return jsonOk(200, state.snap);
  }

  async putSnap(body: unknown, tokenHash: string): Promise<RpcResult> {
    const state = await this.requirePaired(tokenHash);
    if ("status" in state) return state;
    const parsed = parseEnvelope(body, "snap");
    if (!parsed.ok) return jsonError(400, "invalid");
    const storedRev = state.snap?.rev ?? -1;
    if (parsed.envelope.rev <= storedRev) return jsonError(409, "revConflict");
    state.snap = parsed.envelope;
    await this.save(state);
    this.broadcast("snap", parsed.envelope);
    return jsonOk(200, { rev: parsed.envelope.rev });
  }

  async postCmd(body: unknown, tokenHash: string): Promise<RpcResult> {
    const state = await this.requirePaired(tokenHash);
    if ("status" in state) return state;
    const parsed = parseEnvelope(body, "cmd");
    if (!parsed.ok) return jsonError(400, "invalid");
    if (state.cmds.length >= CMD_FIFO_MAX) return jsonError(409, "fifoFull");
    state.cmds.push(parsed.envelope);
    await this.save(state);
    this.broadcast("cmd", parsed.envelope);
    return jsonOk(201, { queued: true });
  }

  async getCmd(tokenHash: string): Promise<RpcResult> {
    const state = await this.requirePaired(tokenHash);
    if ("status" in state) return state;
    return jsonOk(200, { items: state.cmds });
  }

  async putAck(body: unknown, tokenHash: string): Promise<RpcResult> {
    const state = await this.requirePaired(tokenHash);
    if ("status" in state) return state;
    const parsed = parseEnvelope(body, "ack");
    if (!parsed.ok) return jsonError(400, "invalid");
    state.ack = parsed.envelope;
    state.cmds = state.cmds.filter((item) => item.rev !== parsed.envelope.rev);
    await this.save(state);
    this.broadcast("ack", parsed.envelope);
    return jsonOk(200, { stored: true });
  }

  async getAck(tokenHash: string): Promise<RpcResult> {
    const state = await this.requirePaired(tokenHash);
    if ("status" in state) return state;
    if (!state.ack) return jsonError(404, "notFound");
    return jsonOk(200, state.ack);
  }

  async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }
    const tokenHash = request.headers.get("X-Token-Hash");
    const state = await this.requirePaired(tokenHash ?? "");
    if ("status" in state) {
      return Response.json(state.body, { status: state.status });
    }
    const pair = new WebSocketPair();
    this.ctx.acceptWebSocket(pair[1]);
    return new Response(null, { status: 101, webSocket: pair[0] });
  }

  async webSocketMessage(_ws: WebSocket, _message: string | ArrayBuffer): Promise<void> {
    // Clients do not send protocol frames. Ignore.
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string, _wasClean: boolean): Promise<void> {
    try {
      ws.close(code, reason);
    } catch {
      // already closed
    }
  }

  private async requirePaired(tokenHash: string): Promise<PairingState | RpcResult> {
    if (!isTokenHash32(tokenHash)) return jsonError(401, "unauthorized");
    const state = await this.load();
    if (!state?.confirmed || !state.tokenHash) return jsonError(401, "unauthorized");
    if (state.tokenHash !== tokenHash) return jsonError(401, "unauthorized");
    return state;
  }

  private broadcast(t: WireEnvelope["kind"], envelope: WireEnvelope): void {
    const frame = encodeWsFrame(t, envelope);
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.send(frame);
      } catch {
        try {
          ws.close();
        } catch {
          // ignore
        }
      }
    }
  }
}

export { STATE_KEY };
export type { PairingState };

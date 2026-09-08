import { Hono } from "hono";
import { decodeB64u, encodeB64u } from "./b64.ts";
import { isPub32, isTokenHash32, isUuid } from "./ids.ts";
import type { RpcResult } from "./result.ts";
import { unixSeconds } from "./time.ts";

type PairingRpc = {
  createOffer(input: { pairingId: string; offerId: string; x: string; now: number }): Promise<RpcResult>;
  bind(input: { body: unknown; now: number }): Promise<RpcResult>;
  confirm(input: { role: "iphone" | "mac"; body: unknown; now: number }): Promise<RpcResult>;
  deleteOffer(): Promise<RpcResult>;
  putTokenHash(tokenHash: string): Promise<RpcResult>;
  getSnap(): Promise<RpcResult>;
  putSnap(body: unknown): Promise<RpcResult>;
  postCmd(body: unknown): Promise<RpcResult>;
  getCmd(): Promise<RpcResult>;
  putAck(body: unknown): Promise<RpcResult>;
  getAck(): Promise<RpcResult>;
  fetch(request: Request): Promise<Response>;
};

type DirectoryRpc = {
  registerOffer(offerId: string, pairingId: string): Promise<void>;
  lookupOffer(offerId: string): Promise<string | null>;
  dropOffer(offerId: string): Promise<void>;
  registerTokenHash(tokenHash: string, pairingId: string): Promise<void>;
  lookupTokenHash(tokenHash: string): Promise<string | null>;
};

export type Env = {
  PAIRING: DurableObjectNamespace;
  DIRECTORY: DurableObjectNamespace;
};

const app = new Hono<{ Bindings: Env }>();

function directory(env: Env): DirectoryRpc {
  return env.DIRECTORY.get(env.DIRECTORY.idFromName("v1")) as unknown as DirectoryRpc;
}

function pairing(env: Env, pairingId: string): PairingRpc {
  return env.PAIRING.get(env.PAIRING.idFromName(pairingId)) as unknown as PairingRpc;
}

function errorJson(status: number, error: string) {
  return Response.json({ error }, { status });
}

function fromRpc(result: RpcResult): Response {
  if (result.status === 204) return new Response(null, { status: 204 });
  return Response.json(result.body, { status: result.status });
}

async function readJson(request: Request): Promise<unknown | typeof JSON_FAIL> {
  try {
    return await request.json();
  } catch {
    return JSON_FAIL;
  }
}

const JSON_FAIL = Symbol("json-fail");

function bearerToken(header: string | undefined): string | null {
  if (!header) return null;
  const match = /^Bearer[ ]+(\S+)$/i.exec(header);
  return match ? match[1] : null;
}

async function tokenHashOf(tokenB64u: string): Promise<string | null> {
  const bytes = decodeB64u(tokenB64u);
  if (!bytes || bytes.byteLength !== 32) return null;
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return encodeB64u(new Uint8Array(digest));
}

async function requirePairing(
  env: Env,
  authorization: string | undefined,
): Promise<{ pairingId: string } | Response> {
  const token = bearerToken(authorization);
  if (!token) return errorJson(401, "unauthorized");
  const hash = await tokenHashOf(token);
  if (!hash) return errorJson(401, "unauthorized");
  const pairingId = await directory(env).lookupTokenHash(hash);
  if (!pairingId) return errorJson(401, "unauthorized");
  return { pairingId };
}

async function applySideEffects(env: Env, offerId: string | undefined, pairingId: string, result: RpcResult) {
  if (result.dropOffer && offerId) await directory(env).dropOffer(offerId);
  if (result.registerTokenHash) {
    await directory(env).registerTokenHash(result.registerTokenHash, pairingId);
  }
}

app.post("/v1/offers", async (c) => {
  const body = await readJson(c.req.raw);
  if (body === JSON_FAIL || body === null || typeof body !== "object" || Array.isArray(body)) {
    return errorJson(400, "invalid");
  }
  const x = (body as { x?: unknown }).x;
  if (typeof x !== "string" || !isPub32(x)) return errorJson(400, "invalid");
  const pairingId = crypto.randomUUID();
  const offerId = crypto.randomUUID();
  const stub = pairing(c.env, pairingId);
  const result = await (stub.createOffer({ pairingId, offerId, x, now: unixSeconds() }));
  if (result.status === 201) await directory(c.env).registerOffer(offerId, pairingId);
  return fromRpc(result);
});

app.post("/v1/offers/:id/bind", async (c) => {
  const offerId = c.req.param("id");
  const pairingId = await directory(c.env).lookupOffer(offerId);
  if (!pairingId) return errorJson(404, "notFound");
  const body = await readJson(c.req.raw);
  if (body === JSON_FAIL) return errorJson(400, "invalid");
  const result = await (pairing(c.env, pairingId).bind({ body, now: unixSeconds() }));
  await applySideEffects(c.env, offerId, pairingId, result);
  return fromRpc(result);
});

app.post("/v1/offers/:id/confirm-iphone", async (c) => {
  return confirm(c, "iphone");
});

app.post("/v1/offers/:id/confirm-mac", async (c) => {
  return confirm(c, "mac");
});

async function confirm(
  c: { req: { param: (k: string) => string; raw: Request }; env: Env },
  role: "iphone" | "mac",
) {
  const offerId = c.req.param("id");
  const pairingId = await directory(c.env).lookupOffer(offerId);
  if (!pairingId) return errorJson(404, "notFound");
  const body = await readJson(c.req.raw);
  if (body === JSON_FAIL) return errorJson(400, "invalid");
  const result = await (pairing(c.env, pairingId).confirm({ role, body, now: unixSeconds() }));
  await applySideEffects(c.env, offerId, pairingId, result);
  return fromRpc(result);
}

app.delete("/v1/offers/:id", async (c) => {
  const offerId = c.req.param("id");
  const pairingId = await directory(c.env).lookupOffer(offerId);
  if (!pairingId) return errorJson(404, "notFound");
  const result = await (pairing(c.env, pairingId).deleteOffer());
  await applySideEffects(c.env, offerId, pairingId, result);
  return fromRpc(result);
});

app.put("/v1/pairings/:id", async (c) => {
  const pairingId = c.req.param("id");
  if (!isUuid(pairingId)) return errorJson(404, "notFound");
  const body = await readJson(c.req.raw);
  if (body === JSON_FAIL || body === null || typeof body !== "object" || Array.isArray(body)) {
    return errorJson(400, "invalid");
  }
  const tokenHash = (body as { tokenHash?: unknown }).tokenHash;
  if (typeof tokenHash !== "string" || !isTokenHash32(tokenHash)) return errorJson(400, "invalid");
  const result = await (pairing(c.env, pairingId).putTokenHash(tokenHash));
  await applySideEffects(c.env, undefined, pairingId, result);
  return fromRpc(result);
});

app.get("/v1/snap", async (c) => {
  const auth = await requirePairing(c.env, c.req.header("Authorization"));
  if (auth instanceof Response) return auth;
  return fromRpc(await (pairing(c.env, auth.pairingId).getSnap()));
});

app.put("/v1/snap", async (c) => {
  const auth = await requirePairing(c.env, c.req.header("Authorization"));
  if (auth instanceof Response) return auth;
  const body = await readJson(c.req.raw);
  if (body === JSON_FAIL) return errorJson(400, "invalid");
  return fromRpc(await (pairing(c.env, auth.pairingId).putSnap(body)));
});

app.post("/v1/cmd", async (c) => {
  const auth = await requirePairing(c.env, c.req.header("Authorization"));
  if (auth instanceof Response) return auth;
  const body = await readJson(c.req.raw);
  if (body === JSON_FAIL) return errorJson(400, "invalid");
  return fromRpc(await (pairing(c.env, auth.pairingId).postCmd(body)));
});

app.get("/v1/cmd", async (c) => {
  const auth = await requirePairing(c.env, c.req.header("Authorization"));
  if (auth instanceof Response) return auth;
  return fromRpc(await (pairing(c.env, auth.pairingId).getCmd()));
});

app.put("/v1/ack", async (c) => {
  const auth = await requirePairing(c.env, c.req.header("Authorization"));
  if (auth instanceof Response) return auth;
  const body = await readJson(c.req.raw);
  if (body === JSON_FAIL) return errorJson(400, "invalid");
  return fromRpc(await (pairing(c.env, auth.pairingId).putAck(body)));
});

app.get("/v1/ack", async (c) => {
  const auth = await requirePairing(c.env, c.req.header("Authorization"));
  if (auth instanceof Response) return auth;
  return fromRpc(await (pairing(c.env, auth.pairingId).getAck()));
});

app.get("/v1/ws", async (c) => {
  if (c.req.header("Upgrade")?.toLowerCase() !== "websocket") {
    return errorJson(400, "invalid");
  }
  const auth = await requirePairing(c.env, c.req.header("Authorization"));
  if (auth instanceof Response) return auth;
  return pairing(c.env, auth.pairingId).fetch(c.req.raw);
});

app.notFound(() => errorJson(404, "notFound"));

app.onError(() => errorJson(500, "invalid"));

export { DirectoryDurableObject } from "./directory.ts";
export { PairingDurableObject } from "./pairing.ts";
export default app;

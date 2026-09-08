import { SELF } from "cloudflare:test";
import { decodeB64u, encodeB64u } from "../src/b64.ts";
import { HMAC_IPHONE, HMAC_MAC, S, X, Y } from "./contract-bytes.ts";

export async function request(
  path: string,
  init: RequestInit = {},
): Promise<{ status: number; body: unknown; raw: Response }> {
  const raw = await SELF.fetch(`https://relay.test${path}`, init);
  const text = await raw.text();
  let body: unknown = null;
  if (text.length > 0) {
    try {
      body = JSON.parse(text);
    } catch {
      body = text;
    }
  }
  return { status: raw.status, body, raw };
}

export async function requestJson(
  path: string,
  method: string,
  body: unknown,
  token?: string,
): Promise<{ status: number; body: unknown }> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return request(path, { method, headers, body: JSON.stringify(body) });
}

export async function requestAuth(
  path: string,
  method: string,
  token: string,
  body?: unknown,
): Promise<{ status: number; body: unknown }> {
  const headers: Record<string, string> = { authorization: `Bearer ${token}` };
  if (body !== undefined) headers["content-type"] = "application/json";
  return request(path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

export function randomWriteToken(): string {
  return encodeB64u(crypto.getRandomValues(new Uint8Array(32)));
}

export async function tokenHash(token: string): Promise<string> {
  const bytes = decodeB64u(token);
  if (!bytes) throw new Error("bad token");
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return encodeB64u(new Uint8Array(digest));
}

export async function createOffer(x = X) {
  const res = await requestJson("/v1/offers", "POST", { x });
  if (res.status !== 201) throw new Error(`createOffer ${res.status} ${JSON.stringify(res.body)}`);
  const body = res.body as { offerId: string; pairingId: string; expiresAt: number };
  return body;
}

export async function bindBoth(offerId: string) {
  const iphone = await requestJson(`/v1/offers/${offerId}/bind`, "POST", {
    role: "iphone",
    s: S,
    y: Y,
  });
  const mac = await requestJson(`/v1/offers/${offerId}/bind`, "POST", {
    role: "mac",
    s: S,
    x: X,
  });
  return { iphone, mac };
}

export async function confirmBoth(offerId: string) {
  const iphone = await requestJson(`/v1/offers/${offerId}/confirm-iphone`, "POST", {
    hmac: HMAC_IPHONE,
  });
  const mac = await requestJson(`/v1/offers/${offerId}/confirm-mac`, "POST", {
    hmac: HMAC_MAC,
  });
  return { iphone, mac };
}

export async function pairedClient() {
  const offer = await createOffer();
  const bind = await bindBoth(offer.offerId);
  const confirm = await confirmBoth(offer.offerId);
  const writeToken = randomWriteToken();
  const hash = await tokenHash(writeToken);
  const put = await requestJson(`/v1/pairings/${offer.pairingId}`, "PUT", { tokenHash: hash });
  return { ...offer, writeToken, tokenHash: hash, bind, confirm, put };
}

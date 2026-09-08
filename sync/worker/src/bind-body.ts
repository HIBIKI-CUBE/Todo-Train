import { isHmac32, isPub32, isUuid } from "./ids.ts";

export type BindIphone = { role: "iphone"; s: string; y: string };
export type BindMac = { role: "mac"; s: string; x: string };
export type BindPayload = BindIphone | BindMac;

export function parseBind(body: unknown): BindPayload | null {
  if (body === null || typeof body !== "object" || Array.isArray(body)) return null;
  const o = body as Record<string, unknown>;
  if (o.role === "iphone") {
    if (typeof o.s !== "string" || typeof o.y !== "string") return null;
    if (!isUuid(o.s) || !isPub32(o.y)) return null;
    return { role: "iphone", s: o.s, y: o.y };
  }
  if (o.role === "mac") {
    if (typeof o.s !== "string" || typeof o.x !== "string") return null;
    if (!isUuid(o.s) || !isPub32(o.x)) return null;
    return { role: "mac", s: o.s, x: o.x };
  }
  return null;
}

export function parseHmacBody(body: unknown): string | "missing" | "bad" {
  if (body === null || typeof body !== "object" || Array.isArray(body)) return "missing";
  const o = body as Record<string, unknown>;
  if (!("hmac" in o)) return "missing";
  if (typeof o.hmac !== "string") return "missing";
  if (!isHmac32(o.hmac)) return "bad";
  return o.hmac;
}

import { isB64uBytes } from "./b64.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function isUuid(s: string): boolean {
  return UUID.test(s);
}

export function isPub32(s: string): boolean {
  return isB64uBytes(s, 32);
}

export function isHmac32(s: string): boolean {
  return isB64uBytes(s, 32);
}

export function isTokenHash32(s: string): boolean {
  return isB64uBytes(s, 32);
}

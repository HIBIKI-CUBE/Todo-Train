/** Unpadded base64url (RFC 4648 §5). Hex is not used on the wire. */

const B64U = /^[A-Za-z0-9_-]+$/;

export function decodeB64u(s: string): Uint8Array | null {
  if (s.length === 0 || s.includes("=") || !B64U.test(s)) return null;
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + pad;
  try {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch {
    return null;
  }
}

export function encodeB64u(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export function isB64uBytes(s: string, byteLength: number): boolean {
  const decoded = decodeB64u(s);
  return decoded !== null && decoded.byteLength === byteLength;
}

export function b64uByteLength(s: string): number | null {
  const decoded = decodeB64u(s);
  return decoded === null ? null : decoded.byteLength;
}

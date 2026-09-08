import { b64uByteLength, isB64uBytes } from "./b64.ts";

export const KINDS = ["snap", "cmd", "ack"] as const;
export type Kind = (typeof KINDS)[number];

export type WireEnvelope = {
  rev: number;
  kind: Kind;
  n: string;
  ct: string;
};

/**
 * Validate a wire envelope. Look at rev / kind / n / ct as opaque fields.
 * Never JSON.parse `ct`. Never decode `ct` into structured plaintext.
 */
export function parseEnvelope(
  input: unknown,
  expectedKind: Kind,
): { ok: true; envelope: WireEnvelope } | { ok: false } {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return { ok: false };
  }
  const o = input as Record<string, unknown>;
  if (typeof o.rev !== "number" || !Number.isInteger(o.rev) || o.rev < 0) {
    return { ok: false };
  }
  if (o.kind !== expectedKind) return { ok: false };
  if (typeof o.n !== "string" || !isB64uBytes(o.n, 12)) return { ok: false };
  if (typeof o.ct !== "string") return { ok: false };
  const ctLen = b64uByteLength(o.ct);
  // ciphertext || 16-byte tag. Opaque; do not parse the bytes.
  if (ctLen === null || ctLen < 16) return { ok: false };
  return {
    ok: true,
    envelope: { rev: o.rev, kind: expectedKind, n: o.n, ct: o.ct },
  };
}

export type Announcement = { contract: number; minReadable: number };

/** A peer that does not announce. */
export const LEGACY_ANNOUNCEMENT: Announcement = { contract: 3, minReadable: 3 };

export function parseContractHeader(
  value: string | undefined,
): { ok: true; announcement: Announcement } | { ok: false } {
  if (value === undefined) return { ok: true, announcement: LEGACY_ANNOUNCEMENT };
  const match = /^(\d+);min=(\d+)$/.exec(value.trim());
  if (!match) return { ok: false };
  const contract = Number(match[1]);
  const minReadable = Number(match[2]);
  if (contract < 1 || minReadable < 1) return { ok: false };
  return { ok: true, announcement: { contract, minReadable } };
}

export type ContractRange = "ok" | "peerTooOld" | "selfTooOld";

/** `ok` includes a newer peer. Operations stop only when the ranges do not overlap. */
export function contractRange(self: Announcement, peer: Announcement): ContractRange {
  if (peer.contract < self.minReadable) return "peerTooOld";
  if (self.contract < peer.minReadable) return "selfTooOld";
  return "ok";
}

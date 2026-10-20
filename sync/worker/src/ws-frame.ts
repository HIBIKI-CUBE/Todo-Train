import type { WireEnvelope } from "./envelope.ts";

export type WsFrame = {
  t: WireEnvelope["kind"];
  envelope: WireEnvelope;
};

export function encodeWsFrame(t: WireEnvelope["kind"], envelope: WireEnvelope): string {
  return JSON.stringify({ t, envelope } satisfies WsFrame);
}

export type HelloFrame = {
  t: "hello";
  contract: number;
  minReadable: number;
};

export function encodeHello(contract: number, minReadable: number): string {
  return JSON.stringify({ t: "hello", contract, minReadable } satisfies HelloFrame);
}

/** A hello frame. Incomplete numbers are the legacy announcement (v3). Not a hello → null. */
export function parseHello(message: string): { contract: number; minReadable: number } | null {
  let value: unknown;
  try {
    value = JSON.parse(message);
  } catch {
    return null;
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  const record = value as Record<string, unknown>;
  if (record.t !== "hello") return null;
  const contract = record.contract;
  const minReadable = record.minReadable;
  if (
    typeof contract === "number" && Number.isInteger(contract) && contract > 0
    && typeof minReadable === "number" && Number.isInteger(minReadable) && minReadable > 0
  ) {
    return { contract, minReadable };
  }
  return { contract: 3, minReadable: 3 };
}

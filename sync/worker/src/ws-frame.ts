import type { WireEnvelope } from "./envelope.ts";
import { isUuid } from "./ids.ts";

export type WsFrame = {
  t: WireEnvelope["kind"];
  envelope: WireEnvelope;
};

export function encodeWsFrame(t: WireEnvelope["kind"], envelope: WireEnvelope): string {
  return JSON.stringify({ t, envelope } satisfies WsFrame);
}

export type HelloRole = "iphone" | "mac";

export type HelloFrame = {
  t: "hello";
  contract: number;
  minReadable: number;
  role?: HelloRole;
};

export type HelloAnnouncement = {
  contract: number;
  minReadable: number;
  role?: HelloRole;
};

export function encodeHello(contract: number, minReadable: number): string {
  return JSON.stringify({ t: "hello", contract, minReadable } satisfies HelloFrame);
}

/** A hello frame. Incomplete numbers are the legacy announcement (v3). Not a hello → null. */
export function parseHello(message: string): HelloAnnouncement | null {
  const record = parseRecord(message);
  if (!record || record.t !== "hello") return null;
  const contract = record.contract;
  const minReadable = record.minReadable;
  const announcement: HelloAnnouncement =
    typeof contract === "number" && Number.isInteger(contract) && contract > 0
    && typeof minReadable === "number" && Number.isInteger(minReadable) && minReadable > 0
      ? { contract, minReadable }
      : { contract: 3, minReadable: 3 };
  if (record.role === "iphone" || record.role === "mac") announcement.role = record.role;
  return announcement;
}

/** Contract that added ping, pong, and echo. Older sockets stay on snap, cmd, ack, and hello. */
export const CONTROL_CONTRACT = 16;
export const CONTROL_FRAME_MAX_BYTES = 256;
export const PING_MIN_INTERVAL_MS = 1000;

export type ControlFrame =
  | { t: "ping"; id: string }
  | { t: "pong"; id: string }
  | { t: "echo"; id: string };

export function utf8ByteLength(text: string): number {
  return new TextEncoder().encode(text).byteLength;
}

/** ping, pong, or echo. Over 256 bytes, or an id that is not a lowercase UUID, is not a control frame. */
export function parseControlFrame(message: string): ControlFrame | null {
  if (utf8ByteLength(message) > CONTROL_FRAME_MAX_BYTES) return null;
  const record = parseRecord(message);
  if (!record) return null;
  const t = record.t;
  if (t !== "ping" && t !== "pong" && t !== "echo") return null;
  const id = record.id;
  if (typeof id !== "string" || !isUuid(id)) return null;
  return { t, id };
}

export function encodePing(id: string): string {
  return JSON.stringify({ t: "ping", id } satisfies ControlFrame);
}

export function encodePong(id: string): string {
  return JSON.stringify({ t: "pong", id } satisfies ControlFrame);
}

export function encodeEcho(id: string, mac: boolean): string {
  return JSON.stringify({ t: "echo", id, mac });
}

/** True when this socket has not sent a ping in the last second. */
export function pingIntervalOpen(lastPingAt: number | undefined, now: number): boolean {
  return lastPingAt === undefined || now - lastPingAt >= PING_MIN_INTERVAL_MS;
}

function parseRecord(message: string): Record<string, unknown> | null {
  let value: unknown;
  try {
    value = JSON.parse(message);
  } catch {
    return null;
  }
  if (value === null || typeof value !== "object" || Array.isArray(value)) return null;
  return value as Record<string, unknown>;
}

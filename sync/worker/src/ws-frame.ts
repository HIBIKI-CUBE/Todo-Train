import type { WireEnvelope } from "./envelope.ts";

export type WsFrame = {
  t: WireEnvelope["kind"];
  envelope: WireEnvelope;
};

export function encodeWsFrame(t: WireEnvelope["kind"], envelope: WireEnvelope): string {
  return JSON.stringify({ t, envelope } satisfies WsFrame);
}

import { SELF } from "cloudflare:test";
import type { WireEnvelope } from "../src/envelope.ts";
import { SNAP } from "./contract-bytes.ts";

export type RelayMessage = {
  t: string;
  envelope?: WireEnvelope;
  contract?: number;
  minReadable?: number;
  id?: string;
  mac?: boolean;
};

export function envelope(kind: WireEnvelope["kind"], rev: number, ct = SNAP.ct, n = SNAP.n): WireEnvelope {
  return { rev, kind, n, ct };
}

export async function openWs(
  token: string,
  pairingId?: string,
): Promise<{ ws: WebSocket; next: () => Promise<RelayMessage> }> {
  const headers: Record<string, string> = {
    upgrade: "websocket",
    connection: "Upgrade",
    authorization: `Bearer ${token}`,
  };
  if (pairingId) headers["X-Pairing-Id"] = pairingId;
  const upgrade = await SELF.fetch("https://relay.test/v1/ws", { headers });
  if (upgrade.status !== 101 || !upgrade.webSocket) {
    throw new Error(`ws upgrade ${upgrade.status}`);
  }
  const ws = upgrade.webSocket;
  ws.accept();
  const queued: RelayMessage[] = [];
  const waiters: Array<(frame: RelayMessage) => void> = [];
  ws.addEventListener("message", (event) => {
    const frame = JSON.parse(String(event.data)) as RelayMessage;
    const waiter = waiters.shift();
    if (waiter) waiter(frame);
    else queued.push(frame);
  });
  return {
    ws,
    next: () => {
      const already = queued.shift();
      if (already) return Promise.resolve(already);
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => reject(new Error("websocket frame timeout")), 5000);
        waiters.push((frame) => {
          clearTimeout(timer);
          resolve(frame);
        });
      });
    },
  };
}

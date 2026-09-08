import { SELF } from "cloudflare:test";
import type { WireEnvelope } from "../src/envelope.ts";
import type { WsFrame } from "../src/ws-frame.ts";
import { SNAP } from "./contract-bytes.ts";

export function envelope(kind: WireEnvelope["kind"], rev: number, ct = SNAP.ct, n = SNAP.n): WireEnvelope {
  return { rev, kind, n, ct };
}

export async function openWs(token: string): Promise<{ ws: WebSocket; next: () => Promise<WsFrame> }> {
  const upgrade = await SELF.fetch("https://relay.test/v1/ws", {
    headers: {
      upgrade: "websocket",
      connection: "Upgrade",
      authorization: `Bearer ${token}`,
    },
  });
  if (upgrade.status !== 101 || !upgrade.webSocket) {
    throw new Error(`ws upgrade ${upgrade.status}`);
  }
  const ws = upgrade.webSocket;
  ws.accept();
  const queued: WsFrame[] = [];
  const waiters: Array<(frame: WsFrame) => void> = [];
  ws.addEventListener("message", (event) => {
    const frame = JSON.parse(String(event.data)) as WsFrame;
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

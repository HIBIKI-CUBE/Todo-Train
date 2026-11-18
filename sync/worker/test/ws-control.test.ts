import { evictDurableObject, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { CONTRACT, MIN_READABLE } from "../src/contract-version.ts";
import { CONTROL_CONTRACT, encodeEcho, encodePing, utf8ByteLength } from "../src/ws-frame.ts";
import { ACK, CMD, SNAP } from "./contract-bytes.ts";
import { pairingStub } from "./do.ts";
import { pairedClient, requestAuth } from "./http.ts";
import { openWs, type RelayMessage } from "./ws-util.ts";

const ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const ID_B = "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff";

function clientHello(contract: number, role?: "iphone" | "mac", minReadable = 3): string {
  const frame: Record<string, number | string> = { t: "hello", contract, minReadable };
  if (role) frame.role = role;
  return JSON.stringify(frame);
}

async function join(token: string, hello: string) {
  const opened = await openWs(token);
  opened.ws.send(hello);
  expect(await opened.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });
  return opened;
}

async function pushSnapCmdAck(token: string): Promise<void> {
  await requestAuth("/v1/snap", "PUT", token, SNAP);
  await requestAuth("/v1/cmd", "POST", token, CMD);
  await requestAuth("/v1/ack", "PUT", token, ACK);
}

async function expectSnapCmdAck(next: () => Promise<RelayMessage>): Promise<void> {
  expect(await next()).toEqual({ t: "snap", envelope: SNAP });
  expect(await next()).toEqual({ t: "cmd", envelope: CMD });
  expect(await next()).toEqual({ t: "ack", envelope: ACK });
}

function pingOfSize(bytes: number, id: string): string {
  const prefix = `{"t":"ping","id":"${id}","pad":"`;
  const suffix = `"}`;
  const room = bytes - utf8ByteLength(prefix + suffix);
  const frame = prefix + "x".repeat(room) + suffix;
  if (utf8ByteLength(frame) !== bytes) throw new Error(`frame is ${utf8ByteLength(frame)} bytes`);
  return frame;
}

describe("control frames", () => {
  it("sends no ping, pong, or echo to a hello without role, and snap cmd ack stay the same", async () => {
    const client = await pairedClient();
    const token = client.writeToken;
    const legacy = await join(token, JSON.stringify({ t: "hello" }));
    const installed = await join(token, clientHello(15));
    const numberedWithoutRole = await join(token, clientHello(CONTROL_CONTRACT));
    const oldWithRole = await join(token, clientHello(15, "iphone"));
    const iphone = await join(token, clientHello(CONTROL_CONTRACT, "iphone"));
    const mac = await join(token, clientHello(CONTROL_CONTRACT, "mac"));

    iphone.ws.send(encodePing(ID));
    expect(await iphone.next()).toEqual({ t: "pong", id: ID });
    expect(await mac.next()).toEqual({ t: "ping", id: ID });
    mac.ws.send(JSON.stringify({ t: "echo", id: ID }));
    expect(await iphone.next()).toEqual({ t: "echo", id: ID, mac: true });

    // A later hello on the same socket is ordered after any control frame already queued.
    for (const opened of [legacy, installed, numberedWithoutRole, oldWithRole]) {
      opened.ws.send(JSON.stringify({ t: "hello" }));
      expect(await opened.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });
    }

    await pushSnapCmdAck(token);
    await expectSnapCmdAck(legacy.next);
    await expectSnapCmdAck(installed.next);
    await expectSnapCmdAck(numberedWithoutRole.next);
    await expectSnapCmdAck(oldWithRole.next);
    await expectSnapCmdAck(iphone.next);
    await expectSnapCmdAck(mac.next);

    for (const opened of [legacy, installed, numberedWithoutRole, oldWithRole, iphone, mac]) {
      opened.ws.close(1000, "done");
    }
  });

  it("drops ping and echo from a socket that omitted role, then still pushes snap, cmd, and ack", async () => {
    const client = await pairedClient();
    const token = client.writeToken;
    const old = await join(token, clientHello(15));
    const mac = await join(token, clientHello(CONTROL_CONTRACT, "mac"));

    old.ws.send(encodePing(ID));
    old.ws.send(JSON.stringify({ t: "echo", id: ID, mac: true }));
    old.ws.send(clientHello(15));
    expect(await old.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });
    mac.ws.send(clientHello(CONTROL_CONTRACT, "mac"));
    expect(await mac.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });
    await pushSnapCmdAck(token);
    await expectSnapCmdAck(old.next);
    await expectSnapCmdAck(mac.next);
    old.ws.close(1000, "done");
    mac.ws.close(1000, "done");
  });

  it("answers ping with pong and echo mac false when no mac is present", async () => {
    const client = await pairedClient();
    const iphone = await join(client.writeToken, clientHello(CONTROL_CONTRACT, "iphone"));
    iphone.ws.send(encodePing(ID));
    expect(await iphone.next()).toEqual({ t: "pong", id: ID });
    expect(await iphone.next()).toEqual({ t: "echo", id: ID, mac: false });
    iphone.ws.close(1000, "done");
  });

  it("forwards one ping to every current mac and the echo to every current iphone", async () => {
    const client = await pairedClient();
    const token = client.writeToken;
    const first = await join(token, clientHello(CONTROL_CONTRACT, "iphone"));
    const second = await join(token, clientHello(CONTROL_CONTRACT, "iphone"));
    const macA = await join(token, clientHello(CONTROL_CONTRACT, "mac"));
    const macB = await join(token, clientHello(CONTROL_CONTRACT, "mac"));
    const staleMac = await join(token, clientHello(15, "mac"));

    first.ws.send(encodePing(ID));
    expect(await first.next()).toEqual({ t: "pong", id: ID });
    expect(await macA.next()).toEqual({ t: "ping", id: ID });
    expect(await macB.next()).toEqual({ t: "ping", id: ID });
    macA.ws.send(JSON.stringify({ t: "echo", id: ID, mac: false }));
    expect(await first.next()).toEqual({ t: "echo", id: ID, mac: true });
    expect(await second.next()).toEqual({ t: "echo", id: ID, mac: true });
    staleMac.ws.send(clientHello(15, "mac"));
    expect(await staleMac.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });

    await requestAuth("/v1/snap", "PUT", token, SNAP);
    expect(await second.next()).toEqual({ t: "snap", envelope: SNAP });
    expect(await macA.next()).toEqual({ t: "snap", envelope: SNAP });
    expect(await staleMac.next()).toEqual({ t: "snap", envelope: SNAP });
    for (const opened of [first, second, macA, macB, staleMac]) opened.ws.close(1000, "done");
  });

  it("discards a second ping inside one second and accepts one after the second", async () => {
    const client = await pairedClient();
    const iphone = await join(client.writeToken, clientHello(CONTROL_CONTRACT, "iphone"));
    const mac = await join(client.writeToken, clientHello(CONTROL_CONTRACT, "mac"));
    iphone.ws.send(encodePing(ID));
    expect(await iphone.next()).toEqual({ t: "pong", id: ID });
    expect(await mac.next()).toEqual({ t: "ping", id: ID });

    iphone.ws.send(encodePing(ID_B));
    iphone.ws.send(clientHello(CONTROL_CONTRACT, "iphone"));
    expect(await iphone.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });
    mac.ws.send(clientHello(CONTROL_CONTRACT, "mac"));
    expect(await mac.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });

    await new Promise((resolve) => setTimeout(resolve, 1_100));
    iphone.ws.send(encodePing(ID));
    expect(await iphone.next()).toEqual({ t: "pong", id: ID });
    expect(await mac.next()).toEqual({ t: "ping", id: ID });
    iphone.ws.close(1000, "done");
    mac.ws.close(1000, "done");
  }, 20_000);

  it("discards a ping before hello, a bad id, an oversized frame, and echo from an iphone", async () => {
    const client = await pairedClient();
    const token = client.writeToken;
    const iphone = await openWs(token);
    iphone.ws.send(encodePing(ID));
    iphone.ws.send(clientHello(CONTROL_CONTRACT, "iphone"));
    expect(await iphone.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });

    const mac = await join(token, clientHello(CONTROL_CONTRACT, "mac"));
    iphone.ws.send(JSON.stringify({ t: "ping", id: "not-a-uuid" }));
    iphone.ws.send(JSON.stringify({ t: "ping", id: ID.toUpperCase() }));
    iphone.ws.send(JSON.stringify({ t: "ping" }));
    iphone.ws.send(pingOfSize(257, ID_B));
    iphone.ws.send(JSON.stringify({ t: "pong", id: ID }));
    iphone.ws.send(encodeEcho(ID, true));
    iphone.ws.send(clientHello(CONTROL_CONTRACT, "iphone"));
    expect(await iphone.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });
    mac.ws.send(clientHello(CONTROL_CONTRACT, "mac"));
    expect(await mac.next()).toEqual({ t: "hello", contract: CONTRACT, minReadable: MIN_READABLE });

    iphone.ws.send(pingOfSize(256, ID));
    expect(await iphone.next()).toEqual({ t: "pong", id: ID });
    expect(await mac.next()).toEqual({ t: "ping", id: ID });
    iphone.ws.close(1000, "done");
    mac.ws.close(1000, "done");
  });

  it("keeps role and contract across hibernation and does not store the ping id", async () => {
    const client = await pairedClient();
    const iphone = await join(client.writeToken, clientHello(CONTROL_CONTRACT, "iphone"));
    await evictDurableObject(pairingStub(client.pairingId), { webSockets: "hibernate" });
    iphone.ws.send(encodePing(ID));
    expect(await iphone.next()).toEqual({ t: "pong", id: ID });
    expect(await iphone.next()).toEqual({ t: "echo", id: ID, mac: false });

    const dumped = await runInDurableObject(
      pairingStub(client.pairingId),
      async (_instance, state) => {
        const stored = await state.storage.list();
        const attachments = state.getWebSockets().map((socket) => socket.deserializeAttachment());
        return { stored: [...stored.values()], attachments };
      },
    );
    expect(JSON.stringify(dumped)).not.toContain(ID);
    expect(dumped.attachments).toEqual([
      { contract: CONTROL_CONTRACT, minReadable: 3, role: "iphone", lastPingAt: expect.any(Number) },
    ]);
    iphone.ws.close(1000, "done");
  });
});

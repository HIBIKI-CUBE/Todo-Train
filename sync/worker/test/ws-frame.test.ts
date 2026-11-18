import { describe, expect, it } from "vitest";
import {
  CONTROL_CONTRACT,
  CONTROL_FRAME_MAX_BYTES,
  encodeEcho,
  encodeHello,
  encodePing,
  encodePong,
  parseControlFrame,
  parseHello,
  pingIntervalOpen,
  utf8ByteLength,
} from "../src/ws-frame.ts";

const ID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";

describe("hello and control frames", () => {
  it("keeps a hello without role on the old shape", () => {
    expect(parseHello(JSON.stringify({ t: "hello" }))).toEqual({ contract: 3, minReadable: 3 });
    expect(parseHello(encodeHello(15, 3))).toEqual({ contract: 15, minReadable: 3 });
    expect(JSON.parse(encodeHello(CONTROL_CONTRACT, 3))).toEqual({
      t: "hello",
      contract: CONTROL_CONTRACT,
      minReadable: 3,
    });
  });

  it("reads iphone and mac and ignores any other role", () => {
    expect(parseHello(JSON.stringify({
      t: "hello",
      contract: 16,
      minReadable: 3,
      role: "iphone",
    }))).toEqual({ contract: 16, minReadable: 3, role: "iphone" });
    expect(parseHello(JSON.stringify({
      t: "hello",
      contract: 16,
      minReadable: 3,
      role: "mac",
    }))).toEqual({ contract: 16, minReadable: 3, role: "mac" });
    expect(parseHello(JSON.stringify({
      t: "hello",
      contract: 16,
      minReadable: 3,
      role: "watch",
    }))).toEqual({ contract: 16, minReadable: 3 });
  });

  it("parses ping, pong, and echo and rejects a bad id or an oversized frame", () => {
    expect(parseControlFrame(encodePing(ID))).toEqual({ t: "ping", id: ID });
    expect(parseControlFrame(encodePong(ID))).toEqual({ t: "pong", id: ID });
    expect(parseControlFrame(encodeEcho(ID, false))).toEqual({ t: "echo", id: ID });
    expect(parseControlFrame(JSON.stringify({ t: "echo", id: ID, mac: false }))).toEqual({
      t: "echo",
      id: ID,
    });
    expect(parseControlFrame(JSON.stringify({ t: "ping", id: ID.toUpperCase() }))).toBeNull();
    expect(parseControlFrame(JSON.stringify({ t: "ping", id: "not-a-uuid" }))).toBeNull();
    expect(parseControlFrame(JSON.stringify({ t: "ping" }))).toBeNull();
    expect(parseControlFrame(encodeHello(16, 3))).toBeNull();
    expect(parseHello(encodePing(ID))).toBeNull();

    const oversized = `${encodePing(ID).slice(0, -1)},"pad":"${"x".repeat(CONTROL_FRAME_MAX_BYTES)}"}`;
    expect(utf8ByteLength(oversized)).toBeGreaterThan(CONTROL_FRAME_MAX_BYTES);
    expect(parseControlFrame(oversized)).toBeNull();
    for (const frame of [encodePing(ID), encodePong(ID), encodeEcho(ID, true)]) {
      expect(utf8ByteLength(frame)).toBeLessThanOrEqual(CONTROL_FRAME_MAX_BYTES);
    }
  });

  it("accepts the next ping only after a full second", () => {
    expect(pingIntervalOpen(undefined, 5_000)).toBe(true);
    expect(pingIntervalOpen(5_000, 5_999)).toBe(false);
    expect(pingIntervalOpen(5_000, 6_000)).toBe(true);
  });
});

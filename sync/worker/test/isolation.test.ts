import { describe, expect, it } from "vitest";
import { SNAP } from "./contract-bytes.ts";
import { pairedClient, requestAuth } from "./http.ts";
import { envelope } from "./ws-util.ts";

describe("pairing isolation", () => {
  it("does not leak snap, cmd, or ack across pairings", async () => {
    const a = await pairedClient();
    const b = await pairedClient();
    await requestAuth("/v1/snap", "PUT", a.writeToken, SNAP);
    await requestAuth("/v1/cmd", "POST", a.writeToken, envelope("cmd", 1));
    await requestAuth("/v1/ack", "PUT", a.writeToken, envelope("ack", 1));

    expect((await requestAuth("/v1/snap", "GET", b.writeToken)).status).toBe(404);
    expect((await requestAuth("/v1/cmd", "GET", b.writeToken)).body).toEqual({ items: [] });
    expect((await requestAuth("/v1/ack", "GET", b.writeToken)).status).toBe(404);

    const snapA = await requestAuth("/v1/snap", "GET", a.writeToken);
    expect(snapA.body).toEqual(SNAP);
  });

  it("requires bearer on every post-pairing surface", async () => {
    const paths = [
      ["GET", "/v1/snap"],
      ["PUT", "/v1/snap"],
      ["POST", "/v1/cmd"],
      ["GET", "/v1/cmd"],
      ["PUT", "/v1/ack"],
      ["GET", "/v1/ack"],
    ] as const;
    for (const [method, path] of paths) {
      const res = await requestAuth(path, method, "not-a-token", method === "GET" ? undefined : SNAP);
      expect(res.status, `${method} ${path}`).toBe(401);
    }
  });

  it("accepts X-Pairing-Id and rejects a foreign pairing", async () => {
    const a = await pairedClient();
    const b = await pairedClient();
    const put = await requestAuth("/v1/snap", "PUT", a.writeToken, SNAP, a.pairingId);
    expect(put.status).toBe(200);
    const got = await requestAuth("/v1/snap", "GET", a.writeToken, undefined, a.pairingId);
    expect(got.body).toEqual(SNAP);

    const foreign = await requestAuth("/v1/snap", "GET", a.writeToken, undefined, b.pairingId);
    expect(foreign.status).toBe(401);
    const still = await requestAuth("/v1/snap", "GET", a.writeToken);
    expect(still.body).toEqual(SNAP);

    const badId = await requestAuth("/v1/snap", "GET", a.writeToken, undefined, "not-a-uuid");
    expect(badId.status).toBe(401);
  });
});

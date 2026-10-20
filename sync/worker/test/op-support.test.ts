import { describe, expect, it } from "vitest";
import { CONTRACT } from "../src/contract-version.ts";
import { opAck } from "../src/op-support.ts";

describe("op support", () => {
  it("passes ops introduced at or before the receiver contract", () => {
    expect(opAck("pause", 3)).toBe("ok");
    expect(opAck("issueAndBoard", 4)).toBe("ok");
    expect(opAck("answer", CONTRACT)).toBe("ok");
    expect(opAck("boardReserved", CONTRACT)).toBe("ok");
    expect(opAck("presence", CONTRACT)).toBe("ok");
    expect(opAck("pauseInputReport", CONTRACT)).toBe("ok");
    expect(opAck("reestimate", CONTRACT)).toBe("ok");
    expect(opAck("undoReestimate", CONTRACT)).toBe("ok");
  });

  it("returns unsupportedOp when the receiver contract predates the op", () => {
    expect(opAck("answer", 4)).toBe("unsupportedOp");
    expect(opAck("boardReserved", 4)).toBe("unsupportedOp");
    expect(opAck("presence", 3)).toBe("unsupportedOp");
    expect(opAck("pauseInputReport", 11)).toBe("unsupportedOp");
    expect(opAck("reestimate", 14)).toBe("unsupportedOp");
    expect(opAck("undoReestimate", 14)).toBe("unsupportedOp");
    expect(opAck("extend", CONTRACT)).toBe("unsupportedOp");
    expect(opAck("arrive", CONTRACT)).toBe("unsupportedOp");
  });
});

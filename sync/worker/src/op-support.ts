import enums from "../../contract/enums.json" with { type: "json" };

const introduced = enums.opIntroduced as Record<string, number>;

/**
 * Receiver ack for an op at a contract version.
 * The relay does not open `ct`, so it does not call this on the request path.
 * In-range envelopes, including those from an installed v4 client, are forwarded.
 * A receiver whose contract predates the op returns `unsupportedOp`.
 */
export function opAck(op: string, receiverContract: number): "ok" | "unsupportedOp" {
  const at = introduced[op];
  if (typeof at !== "number" || receiverContract < at) return "unsupportedOp";
  return "ok";
}

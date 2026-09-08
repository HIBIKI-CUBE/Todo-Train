export type ErrorCode =
  | "invalid"
  | "notFound"
  | "expired"
  | "unauthorized"
  | "notBound"
  | "confirmWindow"
  | "hmacMismatch"
  | "tokenHashMismatch"
  | "revConflict"
  | "fifoFull";

export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

export type RpcResult = {
  status: number;
  body: JsonValue;
  dropOffer?: boolean;
  registerTokenHash?: string;
};

export function jsonError(status: number, error: ErrorCode): RpcResult {
  return { status, body: { error } };
}

export function jsonOk(status: number, body: JsonValue): RpcResult {
  return { status, body };
}

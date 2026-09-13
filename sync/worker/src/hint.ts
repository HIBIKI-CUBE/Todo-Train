import type { HintBody } from "./result.ts";

export const HINT_MAX_AGE_SECONDS = 5;

export function hintETag(hint: HintBody): string {
  return `"${hint.snapRev}-${hint.ackRev}-${hint.cmdCount}"`;
}

export function hintHeaders(hint: HintBody): Headers {
  return new Headers({
    ETag: hintETag(hint),
    "Cache-Control": `public, max-age=${HINT_MAX_AGE_SECONDS}`,
  });
}

export function hintHTTPResponse(hint: HintBody, ifNoneMatch: string | undefined): Response {
  const headers = hintHeaders(hint);
  if (ifNoneMatch === headers.get("ETag")) {
    return new Response(null, { status: 304, headers });
  }
  return Response.json(hint, { status: 200, headers });
}

export function hintCacheKey(requestUrl: string, pairingId: string): Request {
  return new Request(new URL(`/v1/hint/${pairingId}`, requestUrl), { method: "GET" });
}

export async function storeHintCache(
  requestUrl: string,
  pairingId: string,
  hint: HintBody,
): Promise<void> {
  try {
    await caches.default.put(hintCacheKey(requestUrl, pairingId), hintHTTPResponse(hint, undefined));
  } catch {
    // Cache is optional. Misses fall through to the Durable Object.
  }
}

export async function readHintCache(
  requestUrl: string,
  pairingId: string,
): Promise<Response | undefined> {
  try {
    return await caches.default.match(hintCacheKey(requestUrl, pairingId));
  } catch {
    return undefined;
  }
}

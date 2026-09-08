import { runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { STATE_KEY, type PairingState } from "../src/pairing.ts";

export function pairingStub(pairingId: string) {
  return env.PAIRING.get(env.PAIRING.idFromName(pairingId)) as never;
}

export async function readPairingState(pairingId: string): Promise<PairingState | undefined> {
  return runInDurableObject(pairingStub(pairingId), async (_instance, state: DurableObjectState) => {
    return state.storage.get<PairingState>(STATE_KEY);
  });
}

export async function patchPairingState(
  pairingId: string,
  patch: (stored: PairingState) => void,
): Promise<void> {
  await runInDurableObject(pairingStub(pairingId), async (_instance, state: DurableObjectState) => {
    const stored = await state.storage.get<PairingState>(STATE_KEY);
    if (!stored) throw new Error("missing pairing state");
    patch(stored);
    await state.storage.put(STATE_KEY, stored);
  });
}

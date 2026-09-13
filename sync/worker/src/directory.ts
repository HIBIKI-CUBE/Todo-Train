import { DurableObject } from "cloudflare:workers";

const OFFER = "offer:";
const TOKEN = "token:";

export class DirectoryDurableObject extends DurableObject<unknown> {
  async registerOffer(offerId: string, pairingId: string): Promise<void> {
    await this.ctx.storage.put(OFFER + offerId, pairingId);
  }

  async lookupOffer(offerId: string): Promise<string | null> {
    return (await this.ctx.storage.get<string>(OFFER + offerId)) ?? null;
  }

  async dropOffer(offerId: string): Promise<void> {
    await this.ctx.storage.delete(OFFER + offerId);
  }

  async registerTokenHash(tokenHash: string, pairingId: string): Promise<void> {
    await this.ctx.storage.put(TOKEN + tokenHash, pairingId);
  }

  async lookupTokenHash(tokenHash: string): Promise<string | null> {
    return (await this.ctx.storage.get<string>(TOKEN + tokenHash)) ?? null;
  }
}

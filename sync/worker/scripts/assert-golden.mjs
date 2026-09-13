import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const workerRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const contractRoot = join(workerRoot, "../contract");

const http = JSON.parse(readFileSync(join(contractRoot, "http.json"), "utf8"));
const constants = JSON.parse(readFileSync(join(contractRoot, "constants.json"), "utf8"));
const localConstants = JSON.parse(readFileSync(join(workerRoot, "src/constants.json"), "utf8"));
const bytes = readFileSync(join(workerRoot, "test/contract-bytes.ts"), "utf8");
const fixture = JSON.parse(readFileSync(join(contractRoot, "fixtures/snap.json"), "utf8"));

const route = (id) => {
  const found = http.routes.find((r) => r.id === id);
  if (!found) throw new Error(`missing route ${id}`);
  return found;
};

function mustContain(label, value) {
  if (typeof value !== "string" || value.length === 0) throw new Error(`empty ${label}`);
  if (!bytes.includes(value)) throw new Error(`test/contract-bytes.ts is missing ${label}: ${value}`);
}

mustContain("createOffer.x", route("createOffer").request.x);
mustContain("bind.s", route("bindOffer").requestIphone.s);
mustContain("bind.y", route("bindOffer").requestIphone.y);
mustContain("bind.x", route("bindOffer").requestMac.x);
mustContain("confirm-iphone.hmac", route("confirmIphone").request.hmac);
mustContain("confirm-mac.hmac", route("confirmMac").request.hmac);
mustContain("snap.n", route("putSnap").request.n);
mustContain("snap.ct", route("putSnap").request.ct);
mustContain("snap title", fixture.title);

if (JSON.stringify(localConstants) !== JSON.stringify(constants)) {
  throw new Error("src/constants.json drifted from sync/contract/constants.json");
}

console.log("assert-golden: contract bytes and constants match");

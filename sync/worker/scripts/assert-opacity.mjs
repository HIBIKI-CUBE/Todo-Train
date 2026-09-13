import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const srcDir = join(dirname(fileURLToPath(import.meta.url)), "../src");
const forbidden = [
  "週次レポート",
  "masterKey",
  "fixtures/snap",
  "aes-gcm-snap",
  "plaintext",
];
const parseCt = /JSON\.parse\s*\(\s*[^)]*\bct\b/;

for (const name of readdirSync(srcDir)) {
  if (!name.endsWith(".ts") && !name.endsWith(".json")) continue;
  const text = readFileSync(join(srcDir, name), "utf8");
  for (const needle of forbidden) {
    if (text.includes(needle)) {
      throw new Error(`${name} contains forbidden ${needle}`);
    }
  }
  if (parseCt.test(text)) {
    throw new Error(`${name} JSON.parse()s ct`);
  }
}

console.log("assert-opacity: worker src has no plaintext fixtures or ct JSON.parse");

#!/usr/bin/env node
// 指紋が AppSchema.fingerprint と合うこと、
// base より指紋が変わったのに版が上がっていなければ落とすこと。

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import {
  compareVersion,
  fingerprintOf,
  latestSchema,
  readAppSchema,
  readFingerprint,
} from "./fingerprint.mjs";

export const MODEL_CHANGED =
  "モデルが変わりました。AppSchema に新しい版を足し、移行段を書いてください";

export function judge({ computed, head, latest, base }) {
  const errors = [];
  const hashMismatch = !head || head.fingerprint !== computed;
  const notPaired = !head || head.name !== latest.name || head.version !== latest.version;
  const versionNotRaised = Boolean(
    base
    && head
    && head.fingerprint !== base.fingerprint
    && compareVersion(head.version, base.version) <= 0,
  );
  if (hashMismatch || notPaired || versionNotRaised) errors.push(MODEL_CHANGED);
  return errors;
}

function git(args) {
  return spawnSync("git", args, { encoding: "utf8" });
}

function commitExists(sha) {
  if (!sha || /^0+$/.test(sha)) return false;
  return git(["cat-file", "-e", `${sha}^{commit}`]).status === 0;
}

function readFingerprintAt(ref) {
  const result = git(["show", `${ref}:Todo train/App/AppSchema.fingerprint`]);
  if (result.status !== 0) return null;
  try {
    return JSON.parse(result.stdout);
  } catch {
    return null;
  }
}

function readHead() {
  try {
    return readFingerprint();
  } catch {
    return null;
  }
}

function main() {
  const head = readHead();
  const computed = fingerprintOf();
  const latest = latestSchema(readAppSchema());
  const baseSha = process.env.BASE_SHA;
  const base = commitExists(baseSha) ? readFingerprintAt(baseSha) : null;
  const errors = judge({ computed, head, latest, base });
  if (errors.length > 0) {
    for (const error of errors) console.error(error);
    console.error(`computed ${computed}`);
    console.error(`file     ${head ? head.fingerprint : "(なし)"}`);
    process.exit(1);
  }
  console.log(`schema-guard: ${head.name} ${head.version} fingerprint ok`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main();
}

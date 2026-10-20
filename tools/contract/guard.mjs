#!/usr/bin/env node
// 指紋が version.json と合うこと、base より指紋が変わったのに contract が上がっていなければ落とすこと、
// base に既にある凍結 fixtures が変わっていなければ落とすこと。

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";
import { fingerprintOf, readVersion } from "./fingerprint.mjs";

export function judge({ computed, head, base, frozenChanged }) {
  const errors = [];
  if (head.fingerprint !== computed) {
    errors.push("指紋が version.json と合わない");
  }
  if (
    base
    && head.fingerprint !== base.fingerprint
    && !(head.contract > base.contract)
  ) {
    errors.push("指紋が変わったのに contract が上がっていない");
  }
  if (frozenChanged) {
    errors.push("凍結した fixtures が変わっている");
  }
  return errors;
}

function git(args) {
  return spawnSync("git", args, { encoding: "utf8" });
}

function commitExists(sha) {
  if (!sha || /^0+$/.test(sha)) return false;
  const result = git(["cat-file", "-e", `${sha}^{commit}`]);
  return result.status === 0;
}

export function frozenDirectories(ref) {
  const result = git(["ls-tree", "-r", "--name-only", ref, "--", "sync/contract/fixtures"]);
  if (result.status !== 0) return [];
  const dirs = new Set();
  for (const line of result.stdout.split("\n")) {
    const match = line.match(/^(sync\/contract\/fixtures\/v\d+)\//);
    if (match) dirs.add(match[1]);
  }
  return [...dirs].sort();
}

export function frozenChangedSince(base) {
  const dirs = frozenDirectories(base);
  for (const dir of dirs) {
    const diff = git(["diff", "--exit-code", base, "HEAD", "--", dir]);
    if (diff.status !== 0) return true;
  }
  return false;
}

function readVersionAt(ref) {
  const result = git(["show", `${ref}:sync/contract/version.json`]);
  if (result.status !== 0) return null;
  return JSON.parse(result.stdout);
}

function main() {
  const head = readVersion();
  const computed = fingerprintOf();
  const baseSha = process.env.BASE_SHA;
  const base = commitExists(baseSha) ? readVersionAt(baseSha) : null;
  const frozenChanged = commitExists(baseSha) ? frozenChangedSince(baseSha) : false;
  const errors = judge({ computed, head, base, frozenChanged });
  if (errors.length > 0) {
    for (const error of errors) console.error(error);
    console.error(`computed ${computed}`);
    console.error(`version   ${head.fingerprint}`);
    process.exit(1);
  }
  console.log(`contract-guard: contract ${head.contract} fingerprint ok`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main();
}

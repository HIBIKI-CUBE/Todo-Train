#!/usr/bin/env node
// ワイヤに出るものから指紋を作る。空白とコメントは正規化してから SHA-256。
// version.json 自身は含めない（指紋をその中に書くため）。
//
//   node tools/contract/fingerprint.mjs            指紋を出す
//   node tools/contract/fingerprint.mjs --write    version.json の指紋だけを更新する
//   node tools/contract/fingerprint.mjs --bump --note "一行"
//       contract を 1 上げ、history に足し、指紋を更新する

import { createHash } from "node:crypto";
import { readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, extname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

const swiftWire = [
  "Packages/TodoTrainSync/Sources/TodoTrainSync/Snap.swift",
  "Packages/TodoTrainSync/Sources/TodoTrainSync/Command.swift",
  "Packages/TodoTrainSync/Sources/TodoTrainSync/Ack.swift",
  "Packages/TodoTrainSync/Sources/TodoTrainSync/WireTypes.swift",
  "Packages/TodoTrainSync/Sources/TodoTrainSync/WireDTOs.swift",
  "Packages/TodoTrainSync/Sources/TodoTrainSync/WireBuildInfo.swift",
];

const workerWire = [
  "sync/worker/src/envelope.ts",
  "sync/worker/src/ws-frame.ts",
  "sync/worker/src/bind-body.ts",
  "sync/worker/src/hint.ts",
  "sync/worker/src/result.ts",
  "sync/worker/src/constants.ts",
];

export function versionPath(root = repoRoot) {
  return join(root, "sync/contract/version.json");
}

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    if (name === ".DS_Store") continue;
    const abs = join(dir, name);
    const info = statSync(abs);
    if (info.isDirectory()) walk(abs, out);
    else out.push(abs);
  }
}

export function inputPaths(root = repoRoot) {
  const paths = [];
  const contractDir = join(root, "sync/contract");
  walk(contractDir, paths);
  const rel = paths
    .map((abs) => relative(root, abs).split("\\").join("/"))
    .filter((path) => path !== "sync/contract/version.json");
  for (const path of [...swiftWire, ...workerWire]) {
    rel.push(path);
  }
  return rel.sort();
}

export function normalize(source, ext) {
  const text = source.replace(/\r\n/g, "\n");
  return stripComments(text, ext).replace(/\s+/g, " ").trim();
}

function stripComments(source, ext) {
  const code = ext === ".swift" || ext === ".ts" || ext === ".mjs" || ext === ".js";
  const markdown = ext === ".md";
  if (!code && !markdown) return source;
  let out = "";
  let i = 0;
  let inString = false;
  let quote = "";
  let escape = false;
  while (i < source.length) {
    if (markdown && source.startsWith("<!--", i)) {
      const end = source.indexOf("-->", i + 4);
      i = end === -1 ? source.length : end + 3;
      out += " ";
      continue;
    }
    const ch = source[i];
    if (inString) {
      out += ch;
      if (escape) escape = false;
      else if (ch === "\\") escape = true;
      else if (ch === quote) inString = false;
      i += 1;
      continue;
    }
    if (code && (ch === "\"" || ch === "'" || ch === "`")) {
      inString = true;
      quote = ch;
      escape = false;
      out += ch;
      i += 1;
      continue;
    }
    if (code && source.startsWith("//", i)) {
      const end = source.indexOf("\n", i);
      i = end === -1 ? source.length : end;
      out += " ";
      continue;
    }
    if (code && source.startsWith("/*", i)) {
      const end = source.indexOf("*/", i + 2);
      i = end === -1 ? source.length : end + 2;
      out += " ";
      continue;
    }
    out += ch;
    i += 1;
  }
  return out;
}

export function fingerprintOf(root = repoRoot) {
  const hash = createHash("sha256");
  for (const path of inputPaths(root)) {
    const abs = join(root, path);
    const text = readFileSync(abs, "utf8");
    hash.update(path);
    hash.update("\0");
    hash.update(normalize(text, extname(path)));
    hash.update("\0");
  }
  return hash.digest("hex");
}

export function readVersion(root = repoRoot) {
  return JSON.parse(readFileSync(versionPath(root), "utf8"));
}

function todayInTokyo() {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Tokyo",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

export function writeVersion(root, version) {
  writeFileSync(versionPath(root), `${JSON.stringify(version, null, 2)}\n`);
}

function argValue(flag) {
  const index = process.argv.indexOf(flag);
  if (index === -1) return undefined;
  return process.argv[index + 1];
}

function main() {
  const bump = process.argv.includes("--bump");
  const write = process.argv.includes("--write") || bump;
  const version = readVersion();
  if (bump) {
    const note = argValue("--note");
    if (!note) {
      console.error("contract:bump には --note \"一行\" が必要です");
      process.exit(1);
    }
    version.contract += 1;
    version.history.push({
      contract: version.contract,
      date: todayInTokyo(),
      note,
    });
  }
  version.fingerprint = fingerprintOf();
  if (!write) {
    console.log(version.fingerprint);
    return;
  }
  writeVersion(repoRoot, version);
  console.log(`${version.contract} ${version.fingerprint}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main();
}

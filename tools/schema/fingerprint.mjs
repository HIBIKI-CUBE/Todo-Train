#!/usr/bin/env node
// @Model の保存される宣言から指紋を作る。空白とコメントは正規化してから SHA-256。
// 入れるもの: 格納プロパティの名前・型・既定値、@Attribute、@Relationship。
// 入れないもの: @Transient、計算プロパティ、メソッド、static。
// Swift の構文解析は使わない。
//
//   node tools/schema/fingerprint.mjs
//   node tools/schema/fingerprint.mjs --write
//       AppSchema の最新の版と指紋を AppSchema.fingerprint に書く

import { createHash } from "node:crypto";
import { readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

const MODIFIERS = new Set([
  "public",
  "open",
  "internal",
  "fileprivate",
  "private",
  "package",
  "final",
  "override",
  "weak",
  "unowned",
  "static",
  "class",
  "convenience",
  "required",
  "lazy",
  "dynamic",
  "nonisolated",
  "mutating",
  "nonmutating",
]);

export function fingerprintPath(root = repoRoot) {
  return join(root, "Todo train/App/AppSchema.fingerprint");
}

export function appSchemaPath(root = repoRoot) {
  return join(root, "Todo train/App/AppSchema.swift");
}

export function modelsDir(root = repoRoot) {
  return join(root, "Todo train/Models");
}

function collapse(text) {
  return text.replace(/\s+/g, " ").trim();
}

function skipString(source, index) {
  if (source.startsWith('"""', index)) {
    const end = source.indexOf('"""', index + 3);
    return end === -1 ? source.length : end + 3;
  }
  if (source[index] !== '"') return index;
  let i = index + 1;
  while (i < source.length) {
    if (source[i] === "\\") {
      i += 2;
      continue;
    }
    if (source[i] === '"') return i + 1;
    i += 1;
  }
  return i;
}

function skipComment(source, index) {
  if (source.startsWith("//", index)) {
    const end = source.indexOf("\n", index);
    return end === -1 ? source.length : end;
  }
  if (source.startsWith("/*", index)) {
    const end = source.indexOf("*/", index + 2);
    return end === -1 ? source.length : end + 2;
  }
  return index;
}

export function stripSwiftComments(source) {
  let out = "";
  let i = 0;
  while (i < source.length) {
    const afterString = skipString(source, i);
    if (afterString !== i) {
      out += source.slice(i, afterString);
      i = afterString;
      continue;
    }
    const afterComment = skipComment(source, i);
    if (afterComment !== i) {
      out += " ";
      i = afterComment;
      continue;
    }
    out += source[i];
    i += 1;
  }
  return out;
}

export function matchingBrace(source, openIndex) {
  let depth = 0;
  let i = openIndex;
  while (i < source.length) {
    const afterString = skipString(source, i);
    if (afterString !== i) {
      i = afterString;
      continue;
    }
    const afterComment = skipComment(source, i);
    if (afterComment !== i) {
      i = afterComment;
      continue;
    }
    if (source[i] === "{") depth += 1;
    else if (source[i] === "}") {
      depth -= 1;
      if (depth === 0) return i;
    }
    i += 1;
  }
  throw new Error("閉じ括弧がない");
}

function skipWs(source, index) {
  let i = index;
  while (i < source.length && /\s/.test(source[i])) i += 1;
  return i;
}

function peekWord(source, index) {
  const match = source.slice(index).match(/^[A-Za-z_][A-Za-z0-9_]*/);
  return match ? match[0] : "";
}

function skipBalanced(source, index, open, close) {
  let depth = 0;
  let i = index;
  while (i < source.length) {
    const afterString = skipString(source, i);
    if (afterString !== i) {
      i = afterString;
      continue;
    }
    if (source[i] === open) depth += 1;
    else if (source[i] === close) {
      depth -= 1;
      i += 1;
      if (depth === 0) return i;
      continue;
    }
    i += 1;
  }
  throw new Error("対応する括弧がない");
}

function skipBraceBlock(source, index) {
  return matchingBrace(source, index) + 1;
}

function consumeAttribute(source, index) {
  if (source[index] !== "@") throw new Error("@ ではない");
  let i = index + 1;
  if (!/[A-Za-z_]/.test(source[i] ?? "")) throw new Error("属性名がない");
  i += 1;
  while (i < source.length && /[A-Za-z0-9_]/.test(source[i])) i += 1;
  const next = skipWs(source, i);
  if (source[next] === "(") return skipBalanced(source, next, "(", ")");
  return i;
}

function matchMember(source, index) {
  const modifiers = [];
  let j = index;
  while (true) {
    const word = peekWord(source, j);
    if (!MODIFIERS.has(word)) break;
    let consumed = j + word.length;
    if (source[consumed] === "(") consumed = skipBalanced(source, consumed, "(", ")");
    if (!/\s/.test(source[consumed] ?? "")) break;
    if (word === "class") {
      const after = skipWs(source, consumed);
      const next = peekWord(source, after);
      if (next !== "func" && next !== "var" && next !== "let" && next !== "subscript") break;
    }
    modifiers.push(word);
    j = skipWs(source, consumed);
  }
  const keyword = peekWord(source, j);
  if (!/^(var|let|func|init|subscript|deinit|typealias|enum|struct|class)$/.test(keyword)) {
    return null;
  }
  return { modifiers, keyword, keywordAt: j, end: j + keyword.length };
}

function consumeProperty(source, index) {
  let paren = 0;
  let bracket = 0;
  let brace = 0;
  let assigned = false;
  let declEnd = index;
  let i = index;
  while (i < source.length) {
    const afterString = skipString(source, i);
    if (afterString !== i) {
      if (paren === 0 && bracket === 0 && brace === 0) declEnd = afterString;
      i = afterString;
      continue;
    }
    const ch = source[i];
    if (ch === "(") paren += 1;
    else if (ch === ")") paren -= 1;
    else if (ch === "[") bracket += 1;
    else if (ch === "]") bracket -= 1;
    else if (ch === "{") {
      if (paren === 0 && bracket === 0 && brace === 0) {
        if (!assigned) return { end: skipBraceBlock(source, i), declEnd, computed: true };
        const word = peekWord(source, skipWs(source, i + 1));
        if (word === "willSet" || word === "didSet" || word === "get" || word === "set") {
          return { end: skipBraceBlock(source, i), declEnd, computed: false };
        }
        brace += 1;
      } else brace += 1;
    } else if (ch === "}") {
      if (brace === 0 && paren === 0 && bracket === 0) {
        return { end: i, declEnd, computed: false };
      }
      brace -= 1;
    } else if (paren === 0 && bracket === 0 && brace === 0 && ch === "=") {
      assigned = true;
    } else if (paren === 0 && bracket === 0 && brace === 0 && (ch === "\n" || ch === ";")) {
      if (ch === "\n" && source[skipWs(source, i + 1)] === "{") {
        i += 1;
        continue;
      }
      return { end: i + 1, declEnd, computed: false };
    }
    if (paren === 0 && bracket === 0 && brace === 0 && ch !== "\n" && ch !== ";") declEnd = i + 1;
    i += 1;
  }
  return { end: i, declEnd, computed: false };
}

function consumeMemberBody(source, index) {
  let paren = 0;
  let bracket = 0;
  let brace = 0;
  let i = index;
  while (i < source.length) {
    const afterString = skipString(source, i);
    if (afterString !== i) {
      i = afterString;
      continue;
    }
    const ch = source[i];
    if (ch === "(") paren += 1;
    else if (ch === ")") paren -= 1;
    else if (ch === "[") bracket += 1;
    else if (ch === "]") bracket -= 1;
    else if (ch === "{") {
      if (paren === 0 && bracket === 0 && brace === 0) return skipBraceBlock(source, i);
      brace += 1;
    } else if (ch === "}") {
      if (brace === 0 && paren === 0 && bracket === 0) return i;
      brace -= 1;
    } else if (ch === "\n" && paren === 0 && bracket === 0 && brace === 0) {
      if (source[skipWs(source, i + 1)] === "{") {
        i += 1;
        continue;
      }
      return i + 1;
    }
    i += 1;
  }
  return i;
}

export function storedProperties(classBody) {
  const source = stripSwiftComments(classBody);
  const properties = [];
  let i = 0;
  let pending = [];
  while (i < source.length) {
    const before = i;
    i = skipWs(source, i);
    if (i >= source.length) break;
    if (source[i] === "@") {
      const end = consumeAttribute(source, i);
      pending.push(collapse(source.slice(i, end)));
      i = end;
      if (i === before) throw new Error("属性を読み進められない");
      continue;
    }
    const member = matchMember(source, i);
    if (!member) {
      throw new Error(`モデルの宣言を読めない: ${collapse(source.slice(i, i + 48))}`);
    }
    if (member.keyword === "var" || member.keyword === "let") {
      const parsed = consumeProperty(source, member.end);
      const declaration = collapse(source.slice(member.keywordAt, parsed.declEnd));
      const transient = pending.some((attr) => attr.startsWith("@Transient"));
      const isStatic = member.modifiers.includes("static") || member.modifiers.includes("class");
      if (!transient && !isStatic && !parsed.computed) {
        const attrs = pending.filter((attr) => !attr.startsWith("@Transient"));
        properties.push(collapse(`${attrs.join(" ")} ${declaration}`));
      }
      pending = [];
      i = parsed.end;
      if (i === before) throw new Error("プロパティを読み進められない");
      continue;
    }
    pending = [];
    i = consumeMemberBody(source, member.end);
    if (i === before) throw new Error("メンバーを読み進められない");
  }
  return properties;
}

export function modelClasses(source) {
  const stripped = stripSwiftComments(source);
  const found = [];
  const marker = /@Model\b/g;
  let match = marker.exec(stripped);
  while (match) {
    const after = stripped.slice(match.index + match[0].length);
    const head = after.match(
      /^\s*(?:(?:public|open|internal|fileprivate|private|package|final|nonisolated)\s+)*class\s+([A-Za-z_][A-Za-z0-9_]*)/,
    );
    if (!head) {
      match = marker.exec(stripped);
      continue;
    }
    const headEnd = match.index + match[0].length + head.index + head[0].length;
    const open = stripped.indexOf("{", headEnd);
    if (open === -1) throw new Error(`${head[1]} の本体がない`);
    const close = matchingBrace(stripped, open);
    found.push({ name: head[1], body: stripped.slice(open + 1, close) });
    marker.lastIndex = close + 1;
    match = marker.exec(stripped);
  }
  return found;
}

export function declarationsIn(source) {
  return modelClasses(source).map((model) => ({
    name: model.name,
    properties: storedProperties(model.body),
  }));
}

function walkSwift(dir, root, out) {
  for (const name of readdirSync(dir)) {
    if (name === ".DS_Store") continue;
    const abs = join(dir, name);
    if (statSync(abs).isDirectory()) walkSwift(abs, root, out);
    else if (name.endsWith(".swift")) out.push(abs);
  }
}

export function modelSources(root = repoRoot) {
  const absPaths = [];
  walkSwift(modelsDir(root), root, absPaths);
  return absPaths.sort().map((abs) => ({
    path: relative(root, abs).split("\\").join("/"),
    source: readFileSync(abs, "utf8"),
  }));
}

export function fingerprintFromSources(sources) {
  const classes = [];
  for (const file of sources) {
    for (const model of declarationsIn(file.source)) {
      classes.push({ ...model, path: file.path });
    }
  }
  if (classes.length === 0) throw new Error("@Model がない");
  classes.sort(
    (a, b) => a.name.localeCompare(b.name, "en") || a.path.localeCompare(b.path, "en"),
  );
  const hash = createHash("sha256");
  for (const model of classes) {
    hash.update(model.name);
    hash.update("\0");
    for (const property of model.properties) {
      hash.update(property);
      hash.update("\0");
    }
    hash.update("\0");
  }
  return hash.digest("hex");
}

export function fingerprintOf(root = repoRoot) {
  return fingerprintFromSources(modelSources(root));
}

export function compareVersion(left, right) {
  const a = left.split(".").map(Number);
  const b = right.split(".").map(Number);
  for (let i = 0; i < 3; i += 1) {
    if (a[i] !== b[i]) return a[i] > b[i] ? 1 : -1;
  }
  return 0;
}

export function versionedSchemas(source) {
  const found = [];
  const marker = /^enum (AppSchemaV[A-Za-z0-9_]+)\b/gm;
  let match = marker.exec(source);
  while (match) {
    const open = source.indexOf("{", match.index);
    if (open === -1) throw new Error(`${match[1]} の本体がない`);
    const close = matchingBrace(source, open);
    const body = source.slice(match.index, close + 1);
    const version = body.match(/Schema\.Version\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)/);
    if (!version) throw new Error(`${match[1]} に Schema.Version がない`);
    found.push({
      name: match[1],
      version: `${version[1]}.${version[2]}.${version[3]}`,
      body,
    });
    marker.lastIndex = close + 1;
    match = marker.exec(source);
  }
  return found;
}

export function latestSchema(source) {
  const schemas = versionedSchemas(source);
  if (schemas.length === 0) throw new Error("AppSchema の版がない");
  return schemas.reduce((best, item) => (compareVersion(item.version, best.version) > 0 ? item : best));
}

// base にある最新より前の版（V3、V3_1 など）。最新の版の enum は、次の版を足すときに書き換わる。
export function frozenBodiesChanged(baseSource, headSource) {
  const baseSchemas = versionedSchemas(baseSource);
  if (baseSchemas.length === 0) return false;
  const latest = latestSchema(baseSource);
  const headByName = new Map(versionedSchemas(headSource).map((item) => [item.name, item]));
  for (const item of baseSchemas) {
    if (item.name === latest.name) continue;
    const head = headByName.get(item.name);
    if (!head || head.body !== item.body) return true;
  }
  return false;
}

export function readFingerprint(root = repoRoot) {
  return JSON.parse(readFileSync(fingerprintPath(root), "utf8"));
}

export function readAppSchema(root = repoRoot) {
  return readFileSync(appSchemaPath(root), "utf8");
}

function currentRecord(root = repoRoot) {
  const latest = latestSchema(readAppSchema(root));
  return {
    name: latest.name,
    version: latest.version,
    fingerprint: fingerprintOf(root),
  };
}

function main() {
  const write = process.argv.includes("--write");
  const record = currentRecord();
  if (!write) {
    console.log(record.fingerprint);
    return;
  }
  writeFileSync(fingerprintPath(), `${JSON.stringify(record, null, 2)}\n`);
  console.log(`${record.name} ${record.version} ${record.fingerprint}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  main();
}

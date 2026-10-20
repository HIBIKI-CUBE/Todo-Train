import assert from "node:assert/strict";
import { test } from "node:test";
import { normalize } from "./fingerprint.mjs";
import { judge } from "./guard.mjs";

const base = { contract: 3, fingerprint: "aaa" };
const head = { contract: 4, minReadable: 3, fingerprint: "bbb" };

test("指紋が計算と違うと落ちる", () => {
  const errors = judge({
    computed: "ccc",
    head: { ...head, fingerprint: "bbb" },
    base,
    frozenChanged: false,
  });
  assert.ok(errors.some((error) => error.includes("合わない")));
});

test("指紋だけを書き換えて版を上げないと落ちる", () => {
  const errors = judge({
    computed: "bbb",
    head: { ...head, contract: 3, fingerprint: "bbb" },
    base,
    frozenChanged: false,
  });
  assert.ok(errors.some((error) => error.includes("上がって")));
});

test("版を上げて指紋を更新すると通る", () => {
  const errors = judge({
    computed: "bbb",
    head,
    base,
    frozenChanged: false,
  });
  assert.deepEqual(errors, []);
});

test("凍結した fixtures を変えると落ちる", () => {
  const errors = judge({
    computed: "bbb",
    head,
    base,
    frozenChanged: true,
  });
  assert.ok(errors.some((error) => error.includes("凍結")));
});

test("base に version.json が無くても指紋が合えば通る", () => {
  const errors = judge({
    computed: "bbb",
    head,
    base: null,
    frozenChanged: false,
  });
  assert.deepEqual(errors, []);
});

test("空白とコメントは指紋に入らない", () => {
  const left = normalize("let a = 1 // note\n", ".swift");
  const right = normalize("let a = 1\n/* block */\n", ".swift");
  assert.equal(left, "let a = 1");
  assert.equal(right, "let a = 1");
  const markdown = normalize("本文 <!-- secret --> 終わり\n", ".md");
  assert.equal(markdown, "本文 終わり");
});

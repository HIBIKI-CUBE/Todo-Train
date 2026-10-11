#!/usr/bin/env python3
"""文言の門。docs/03-terminology.md「文体」のうち、機械で判定できるものを落とす。

使い方: python extract_app.py > app.jsonl && python check.py app.jsonl
意図して残す文字列は allow.tsv に理由つきで足す。門を足すときは analyze.py で人間の文との差を測ってから。
"""
import json
import sys
from pathlib import Path

from analyze import QUOTED, ending, plain_kind, sahen_label, sentences

ALLOW = Path(__file__).with_name("allow.tsv")


def allowed() -> set[str]:
    out = set()
    for line in ALLOW.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            text, _, reason = line.partition("\t")
            if not reason.strip():
                sys.exit(f"allow.tsv: 理由がない行 {text!r}")
            out.add(text)
    return out


def problems(text: str, kind: str, allow: set[str]) -> list[str]:
    t = QUOTED.sub("◯", text)
    sents = sentences(t) or [t]
    ends = [ending(s) for s in sents]
    out = []
    if any(s.endswith("。") and e == "plain" for s, e in zip(sents, ends)):
        out.append("句点で閉じた文が常体（です・ます にする）")
    if "polite" in ends and "plain" in ends:
        out.append("敬体と常体が混ざっている")
    if len(sents) >= 2 and any(e != "polite" for e in ends):
        out.append("2 文以上なのに です・ます で閉じていない文がある（体言止めを続けない）")
    if len(sents) >= 3:
        out.append(f"{len(sents)} 文ある（2 文までに削る）")
    if kind == "hint" and ends[-1] != "polite":
        out.append("VoiceOver ヒントが です・ます で終わっていない")
    if text in allow:
        return out
    if sahen_label(t) == "suru":
        out.append("ラベルが「〜する」まで書いている（「追加」のように名詞で止める）")
    if any(plain_kind(s) in ("past", "neg", "colloquial") and not s.rstrip("）)").endswith("なし") for s in sents):
        out.append("状態や結果を常体で言い切っている（「送りました」「ありません」にする）")
    return out


def main(path: str) -> int:
    allow = allowed()
    rows = [json.loads(line) for line in open(path, encoding="utf-8")]
    bad = 0
    for r in rows:
        for p in problems(r["text"], r.get("kind", ""), allow):
            print(f"{r['file']}:{r['line']}: {r['text']!r} — {p}")
            bad += 1
    print(f"{len(rows)} 件中 {bad} 件の指摘", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

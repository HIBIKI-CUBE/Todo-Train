#!/usr/bin/env python3
"""文言の門。docs/03-terminology.md「文体」のうち、機械で判定できるものを落とす。

使い方: python extract_app.py > app.jsonl && python check.py app.jsonl
規則は場面の役で変わる。ファイルと役の対応は roles.tsv（書いていないファイルはアプリの声）。
門を足すときは analyze.py で人間の文との差を測ってから。
"""
import json
import re
import sys
from fnmatch import fnmatch
from pathlib import Path

from analyze import QUOTED, ending, plain_kind, sahen_label, sentences

ROLES = Path(__file__).with_name("roles.tsv")
# docs/19: 乗客の面では切符の語を出さない
PASSENGER_BANNED = ("切符", "発車", "停車", "再乗車", "途中下車", "発券", "マルス", "運転台", "乗り換え")
# docs/02: 指図する案内・「して」の授業はしない
IMPERATIVE = re.compile(r"(して|しよう|しましょう|てください|なさい|てね)[。！？!?]?$")


def roles() -> list[tuple[str, str]]:
    out = []
    for line in ROLES.read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            pattern, _, role = line.partition("\t")
            out.append((pattern, role.strip()))
    return out


def role_of(path: str, table: list[tuple[str, str]]) -> str:
    return next((role for pattern, role in table if fnmatch(path, pattern)), "アプリ")


def problems(text: str, kind: str, role: str) -> list[str]:
    t = QUOTED.sub("◯", text)
    sents = sentences(t) or [t]
    ends = [ending(s) for s in sents]
    out = []
    if "polite" in ends and "plain" in ends:
        out.append("敬体と常体が混ざっている")
    if len(sents) >= 2 and any(e != "polite" for e in ends):
        out.append("2 文以上なのに です・ます で閉じていない文がある（体言止めを続けない）")
    if len(sents) >= 3:
        out.append(f"{len(sents)} 文ある（2 文までに削る）")
    if kind == "hint" and ends[-1] != "polite":
        out.append("VoiceOver ヒントが です・ます で終わっていない")

    if role == "車内放送":
        if any(IMPERATIVE.search(s) for s in sents):
            out.append("車内放送が指図している（問うか知らせるだけにする）")
        return out

    if any(s.endswith("。") and e == "plain" for s, e in zip(sents, ends)):
        out.append("句点で閉じた文が常体（です・ます にする）")
    if sahen_label(t) == "suru":
        out.append("ラベルが「〜する」まで書いている（「延長」のように名詞で止める）")
    if any(
        plain_kind(s) in ("past", "neg", "colloquial") and not s.rstrip("）)").endswith("なし")
        for s in sents
    ):
        out.append("常体で言い切っている（操作は名前で、状態は です・ます で）")
    if role == "乗客":
        hit = [w for w in PASSENGER_BANNED if w in t]
        if hit:
            out.append(f"乗客の面に切符の語がある（{'、'.join(hit)}）")
    return out


def main(path: str) -> int:
    table = roles()
    rows = [json.loads(line) for line in open(path, encoding="utf-8")]
    bad = 0
    for r in rows:
        for p in problems(r["text"], r.get("kind", ""), role_of(r["file"], table)):
            print(f"{r['file']}:{r['line']}: {r['text']!r} — {p}")
            bad += 1
    print(f"{len(rows)} 件中 {bad} 件の指摘", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

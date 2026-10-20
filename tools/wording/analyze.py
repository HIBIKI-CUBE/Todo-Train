#!/usr/bin/env python3
"""文言の「AIっぽさ」を、人間の基準コーパスとの差で測る。

コーパス
  app    : extract_app.py の出力（このアプリ）
  apple  : extract_reference.py の出力（Apple 純正アプリの日本語 UI。人間の基準）
  llm    : llm_baseline.swift の出力（同じ英語原文をオンデバイス LLM が日本語化）
  pair   : llm と同じ英語原文に対する Apple の日本語（llm と内容を揃えた人間側）

指標の出典
  ダッシュ・否定対比 ... Paech et al. 2025 "Antislop" (arXiv:2510.15061)、
                        "Artificial Epanorthosis" (arXiv:2607.21498)
  機能語率・読点の位置 ... Zaitsu & Jin 2023, PLOS ONE 18(8): e0288453
  語の偏り ............ Monroe, Colaresi & Quinn 2008 (informative Dirichlet prior の対数オッズ比)

使い方: python analyze.py app.jsonl ref.jsonl [llm_in.jsonl llm_out.jsonl] [--strings]
janome が要る（pip install janome）。
"""
import json
import math
import re
import sys
from collections import Counter
from functools import lru_cache

from janome.tokenizer import Tokenizer

TOK = Tokenizer()

# docs/03-terminology.md の用語。言い換え禁止なので、偏っていても候補から外す
TERMS = set(
    "切符 Hub 運行 発車 停車 到着 途中下車 乗り継ぎ 放棄 到着整理 超過 延長 割り込み 再乗車 定時 早着 "
    "定時運行 車内放送 掲示 ダイヤ 着発 通過 スジ 待避 予定 予測 乗車 乗務 走行 運休 発券 発行 印 行き先 "
    "編成 盤 表示灯 接近 クリアランス 終了ベル 見積もり 見積 掃き出し 掃き出す 予約 一本 リレー ペア "
    "連携 乗る 乗客 ドア 非常 退出 区間 所要 題名 経由 枠 占有 跡 検札 タグ セッション フォーカス "
    "Live Activity Mac iPhone QR Face ID Touch AlarmKit".split()
)

SENT_SPLIT = re.compile(r"(?<=[。！？!?])")
# 引用は書き手の文ではない（利用者の発話や題名を指しているだけ）
QUOTED = re.compile(r"「[^」]*」|『[^』]*』|“[^”]*”")
DASH = re.compile(r"[—–―]")
DOT_SEP = re.compile(r"\s[·•・]\s|[·•]")
COLON = re.compile(r"[:：]")
FUNC_POS = {"助詞", "助動詞", "接続詞", "副詞"}


@lru_cache(maxsize=None)
def tokens(text: str):
    return tuple(
        (t.surface, t.part_of_speech.split(",")[0], t.part_of_speech.split(",")[1], t.base_form,
         t.infl_form)
        for t in TOK.tokenize(text)
        if t.part_of_speech.split(",")[1] != "空白"
    )


def sentences(text: str) -> list[str]:
    return [s.strip() for s in SENT_SPLIT.split(text.replace("\n", "")) if s.strip()]


def content_tokens(s):
    return [t for t in tokens(s) if t[1] != "記号" and t[0] != "◯"]


def has_predicate(s: str) -> bool:
    return any(t[1] in ("動詞", "形容詞", "助動詞") for t in content_tokens(s))


def ending(s: str) -> str:
    """文末の形: polite（です・ます）/ plain（常体の用言・た）/ noun（体言止め）/ other"""
    toks = [t for t in tokens(s) if t[1] != "記号"]
    if not toks:
        return "other"
    tail = toks[-3:]
    bases = [t[3] for t in tail]
    if "ます" in bases or "です" in bases or toks[-1][0] in ("ください", "下さい"):
        return "polite"
    last = toks[-1]
    if last[1] in ("名詞",) or last[0] == "◯":
        return "noun"
    if last[1] == "助詞" and last[3] in ("か", "ね", "よ"):
        return "other"
    if last[1] in ("動詞", "形容詞", "助動詞") or (last[1] == "助詞" and last[2] == "接続助詞"):
        return "plain"
    return "other"


def plain_kind(s: str) -> str | None:
    """常体で終わる文の中身: past（〜た）/ neg（〜ない）/ colloquial（〜てる・〜てた）/ dict（辞書形）"""
    if ending(s) != "plain":
        return None
    toks = [t for t in tokens(s) if t[1] != "記号"]
    last = toks[-1]
    if last[0] in ("てる", "てた", "でる", "でた", "ちゃう", "ちゃった") or (
        last[3] in ("てる", "る") and len(toks) >= 2 and toks[-2][4] == "連用タ接続"
    ):
        return "colloquial"
    if len(toks) >= 2 and toks[-2][0] in ("て", "で") and last[3] in ("る", "た"):
        return "colloquial"
    if last[1] == "助動詞" and last[3] == "た":
        if len(toks) >= 2 and toks[-2][0] in ("て", "で"):
            return "colloquial"
        return "past"
    if last[3] in ("ない", "ぬ", "ん"):
        return "neg"
    return "dict"


def sahen_label(t: str) -> str | None:
    """句点のないラベルが サ変名詞で止まるか（"追加"）、「する」まで書くか（"追加する"）。"""
    if any(c in t for c in "。？?！!"):
        return None
    toks = [x for x in tokens(t) if x[1] != "記号"]
    if len(toks) < 1:
        return None
    last = toks[-1]
    if last[3] == "する" and len(toks) >= 2 and toks[-2][2] == "サ変接続":
        return "suru"
    if last[1] == "名詞" and last[2] == "サ変接続":
        return "noun"
    return None


def negated(s: str) -> bool:
    for t in tokens(s):
        if t[1] == "助動詞" and t[3] in ("ない", "ぬ", "ん"):
            return True
        if t[1] == "形容詞" and t[3] == "ない":
            return True
    return "ではなく" in s or "じゃなく" in s


def string_features(text: str) -> dict:
    sents = sentences(text)
    full = [s for s in sents if has_predicate(s)]
    ends = [ending(s) for s in sents]
    toks = content_tokens(text)
    return {
        "chars": len(text),
        "sents": len(sents),
        "dash": bool(DASH.search(text)),
        "dot_sep": bool(DOT_SEP.search(text)),
        "colon": bool(COLON.search(text)),
        "neg_sents": sum(negated(s) for s in full),
        "full_sents": len(full),
        "ends": ends,
        "mixed_style": ("polite" in ends) and ("plain" in ends),
        "fragment_chain": len(sents) >= 2 and ends.count("noun") >= 1
        and any(e in ("plain", "polite") for e in ends),
        "func": sum(1 for t in toks if t[1] in FUNC_POS),
        "toks": len(toks),
        "topic_ha": sum(1 for t in tokens(text) if t[0] in ("は", "が", "を") and t[1] == "助詞"),
        "topic_ha_comma": len(re.findall(r"[はがを]、", text)),
        "question": text.rstrip().endswith(("？", "?")),
    }


def wilson(k, n, z=1.96):
    if n == 0:
        return (float("nan"),) * 3
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return p, (c - r) / d, (c + r) / d


def two_prop_z(k1, n1, k2, n2):
    if n1 == 0 or n2 == 0:
        return float("nan")
    p = (k1 + k2) / (n1 + n2)
    se = math.sqrt(p * (1 - p) * (1 / n1 + 1 / n2)) or float("nan")
    return (k1 / n1 - k2 / n2) / se


def summarize(name: str, texts: list[str]) -> dict:
    texts = [QUOTED.sub("◯", t) for t in texts]
    fs = [string_features(t) for t in texts]
    sent_strings = [f for f in fs if f["full_sents"] >= 1]
    multi = [f for f in fs if f["sents"] >= 2]
    all_ends = [e for f in fs for e, in zip(f["ends"])]
    pred_ends = [e for e in all_ends if e in ("polite", "plain")]
    # 句点で閉じた文だけ（ボタンなどのラベルを除く）
    period_ends = [
        ending(s) for t in texts for s in sentences(t) if s.endswith("。") and has_predicate(s)
    ]
    period_pred = [e for e in period_ends if e in ("polite", "plain")]
    polite_strings = [t for t in texts if ending(sentences(t)[-1] if sentences(t) else t) == "polite"]
    pred_sents = [s for t in texts for s in sentences(t) if ending(s) in ("polite", "plain")]
    kinds = Counter(plain_kind(s) for s in pred_sents)
    sahen = Counter(sahen_label(t) for t in texts)
    inner_period = [t for t in texts if "。" in t.rstrip()[:-1]]
    return {
        "name": name,
        "n": len(fs),
        "metrics": {
            # 母数, 該当数
            "ダッシュ区切り（文字列）": (len(fs), sum(f["dash"] for f in fs)),
            "中黒・ドット区切り（文字列）": (len(fs), sum(f["dot_sep"] for f in fs)),
            "コロン（文字列）": (len(fs), sum(f["colon"] for f in fs)),
            "否定を含む文（用言のある文）": (
                sum(f["full_sents"] for f in fs), sum(f["neg_sents"] for f in fs)),
            "常体で終わる文（用言で終わる文）": (len(pred_ends), pred_ends.count("plain")),
            "常体で終わる文（句点で閉じた文）": (len(period_pred), period_pred.count("plain")),
            "  うち辞書形（用言で終わる文）": (len(pred_sents), kinds["dict"]),
            "  うち「〜た」（用言で終わる文）": (len(pred_sents), kinds["past"]),
            "  うち「〜ない」（用言で終わる文）": (len(pred_sents), kinds["neg"]),
            "  うち「〜てる・〜てた」（用言で終わる文）": (len(pred_sents), kinds["colloquial"]),
            "体言止めの文（句点で閉じた文）": (
                len(period_ends), sum(1 for e in period_ends if e == "noun")),
            "敬体の文字列が句点で終わる": (
                len(polite_strings), sum(t.rstrip().endswith("。") for t in polite_strings)),
            "末尾の句点抜け（文中に句点がある文字列）": (
                len(inner_period),
                sum(not t.rstrip().endswith(("。", "？", "?", "！", "!", "…")) for t in inner_period)),
            "ラベルを「〜する」まで書く（サ変で終わるラベル）": (
                sahen["suru"] + sahen["noun"], sahen["suru"]),
            "敬体・常体の混在（2文以上）": (len(multi), sum(f["mixed_style"] for f in multi)),
            "体言止め＋用言文の連なり（2文以上）": (len(multi), sum(f["fragment_chain"] for f in multi)),
            "3文以上の文字列（文のある文字列）": (
                len(sent_strings), sum(f["sents"] >= 3 for f in sent_strings)),
            "機能語率（語）": (sum(f["toks"] for f in fs), sum(f["func"] for f in fs)),
            "は・が・を の直後の読点": (
                sum(f["topic_ha"] for f in fs), sum(f["topic_ha_comma"] for f in fs)),
            "疑問で終わる（文字列）": (len(fs), sum(f["question"] for f in fs)),
        },
    }


def log_odds(a: Counter, b: Counter, prior: Counter, alpha0=1000):
    """Monroe et al. 2008: a vs b の z。prior は背景コーパスの相対頻度を alpha0 に縮めたもの。"""
    na, nb, n0 = sum(a.values()), sum(b.values()), sum(prior.values())
    out = {}
    for w in set(a) | set(b):
        aw = prior.get(w, 0) / n0 * alpha0 + 0.01
        ya, yb = a.get(w, 0), b.get(w, 0)
        la = math.log((ya + aw) / (na + alpha0 - ya - aw))
        lb = math.log((yb + aw) / (nb + alpha0 - yb - aw))
        var = 1 / (ya + aw) + 1 / (yb + aw)
        out[w] = ((la - lb) / math.sqrt(var), ya, yb)
    return out


def grams(texts: list[str]) -> Counter:
    c = Counter()
    for t in texts:
        for s in sentences(t) or [t]:
            ws = [x[3] if x[3] != "*" else x[0] for x in tokens(s) if x[0] != "◯"]
            c.update(ws)
            c.update(" ".join(p) for p in zip(ws, ws[1:]))
    return c


def is_term(gram: str) -> bool:
    parts = gram.split(" ")
    return any(p in TERMS for p in parts) or all(re.fullmatch(r"[\W\d]+", p) for p in parts)


def load(path, key):
    return [json.loads(l) for l in open(path, encoding="utf-8")]


def print_table(rows: list[dict]):
    names = [r["name"] for r in rows]
    print("| 指標 | " + " | ".join(names) + " |")
    print("|---|" + "---|" * len(names))
    for m in rows[0]["metrics"]:
        cells = []
        for r in rows:
            n, k = r["metrics"][m]
            p, lo, hi = wilson(k, n)
            cells.append(f"{p*100:.1f}% [{lo*100:.1f}–{hi*100:.1f}] ({k}/{n})")
        print(f"| {m} | " + " | ".join(cells) + " |")


def main(argv):
    show_strings = "--strings" in argv
    argv = [a for a in argv if not a.startswith("--")]
    app = [r["text"] for r in load(argv[0], "text")]
    ref_rows = load(argv[1], "ja")
    apple = [r["ja"] for r in ref_rows]
    corpora = [summarize("app", app), summarize("apple", apple)]
    llm, pair = [], []
    if len(argv) >= 4:
        ids = {json.loads(l)["id"] for l in open(argv[2])}
        outs = {r["id"]: r["ja"] for r in load(argv[3], "ja")}
        for i in sorted(outs):
            if i in ids:
                llm.append(outs[i])
                pair.append(ref_rows[i]["ja"])
        corpora += [summarize("llm", llm), summarize("pair(apple)", pair)]

    print("## 指標（割合 [95% Wilson CI] (該当/母数)）\n")
    print_table(corpora)

    print("\n## z 検定（二標本比率）\n")
    print("| 指標 | app vs apple | llm vs pair |")
    print("|---|---|---|")
    for m in corpora[0]["metrics"]:
        n1, k1 = corpora[0]["metrics"][m]
        n2, k2 = corpora[1]["metrics"][m]
        z1 = two_prop_z(k1, n1, k2, n2)
        z2 = float("nan")
        if llm:
            n3, k3 = corpora[2]["metrics"][m]
            n4, k4 = corpora[3]["metrics"][m]
            z2 = two_prop_z(k3, n3, k4, n4)
        print(f"| {m} | {z1:+.2f} | {z2:+.2f} |")

    app_hints = [r["text"] for r in load(argv[0], "text") if r.get("kind") == "hint"]
    apple_hints = [r["ja"] for r in ref_rows if re.search(r"hint", r["key"], re.I)]
    if app_hints:
        print("\n## VoiceOver ヒントだけで比べる（文字列の最後の文の形）\n")
        print("| 形 | app | apple |")
        print("|---|---|---|")
        ea = Counter(ending((sentences(t) or [t])[-1]) for t in app_hints)
        eb = Counter(ending((sentences(t) or [t])[-1]) for t in apple_hints)
        for k in ("polite", "plain", "noun", "other"):
            pa, la, ha = wilson(ea[k], len(app_hints))
            pb, lb, hb = wilson(eb[k], len(apple_hints))
            print(f"| {k} | {pa*100:.1f}% [{la*100:.1f}–{ha*100:.1f}] ({ea[k]}/{len(app_hints)}) | "
                  f"{pb*100:.1f}% [{lb*100:.1f}–{hb*100:.1f}] ({eb[k]}/{len(apple_hints)}) |")

    ga, gr = grams(app), grams(apple)
    lo = log_odds(ga, gr, gr)
    print("\n## app で過剰な語・語連鎖（用語表を除く, z>3, app 内 3 回以上）\n")
    print("| 語 | z | app | apple |")
    print("|---|---|---|---|")
    for w, (z, ya, yb) in sorted(lo.items(), key=lambda x: -x[1][0]):
        if z < 3:
            break
        if ya < 3 or is_term(w):
            continue
        print(f"| {w} | {z:.1f} | {ya} | {yb} |")

    if llm:
        gl, gp = grams(llm), grams(pair)
        lo2 = log_odds(gl, gp, gr)
        print("\n## llm で過剰な語・語連鎖（同じ原文の Apple 訳と比較, z>2.5）\n")
        print("| 語 | z | llm | pair | app |")
        print("|---|---|---|---|---|")
        for w, (z, yl, yp) in sorted(lo2.items(), key=lambda x: -x[1][0])[:60]:
            if z < 2.5:
                break
            print(f"| {w} | {z:.1f} | {yl} | {yp} | {ga.get(w, 0)} |")

    if show_strings:
        print("\n## 該当する app の文字列\n")
        rows = load(argv[0], "text")
        for r in rows:
            f = string_features(QUOTED.sub("◯", r["text"]))
            flags = []
            if f["dash"]:
                flags.append("ダッシュ")
            if f["dot_sep"]:
                flags.append("ドット区切り")
            if f["colon"]:
                flags.append("コロン")
            if f["neg_sents"]:
                flags.append(f"否定{f['neg_sents']}/{f['full_sents']}")
            if f["mixed_style"]:
                flags.append("文体混在")
            if f["fragment_chain"]:
                flags.append("体言止め連なり")
            if f["sents"] >= 3:
                flags.append(f"{f['sents']}文")
            if "plain" in f["ends"] and f["full_sents"]:
                flags.append("常体")
            if flags:
                print(f"- `{r['file']}:{r['line']}` {r['text']!r} — {', '.join(flags)}")


if __name__ == "__main__":
    main(sys.argv[1:])

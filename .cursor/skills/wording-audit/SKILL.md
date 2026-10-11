---
name: wording-audit
description: >-
  Todo train の画面文言が「AI っぽい」かを、Apple 純正アプリの日本語 UI（人間の文）とオンデバイス LLM
  訳との差で定量的に監査し、根拠のある指摘だけ直す。文言の全体見直し、「AI っぽい」「不自然」という指摘、
  tools/wording/check.py に門を足したいときに使う。
---

# 文言の監査

感覚で直さない。「LLM に多い」と「このアプリに多い」の両方が測れた形だけを直す。

## 進め方

```
- [ ] 1. コーパスを作る
- [ ] 2. 指標を測る
- [ ] 3. 直す対象を決める
- [ ] 4. 直して門を通す
- [ ] 5. 必要なら門を足す
```

**1. コーパスを作る**（Mac が要る。Linux では app だけ作れる）

```bash
cd tools/wording && pip install -r requirements.txt
python extract_app.py > /tmp/app.jsonl          # このアプリ
python extract_reference.py > /tmp/ref.jsonl    # Apple 純正アプリの日本語（約 38,000 件）
```

LLM 側は `data/llm_in.jsonl`（英語原文）と `data/llm_out.jsonl`（オンデバイス LLM 訳）がある。作り直すときだけ `swift llm_baseline.swift < data/llm_in.jsonl > data/llm_out.jsonl`（Apple Intelligence が要る）。

**2. 指標を測る**

```bash
python analyze.py /tmp/app.jsonl /tmp/ref.jsonl data/llm_in.jsonl data/llm_out.jsonl --strings
```

**3. 直す対象を決める**。z 検定の表で次の両方を満たす指標だけ:

- `llm vs pair` が +2 を超える（LLM 訳が同じ原文の人間訳より多い）
- `app vs apple` が +2 を超える（このアプリが人間の文より多い）

片方だけなら AI の癖とは言えない。アプリ独自の書き方として報告に留める。「過剰な語」の表は用語表（`docs/03-terminology.md`）の語を除いてから見る。

**4. 直して門を通す**。`--strings` の出力から該当箇所を開き、[docs/03-terminology.md](../../../docs/03-terminology.md) の「文体」に沿って直す。

```bash
python extract_app.py > /tmp/app.jsonl && python check.py /tmp/app.jsonl
```

利用者自身の声は直さず `allow.tsv` に理由を書く。テストが文言を固定していれば一緒に直す。

**5. 門を足す**。3 で根拠が立ち、例外が少なく機械で判定できる形だけ `check.py` に足す。足したら docs/03「文体」にも一行書き、過去の誤りを入れた JSON Lines で検出できることを確かめる。

## 報告

指標ごとに app / apple / llm / pair の割合と 95% 信頼区間、z 値を表にする。直した形、直さなかった形とその理由（片方だけ有意、利用者の声など）を分けて書く。

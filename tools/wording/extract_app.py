#!/usr/bin/env python3
"""アプリの Swift から、ユーザーに見える日本語リテラルを抜く。

出力: JSON Lines（file, line, text, context）。補間は ◯ に置き換える。
ログ・アサーション・オンデバイスモデルへの指示文は UI ではないので外す。
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
JA = re.compile(r"[ぁ-んァ-ヶー一-龠々]")

# 行にこれが含まれるリテラルは画面に出ない
NON_UI_CONTEXT = re.compile(
    r"\b(Logger|logger|os_log|print|debugPrint|fatalError|precondition|preconditionFailure|"
    r"assert|assertionFailure|XCTAssert\w*|#expect|#require|Instructions|@Guide|prompt|"
    r"Prompt|instructions|description:\s*\"|dump)\b"
)
# この見出しで始まるブロックの中は、モデル入力かプレビュー用の見本
NON_UI_BLOCK = re.compile(
    r"(#Preview|enum\s+\w*Prompt\b|func\s+\w*[Pp]rompt\w*\s*\(|"
    r"(enum|struct)\s+\w*(Preview|Fixture)\w*)"
)
DATE_FORMAT = re.compile(r"^[yMdEHhmsa年月日（）\s:]+$")
HINT_CONTEXT = re.compile(r"accessibilityHint|\bhint:")
HINT_BLOCK = re.compile(r"var\s+\w*[Hh]int\w*\s*:\s*String\s*\{")


def hint_lines(lines: list[str]) -> set[int]:
    out: set[int] = set()
    for i, line in enumerate(lines):
        if HINT_CONTEXT.search(line):
            out.add(i + 1)
            # 引数が次の行以降に続く（三項演算子など）
            depth = line.count("(") - line.count(")")
            j = i + 1
            while j < len(lines) and (depth > 0 or re.match(r"\s*[?:]\s*\"", lines[j])):
                depth += lines[j].count("(") - lines[j].count(")")
                out.add(j + 1)
                j += 1
        if HINT_BLOCK.search(line):
            depth, j = 0, i
            while j < len(lines):
                depth += lines[j].count("{") - lines[j].count("}")
                out.add(j + 1)
                if depth <= 0 and j > i:
                    break
                j += 1
    return out


def excluded_lines(lines: list[str]) -> set[int]:
    out: set[int] = set()
    i = 0
    while i < len(lines):
        if NON_UI_BLOCK.search(lines[i]):
            depth, started, j = 0, False, i
            while j < len(lines):
                depth += lines[j].count("{") - lines[j].count("}")
                started = started or "{" in lines[j]
                out.add(j + 1)
                if started and depth <= 0:
                    break
                j += 1
            i = j + 1
        else:
            i += 1
    return out


def swift_sources() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "*.swift"], cwd=ROOT, capture_output=True, text=True, check=True
    ).stdout.splitlines()
    keep = []
    for rel in out:
        if re.search(r"(Tests?/|Tests\.swift$|UITests|sync/e2e/|Preview)", rel):
            continue
        keep.append(ROOT / rel)
    return keep


def literals(src: str):
    """コメントを飛ばしながら、(行番号, 中身) を返す。補間 \\( ... ) は ◯ に潰す。"""
    i, n, line = 0, len(src), 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            i += 1
        elif src.startswith("//", i):
            while i < n and src[i] != "\n":
                i += 1
        elif src.startswith("/*", i):
            depth = 1
            i += 2
            while i < n and depth:
                if src.startswith("/*", i):
                    depth += 1
                    i += 2
                elif src.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    if src[i] == "\n":
                        line += 1
                    i += 1
        elif c == '"' or (c == "#" and src.startswith('#"', i)):
            raw = c == "#"
            if raw:
                i += 1
            multi = src.startswith('"""', i)
            quote = '"""' if multi else '"'
            i += len(quote)
            start_line = line
            buf = []
            while i < n:
                if src.startswith(quote + ("#" if raw else ""), i):
                    i += len(quote) + (1 if raw else 0)
                    break
                ch = src[i]
                if ch == "\\" and not raw:
                    if src[i + 1 : i + 2] == "(":
                        depth = 0
                        i += 1
                        while i < n:
                            if src[i] == "(":
                                depth += 1
                            elif src[i] == ")":
                                depth -= 1
                                if depth == 0:
                                    i += 1
                                    break
                            elif src[i] == "\n":
                                line += 1
                            i += 1
                        buf.append("◯")
                        continue
                    nxt = src[i + 1 : i + 2]
                    buf.append({"n": "\n", "t": "\t"}.get(nxt, nxt))
                    i += 2
                    continue
                if ch == "\n":
                    line += 1
                buf.append(ch)
                i += 1
            yield start_line, "".join(buf)
        else:
            i += 1


def main() -> None:
    rows = []
    for path in swift_sources():
        src = path.read_text(encoding="utf-8")
        lines = src.splitlines()
        skip = excluded_lines(lines)
        hints = hint_lines(lines)
        for ln, text in literals(src):
            if not JA.search(text) or ln in skip or DATE_FORMAT.match(text):
                continue
            ctx = lines[ln - 1].strip() if ln - 1 < len(lines) else ""
            if NON_UI_CONTEXT.search(ctx):
                continue
            rows.append(
                {
                    "file": str(path.relative_to(ROOT)),
                    "line": ln,
                    "text": text.strip(),
                    "context": ctx,
                    "kind": "hint"
                    if ln in hints and f'title: "{text}"' not in ctx
                    else "",
                }
            )
    for r in rows:
        sys.stdout.write(json.dumps(r, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()

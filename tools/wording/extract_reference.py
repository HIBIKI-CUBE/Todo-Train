#!/usr/bin/env python3
"""人間側の基準コーパス: この Mac の Apple 純正アプリの日本語 UI 文字列。

.loctable（言語→キー→値の plist）と ja.lproj/*.strings から、ja と対応する en を対にして抜く。
出力: JSON Lines（app, key, ja, en）。重複する ja は 1 件にまとめる。
"""
import json
import plistlib
import re
import sys
from pathlib import Path

ROOTS = [Path("/System/Applications"), Path("/System/Applications/Utilities")]
JA = re.compile(r"[ぁ-んァ-ヶ一-龠]")
FORMAT = re.compile(r"%(\d+\$)?(#@\w+@|[@dDuUxXoOfeEgGcCsSpaFlh]+|ld|lu|lld|llu)")


def flatten(v):
    """複数形などの辞書値は、文字列の葉だけを拾う。"""
    if isinstance(v, str):
        yield v
    elif isinstance(v, dict):
        for k, x in v.items():
            if k.startswith("NSStringFormat"):
                continue
            yield from flatten(x)


def load_plist(path: Path):
    data = path.read_bytes()
    try:
        return plistlib.loads(data)
    except Exception:
        pass
    # 旧来のテキスト .strings
    for enc in ("utf-16", "utf-8"):
        try:
            text = data.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    else:
        return None
    out = {}
    for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', text):
        out[m.group(1)] = m.group(2).encode().decode("unicode_escape", errors="ignore")
    return out


def normalize(s: str) -> str:
    return FORMAT.sub("◯", s).strip()


def main() -> None:
    seen = set()
    apps = [p for r in ROOTS if r.exists() for p in r.glob("*.app")]
    for app in sorted(apps):
        for table in app.rglob("*.loctable"):
            d = load_plist(table)
            if not isinstance(d, dict):
                continue
            ja, en = d.get("ja") or {}, d.get("en") or {}
            for key, val in ja.items():
                ens = list(flatten(en.get(key, "")))
                for i, s in enumerate(flatten(val)):
                    emit(seen, app.stem, key, s, ens[i] if i < len(ens) else "")
        for strings in app.rglob("ja.lproj/*.strings"):
            d = load_plist(strings)
            if not isinstance(d, dict):
                continue
            en_path = strings.parent.parent / "en.lproj" / strings.name
            en = load_plist(en_path) if en_path.exists() else {}
            en = en if isinstance(en, dict) else {}
            for key, val in d.items():
                ens = list(flatten(en.get(key, "")))
                for i, s in enumerate(flatten(val)):
                    emit(seen, app.stem, key, s, ens[i] if i < len(ens) else "")


def emit(seen, app, key, ja, en):
    ja = normalize(ja)
    if not JA.search(ja) or ja in seen:
        return
    seen.add(ja)
    sys.stdout.write(
        json.dumps({"app": app, "key": key, "ja": ja, "en": normalize(en)}, ensure_ascii=False)
        + "\n"
    )


if __name__ == "__main__":
    main()

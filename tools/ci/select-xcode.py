#!/usr/bin/env python3
"""開発に使っている Xcode 27.2（build 27B5019j）に最も近いインストールを選ぶ。

選んだ Developer ディレクトリを stdout に 1 行で出す。一覧は stderr。
"""

import os
import subprocess
import sys
from pathlib import Path

PREFERRED_VERSION = (27, 2, 0)
PREFERRED_BUILD = "27B5019j"


def version_tuple(text):
    parts = text.split(".")
    nums = []
    for i in range(3):
        if i < len(parts) and parts[i].isdigit():
            nums.append(int(parts[i]))
        else:
            nums.append(0)
    return tuple(nums)


def discover():
    found = {}
    for app in sorted(Path("/Applications").glob("Xcode*.app")):
        dev = app / "Contents" / "Developer"
        xcb = dev / "usr" / "bin" / "xcodebuild"
        if not xcb.is_file():
            continue
        real = dev.resolve()
        if real in found:
            continue
        env = os.environ.copy()
        env["DEVELOPER_DIR"] = str(real)
        proc = subprocess.run(
            [str(xcb), "-version"],
            env=env,
            check=False,
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            print(f"skip {app}: xcodebuild failed", file=sys.stderr)
            continue
        lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        if not lines or not lines[0].startswith("Xcode "):
            print(f"skip {app}: {proc.stdout!r}", file=sys.stderr)
            continue
        ver_text = lines[0].split(" ", 1)[1].strip()
        build = ""
        for line in lines:
            if line.startswith("Build version "):
                build = line.split(" ", 2)[2].strip()
        found[real] = (version_tuple(ver_text), ver_text, build, app)
    return found


def rank(item):
    ver, build, real, _ver_text = item
    dist = (
        abs(ver[0] - PREFERRED_VERSION[0]) * 100
        + abs(ver[1] - PREFERRED_VERSION[1]) * 10
        + abs(ver[2] - PREFERRED_VERSION[2])
    )
    exact_build = 0 if build == PREFERRED_BUILD else 1
    newer_build = tuple(-ord(ch) for ch in build)
    return (dist, exact_build, newer_build, str(real))


def main():
    found = discover()
    if not found:
        print("Xcode が見つからない", file=sys.stderr)
        return 1
    items = []
    for real, (ver, ver_text, build, app) in found.items():
        print(f"{app}  Xcode {ver_text}  {build}  {real}", file=sys.stderr)
        items.append((ver, build, real, ver_text))
    items.sort(key=rank)
    _ver, build, real, ver_text = items[0]
    print(f"selected Xcode {ver_text} {build} ({real})", file=sys.stderr)
    print(real)
    return 0


if __name__ == "__main__":
    sys.exit(main())

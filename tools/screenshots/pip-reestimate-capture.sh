#!/usr/bin/env bash
# Mac PiP 位置確認バンドのスクショを docs に書き出す。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHOT_DIR="${PIP_BAND_DIR:-$ROOT/docs/screenshots/pip-reestimate}"
SCHEME="$ROOT/Todo train.xcodeproj/xcshareddata/xcschemes/TodoTrainCompanion.xcscheme"
mkdir -p "$SHOT_DIR"

enable_stdout() {
  perl -i -pe '
    if (/key = "PIP_BAND_STDOUT"/) { $on = 1 }
    if ($on && /isEnabled = "NO"/) { s/isEnabled = "NO"/isEnabled = "YES"/; $on = 0 }
  ' "$SCHEME"
}

disable_stdout() {
  perl -i -pe '
    if (/key = "PIP_BAND_STDOUT"/) { $on = 1 }
    if ($on && /isEnabled = "YES"/) { s/isEnabled = "YES"/isEnabled = "NO"/; $on = 0 }
  ' "$SCHEME"
}

cleanup() { disable_stdout; }
trap cleanup EXIT

cd "$ROOT"
LOG="$(mktemp)"
enable_stdout
xcodebuild test \
  -scheme TodoTrainCompanion \
  -only-testing:TodoTrainCompanionTests/MacPipReestimateTests \
  -destination 'platform=macOS' \
  2>&1 | tee "$LOG"

python3 - "$LOG" "$SHOT_DIR" <<'PY'
import base64, pathlib, re, sys
log, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
pattern = re.compile(r'^PIP_BAND_PNG:([^:]+):(.+)$')
count = 0
for line in log.read_text(errors='replace').splitlines():
    match = pattern.match(line.strip())
    if not match:
        continue
    name, payload = match.group(1), match.group(2)
    (out / f"{name}.png").write_bytes(base64.b64decode(payload))
    count += 1
if count != 4:
    raise SystemExit(f'expected 4 PNG payloads, got {count}')
PY

echo "Wrote $SHOT_DIR"
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="dev.hibiki-cube.Todo-train"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_NAME="pr162-shots"
SHOT_DIR="${PR157B_SHOT_DIR:-$ROOT/../AgentStores-placeholder/pr157b-screenshots}"

mkdir -p "$SHOT_DIR"
rm -f "$SHOT_DIR"/*.png

xcrun simctl delete "$DEVICE_NAME" 2>/dev/null || true
UDID="$(xcrun simctl create "$DEVICE_NAME" "iPhone 17" "$RUNTIME")"
echo "Simulator $DEVICE_NAME → $UDID"

cd "$ROOT"
xcodebuild \
  -scheme "Todo train" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath /tmp/TodoTrain-pr157b-dd \
  build-for-testing \
  -quiet

APP="/tmp/TodoTrain-pr157b-dd/Build/Products/Debug-iphonesimulator/Todo train.app"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

capture() {
  local file="$1"
  local state="$2"
  local landscape="${3:-0}"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.6
  local args=( "$BUNDLE_ID" -uiPreviewState "$state" )
  if [[ "$landscape" == "1" ]]; then
    args+=( -uiPreviewLandscape )
  fi
  xcrun simctl launch "$UDID" "${args[@]}" >/dev/null
  if [[ "$state" == arrival* ]]; then
    sleep 5.5
  elif [[ "$landscape" == "1" ]]; then
    sleep 4.5
  else
    sleep 3.0
  fi
  xcrun simctl io "$UDID" screenshot "$SHOT_DIR/$file"
  echo "Wrote $SHOT_DIR/$file"
}

VERIFY_PY="$ROOT/tools/wording/.venv/bin/python"
if [[ ! -x "$VERIFY_PY" ]]; then
  python3 -m venv "$ROOT/tools/wording/.venv"
  "$ROOT/tools/wording/.venv/bin/pip" install -q pillow
  VERIFY_PY="$ROOT/tools/wording/.venv/bin/python"
fi

verify_image() {
  local file="$1"
  local expect_landscape="$2"
  "$VERIFY_PY" - "$SHOT_DIR/$file" "$expect_landscape" <<'PY'
import sys
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    print("skip verify (no PIL)", file=sys.stderr)
    sys.exit(0)
path = Path(sys.argv[1])
expect_landscape = sys.argv[2] == "1"
im = Image.open(path).convert("RGB")
w, h = im.size
if expect_landscape and w <= h:
    print(f"FAIL {path.name}: expected landscape, got {w}x{h}", file=sys.stderr)
    sys.exit(1)
if not expect_landscape and h > w:
    pass
elif not expect_landscape and w > h:
    print(f"FAIL {path.name}: expected portrait, got {w}x{h}", file=sys.stderr)
    sys.exit(1)
# reject mostly-white frames (status bar only)
pixels = list(im.getdata())
avg = sum(sum(p) for p in pixels) / (3 * len(pixels))
if avg > 245:
    print(f"FAIL {path.name}: image too bright (avg={avg:.1f})", file=sys.stderr)
    sys.exit(1)
print(f"OK {path.name}: {w}x{h} avg={avg:.1f}")
PY
}

for state in homeSignalGreen homeSignalYellow homeSignalOff; do
  capture "portrait_${state}.png" "$state" 0
  verify_image "portrait_${state}.png" 0
  capture "landscape_${state}.png" "$state" 1
  verify_image "landscape_${state}.png" 1
done

for state in arrivalOnTimeTicketing arrivalOnTimeEarly arrivalOnTimeLate arrivalNotOnTime arrivalLateLog; do
  capture "portrait_${state}.png" "$state" 0
  verify_image "portrait_${state}.png" 0
  capture "landscape_${state}.png" "$state" 1
  verify_image "landscape_${state}.png" 1
done

xcrun simctl shutdown "$UDID" || true

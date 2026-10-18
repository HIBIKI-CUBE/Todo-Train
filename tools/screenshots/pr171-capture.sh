#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="dev.hibiki-cube.Todo-train"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_NAME="pr171-shots"
SHOT_DIR="${PR171_SHOT_DIR:-$ROOT/docs/screenshots/pr-171-b}"

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
  -derivedDataPath /tmp/TodoTrain-pr171-dd \
  build-for-testing \
  -quiet

APP="/tmp/TodoTrain-pr171-dd/Build/Products/Debug-iphonesimulator/Todo train.app"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

capture() {
  local file="$1"
  local state="$2"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.6
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiPreviewState "$state" >/dev/null
  if [[ "$state" == arrival* ]]; then
    sleep 5.5
  else
    sleep 3.2
  fi
  local tmp="/tmp/pr171-${file}"
  xcrun simctl io "$UDID" screenshot "$tmp"
  cp "$tmp" "$SHOT_DIR/$file"
  echo "Wrote $SHOT_DIR/$file"
}

VERIFY_PY="$ROOT/tools/wording/.venv/bin/python"
if [[ ! -x "$VERIFY_PY" ]]; then
  python3 -m venv "$ROOT/tools/wording/.venv"
  "$ROOT/tools/wording/.venv/bin/pip" install -q pillow
  VERIFY_PY="$ROOT/tools/wording/.venv/bin/python"
fi

capture seal-gallery.png sealGallery
capture arrival-on-time-ticketing.png arrivalOnTimeTicketing
capture arrival-on-time-early.png arrivalOnTimeEarly
capture arrival-on-time-late.png arrivalOnTimeLate
capture home-signal-green.png homeSignalGreen
capture position-report-declare.png positionReportDeclare

"$VERIFY_PY" "$ROOT/tools/screenshots/pr171-gray.py" "$SHOT_DIR/seal-gallery.png" "$SHOT_DIR"

xcrun simctl shutdown "$UDID" || true
echo "Done → $SHOT_DIR"

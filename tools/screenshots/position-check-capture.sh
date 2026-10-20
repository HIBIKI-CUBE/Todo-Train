#!/usr/bin/env bash
# 位置確認（#182）のスクショ。発券シートが変わっていないことも 1 枚残す。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="dev.hibiki-cube.Todo-train"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_NAME="position-check-shots"
SHOT_DIR="${POSITION_CHECK_SHOT_DIR:-$ROOT/docs/screenshots/position-check}"

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
  -derivedDataPath /tmp/TodoTrain-position-check-dd \
  build-for-testing \
  -quiet

APP="/tmp/TodoTrain-position-check-dd/Build/Products/Debug-iphonesimulator/Todo train.app"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

capture() {
  local file="$1"
  local state="$2"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.6
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiPreviewState "$state" >/dev/null
  sleep 3.6
  local tmp="/tmp/position-check-${file}"
  xcrun simctl io "$UDID" screenshot "$tmp"
  cp "$tmp" "$SHOT_DIR/$file"
  echo "Wrote $SHOT_DIR/$file"
}

capture position-check-open.png positionCheckOpen
capture position-check-live-6.png positionCheckLive6
capture position-check-out-6.png positionCheckOut6
capture position-check-home-7.png positionCheckHome7
capture position-check-full.png positionCheckFull
capture position-check-banner.png positionCheckBanner
capture position-check-overtime.png positionReportOvertime
capture quick-add-unchanged.png quickAdd

xcrun simctl shutdown "$UDID" || true
echo "Done → $SHOT_DIR"

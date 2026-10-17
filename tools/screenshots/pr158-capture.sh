#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="dev.hibiki-cube.Todo-train"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_NAME="pr158-shots"
SHOT_DIR="${PR158_SHOT_DIR:-$ROOT/tools/screenshots/pr158-screenshots}"
CROP_DIR="$SHOT_DIR/crops"

mkdir -p "$SHOT_DIR" "$CROP_DIR"
rm -f "$SHOT_DIR"/*.png "$CROP_DIR"/*.png

xcrun simctl delete "$DEVICE_NAME" 2>/dev/null || true
UDID="$(xcrun simctl create "$DEVICE_NAME" "iPhone 17" "$RUNTIME")"
echo "Simulator $DEVICE_NAME → $UDID"

cd "$ROOT"
xcodebuild \
  -scheme "Todo train" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath /tmp/TodoTrain-pr158-dd \
  build-for-testing \
  -quiet

APP="/tmp/TodoTrain-pr158-dd/Build/Products/Debug-iphonesimulator/Todo train.app"

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
  if [[ "$landscape" == "1" ]]; then
    sleep 4.5
  else
    sleep 3.2
  fi
  local tmp="/tmp/pr158-${file}"
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

CROP_PY="$ROOT/tools/screenshots/pr158-crop.py"
chmod +x "$CROP_PY"

crop_region() {
  local src="$1"
  local out="$2"
  local mode="$3"
  "$VERIFY_PY" "$CROP_PY" "$mode" "$SHOT_DIR/$src" "$CROP_DIR/$out"
}

capture shutdown-bundle-portrait.png shutdownBundle 0
capture shutdown-bundle-landscape.png shutdownBundleLandscape 1
capture shutdown-bundle-peel-portrait.png shutdownBundlePeel 0
capture shutdown-bundle-peel-landscape.png shutdownBundlePeelLandscape 1
capture history-bundle-portrait.png historyBundle 0
capture history-bundle-landscape.png historyBundleLandscape 1
capture history-bundle-viewer-portrait.png historyBundleViewer 0
capture history-bundle-viewer-landscape.png historyBundleViewerLandscape 1
capture history-bundle-viewer-boundary-portrait.png historyBundleViewerBoundary 0
capture history-bundle-viewer-boundary-landscape.png historyBundleViewerBoundaryLandscape 1
capture history-empty-bundle-portrait.png historyEmptyBundle 0
capture history-empty-bundle-landscape.png historyEmptyBundle 1

crop_region shutdown-bundle-portrait.png shutdown-bundle-portrait-tickets.png shutdown
crop_region shutdown-bundle-peel-portrait.png shutdown-bundle-peel-portrait-tickets.png shutdown
crop_region history-bundle-portrait.png history-bundle-portrait-tickets.png history-day
crop_region history-bundle-viewer-portrait.png history-bundle-viewer-tickets.png viewer
crop_region history-bundle-viewer-boundary-portrait.png history-bundle-viewer-boundary-tickets.png viewer
cp "$CROP_DIR/history-bundle-portrait-tickets.png" "$CROP_DIR/history-bundle-tickets.png"

xcrun simctl shutdown "$UDID" || true
echo "Done → $SHOT_DIR"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="dev.hibiki-cube.Todo-train"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_NAME="pr171-shots"
SHOT_DIR="${PR171_SHOT_DIR:-$ROOT/docs/screenshots/pr-171-b}"

mkdir -p "$SHOT_DIR"
if [[ "${PR171_SKIP_B:-}" != "1" ]]; then
  rm -f "$SHOT_DIR"/*.png
fi

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
  local landscape="${3:-0}"
  local dir="${4:-$SHOT_DIR}"
  local spread="${5:-}"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.6
  local args=( "$BUNDLE_ID" -uiPreviewState "$state" )
  if [[ "$landscape" == "1" ]]; then
    args+=( -uiPreviewLandscape )
  fi
  if [[ -n "$spread" ]]; then
    args+=( -uiPreviewBundleSpread "$spread" )
  fi
  xcrun simctl launch "$UDID" "${args[@]}" >/dev/null
  if [[ "$state" == arrival* ]]; then
    sleep 5.5
  elif [[ "$landscape" == "1" ]]; then
    sleep 4.5
  else
    sleep 3.6
  fi
  local tmp="/tmp/pr171-${file}"
  xcrun simctl io "$UDID" screenshot "$tmp"
  cp "$tmp" "$dir/$file"
  echo "Wrote $dir/$file"
}

VERIFY_PY="$ROOT/tools/wording/.venv/bin/python"
if [[ ! -x "$VERIFY_PY" ]]; then
  python3 -m venv "$ROOT/tools/wording/.venv"
  "$ROOT/tools/wording/.venv/bin/pip" install -q pillow
  VERIFY_PY="$ROOT/tools/wording/.venv/bin/python"
fi

if [[ "${PR171_SKIP_B:-}" != "1" ]]; then
  capture seal-gallery.png sealGallery
  capture arrival-on-time-ticketing.png arrivalOnTimeTicketing
  capture arrival-on-time-early.png arrivalOnTimeEarly
  capture arrival-on-time-late.png arrivalOnTimeLate
  capture home-signal-green.png homeSignalGreen
  capture position-report-declare.png positionReportDeclare

  "$VERIFY_PY" "$ROOT/tools/screenshots/pr171-gray.py" "$SHOT_DIR/seal-gallery.png" "$SHOT_DIR"
fi

C_DIR="${PR171_C_DIR:-$ROOT/docs/screenshots/pr-171-c}"
mkdir -p "$C_DIR"
rm -f "$C_DIR"/*.png

capture shutdown-bundle.png shutdownBundle 0 "$C_DIR"
capture shutdown-bundle-spread-05.png shutdownBundle 0 "$C_DIR" 0.5
capture shutdown-bundle-spread-1.png shutdownBundle 0 "$C_DIR" 1
capture shutdown-bundle-landscape.png shutdownBundleLandscape 1 "$C_DIR"
capture history-bundle.png historyBundle 0 "$C_DIR"
capture history-bundle-spread-05.png historyBundle 0 "$C_DIR" 0.5
capture history-bundle-spread-1.png historyBundle 0 "$C_DIR" 1
capture history-bundle-landscape.png historyBundleLandscape 1 "$C_DIR"
capture history-bundle-viewer.png historyBundleViewer 0 "$C_DIR"
capture history-bundle-viewer-landscape.png historyBundleViewerLandscape 1 "$C_DIR"
capture arrival-on-time-ticketing.png arrivalOnTimeTicketing 0 "$C_DIR"

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
sleep 0.4
VIDEO="$C_DIR/fan-open.mp4"
rm -f "$VIDEO"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$VIDEO" >/dev/null 2>&1 &
RECORD_PID=$!
sleep 0.4
xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiPreviewState shutdownBundle -uiPreviewBundleFanDemo >/dev/null
sleep 3.6
kill -INT "$RECORD_PID" 2>/dev/null || true
wait "$RECORD_PID" 2>/dev/null || true
if [[ -f "$VIDEO" ]]; then
  echo "Wrote $VIDEO ($(wc -c < "$VIDEO") bytes)"
else
  echo "Fan video was not written"
fi

xcrun simctl shutdown "$UDID" || true

# 小さい iPhone がこのランタイムにあれば、運行終了の束を 1 枚。
SMALL_NAME="pr171-shots-small"
SMALL_UDID=""
SMALL_TYPE=""
for candidate in "iPhone SE (3rd generation)" "iPhone 16e" "iPhone 17e"; do
  if ! xcrun simctl list devicetypes | grep -F "$candidate (" >/dev/null \
    && ! xcrun simctl list devicetypes | grep -F "$candidate" >/dev/null; then
    continue
  fi
  xcrun simctl delete "$SMALL_NAME" 2>/dev/null || true
  if SMALL_UDID="$(xcrun simctl create "$SMALL_NAME" "$candidate" "$RUNTIME" 2>/dev/null)"; then
    SMALL_TYPE="$candidate"
    break
  fi
done
if [[ -n "$SMALL_UDID" ]]; then
  echo "Small simulator $SMALL_TYPE → $SMALL_UDID"
  xcrun simctl boot "$SMALL_UDID" || true
  xcrun simctl bootstatus "$SMALL_UDID" -b
  xcrun simctl install "$SMALL_UDID" "$APP"
  UDID="$SMALL_UDID"
  capture shutdown-bundle-small.png shutdownBundle 0 "$C_DIR"
  xcrun simctl shutdown "$SMALL_UDID" || true
  xcrun simctl delete "$SMALL_UDID" || true
else
  echo "No small iPhone for $RUNTIME — skipped"
fi

echo "Done → $SHOT_DIR and $C_DIR"

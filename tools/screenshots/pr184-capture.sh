#!/usr/bin/env bash
# きっぷの束の扇。縦横、spread 0・0.5・1、focus 最古・中ほど・最新、20 枚。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="dev.hibiki-cube.Todo-train"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_NAME="pr184-shots"
SHOT_DIR="${PR184_SHOT_DIR:-$ROOT/docs/screenshots/pr-184}"

mkdir -p "$SHOT_DIR"
rm -f "$SHOT_DIR"/*.png "$SHOT_DIR"/*.mp4

xcrun simctl delete "$DEVICE_NAME" 2>/dev/null || true
UDID="$(xcrun simctl create "$DEVICE_NAME" "iPhone 17" "$RUNTIME")"
echo "Simulator $DEVICE_NAME → $UDID"

cd "$ROOT"
xcodebuild \
  -scheme "Todo train" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath /tmp/TodoTrain-pr184-dd \
  build-for-testing \
  -quiet

APP="/tmp/TodoTrain-pr184-dd/Build/Products/Debug-iphonesimulator/Todo train.app"

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$APP"

capture() {
  local file="$1"
  local state="$2"
  local landscape="${3:-0}"
  local spread="${4:-}"
  local focus="${5:-}"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.4
  local args=( "$BUNDLE_ID" -uiPreviewState "$state" )
  if [[ "$landscape" == "1" ]]; then
    args+=( -uiPreviewLandscape )
  fi
  if [[ -n "$spread" ]]; then
    args+=( -uiPreviewBundleSpread "$spread" )
  fi
  if [[ -n "$focus" ]]; then
    args+=( -uiPreviewBundleFocus "$focus" )
  fi
  xcrun simctl launch "$UDID" "${args[@]}" >/dev/null
  if [[ "$landscape" == "1" ]]; then
    sleep 4.2
  else
    sleep 3.2
  fi
  local tmp="/tmp/pr184-${file}"
  xcrun simctl io "$UDID" screenshot "$tmp"
  cp "$tmp" "$SHOT_DIR/$file"
  echo "Wrote $SHOT_DIR/$file"
}

focus_name() {
  case "$1" in
    0) echo "oldest" ;;
    0.5) echo "mid" ;;
    1) echo "newest" ;;
    *) echo "focus$1" ;;
  esac
}

spread_name() {
  case "$1" in
    0) echo "0" ;;
    0.5) echo "0.5" ;;
    1) echo "1" ;;
    *) echo "$1" ;;
  esac
}

for state in historyBundle shutdownBundle historyBundleViewer historyBundleMany; do
  for landscape in 0 1; do
    if [[ "$landscape" == "1" ]]; then
      orient="landscape"
    else
      orient="portrait"
    fi
    for spread in 0 0.5 1; do
      for focus in 0 0.5 1; do
        file="${state}-${orient}-spread$(spread_name "$spread")-focus-$(focus_name "$focus").png"
        capture "$file" "$state" "$landscape" "$spread" "$focus"
      done
    done
  done
done

xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
sleep 0.4
VIDEO="$SHOT_DIR/fan-scrub.mp4"
rm -f "$VIDEO"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$VIDEO" >/dev/null 2>&1 &
RECORD_PID=$!
sleep 0.4
xcrun simctl launch "$UDID" "$BUNDLE_ID" -uiPreviewState historyBundle -uiPreviewBundleFanDemo >/dev/null
sleep 4.6
kill -INT "$RECORD_PID" 2>/dev/null || true
wait "$RECORD_PID" 2>/dev/null || true
if [[ -f "$VIDEO" ]]; then
  echo "Wrote $VIDEO ($(wc -c < "$VIDEO") bytes)"
else
  echo "Fan video was not written"
fi

xcrun simctl shutdown "$UDID" || true
echo "Done → $SHOT_DIR"

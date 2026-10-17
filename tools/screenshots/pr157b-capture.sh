#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUNDLE_ID="dev.hibiki-cube.Todo-train"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-27-2"
DEVICE_NAME="pr162-shots"
SHOT_DIR="${PR157B_SHOT_DIR:-$ROOT/../AgentStores-placeholder/pr157b-screenshots}"

mkdir -p "$SHOT_DIR"

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
  local extra="${3:-}"
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 0.5
  local args=( "$BUNDLE_ID" -uiPreviewState "$state" )
  if [[ -n "$extra" ]]; then
    args+=( "$extra" )
  fi
  xcrun simctl launch "$UDID" "${args[@]}" >/dev/null
  sleep 2.5
  xcrun simctl io "$UDID" screenshot "$SHOT_DIR/$file"
  echo "Wrote $SHOT_DIR/$file"
}

for state in homeSignalGreen homeSignalYellow homeSignalOff; do
  capture "portrait_${state}.png" "$state"
  capture "landscape_${state}.png" "$state" "-uiPreviewLandscape"
done

for state in arrivalOnTimeTicketing arrivalOnTimeEarly arrivalOnTimeLate arrivalNotOnTime arrivalLateLog; do
  capture "portrait_${state}.png" "$state"
  capture "landscape_${state}.png" "$state" "-uiPreviewLandscape"
done

xcrun simctl shutdown "$UDID" || true

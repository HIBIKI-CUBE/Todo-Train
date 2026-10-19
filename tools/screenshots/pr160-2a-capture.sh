#!/usr/bin/env bash
# PR 160 の 2a。Dynamic Island の compact と開いた表示を撮る。
#
# 実機（このスクリプトは実機へ入れない。HIBIKI が Xcode から入れる）:
#   1. スキームの起動引数に、状態と `-uiPreviewLiveActivity` を足す。
#        -uiPreviewState laRemain12 -uiPreviewLiveActivity
#      状態:
#        laRemain12   走行中、残り約 12:00
#        laRemain90   残り約 1:30
#        laOvertime   超過（カウントアップ）
#        laPaused     停車中（開いた表示の予定は「予定 —」）
#        laPrompt     問いかけ「まだ乗ってる？」
#   2. iPhone で実行し、盤面が出るまで待つ。
#   3. ホームへ戻す。compact の右側に残り時間が見える。
#   4. スクリーンショット。
#   5. Dynamic Island を長押しして開く。残り時間、「予定 HH:mm」（停車中は「予定 —」）、
#      ゲージの両端と列車の頭が角にかかっていないことを撮る。
#   6. compact は laRemain12 / laRemain90 / laOvertime。
#      開いた表示は laRemain12（走行中）/ laPaused / laPrompt / laOvertime。
#   7. ロック画面・StandBy・スマートスタックは、この PR では見た目を変えていない。
#
# Simulator（下の本体。iPhone 18 Pro Max / iOS 27.2）:
#   同じ引数で起動し、ホームのあと島を長押しして PNG を書き出す。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEVICE_NAME="${PR160_DEVICE_NAME:-iPhone 18 Pro Max}"
OS="${PR160_OS:-27.2}"
SHOT_DIR="${PR160_SHOT_DIR:-$ROOT/tools/screenshots/pr160-2a-screenshots}"
DD="${PR160_DD:-/tmp/TodoTrain-pr160-2a-dd}"

mkdir -p "$SHOT_DIR"
touch /tmp/pr160-2a-capture
rm -rf /tmp/pr160-2a-shots
mkdir -p /tmp/pr160-2a-shots

cd "$ROOT"
xcodebuild test \
  -scheme "Todo train" \
  -destination "platform=iOS Simulator,name=${DEVICE_NAME},OS=${OS}" \
  -derivedDataPath "$DD" \
  -only-testing:"Todo trainUITests/PR160IslandCaptureTests" \
  CODE_SIGNING_ALLOWED=NO

rm -f /tmp/pr160-2a-capture
cp -R /tmp/pr160-2a-shots/. "$SHOT_DIR/"
echo "Done → $SHOT_DIR"

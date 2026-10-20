#!/bin/sh
# TodoTrainCompanion の CODE_SIGNING_ALLOWED=NO Release を ditto で zip にする。
# CI と手元の確認は、この xcodebuild と ditto を使う。
# リンカの ad-hoc 印は残る。証明書の署名ではない。外さない。
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"

out_root=${RUNNER_TEMP:-/tmp}
dd="$out_root/TodoTrainCompanion-dd"
zip="$out_root/TodoTrainCompanion.zip"
app="$dd/Build/Products/Release/TodoTrainCompanion.app"

rm -rf "$dd"
mkdir -p "$dd"

xcodebuild \
  -project "Todo train.xcodeproj" \
  -scheme TodoTrainCompanion \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$dd" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [ ! -d "$app" ]; then
  echo "app がない: $app" >&2
  exit 1
fi

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"

echo "app: $app"
echo "zip: $zip"
find "$dd/Build" -name BuildInfo.swift -print -exec cat {} \;

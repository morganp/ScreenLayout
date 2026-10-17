#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP="$PWD/build/ScreenLayout.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ScreenLayout "$APP/Contents/MacOS/ScreenLayout"
cp Info.plist "$APP/Contents/Info.plist"
SOURCE_LIST="$(mktemp)"
CONSTANTS_LIST="$(mktemp)"
trap 'rm -f "$SOURCE_LIST" "$CONSTANTS_LIST"' EXIT
find Sources/ScreenLayout -name '*.swift' -print > "$SOURCE_LIST"
find .build/out/Intermediates.noindex/ScreenLayout.build/Release -name '*.swiftconstvalues' -print > "$CONSTANTS_LIST"
xcrun appintentsmetadataprocessor \
  --output "$APP/Contents/Resources" \
  --toolchain-dir "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain" \
  --module-name ScreenLayout \
  --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/ { print $3 }')" \
  --platform-family macOS \
  --deployment-target 27.0 \
  --target-triple arm64-apple-macos27.0 \
  --source-file-list "$SOURCE_LIST" \
  --swift-const-vals-list "$CONSTANTS_LIST" \
  --force
SIGNING_IDENTITY="${SCREENLAYOUT_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development:/ && !/REVOKED/ { print $2; exit }')}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo 'No valid code signing identity found. Set SCREENLAYOUT_SIGNING_IDENTITY to a stable certificate.' >&2
  exit 1
fi
codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP"
echo "$APP"

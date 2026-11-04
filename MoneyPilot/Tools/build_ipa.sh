#!/bin/zsh
# Builds an unsigned MoneyPilot.ipa for SideStore / AltStore / Sideloadly, which sign it with your own Apple ID.
# Output: build/ipa/MoneyPilot-<version>.ipa (inside the MoneyPilot folder)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION_NAME="${VERSION_NAME:-MK4.1}"
OUT="build/ipa"; ARCHIVE="$OUT/MoneyPilot.xcarchive"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild -project MoneyPilot.xcodeproj -scheme MoneyPilot -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
APP="$ARCHIVE/Products/Applications/MoneyPilot.app"
[[ -d "$APP" ]] || { echo "Archive failed — see the xcodebuild output above." >&2; exit 1; }
codesign --force --sign - --entitlements MoneyPilot/MoneyPilot.entitlements "$APP" # MK4.1: no widget extension any more
mkdir -p "$OUT/Payload"; cp -R "$APP" "$OUT/Payload/"
( cd "$OUT" && zip -qry "MoneyPilot-$VERSION_NAME.ipa" Payload ); rm -rf "$OUT/Payload"
echo "Done: $OUT/MoneyPilot-$VERSION_NAME.ipa"

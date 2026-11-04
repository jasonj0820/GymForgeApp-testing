#!/bin/zsh
# Builds an unsigned MoneyPilot.ipa for SideStore / AltStore / Sideloadly, which sign it with your own Apple ID.
# Each bundle is ad-hoc signed with its entitlements (App Group, Live Activities) so those tools can copy them over.
# Output: build/ipa/MoneyPilot-<version>.ipa (inside the MoneyPilot folder)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION_NAME="${VERSION_NAME:-MK4.0}"
OUT="build/ipa"; ARCHIVE="$OUT/MoneyPilot.xcarchive"
rm -rf "$OUT"; mkdir -p "$OUT"
xcodebuild -project MoneyPilot.xcodeproj -scheme MoneyPilot -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" archive CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
APP="$ARCHIVE/Products/Applications/MoneyPilot.app"
[[ -d "$APP" ]] || { echo "Archive failed — see the xcodebuild output above." >&2; exit 1; }
[[ -d "$APP/PlugIns/MoneyPilotLive.appex" ]] && echo "✓ Widget / Live Activity extension embedded" || echo "⚠︎ MoneyPilotLive.appex missing"
codesign --force --sign - --entitlements MoneyPilotLive/MoneyPilotLive.entitlements "$APP/PlugIns/MoneyPilotLive.appex"
codesign --force --sign - --entitlements MoneyPilot/MoneyPilot.entitlements "$APP"
mkdir -p "$OUT/Payload"; cp -R "$APP" "$OUT/Payload/"
( cd "$OUT" && zip -qry "MoneyPilot-$VERSION_NAME.ipa" Payload ); rm -rf "$OUT/Payload"
echo "Done: $OUT/MoneyPilot-$VERSION_NAME.ipa"

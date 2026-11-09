#!/bin/zsh
# Builds Splitday.ipa for sideloading / auto-signing tools (Sideloadly, AltStore, SideStore, ESign, Feather…).
#
#   ./Scripts/build_ipa.sh            → signed with your Xcode team (keeps HealthKit etc. entitlements
#                                       embedded, which re-signing tools copy over)
#   UNSIGNED=1 ./Scripts/build_ipa.sh → no signing at all (only if your tool adds entitlements itself)
#
# Output: build/ipa/Splitday-<version>.ipa
set -euo pipefail
cd "$(dirname "$0")/.."
# A new build number every build, so iOS re-reads the widget list (new widgets show up without a restart).
BUILD_NUMBER="$(date +%Y%m%d%H%M)"

VERSION_NAME="${VERSION_NAME:-MK20}"
OUT="build/ipa"
ARCHIVE="$OUT/GymForge.xcarchive"
rm -rf "$OUT"
mkdir -p "$OUT"

SIGN_FLAGS=()
if [[ "${UNSIGNED:-0}" == "1" ]]; then
  SIGN_FLAGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
  echo "Building UNSIGNED archive…"
else
  SIGN_FLAGS=(-allowProvisioningUpdates)
  echo "Building archive signed with your Xcode team…"
fi

xcodebuild \
  -project GymForge.xcodeproj \
  -scheme GymForge \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive "${SIGN_FLAGS[@]}" | { if command -v xcpretty >/dev/null; then xcpretty; else cat; fi; } || true

APP="$ARCHIVE/Products/Applications/GymForge.app"
if [[ ! -d "$APP" ]]; then
  echo "Archive failed — open GymForge.xcodeproj and run Product → Archive to see the error." >&2
  exit 1
fi

# Sanity check: the Watch app and Live Activity extension must be inside.
[[ -d "$APP/Watch/GymForge.app" ]] && echo "✓ Watch app embedded" || echo "⚠︎ Watch app missing from GymForge.app/Watch"
[[ -d "$APP/PlugIns/GymForgeWidgets.appex" ]] && echo "✓ Live Activity extension embedded" || echo "⚠︎ Widgets extension missing"

# Unsigned builds carry no entitlements, so re-signing tools (SideStore etc.) would drop HealthKit and the
# App Group. Ad-hoc sign each bundle with its entitlements, innermost first, so the tools can copy them.
if [[ "${UNSIGNED:-0}" == "1" ]]; then
  W="$APP/Watch/GymForge.app"
  [[ -d "$W/PlugIns/GymForgeWatchWidgets.appex" ]] && codesign --force --sign - --entitlements Config/WatchWidgets.entitlements "$W/PlugIns/GymForgeWatchWidgets.appex"
  [[ -d "$W" ]] && codesign --force --sign - --entitlements Config/watchOS.entitlements "$W"
  codesign --force --sign - --entitlements Config/Widgets.entitlements "$APP/PlugIns/GymForgeWidgets.appex"
  codesign --force --sign - --entitlements Config/iOS.entitlements "$APP"
  echo "✓ Entitlements embedded (ad-hoc)"
fi

mkdir -p "$OUT/Payload"
cp -R "$APP" "$OUT/Payload/"
( cd "$OUT" && zip -qry "Splitday-$VERSION_NAME.ipa" Payload )
rm -rf "$OUT/Payload"
echo "Done: $OUT/Splitday-$VERSION_NAME.ipa"

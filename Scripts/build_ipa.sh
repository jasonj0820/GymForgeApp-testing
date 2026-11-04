#!/bin/zsh
# Builds an unsigned Ductile.ipa for SideStore / AltStore (they sign it with your Apple ID).
#   zsh Scripts/build_ipa.sh [version]   → build/ipa/Ductile-<version>.ipa
set -euo pipefail
cd "$(dirname "$0")/.."

V="${1:-dev}"
OUT=build/ipa
ARCHIVE="$OUT/Ductile.xcarchive"
rm -rf "$OUT" && mkdir -p "$OUT"

xcodebuild -project Ductile.xcodeproj -scheme Ductile -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

APP="$ARCHIVE/Products/Applications/Ductile.app"
[[ -d "$APP/PlugIns/DuctileWidgets.appex" ]] || { echo "Widget extension missing from the app" >&2; exit 1; }

# Unsigned builds carry no entitlements, so SideStore would drop the App Group the widget needs.
# Ad-hoc sign each bundle with its entitlements (widget first) so the signer copies them over.
codesign --force --sign - --entitlements Config/Widget.entitlements "$APP/PlugIns/DuctileWidgets.appex"
codesign --force --sign - --entitlements Config/App.entitlements "$APP"

mkdir "$OUT/Payload" && cp -R "$APP" "$OUT/Payload/"
( cd "$OUT" && zip -qry "Ductile-$V.ipa" Payload )
rm -rf "$OUT/Payload"
echo "Done: $OUT/Ductile-$V.ipa"

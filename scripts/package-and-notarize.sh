#!/usr/bin/env bash
#
# package-and-notarize.sh — build, sign, notarize, and package MuseDrop for
# direct distribution (Developer ID, outside the Mac App Store).
#
# One-time setup (creates a Keychain profile so creds aren't passed on the CLI):
#   xcrun notarytool store-credentials "MuseDropNotary" \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
# Required environment variables:
#   DEV_ID_APP     e.g. "Developer ID Application: Your Name (TEAMID)"
#   TEAM_ID        your 10-char Apple Developer Team ID
#   NOTARY_PROFILE the notarytool keychain profile name (e.g. "MuseDropNotary")
#
# Optional:
#   SCHEME (default: MuseDrop)   CONFIG (default: Release)
#
# Usage:
#   DEV_ID_APP="Developer ID Application: …" TEAM_ID=ABCDE12345 \
#   NOTARY_PROFILE=MuseDropNotary ./Scripts/package-and-notarize.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

SCHEME="${SCHEME:-MuseDrop}"
CONFIG="${CONFIG:-Release}"
BUILD_DIR="$ROOT_DIR/build"
ARCHIVE="$BUILD_DIR/MuseDrop.xcarchive"
# Note: the Xcode target/scheme/project keep the internal codename "MuseDrop",
# but PRODUCT_NAME is "Kekasatori", so the built/exported app is Kekasatori.app.
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Kekasatori.app"
DMG="$BUILD_DIR/Kekasatori.dmg"
HELPER_ENTITLEMENTS="$SCRIPT_DIR/helper-entitlements.plist"
APP_ENTITLEMENTS="$ROOT_DIR/MuseDrop/MuseDrop.entitlements"

: "${DEV_ID_APP:?set DEV_ID_APP (e.g. \"Developer ID Application: Name (TEAMID)\")}"
: "${TEAM_ID:?set TEAM_ID}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE (created via 'xcrun notarytool store-credentials')}"

mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$DMG"

echo "▸ [1/7] Archiving ($CONFIG)…"
xcodebuild -project MuseDrop.xcodeproj -scheme "$SCHEME" -configuration "$CONFIG" \
    -archivePath "$ARCHIVE" archive \
    -destination 'generic/platform=macOS' \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$DEV_ID_APP" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    ENABLE_HARDENED_RUNTIME=YES \
    OTHER_CODE_SIGN_FLAGS="--timestamp"

echo "▸ [2/7] Writing ExportOptions.plist…"
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>signingStyle</key><string>manual</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
EOF

echo "▸ [3/7] Exporting Developer ID app…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$EXPORT_DIR"

echo "▸ [4/7] Re-signing bundled CLI helpers under Hardened Runtime…"
# Xcode's synchronized-folder build flattens Resources/bin → Resources/, and it
# may sign the helpers WITHOUT the hardened-runtime flag (notarization then
# rejects them). Find them wherever they landed and re-sign each with
# --options runtime + the helper entitlements. Sign inside-out: helpers first,
# then re-seal the app below.
HELPERS=$(find "$APP/Contents/Resources" -maxdepth 2 \( -name yt-dlp -o -name ffmpeg \) -type f)
if [[ -z "$HELPERS" ]]; then
    echo "ERROR: bundled yt-dlp/ffmpeg not found in the app bundle — aborting (they must be signed to notarize)."
    exit 1
fi
while IFS= read -r bin; do
    codesign --force --timestamp --options runtime \
        --entitlements "$HELPER_ENTITLEMENTS" \
        --sign "$DEV_ID_APP" "$bin"
    echo "    signed $(basename "$bin")"
done <<< "$HELPERS"

codesign --force --timestamp --options runtime \
    --entitlements "$APP_ENTITLEMENTS" \
    --sign "$DEV_ID_APP" "$APP"

echo "▸ [5/7] Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▸ [6/7] Building DMG…"
hdiutil create -volname "Kekasatori" -srcfolder "$APP" -ov -format UDZO "$DMG"
codesign --force --timestamp --sign "$DEV_ID_APP" "$DMG"

echo "▸ [7/7] Notarizing (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling notarization ticket…"
xcrun stapler staple "$DMG"
xcrun stapler staple "$APP"

echo ""
echo "✅ Done. Notarized, stapled disk image:"
echo "   $DMG"
echo ""
echo "Verify Gatekeeper acceptance with:"
echo "   spctl -a -t open --context context:primary-signature -v \"$DMG\""

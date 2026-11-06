#!/usr/bin/env bash
set -euo pipefail

# Builds the release app and packs it as dist/Brim.dmg. Usage: script/make_dmg.sh 0.1.0
# ponytail: signed with a development certificate, not notarized. Add notarytool here once there's a Developer ID.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?usage: make_dmg.sh <version>}"

# The EdDSA key lives in this Mac's Keychain. Create it once with Sparkle's generate_keys (see docs/updates.md).
swift package --package-path "$ROOT_DIR" resolve
sparkle_tool() { find "$ROOT_DIR/.build/artifacts" -type f -name "$1" | head -n1; }
SPARKLE_FEED_URL="https://tapariapurv.github.io/brim/appcast.xml"
SPARKLE_PUBLIC_KEY="$("$(sparkle_tool generate_keys)" -p)"

BUNDLE_ID=com.tapariapurv.brim APP_VERSION="$VERSION" SPARKLE_FEED_URL="$SPARKLE_FEED_URL" SPARKLE_PUBLIC_KEY="$SPARKLE_PUBLIC_KEY" \
  SIGN_ENTITLEMENTS="$ROOT_DIR/script/Brim.release.entitlements.plist" \
  "$ROOT_DIR/script/build_and_run.sh" build

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT_DIR/dist/Brim.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Brim $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$ROOT_DIR/dist/Brim.dmg"
echo "==> dist/Brim.dmg"

# Sign the DMG with the Keychain key and add it to the feed the site serves.
FEED="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$FEED"' EXIT
cp "$ROOT_DIR/dist/Brim.dmg" "$FEED/Brim-$VERSION.dmg"
"$(sparkle_tool generate_appcast)" \
  --download-url-prefix "https://github.com/tapariapurv/brim/releases/download/v$VERSION/" \
  -o "$ROOT_DIR/site/appcast.xml" "$FEED"
echo "==> site/appcast.xml (upload the DMG as Brim-$VERSION.dmg, then publish the site)"

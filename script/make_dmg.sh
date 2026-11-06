#!/usr/bin/env bash
set -euo pipefail

# Builds the release app and packs it as dist/Brim.dmg. Usage: script/make_dmg.sh 0.1.0
# ponytail: signed with a development certificate, not notarized. Add notarytool here once there's a Developer ID.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:?usage: make_dmg.sh <version>}"

BUNDLE_ID=com.tapariapurv.brim APP_VERSION="$VERSION" \
  SIGN_ENTITLEMENTS="$ROOT_DIR/script/Brim.release.entitlements.plist" \
  "$ROOT_DIR/script/build_and_run.sh" build

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$ROOT_DIR/dist/Brim.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Brim $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$ROOT_DIR/dist/Brim.dmg"
echo "==> dist/Brim.dmg"

#!/bin/bash
# Construit l'app puis une image disque à distribuer : build/SweepIt-<version>.dmg
# Le DMG contient SweepIt.app et un raccourci vers Applications (glisser-déposer).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=SweepIt
scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
DMG="build/$APP-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "build/$APP.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "$APP $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null

# Même certificat que l'app, si disponible (voir scripts/setup-signing.sh).
SIGN_DIR="$HOME/.sweepit-signing"
if [[ -f "$SIGN_DIR/signing.keychain-db" ]]; then
    security unlock-keychain -p "$(cat "$SIGN_DIR/password")" "$SIGN_DIR/signing.keychain-db"
    codesign --force --keychain "$SIGN_DIR/signing.keychain-db" --sign "SweepIt Dev" "$DMG"
fi

shasum -a 256 "$DMG" | awk '{print $1}' > "$DMG.sha256"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
echo "  SHA-256 : $(cat "$DMG.sha256")"

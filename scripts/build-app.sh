#!/bin/bash
# Construit build/SweepIt.app (signature ad hoc) et build/SweepIt.zip à partager.
# Usage : scripts/build-app.sh            → architecture de la machine
#         UNIVERSAL=1 scripts/build-app.sh → Apple Silicon + Intel (nécessite Xcode)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=SweepIt
OUT=build/$APP.app
ARGS=(-c release)

# Avec les seules Command Line Tools, le SDK macOS 27 ne fournit pas le plugin
# des macros SwiftUI (@State) : on se rabat sur le SDK 26 le plus récent.
if [[ -z "${SDK:-}" && "$(xcode-select -p)" == *CommandLineTools* ]]; then
    SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
fi
[[ -n "${SDK:-}" ]] && ARGS+=(--sdk "$SDK")
[[ "${UNIVERSAL:-0}" == 1 ]] && ARGS+=(--arch arm64 --arch x86_64)

swift build "${ARGS[@]}"
BIN="$(swift build "${ARGS[@]}" --show-bin-path)/$APP"

rm -rf "$OUT" "build/$APP.zip"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
cp Resources/Info.plist "$OUT/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$OUT/Contents/Resources/"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$OUT/Contents/Info.plist"
fi

# Signature stable si le certificat personnel existe (voir scripts/setup-signing.sh) :
# l'accès complet au disque survit alors aux recompilations. Sinon, signature ad hoc.
SIGN_DIR="$HOME/.sweepit-signing"
if [[ -f "$SIGN_DIR/signing.keychain-db" ]]; then
    security unlock-keychain -p "$(cat "$SIGN_DIR/password")" "$SIGN_DIR/signing.keychain-db"
    codesign --force --deep --keychain "$SIGN_DIR/signing.keychain-db" --sign "SweepIt Dev" "$OUT"
    SIGNATURE="SweepIt Dev (stable)"
else
    codesign --force --deep --sign - "$OUT"
    SIGNATURE="ad hoc : lancez scripts/setup-signing.sh pour garder l'accès au disque entre deux versions"
fi
ditto -c -k --keepParent "$OUT" "build/$APP.zip"

echo "✓ $OUT — signature $SIGNATURE"
echo "✓ build/$APP.zip"

#!/bin/bash
# Crée (une seule fois) un certificat de signature personnel « SweepIt Dev ».
#
# Pourquoi : macOS lie l'accès complet au disque à la signature de l'app. Avec une
# signature ad hoc, chaque recompilation change cette signature et l'accès est perdu.
# Avec un certificat stable, l'accès survit aux recompilations (chez vous et chez vos amis).
#
# Tout est rangé dans ~/.sweepit-signing, dans un trousseau dédié : le trousseau de
# session de l'utilisateur n'est pas modifié. Ne publiez jamais ce dossier, et
# sauvegardez-le : sans lui, les prochaines versions auront une autre signature.
set -euo pipefail

DIR="$HOME/.sweepit-signing"
KC="$DIR/signing.keychain-db"
NAME="SweepIt Dev"
OPENSSL=/usr/bin/openssl   # LibreSSL : ses .p12 s'importent dans le trousseau macOS

if [[ -f "$KC" ]]; then
    echo "Le certificat existe déjà dans $KC"
    exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
PW=$("$OPENSSL" rand -hex 24)
printf '%s' "$PW" > "$DIR/password"
chmod 600 "$DIR/password"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/id.p12" -passout "pass:$PW"

security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"          # pas de verrouillage automatique
security unlock-keychain -p "$PW" "$KC"
security import "$TMP/id.p12" -k "$KC" -P "$PW" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KC" >/dev/null

echo "✓ Certificat « $NAME » créé dans $KC"
echo "  Sauvegardez le dossier $DIR (et ne le publiez pas)."

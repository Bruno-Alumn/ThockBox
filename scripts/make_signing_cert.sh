#!/bin/sh
# Create the "ThockBox Signing" code signing identity in the login keychain.
#
# Run via: make signing-cert
#
# macOS ties the Accessibility grant to how an app is signed. Ad-hoc builds
# get a new identity every time, so each rebuild or update needs the grant
# again. Signing every build with this one self-signed certificate keeps the
# identity the same, so the grant carries over. Only the machine that builds
# releases needs it; keep a backup (Keychain Access → export), since a new
# certificate means one more round of re-granting for everyone.
set -eu

NAME="ThockBox Signing"

if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "\"$NAME\" already exists"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cat > "$work/cert.conf" <<EOF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
    -config "$work/cert.conf" -extensions ext \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
    -name "$NAME" -passout pass:thockbox -out "$work/identity.p12"
security import "$work/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P thockbox -T /usr/bin/codesign >/dev/null

echo "created \"$NAME\""

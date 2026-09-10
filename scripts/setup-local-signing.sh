#!/bin/bash
# --prepare only creates private local files. --install modifies the user's
# login keychain and user-domain code-signing trust; run it with user approval.
set -euo pipefail
umask 077
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="$PROJECT_DIR/.codesign"
CERT_NAME="ClipboardBoard Local Development"
KEYCHAIN_PATH="${SIGNING_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
PASSWORD_FILE="$SIGNING_DIR/wrapping.pass"
MODE="${1:---prepare}"
if [[ "$MODE" != "--prepare" && "$MODE" != "--install" ]]; then
    printf '用法：%s --prepare | --install\n' "$0" >&2
    exit 2
fi
mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"
trap 'rm -f "$SIGNING_DIR/private-key.pem" "$SIGNING_DIR/repackage.pem"' EXIT
if [[ -f "$SIGNING_DIR/identity.sha1" ]]; then
    IDENTITY="$(cat "$SIGNING_DIR/identity.sha1")"
    if security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -Fq "$IDENTITY"; then
        printf '固定签名身份已就绪：%s\n' "$CERT_NAME"
        exit 0
    fi
    # Never silently generate a different private key for an existing identity.
    if [[ ! -f "$SIGNING_DIR/identity.p12" ]]; then
        printf '已登记的签名身份不可用。请恢复钥匙串中的原证书，不要重新生成身份。\n' >&2
        exit 1
    fi
fi

if [[ ! -f "$SIGNING_DIR/identity.p12" ]]; then
    cat > "$SIGNING_DIR/certificate.cnf" <<'EOF'
[req]
distinguished_name = subject
prompt = no
x509_extensions = code_signing
[subject]
CN = ClipboardBoard Local Development
[code_signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid
EOF
    openssl req -newkey rsa:2048 -nodes -x509 -sha256 -days 3650 \
        -config "$SIGNING_DIR/certificate.cnf" \
        -keyout "$SIGNING_DIR/private-key.pem" -out "$SIGNING_DIR/certificate.pem" 2>/dev/null
    # This random password wraps only the temporary import package, not a user account.
    openssl rand -hex 32 > "$PASSWORD_FILE"
    openssl pkcs12 -export -name "$CERT_NAME" \
        -inkey "$SIGNING_DIR/private-key.pem" -in "$SIGNING_DIR/certificate.pem" \
        -out "$SIGNING_DIR/identity.p12" -passout "file:$PASSWORD_FILE" \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES
    rm "$SIGNING_DIR/private-key.pem"
fi
IDENTITY="$(openssl x509 -in "$SIGNING_DIR/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"

# Upgrade packages prepared by the earlier empty-password workflow in place.
# Keep the original certificate and private key; only the transport wrapping changes.
if [[ ! -f "$PASSWORD_FILE" ]]; then
    openssl pkcs12 -in "$SIGNING_DIR/identity.p12" -passin pass: -nodes \
        -out "$SIGNING_DIR/repackage.pem" 2>/dev/null
    openssl rand -hex 32 > "$PASSWORD_FILE"
    openssl pkcs12 -export -name "$CERT_NAME" \
        -inkey "$SIGNING_DIR/repackage.pem" -in "$SIGNING_DIR/certificate.pem" \
        -out "$SIGNING_DIR/identity.p12.new" -passout "file:$PASSWORD_FILE" \
        -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES
    mv "$SIGNING_DIR/identity.p12.new" "$SIGNING_DIR/identity.p12"
    rm "$SIGNING_DIR/repackage.pem"
fi

if [[ "$MODE" == "--prepare" ]]; then
    openssl x509 -in "$SIGNING_DIR/certificate.pem" -noout -subject -dates -fingerprint -sha1
    printf '已准备本机证书，尚未写入钥匙串或信任设置。\n'
    exit 0
fi

# Import only this identity, with key access limited to the system codesign tool.
# Do not use -A (allow any application), admin trust, or TLS trust.
if ! security find-identity -p codesigning "$KEYCHAIN_PATH" | grep -Fq "$IDENTITY"; then
    security import "$SIGNING_DIR/identity.p12" -k "$KEYCHAIN_PATH" -f pkcs12 \
        -P "$(cat "$PASSWORD_FILE")" -x -T /usr/bin/codesign
fi
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN_PATH" "$SIGNING_DIR/certificate.pem"
if ! security find-identity -v -p codesigning "$KEYCHAIN_PATH" | grep -Fq "$IDENTITY"; then
    printf '签名证书尚未可用；请完成 macOS 的钥匙串确认后重试。\n' >&2
    exit 1
fi
printf '%s\n' "$IDENTITY" > "$SIGNING_DIR/identity.sha1"
rm "$SIGNING_DIR/identity.p12" "$PASSWORD_FILE"
printf '固定签名身份已安装：%s\n' "$CERT_NAME"

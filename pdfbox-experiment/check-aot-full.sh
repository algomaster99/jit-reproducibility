#!/bin/bash
# Verify that tree.aot (produced by orchestrate-combine-4.sh) contains classes
# from ALL dependency groups, including the newly added bc and commons-logging.
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

PASS="\033[1;32mPASS\033[0m"
FAIL="\033[1;31mFAIL\033[0m"

cd "$(dirname "${BASH_SOURCE[0]}")"

JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
PDF="pdfbox/test.pdf"
AOT="tree.aot"
TMP="workload-tmp"
KEYSTORE="$TMP/check-bc.p12"
CERT="$TMP/check-bc.der"
STOREPASS="changeit"
ALIAS="check-bc"

[ -f "$AOT" ] || { echo "$AOT not found (run orchestrate-combine-4.sh first)" >&2; exit 1; }
[ -f "$JAR" ] || { echo "$JAR not found (build pdfbox first)" >&2; exit 1; }
mkdir -p "$TMP"

# Generate a throwaway self-signed RSA cert on first run. Cert-based PDF
# encryption uses PKCS#7/CMS enveloping, which pdfbox builds via BouncyCastle
# so this check actually loads BC classes at runtime. Password-based
# encryption does not.
if [ ! -f "$CERT" ]; then
    log "Generating throwaway cert for BC-exercising check"
    rm -f "$KEYSTORE"
    keytool -genkeypair -alias "$ALIAS" -keyalg RSA -keysize 2048 \
        -validity 365 -dname "CN=check, O=check, C=US" \
        -keystore "$KEYSTORE" -storetype PKCS12 \
        -storepass "$STOREPASS" -keypass "$STOREPASS" >/dev/null
    keytool -exportcert -alias "$ALIAS" -keystore "$KEYSTORE" \
        -storepass "$STOREPASS" -file "$CERT" >/dev/null
fi

run_java() {
    java -Xlog:class+load=info -XX:AOTCache="$AOT" -cp "$JAR" "$MAIN" \
        encrypt -certFile "$CERT" \
        --input "$PDF" --output "$TMP/check-locked.pdf" 2>&1
}

# Cache the output once so we don't re-run for each check
OUTPUT=$(run_java)

assert_cached() {
    local name="$1"
    local prefix="$2"

    log "Checking $name ($prefix)..."
    local cached
    cached=$(echo "$OUTPUT" | grep "$prefix" | grep "shared objects file" || true)

    if [ -z "$cached" ]; then
        echo -e "  [$FAIL] No $name classes found in AOT cache"
        return 1
    fi

    echo "$cached" | while IFS= read -r line; do
        class=$(echo "$line" | grep -oP '(?<=\] )[\w.$]+')
        echo -e "  [$PASS] $class"
    done
}

ERRORS=0

# Existing checks from check-aot-tree.sh
assert_cached "pdfbox-tools"    "org.apache.pdfbox.tools"    || ERRORS=$((ERRORS+1))
assert_cached "jbig2-imageio"   "org.apache.pdfbox.jbig2"    || ERRORS=$((ERRORS+1))

# BouncyCastle
assert_cached "bcprov (crypto)" "org.bouncycastle.crypto"    || ERRORS=$((ERRORS+1))
assert_cached "bcutil (asn1)"   "org.bouncycastle.asn1"      || ERRORS=$((ERRORS+1))
assert_cached "bcpkix (pkcs)"   "org.bouncycastle.pkcs"      || ERRORS=$((ERRORS+1))

# commons-logging
assert_cached "commons-logging" "org.apache.commons.logging" || ERRORS=$((ERRORS+1))

if [ "$ERRORS" -eq 0 ]; then
    log "All checks passed; tree.aot covers all expected dependency groups."
else
    echo -e "\033[1;31m[FAIL] One or more expected classes were not loaded from AOT.\033[0m" >&2
    echo -e "\033[1;31m$ERRORS check(s) failed.\033[0m" >&2
    exit 1
fi

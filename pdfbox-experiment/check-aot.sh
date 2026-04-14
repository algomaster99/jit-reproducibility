#!/bin/bash
set -e

# Reactor order:
# io -> fontbox -> xmpbox -> pdfbox -> preflight -> tools -> examples
# find . -type f -name "*.aot" -exec du -h {} +
# 30MB -> 29MB  -> 33 MB  -> 53MB   -> 53MB      -> 57MB  -> 69MB

cd "$(dirname "${BASH_SOURCE[0]}")"

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

PASS="\033[1;32mPASS\033[0m"
FAIL="\033[1;31mFAIL\033[0m"

JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
PDF="pdfbox/test.pdf"
TOOLS_PKG="org.apache.pdfbox.tools"

run_java() {
    local aot=$1
    java -Xlog:class+load=info -XX:AOTCache="$aot" -cp "$JAR" "$MAIN" export:text -i "$PDF" 2>&1
}

# Assert that NO tools classes are loaded from the AOT cache (tools not yet in chain)
assert_tools_not_cached() {
    local name=$1
    local aot=$2

    log "Checking $name (tools classes must NOT be from AOT cache)..."
    local cached
    cached=$(run_java "$aot" | grep "$TOOLS_PKG" | grep "shared objects file" || true)

    if [ -n "$cached" ]; then
        echo -e "  [$FAIL] Tools classes found in AOT cache (not expected):"
        echo "$cached" | while IFS= read -r line; do
            class=$(echo "$line" | grep -oP '(?<=\] )[\w.$]+')
            echo -e "    $class"
        done
        exit 1
    fi

    echo -e "  [$PASS] No tools classes in AOT cache (expected)."
}

# Assert that AT LEAST ONE tools class is loaded from the AOT cache (tools is in chain)
assert_tools_cached() {
    local name=$1
    local aot=$2

    log "Checking $name (tools classes must be from AOT cache)..."
    local cached
    cached=$(run_java "$aot" | grep "$TOOLS_PKG" | grep "shared objects file" || true)

    if [ -z "$cached" ]; then
        echo -e "  [$FAIL] No tools classes found in AOT cache"
        exit 1
    fi

    echo "$cached" | while IFS= read -r line; do
        class=$(echo "$line" | grep -oP '(?<=\] )[\w.$]+')
        echo -e "  [$PASS] $class"
    done
}

assert_tools_not_cached "io"        "io/cache.aot"
assert_tools_not_cached "fontbox"   "fontbox/cache.aot"
assert_tools_not_cached "xmpbox"    "xmpbox/cache.aot"
assert_tools_not_cached "pdfbox"    "pdfbox/cache.aot"
assert_tools_not_cached "preflight" "preflight/cache.aot"
assert_tools_cached     "tools"     "tools/cache.aot"
assert_tools_cached     "examples"  "examples/cache.aot"

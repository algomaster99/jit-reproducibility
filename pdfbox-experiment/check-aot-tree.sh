#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

PASS="\033[1;32mPASS\033[0m"
FAIL="\033[1;31mFAIL\033[0m"

JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
PDF="pdfbox/test.pdf"

if [ ! -f tree.aot ]; then
  echo "tree.aot not found (run orchestrate-combine-*.sh first)" >&2
  exit 1
fi

run_java() {
  local aot=$1
  java -Xlog:class+load=info -XX:AOTCache="$aot" -cp "$JAR" "$MAIN" export:text -i "$PDF" 2>&1
}

assert_prefix_cached() {
  local name=$1
  local prefix=$2
  local aot=$3

  log "Checking $name classes from AOT cache ($prefix)..."
  local cached
  cached=$(run_java "$aot" | grep "$prefix" | grep "shared objects file" || true)

  if [ -z "$cached" ]; then
    echo -e "  [$FAIL] No $name classes found in AOT cache"
    return 1
  fi

  echo "$cached" | while IFS= read -r line; do
    class=$(echo "$line" | grep -oP '(?<=\] )[\w.$]+')
    echo -e "  [$PASS] $class"
  done
}

assert_any_prefix_cached() {
  local name=$1
  local aot=$2
  shift 2

  local ok=1
  for prefix in "$@"; do
    if assert_prefix_cached "$name" "$prefix" "$aot"; then
      ok=0
      break
    fi
  done

  if [ "$ok" -ne 0 ]; then
    echo -e "  [$FAIL] No $name classes found in AOT cache for any known package prefix"
    exit 1
  fi
}

assert_any_prefix_cached "tools" "tree.aot" "org.apache.pdfbox.tools"
assert_any_prefix_cached "jbig2" "tree.aot" "org.apache.pdfbox.jbig2"

#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

SINGLE_AOT="single.aot"
SINGLE_CONF="single.aotconf"
FAT_JAR="benchmark/target/benchmark-fat.jar"
MAIN="dev.thyexp.Main"

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

if [[ -f "$SINGLE_AOT" ]]; then
  log "single.aot already exists, skipping."
  exit 0
fi

rm -f "$SINGLE_CONF" "$SINGLE_AOT"

# Step 1 — record: single.aot trained on html-render only.
# This loads the HTML parser path (attoparser HTML mode), OGNL expression evaluator,
# and the HTML escape symbol tables (unbescape). xml-render, text-render, and
# fragment-render all load different class subtrees, widening the gap vs tree.aot.
log "Step 1/2 — recording AOT configuration (training op: html-render)"
java -XX:AOTMode=record -XX:AOTConfiguration="$SINGLE_CONF" \
  -XX:+AOTClassLinking \
  -jar "$FAT_JAR" html-render

[[ -f "$SINGLE_CONF" ]] || fail "AOT configuration file was not produced"

# Step 2 — create: compile the configuration into a usable cache file.
# AOTMode=create does not run main; -cp is sufficient.
log "Step 2/2 — creating single.aot from configuration"
java -XX:AOTMode=create \
  -XX:AOTConfiguration="$SINGLE_CONF" \
  -XX:AOTCache="$SINGLE_AOT" \
  -XX:+AOTClassLinking \
  -cp "$FAT_JAR"

[[ -f "$SINGLE_AOT" ]] || fail "single.aot was not created"
log "single.aot created ($(du -sh "$SINGLE_AOT" | cut -f1))"

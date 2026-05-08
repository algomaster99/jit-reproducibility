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
MAIN="dev.batikexp.Main"
WORK_DIR="workload-tmp"

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

if [[ -f "$SINGLE_AOT" ]]; then
  log "single.aot already exists, skipping."
  exit 0
fi

JAVA_ARGS=(
  -Djava.awt.headless=true
  -cp "$FAT_JAR"
)

mkdir -p "$WORK_DIR"

log "Preparing workload inputs"
java "${JAVA_ARGS[@]}" "$MAIN" prepare "$WORK_DIR"

rm -f "$SINGLE_CONF" "$SINGLE_AOT"

# Step 1 — record: single.aot is trained on svg-to-svg only.
# This is the lightest workload (~65ms), so it captures very few compiled
# methods. All heavier ops (svg-to-png, svg-to-jpeg, svg-parse, svg-generate)
# miss the cache, making the gap between single.aot and tree.aot clearly visible.
log "Step 1/2 — recording AOT configuration (training op: svg-to-svg)"
java -XX:AOTMode=record -XX:AOTConfiguration="$SINGLE_CONF" \
  -XX:+AOTClassLinking \
  "${JAVA_ARGS[@]}" "$MAIN" svg-to-svg "$WORK_DIR"

[[ -f "$SINGLE_CONF" ]] || fail "AOT configuration file was not produced"

# Step 2 — create: compile the configuration into a usable cache file
log "Step 2/2 — creating single.aot from configuration"
java -XX:AOTMode=create \
  -XX:AOTConfiguration="$SINGLE_CONF" \
  -XX:AOTCache="$SINGLE_AOT" \
  -XX:+AOTClassLinking \
  "${JAVA_ARGS[@]}"

[[ -f "$SINGLE_AOT" ]] || fail "single.aot was not created"
log "single.aot created ($(du -sh "$SINGLE_AOT" | cut -f1))"

#!/bin/bash
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

log "Java version:"
java -version

SINGLE_AOT="single.aot"
SINGLE_CONF="single.aotconf"
JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
CP="$JAR:\
commons-compress/target/classes:\
commons-compress-deps/commons-lang/target/classes:\
commons-compress-deps/commons-codec/target/classes:\
commons-compress-deps/apache-commons-io/target/classes"
MAIN="dev.compressexp.Main"
WORK_DIR="workload-tmp"

if [ -f "$SINGLE_AOT" ]; then
  log "single.aot already exists, skipping creation."
  exit 0
fi

log "Creating single.aot (two-step: record + create)"
rm -f "$SINGLE_AOT"
rm -f "$SINGLE_CONF"

[[ -f "$JAR" ]] || { echo "Missing $JAR (build benchmark first)" >&2; exit 1; }

mkdir -p "$WORK_DIR"

java -Xlog:aot -XX:AOTMode=record -XX:AOTConfiguration="$SINGLE_CONF" \
  --add-modules java.instrument \
  --add-opens java.base/java.io=ALL-UNNAMED \
  -cp "$CP" "$MAIN" prepare "$WORK_DIR"
test -f "$SINGLE_CONF"

java -Xlog:aot -XX:AOTMode=create -XX:AOTConfiguration="$SINGLE_CONF" \
  -XX:AOTCache="$SINGLE_AOT" \
  -cp "$CP"

test -f "$SINGLE_AOT"
log "single.aot created."

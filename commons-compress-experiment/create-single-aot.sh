#!/bin/bash
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

SINGLE_AOT="single.aot"
SINGLE_CONF="single.aotconf"
BENCH_JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
DEPS_DIR="single-aot-deps"
MAIN="dev.compressexp.Main"
WORK_DIR="workload-tmp"

MAVEN_CENTRAL="https://repo1.maven.org/maven2"

# Order must match SINGLE_CP in workload-timed.sh exactly — the AOT cache
# fingerprint includes the full classpath string.
declare -a DEP_JARS=(
  "commons-compress-1.28.0.jar"
  "commons-lang3-3.20.0.jar"
  "commons-codec-1.21.0.jar"
  "commons-io-2.20.0.jar"
)
declare -a DEP_URLS=(
  "$MAVEN_CENTRAL/org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0.jar"
  "$MAVEN_CENTRAL/org/apache/commons/commons-lang3/3.20.0/commons-lang3-3.20.0.jar"
  "$MAVEN_CENTRAL/commons-codec/commons-codec/1.21.0/commons-codec-1.21.0.jar"
  "$MAVEN_CENTRAL/commons-io/commons-io/2.20.0/commons-io-2.20.0.jar"
)

if [ -f "$SINGLE_AOT" ]; then
  log "single.aot already exists, skipping creation."
  exit 0
fi

[[ -f "$BENCH_JAR" ]] || { echo "Missing $BENCH_JAR (build benchmark first)" >&2; exit 1; }

log "Downloading dependency JARs from Maven Central"
mkdir -p "$DEPS_DIR"
for i in "${!DEP_JARS[@]}"; do
  dest="$DEPS_DIR/${DEP_JARS[$i]}"
  if [ ! -f "$dest" ]; then
    log "  Downloading ${DEP_JARS[$i]}"
    curl -fsSL "${DEP_URLS[$i]}" -o "$dest"
  else
    log "  ${DEP_JARS[$i]} already present"
  fi
done

CP="$BENCH_JAR:\
$DEPS_DIR/commons-compress-1.28.0.jar:\
$DEPS_DIR/commons-lang3-3.20.0.jar:\
$DEPS_DIR/commons-codec-1.21.0.jar:\
$DEPS_DIR/commons-io-2.20.0.jar"

log "Creating single.aot (two-step: record + create)"
rm -f "$SINGLE_AOT"
rm -f "$SINGLE_CONF"

mkdir -p "$WORK_DIR"

java -XX:AOTMode=record -XX:AOTConfiguration="$SINGLE_CONF" \
  --add-modules java.instrument \
  --add-opens java.base/java.io=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens java.base/java.time=ALL-UNNAMED \
  --add-opens java.base/java.time.chrono=ALL-UNNAMED \
  --add-opens java.base/java.util=ALL-UNNAMED \
  -cp "$CP" "$MAIN" prepare "$WORK_DIR"
test -f "$SINGLE_CONF"

java -XX:AOTMode=create -XX:AOTConfiguration="$SINGLE_CONF" \
  -XX:AOTCache="$SINGLE_AOT" \
  --add-modules java.instrument \
  --add-opens java.base/java.io=ALL-UNNAMED \
  --add-opens java.base/java.lang=ALL-UNNAMED \
  --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens java.base/java.time=ALL-UNNAMED \
  --add-opens java.base/java.time.chrono=ALL-UNNAMED \
  --add-opens java.base/java.util=ALL-UNNAMED \
  -cp "$CP"

test -f "$SINGLE_AOT"
log "single.aot created."

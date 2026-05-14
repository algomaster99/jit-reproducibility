#!/bin/bash
# Creates one single-{op}.aot per workload for the cross-workload experiment.
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

BENCH_JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
DEPS_DIR="single-aot-deps"
MAIN="dev.validatorexp.Main"

MAVEN_CENTRAL="https://repo1.maven.org/maven2"

declare -a DEP_JARS=(
  "commons-validator-1.10.1.jar"
  "commons-beanutils-1.11.0.jar"
  "commons-digester-2.1.jar"
  "commons-logging-1.3.5.jar"
  "commons-collections-3.2.2.jar"
)
declare -a DEP_URLS=(
  "$MAVEN_CENTRAL/commons-validator/commons-validator/1.10.1/commons-validator-1.10.1.jar"
  "$MAVEN_CENTRAL/commons-beanutils/commons-beanutils/1.11.0/commons-beanutils-1.11.0.jar"
  "$MAVEN_CENTRAL/commons-digester/commons-digester/2.1/commons-digester-2.1.jar"
  "$MAVEN_CENTRAL/commons-logging/commons-logging/1.3.5/commons-logging-1.3.5.jar"
  "$MAVEN_CENTRAL/commons-collections/commons-collections/3.2.2/commons-collections-3.2.2.jar"
)

OPS=("validate-email" "validate-url" "validate-ip" "validate-credit-card")

[[ -f "$BENCH_JAR" ]] || { echo "Missing $BENCH_JAR (build benchmark first: cd benchmark && mvn package -DskipTests)" >&2; exit 1; }

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
$DEPS_DIR/commons-validator-1.10.1.jar:\
$DEPS_DIR/commons-beanutils-1.11.0.jar:\
$DEPS_DIR/commons-digester-2.1.jar:\
$DEPS_DIR/commons-logging-1.3.5.jar:\
$DEPS_DIR/commons-collections-3.2.2.jar"

for op in "${OPS[@]}"; do
  aot="single-${op}.aot"
  conf="single-${op}.aotconf"
  if [ -f "$aot" ]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"
  java -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.time=ALL-UNNAMED \
    --add-opens java.base/java.time.chrono=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    -cp "$CP" "$MAIN" "$op"
  test -f "$conf"
  java -XX:AOTMode=create -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.time=ALL-UNNAMED \
    --add-opens java.base/java.time.chrono=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    -cp "$CP"
  test -f "$aot"
  log "$aot created."
done

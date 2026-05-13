#!/bin/bash
# Creates one single-{op}.aot per workload for the cross-workload experiment.
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "Java version:"
java -version

FAT_JAR="benchmark/target/benchmark-fat.jar"
OPS=(html-render text-render xml-render fragment-render)

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"

for op in "${OPS[@]}"; do
  aot="single-${op}.aot"
  conf="single-${op}.aotconf"
  if [[ -f "$aot" ]]; then
    log "$aot already exists, skipping."
    continue
  fi
  log "Creating $aot (training op: $op)"
  rm -f "$conf"
  java -XX:AOTMode=record -XX:AOTConfiguration="$conf" \
    -XX:+AOTClassLinking \
    -jar "$FAT_JAR" "$op"
  [[ -f "$conf" ]] || fail "AOT configuration file was not produced for op=$op"
  java -XX:AOTMode=create \
    -XX:AOTConfiguration="$conf" \
    -XX:AOTCache="$aot" \
    -XX:+AOTClassLinking \
    -cp "$FAT_JAR"
  [[ -f "$aot" ]] || fail "$aot was not created"
  log "$aot created ($(du -sh "$aot" | cut -f1))"
done

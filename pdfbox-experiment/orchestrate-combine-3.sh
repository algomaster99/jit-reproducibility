#!/bin/bash
set -euo pipefail

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

log "Java version:"
java -version

SINGLE_AOT="single.aot"
SINGLE_JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
TEST_PDF="pdfbox/test.pdf"

PICOCLI_VERSION="4.7.7"
PICOCLI_JAR="picocli-${PICOCLI_VERSION}.jar"
PICOCLI_URL="https://repo1.maven.org/maven2/info/picocli/picocli/${PICOCLI_VERSION}/picocli-${PICOCLI_VERSION}.jar"
PICOCLI_WORKLOAD_JAR="../picocli-experiment/workload/target/workload-1.0-SNAPSHOT.jar"
PICOCLI_AOT="picocli.aot"

test -f "$SINGLE_AOT" || { echo "Missing $SINGLE_AOT (run create-single-aot.sh first)" >&2; exit 1; }
log "single.aot found."

if [ ! -f "$PICOCLI_JAR" ]; then
  log "Downloading picocli ${PICOCLI_VERSION}..."
  curl -sL "$PICOCLI_URL" -o "$PICOCLI_JAR"
fi

log "Building picocli workload (pdfbox profile)..."
mvn package -q -Ppdfbox -f ../picocli-experiment/workload/pom.xml
test -f "$PICOCLI_WORKLOAD_JAR"

log "Recording picocli AOT cache..."
rm -f "$PICOCLI_AOT"
java -XX:AOTCacheOutput="$PICOCLI_AOT" -jar "$PICOCLI_WORKLOAD_JAR" --name Alice --count 500
test -f "$PICOCLI_AOT"
log "picocli.aot created."

log "Creating tree.aot (base=pdfbox/pdfbox/cache.aot, inputs=jbig2 + commons-io + picocli + pdfbox modules)"
rm -f tree.aot

java -Xlog:aot \
  -XX:AOTMode=merge \
  -XX:AOTCache=pdfbox/pdfbox/cache.aot \
  -XX:AOTMergeInputs="pdfbox-deps/pdfbox-jbig2/cache.aot:pdfbox-deps/apache-commons-io/cache.aot:$PICOCLI_AOT:pdfbox/io/cache.aot:pdfbox/fontbox/cache.aot:pdfbox/xmpbox/cache.aot:pdfbox/pdfbox/cache.aot:pdfbox/preflight/cache.aot:pdfbox/tools/cache.aot:pdfbox/examples/cache.aot" \
  -XX:AOTCacheOutput=tree.aot \
  -cp "pdfbox-deps/pdfbox-jbig2/target/classes/:pdfbox-deps/apache-commons-io/target/classes/:$PICOCLI_JAR:pdfbox/app/target/pdfbox-app-3.0.7.jar" \
  -version

test -f tree.aot
log "tree.aot created."

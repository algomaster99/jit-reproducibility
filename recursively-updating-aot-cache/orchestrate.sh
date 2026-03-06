#!/bin/bash
set -e

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

log "Java version:"
java -version

log "Deleting exisiting aot files"
find . -name "*.aot" -type f -delete

log "Building AOT cache for sub..."
java -XX:AOTCacheOutput=sub/sub.aot -jar sub/target/sub-1.0-SNAPSHOT.jar
log "sub.aot created."

log "Building AOT cache for add (using sub.aot)..."
java -Xlog:aot+merge=info -XX:AOTMode=merge -XX:AOTCache=sub/sub.aot -XX:AOTCacheOutput=add/add.aot -jar add/target/add-1.0-SNAPSHOT.jar
log "add.aot created."

log "Building AOT cache for mul (using add.aot)..."
java -Xlog:aot+merge=info -XX:AOTMode=merge -XX:AOTCache=add/add.aot -XX:AOTCacheOutput=mul/mul.aot -jar mul/target/mul-1.0-SNAPSHOT.jar
log "mul.aot created."

log "Running math (using mul.aot)..."
java -Xlog:aot+merge=info -XX:AOTMode=merge -XX:AOTCache=mul/mul.aot -XX:AOTCacheOutput=math/math.aot -jar math/target/math-1.0-SNAPSHOT.jar
java -XX:AOTCache=math/math.aot -jar math/target/math-1.0-SNAPSHOT.jar


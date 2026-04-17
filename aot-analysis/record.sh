#!/bin/bash
# Dump class lists from .aot files into sorted .classes text files (one JVM class name per line).
# Usage: record.sh [-o <output-dir>] <file.aot> [file2.aot ...]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

AOTP_JAR="${AOTP_JAR:-$HOME/Desktop/chains/aotp/aotp/target/aotp-0.0.1-SNAPSHOT.jar}"

if [[ ! -f "$AOTP_JAR" ]]; then
    echo "aotp jar not found: $AOTP_JAR" >&2
    echo "Set AOTP_JAR env var to the correct path." >&2
    exit 1
fi

# Parse optional -o <output-dir>
OUT_DIR="${PWD}"
if [[ "${1:-}" == "-o" ]]; then
    OUT_DIR="$(realpath "$2")"
    shift 2
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [-o <output-dir>] <file.aot> [file2.aot ...]" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

for aot in "$@"; do
    aot="$(realpath "$aot")"
    if [[ ! -f "$aot" ]]; then
        echo "Missing .aot file: $aot" >&2
        exit 1
    fi
    stem="$(basename "${aot%.aot}")"
    # When every sub-cache is named cache.aot, use the parent directory name instead
    if [[ "$stem" == "cache" ]]; then
        stem="$(basename "$(dirname "$aot")")"
    fi
    out="${OUT_DIR}/${stem}.classes"
    java -jar "$AOTP_JAR" "$aot" --list-classes | sort > "$out"
    count=$(wc -l < "$out")
    log "$(basename "$aot") → $out  ($count classes)"
done

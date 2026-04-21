#!/bin/bash
# Extract source class lists from target/classes directories or JAR files.
# Multi-release JARs are handled: META-INF/versions/<N>/ entries are stripped
# and deduplicated before writing.
#
# Usage: source.sh [-o <output-dir>] <label>:<path> [<label>:<path> ...]
#
# <path> may be a target/classes directory or a .jar file.
# Output: <output-dir>/<label>.classes  (one JVM class name per line, sorted)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

OUT_DIR="${PWD}"
if [[ "${1:-}" == "-o" ]]; then
    OUT_DIR="$(realpath "$2")"
    shift 2
fi

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 [-o <output-dir>] <label>:<path> [<label>:<path> ...]" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"

for entry in "$@"; do
    label="${entry%%:*}"
    path="$(realpath "${entry#*:}")"
    out="${OUT_DIR}/${label}.classes"

    if [[ -d "$path" ]]; then
        find "$path" -name '*.class' ! -name 'module-info.class' \
            | sed "s|^${path}/||; s|\.class$||" \
            | sort -u > "$out"
    elif [[ -f "$path" && "$path" == *.jar ]]; then
        jar tf "$path" \
            | grep '\.class$' | grep -v 'module-info\.class' \
            | sed 's|^META-INF/versions/[0-9]*/||; s/\.class$//' \
            | sort -u > "$out"
    else
        echo "ERROR: not a directory or .jar: $path" >&2
        exit 1
    fi

    count=$(wc -l < "$out")
    log "${label} → $out  ($count classes)"
done

#!/bin/bash
# Classify classes in a .classes file by type and print a breakdown table.
# With -o <dir>: also writes <stem>-jdk.classes, <stem>-hidden.classes,
#                <stem>-app.classes into <dir>.
# Note: $$Lambda classes are treated as hidden (they are JVM hidden classes).
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

OUT_DIR=""
if [[ "${1:-}" == "-o" ]]; then
    OUT_DIR="$(realpath "$2")"
    shift 2
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [-o <output-dir>] <file.classes>" >&2
    exit 1
fi

f="$(realpath "$1")"
stem="$(basename "${f%.classes}")"

if [[ -n "$OUT_DIR" ]]; then
    mkdir -p "$OUT_DIR"
    > "$OUT_DIR/${stem}-jdk.classes"
    > "$OUT_DIR/${stem}-hidden.classes"
    > "$OUT_DIR/${stem}-app.classes"
fi

awk -v out_dir="$OUT_DIR" -v stem="$stem" '
BEGIN { jdk=0; hidden=0; app=0 }
{
    c = $0
    base = c
    if (base ~ /^\[+L/) { sub(/^\[+L/, "", base); sub(/;$/, "", base) }
    if (c ~ /^\[+[BCDFIJSZ]$/ ||
        base ~ /^java\// || base ~ /^javax\// || base ~ /^sun\// || base ~ /^jdk\// ||
        base ~ /^com\/sun\// || base ~ /^org\/xml\// ||
        base ~ /^org\/w3c\// || base ~ /^org\/ietf\//) {
        jdk++
        if (out_dir != "") print c >> (out_dir "/" stem "-jdk.classes")
    } else if (c ~ /\/0x/ || c ~ /\+0x/ || c ~ /\$\$Lambda/) {
        hidden++
        if (out_dir != "") print c >> (out_dir "/" stem "-hidden.classes")
    } else {
        app++
        if (out_dir != "") print c >> (out_dir "/" stem "-app.classes")
    }
}
END {
    total = jdk + hidden + app
    printf "%-20s %6s   %s\n", "Category", "Count", "Pct"
    printf "%-20s %6d   %d%%\n", "JDK",         jdk,    (total>0 ? int(jdk*100/total+0.5)    : 0)
    printf "%-20s %6d   %d%%\n", "Hidden",       hidden, (total>0 ? int(hidden*100/total+0.5) : 0)
    printf "%-20s %6d   %d%%\n", "App/Library",  app,    (total>0 ? int(app*100/total+0.5)    : 0)
    printf "%-20s %6d\n",        "Total",         total
}
' "$f"

#!/bin/bash
# Compute per-dependency contribution to tree.aot app classes.
#
# For each dependency, computes a three-stage funnel:
#   source          — all classes compiled in the JAR / target/classes
#   source ∩ cache  — how many made it into the module's own cache.aot
#   source ∩ tree   — how many appear in tree-app.classes (final tree, app only)
#
# Classes missing from the last stage are candidates for investigation
# (e.g. dead code, pruned by the AOT merge, or only loaded lazily at runtime).
#
# Usage:
#   funnel.sh <tree-app.classes> <label>:<source.classes>:<cache.classes> [...]
#
# Example:
#   funnel.sh aot-analysis/commons-compress/first-classification/tree-app.classes \
#     "commons-compress:aot-analysis/commons-compress/source/commons-compress.classes:aot-analysis/commons-compress/per-cache/commons-compress.classes" \
#     "commons-io:aot-analysis/commons-compress/source/commons-io.classes:aot-analysis/commons-compress/per-cache/apache-commons-io.classes"
set -euo pipefail

OUT_DIR=""
if [[ "${1:-}" == "-o" ]]; then
    OUT_DIR="$(realpath "$2")"
    shift 2
fi

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 [-o <output-dir>] <tree-app.classes> <label>:<source>:<cache> [...]" >&2
    exit 1
fi

TREE_APP="$(realpath "$1")"; shift
[[ -f "$TREE_APP" ]] || { echo "ERROR: tree-app.classes not found: $TREE_APP" >&2; exit 1; }

intersect2() { comm -12 <(sort "$1") <(sort "$2"); }
pct()        { (( $2 > 0 )) && printf "%d" "$(( $1 * 100 / $2 ))" || printf "0"; }

printf "%-22s  %7s  %10s  %5s  %9s  %5s\n" \
    "Module" "Source" "∩cache" "%" "∩tree" "%"
printf "%-22s  %7s  %10s  %5s  %9s  %5s\n" \
    "----------------------" "-------" "----------" "-----" "---------" "-----"

total_src=0; total_cache=0; total_tree=0

for entry in "$@"; do
    IFS=':' read -r label src_file cache_file <<< "$entry"
    src_file="$(realpath "$src_file")"
    cache_file="$(realpath "$cache_file")"

    [[ -f "$src_file"   ]] || { echo "ERROR: source not found: $src_file" >&2; exit 1; }
    [[ -f "$cache_file" ]] || { echo "ERROR: cache not found: $cache_file" >&2; exit 1; }

    if [[ -n "$OUT_DIR" ]]; then
        mkdir -p "$OUT_DIR/$label"
        intersect2 "$src_file" "$cache_file" > "$OUT_DIR/$label/cache.classes"
        intersect2 "$src_file" "$TREE_APP"   > "$OUT_DIR/$label/tree.classes"
        in_cache=$(wc -l < "$OUT_DIR/$label/cache.classes")
        in_tree=$(wc -l  < "$OUT_DIR/$label/tree.classes")
    else
        in_cache=$(intersect2 "$src_file" "$cache_file" | wc -l)
        in_tree=$(intersect2  "$src_file" "$TREE_APP"   | wc -l)
    fi

    src_count=$(wc -l < "$src_file")

    printf "%-22s  %7d  %10d  %4d%%  %9d  %4d%%\n" \
        "$label" "$src_count" \
        "$in_cache" "$(pct "$in_cache" "$src_count")" \
        "$in_tree"  "$(pct "$in_tree"  "$src_count")"

    (( total_src   += src_count ))
    (( total_cache += in_cache  ))
    (( total_tree  += in_tree   ))
done

printf "%-22s  %7s  %10s  %5s  %9s  %5s\n" \
    "----------------------" "-------" "----------" "-----" "---------" "-----"
printf "%-22s  %7d  %10d  %4d%%  %9d  %4d%%\n" \
    "TOTAL" "$total_src" \
    "$total_cache" "$(pct "$total_cache" "$total_src")" \
    "$total_tree"  "$(pct "$total_tree"  "$total_src")"

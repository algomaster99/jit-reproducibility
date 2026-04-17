#!/bin/bash
# Run the full pdfbox workload against tree.aot with -Xlog:class+load=info and
# record which classes are actually served from the AOT cache at runtime.
#
# Output files (written to ../aot-analysis/pdfbox/classes/):
#   runtime-tree.classes     — classes served from AOT cache (union across all ops)
#   runtime-tree-fs.classes  — classes loaded from jars/dirs instead
#
# Run compare.sh afterwards to diff against the static tree.classes list.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

JAR="pdfbox/app/target/pdfbox-app-3.0.7.jar"
MAIN="org.apache.pdfbox.tools.PDFBox"
PDF="pdfbox/test.pdf"
AOT="tree.aot"
TMP="workload-tmp"
OUT_DIR="../aot-analysis/pdfbox/classes"
COMBINED_LOG="$TMP/classload-all-tree.log"

[ -f "$AOT" ] || fail "tree.aot not found — run orchestrate-combine-4.sh first"
[ -f "$JAR" ] || fail "$JAR not found — build pdfbox first"
[ -f "$PDF" ] || fail "test PDF not found: $PDF"

mkdir -p "$TMP" "$OUT_DIR"
: > "$COMBINED_LOG"   # truncate / create

java_cmd() {
    java -Xlog:class+load=info -XX:AOTCache="$AOT" -cp "$JAR" "$MAIN" "$@"
}

run_op() {
    local label="$1"; shift
    log "  $label"
    # Capture both stdout and stderr — -Xlog destination varies by JDK version
    java_cmd "$@" >> "$COMBINED_LOG" 2>&1 || true
}

log "Running workload with tree.aot + -Xlog:class+load=info"

# Operations in dependency order
run_op "encrypt" \
    encrypt -O 123 -U 123 --input "$PDF" --output "$TMP/rt-locked.pdf"

run_op "decrypt" \
    decrypt -password 123 --input "$TMP/rt-locked.pdf" --output "$TMP/rt-unlocked.pdf"

run_op "export:text" \
    export:text --input "$PDF" --output "$TMP/rt-text.txt"

run_op "export:images" \
    export:images --input "$PDF"

run_op "render" \
    render --input "$PDF"

run_op "fromtext" \
    fromtext --input "$TMP/rt-text.txt" --output "$TMP/rt-from-text.pdf" \
             -standardFont Times-Roman

run_op "split" \
    split --input "$PDF" -split 3 -outputPrefix "$TMP/rt-split"

run_op "merge" \
    merge --input "$TMP/rt-split-1.pdf" --output "$TMP/rt-merged.pdf"

run_op "decode" \
    decode "$PDF" "$TMP/rt-decoded.pdf"

run_op "overlay" \
    overlay -default "$PDF" --input "$PDF" --output "$TMP/rt-overlay.pdf"

log "Extracting class names from combined log"

AOT_CLASSES="$OUT_DIR/runtime-tree.classes"
FS_CLASSES="$OUT_DIR/runtime-tree-fs.classes"

AOT_RAW="$TMP/rt-aot-raw.txt"
FS_RAW="$TMP/rt-fs-raw.txt"
touch "$AOT_RAW" "$FS_RAW"   # ensure files exist even if awk finds no matches

awk '
/\[class,load\]/ {
    match($0, /\[class,load\] ([^ ]+)/, arr)
    if (!arr[1]) next
    cls = arr[1]
    gsub(/\./, "/", cls)
    if (/source: shared objects file/) {
        print cls > "'"$AOT_RAW"'"
    } else {
        print cls > "'"$FS_RAW"'"
    }
}
' "$COMBINED_LOG"

sort -u "$AOT_RAW" > "$AOT_CLASSES"
sort -u "$FS_RAW"  > "$FS_CLASSES"

aot_count=$(wc -l < "$AOT_CLASSES")
fs_count=$(wc -l  < "$FS_CLASSES")

log "Done"
echo "  AOT-served (shared objects file): $aot_count  → $AOT_CLASSES"
echo "  Loaded from jars/dirs:            $fs_count  → $FS_CLASSES"
echo
echo "Compare against static tree.classes:"
echo "  ../aot-analysis/compare.sh $OUT_DIR/tree.classes $AOT_CLASSES"

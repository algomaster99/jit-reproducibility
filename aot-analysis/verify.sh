#!/bin/bash
# Cross-check aotp static class list against -Xlog:class+load=info runtime log.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <aot.classes> <logfile|->" >&2
    exit 1
fi

aot_classes="$(realpath "$1")"
logfile="$2"

# Extract class names loaded from AOT cache and from filesystem into temp files
tmp_aot=$(mktemp)
tmp_fs=$(mktemp)
trap 'rm -f "$tmp_aot" "$tmp_fs"' EXIT

if [[ "$logfile" == "-" ]]; then
    input_cmd="cat"
else
    logfile="$(realpath "$logfile")"
    input_cmd="cat $logfile"
fi

$input_cmd | awk '
/\[class,load\]/ {
    # extract class name (second field after the tag)
    match($0, /\[class,load\] ([^ ]+)/, arr)
    if (!arr[1]) next
    cls = arr[1]
    gsub(/\./, "/", cls)
    if (/source: shared objects file/) {
        print cls > "/dev/stdout"
    } else {
        print cls > "/dev/stderr"
    }
}
' > "$tmp_aot" 2> "$tmp_fs"

sort -o "$tmp_aot" "$tmp_aot"
sort -o "$tmp_fs"  "$tmp_fs"

from_aot=$(wc -l < "$tmp_aot")
from_fs=$(wc -l < "$tmp_fs")
in_aotp_not_loaded=$(comm -23 "$aot_classes" "$tmp_aot" | wc -l)
loaded_not_in_aotp=$(comm -13 "$aot_classes" "$tmp_aot" | wc -l)

printf "%-40s %d\n" "From AOT cache (runtime):"        "$from_aot"
printf "%-40s %d\n" "From filesystem (runtime):"       "$from_fs"
printf "%-40s %d\n" "In aotp list but not AOT-loaded:" "$in_aotp_not_loaded"
printf "%-40s %d\n" "Loaded from AOT but not in aotp:" "$loaded_not_in_aotp"

#!/bin/bash
# Print a summary table comparing two .classes files.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <a.classes> <b.classes>" >&2
    exit 1
fi

a="$(realpath "$1")"
b="$(realpath "$2")"

# Normalize hidden class names: classListWriter emits the internal Symbol form
# (e.g. LambdaForm$DMH+0x...) while -Xlog:class+load uses external_name() which
# converts the last '+' to '/' (e.g. LambdaForm$DMH/0x...). Normalize both sides
# to the external form so hidden classes compare equal across the two sources.
norm() { sed 's/+0x/\/0x/g' "$1" | sort; }

count_a=$(wc -l < "$a")
count_b=$(wc -l < "$b")
only_a=$(comm -23 <(norm "$a") <(norm "$b") | wc -l)
only_b=$(comm -13 <(norm "$a") <(norm "$b") | wc -l)
intersection=$(comm -12 <(norm "$a") <(norm "$b") | wc -l)
union=$(( count_a + count_b - intersection ))

printf "%-24s %s\n"   "A:"           "$a"
printf "%-24s %s\n\n" "B:"           "$b"
printf "%-24s %d\n"   "Classes in A:"     "$count_a"
printf "%-24s %d\n"   "Classes in B:"     "$count_b"
printf "%-24s %d\n"   "Union:"            "$union"
printf "%-24s %d\n"   "Intersection:"     "$intersection"
printf "%-24s %d\n"   "Only in A:"        "$only_a"
printf "%-24s %d\n"   "Only in B:"        "$only_b"

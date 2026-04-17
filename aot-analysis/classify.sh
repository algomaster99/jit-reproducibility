#!/bin/bash
# Classify classes in a .classes file by type and print a breakdown table.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <file.classes>" >&2
    exit 1
fi

f="$(realpath "$1")"

awk '
BEGIN { jdk=0; lambda=0; hidden=0; app=0 }
{
    c = $0
    # strip array prefix [L...;  before prefix-matching
    base = c
    if (base ~ /^\[+L/) { sub(/^\[+L/, "", base); sub(/;$/, "", base) }
    if (base ~ /^java\// || base ~ /^javax\// || base ~ /^sun\// || base ~ /^jdk\// ||
        base ~ /^com\/sun\// || base ~ /^org\/xml\// ||
        base ~ /^org\/w3c\// || base ~ /^org\/ietf\//) {
        jdk++
    } else if (c ~ /\/0x/ || c ~ /\+0x/) {
        hidden++
    } else if (c ~ /\$\$Lambda/) {
        lambda++
    } else {
        app++
    }
}
END {
    total = jdk + lambda + hidden + app
    printf "%-20s %6s   %s\n", "Category", "Count", "Pct"
    printf "%-20s %6d   %d%%\n", "JDK",           jdk,    (total>0 ? int(jdk*100/total+0.5)    : 0)
    printf "%-20s %6d   %d%%\n", "Lambda",         lambda, (total>0 ? int(lambda*100/total+0.5) : 0)
    printf "%-20s %6d   %d%%\n", "Hidden (other)", hidden, (total>0 ? int(hidden*100/total+0.5) : 0)
    printf "%-20s %6d   %d%%\n", "App/Library",    app,    (total>0 ? int(app*100/total+0.5)    : 0)
    printf "%-20s %6d\n",        "Total",           total
}
' "$f"

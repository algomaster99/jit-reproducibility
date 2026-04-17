#!/bin/bash
# Output sorted, deduplicated union of A and B.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <a.classes> <b.classes>" >&2
    exit 1
fi

a="$(realpath "$1")"
b="$(realpath "$2")"

sort -mu "$a" "$b"

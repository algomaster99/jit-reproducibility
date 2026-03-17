#!/bin/bash
set -e

log() { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }

PASS="\033[1;32mPASS\033[0m"
FAIL="\033[1;31mFAIL\033[0m"

ALL_CLASSES=(
    "com.example.Subtractor"
    "com.example.Adder"
    "com.example.Multiplier"
    "com.example.MathApp"
)

check_module() {
    local name=$1
    local aot=$2
    local jar=$3
    shift 3
    local expected_from_aot=("$@")

    log "Checking $name..."
    local output class line
    output=$(java -Xlog:class+load=info -XX:AOTCache="$aot" -jar "$jar" 2>&1 | grep -E "\] com\.example\.[A-Za-z0-9_$.]+" || true)

    declare -A from_aot=()
    while IFS= read -r line; do
        class=$(echo "$line" | grep -oP '(?<=\] )[\w.$]+')
        [[ -z "$class" ]] && continue
        if [[ "$line" == *"shared objects file"* ]]; then
            from_aot["$class"]=true
        else
            from_aot["$class"]=false
        fi
    done <<< "$output"

    declare -A expected_map=()
    local c
    for c in "${expected_from_aot[@]}"; do
        expected_map["$c"]=true
    done

    local all_pass=true
    for c in "${ALL_CLASSES[@]}"; do
        if [[ -z "${from_aot[$c]+x}" ]]; then
            echo -e "  [$FAIL] $c (class not loaded)"
            all_pass=false
            continue
        fi

        if [[ "${expected_map[$c]+x}" ]]; then
            if [[ "${from_aot[$c]}" == "true" ]]; then
                echo -e "  [$PASS] $c (from AOT)"
            else
                echo -e "  [$FAIL] $c (expected from AOT, but wasn't)"
                all_pass=false
            fi
        else
            if [[ "${from_aot[$c]}" == "true" ]]; then
                echo -e "  [$FAIL] $c (unexpectedly from AOT)"
                all_pass=false
            else
                echo -e "  [$PASS] $c (not from AOT)"
            fi
        fi
    done

    $all_pass && echo -e "  Expected classes loaded from AOT cache." || true
}

check_module "sub"  "sub/sub.aot"   "math/target/math-1.0-SNAPSHOT.jar" \
    "com.example.Subtractor"
check_module "add"  "add/add.aot"   "math/target/math-1.0-SNAPSHOT.jar" \
    "com.example.Subtractor" "com.example.Adder"
check_module "mul"  "mul/mul.aot"   "math/target/math-1.0-SNAPSHOT.jar" \
    "com.example.Subtractor" "com.example.Adder" "com.example.Multiplier"
check_module "math" "math/math.aot" "math/target/math-1.0-SNAPSHOT.jar" \
    "com.example.Subtractor" "com.example.Adder" "com.example.Multiplier" "com.example.MathApp"

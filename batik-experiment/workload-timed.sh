#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..68})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FAT_JAR="benchmark/target/benchmark-fat.jar"
MAIN="dev.batikexp.Main"
WORK_DIR="workload-tmp"
SINGLE_AOT="single.aot"
TREE_AOT="tree.aot"

# Override any of these with environment variables before running:
#   RUNS=20 JAVA_TREE_BIN=/path/to/java24 ./workload-timed.sh
RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_SINGLE_BIN="${JAVA_SINGLE_BIN:-java}"
JAVA_TREE_BIN="${JAVA_TREE_BIN:-java}"

OPS=(svg-parse svg-to-png svg-to-jpeg svg-to-svg svg-generate)

[[ -f "$FAT_JAR" ]]   || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"
[[ -f "$SINGLE_AOT" ]] || fail "single.aot not found — run ./create-single-aot.sh first"
[[ -f "$TREE_AOT" ]]   || fail "tree.aot not found — run ./orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java binaries:"
printf "  no-AOT:     %s\n" "$JAVA_NO_BIN";     "$JAVA_NO_BIN"     -version 2>&1 | head -1
printf "  single-AOT: %s\n" "$JAVA_SINGLE_BIN"; "$JAVA_SINGLE_BIN" -version 2>&1 | head -1
printf "  tree-AOT:   %s\n" "$JAVA_TREE_BIN";   "$JAVA_TREE_BIN"   -version 2>&1 | head -1
echo

# Shared flags for all invocations
BASE_ARGS=(-Djava.awt.headless=true -cp "$FAT_JAR")

log "Preparing workload inputs"
"$JAVA_NO_BIN" "${BASE_ARGS[@]}" "$MAIN" prepare "$WORK_DIR" >/dev/null

# ─── timing helpers ──────────────────────────────────────────────────────────

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A _min _max _samples

_update() {
  local key="$1" v="$2"
  _samples[$key]="${_samples[$key]:-} $v"
  if [[ -z "${_min[$key]:-}" ]] || awk "BEGIN{exit !($v < ${_min[$key]})}"; then _min[$key]=$v; fi
  if [[ -z "${_max[$key]:-}" ]] || awk "BEGIN{exit !($v > ${_max[$key]})}"; then _max[$key]=$v; fi
}

_mean() {
  printf "%s\n" ${_samples[$1]:-} | awk '
    {sum+=$1; n++}
    END{
      if(!n){print "n/a"}
      else{printf "%.1f",sum/n}
    }'
}

_stddev() {
  printf "%s\n" ${_samples[$1]:-} | awk '
    {sum+=$1; sumsq+=$1*$1; n++}
    END{
      if(n<2){print "n/a"}
      else{printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))}
    }'
}

# ─── run helpers ─────────────────────────────────────────────────────────────

_run_no()     { "$JAVA_NO_BIN"     "${BASE_ARGS[@]}" "$MAIN" "$1" "$WORK_DIR"; }
_run_single() { "$JAVA_SINGLE_BIN" -XX:AOTCache="$SINGLE_AOT" "${BASE_ARGS[@]}" "$MAIN" "$1" "$WORK_DIR"; }
_run_tree()   { "$JAVA_TREE_BIN"   -XX:AOTCache="$TREE_AOT"   "${BASE_ARGS[@]}" "$MAIN" "$1" "$WORK_DIR"; }

_measure() {
  local op="$1" mode="$2" run="$3"
  local errfile="$WORK_DIR/err-${op}-${mode}-${run}.log"
  local t0 t1 rc=0
  t0=$(ms)
  "_run_${mode}" "$op" >/dev/null 2>"$errfile" || rc=$?
  t1=$(ms)
  if (( rc != 0 )); then
    echo "  WARN: op=$op mode=$mode run=$run exited $rc — see $errfile" >&2
    return
  fi
  local elapsed
  elapsed=$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")
  _update "${op}|${mode}" "$elapsed"
}

# ─── class-load summary ──────────────────────────────────────────────────────

_classload_row() {
  local op="$1" mode="$2"
  local logfile="$WORK_DIR/cl-${op}-${mode}.log"
  case "$mode" in
    no)     "$JAVA_NO_BIN"     -Xlog:class+load:file="$logfile" "${BASE_ARGS[@]}" "$MAIN" "$op" "$WORK_DIR" >/dev/null 2>&1 ;;
    single) "$JAVA_SINGLE_BIN" -XX:AOTCache="$SINGLE_AOT" -Xlog:class+load:file="$logfile" "${BASE_ARGS[@]}" "$MAIN" "$op" "$WORK_DIR" >/dev/null 2>&1 ;;
    tree)   "$JAVA_TREE_BIN"   -XX:AOTCache="$TREE_AOT"   -Xlog:class+load:file="$logfile" "${BASE_ARGS[@]}" "$MAIN" "$op" "$WORK_DIR" >/dev/null 2>&1 ;;
  esac
  printf "  %-14s | %-6s | %8s | %8s\n" "$op" "$mode" \
    "$(awk '/source: file:/{c++} END{print c+0}' "$logfile")" \
    "$(awk '/source: shared object/{c++} END{print c+0}' "$logfile")"
}

# ─── main measurement loop ───────────────────────────────────────────────────

log "Running $RUNS iterations × ${#OPS[@]} ops × 3 modes"
sep

for run in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$run" "$RUNS"
  for op in "${OPS[@]}"; do
    _measure "$op" no     "$run"
    _measure "$op" single "$run"
    _measure "$op" tree   "$run"
  done
done

# ─── results ─────────────────────────────────────────────────────────────────

echo
log "Aggregated timing over $RUNS runs (ms) — lower is better"
sep
printf "  %-14s | %9s %7s %7s %7s | %11s %7s %7s %7s | %9s %7s %7s %7s\n" \
  "Operation" "no-mean" "no-min" "no-max" "no-std" "single-mean" "sng-min" "sng-max" "sng-std" "tree-mean" "tr-min" "tr-max" "tr-std"
sep
for op in "${OPS[@]}"; do
  printf "  %-14s | %9s %7s %7s %7s | %11s %7s %7s %7s | %9s %7s %7s %7s\n" \
    "$op" \
    "$(_mean "${op}|no")"     "${_min[${op}|no]:-n/a}"     "${_max[${op}|no]:-n/a}"     "$(_stddev "${op}|no")" \
    "$(_mean "${op}|single")" "${_min[${op}|single]:-n/a}" "${_max[${op}|single]:-n/a}" "$(_stddev "${op}|single")" \
    "$(_mean "${op}|tree")"   "${_min[${op}|tree]:-n/a}"   "${_max[${op}|tree]:-n/a}"   "$(_stddev "${op}|tree")"
done

_print_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local i=0
  local tex_file="$WORK_DIR/latex-rows.tex"
  echo "\\multirow{${n}}{*}{${project}}" > "$tex_file"
  for op in "${OPS[@]}"; do
    local m_single m_tree s_single s_tree speedup w
    m_single=$(_mean "${op}|single")
    m_tree=$(_mean "${op}|tree")
    s_single=$(_stddev "${op}|single")
    s_tree=$(_stddev "${op}|tree")
    speedup=$(awk -v ms="$m_single" -v mt="$m_tree" 'BEGIN {
      if (ms+0 == 0) { print "n/a" }
      else { printf "%+.1f", (ms - mt) / ms * 100 }
    }')
    if [ "$i" -eq 0 ]; then
      w="\\textbf{${op}}"
    else
      w="${op}"
    fi
    echo "  & ${w} & \$${m_single} \\pm ${s_single}\$ & \$${m_tree} \\pm ${s_tree}\$ & ${speedup}\\% \\\\" >> "$tex_file"
    i=$(( i + 1 ))
  done
  echo "\\midrule" >> "$tex_file"
}

_print_latex_rows "batik"

echo
log "Class-load source breakdown (one run each)"
sep
printf "  %-14s | %-6s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
sep
for op in "${OPS[@]}"; do
  for mode in no single tree; do
    _classload_row "$op" "$mode"
  done
  sep
done

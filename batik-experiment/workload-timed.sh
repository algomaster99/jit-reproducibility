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
MONOLITHIC_AOT="single.aot"
MERGED_AOT="tree.aot"

# Override any of these with environment variables before running:
#   RUNS=20 JAVA_MERGED_BIN=/path/to/java24 ./workload-timed.sh
RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_MONOLITHIC_BIN="${JAVA_MONOLITHIC_BIN:-java}"
JAVA_MERGED_BIN="${JAVA_MERGED_BIN:-java}"

OPS=(svg-parse svg-to-png svg-to-jpeg svg-generate)

[[ -f "$FAT_JAR" ]]   || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"
[[ -f "$MONOLITHIC_AOT" ]] || fail "single.aot not found — run ./create-single-aot.sh first"
[[ -f "$MERGED_AOT" ]]   || fail "tree.aot not found — run ./orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java binaries:"
printf "  no-AOT:     %s\n" "$JAVA_NO_BIN";     "$JAVA_NO_BIN"     -version 2>&1 | head -1
printf "  monolithic-AOT: %s\n" "$JAVA_MONOLITHIC_BIN"; "$JAVA_MONOLITHIC_BIN" -version 2>&1 | head -1
printf "  merged-AOT:     %s\n" "$JAVA_MERGED_BIN";     "$JAVA_MERGED_BIN"     -version 2>&1 | head -1
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
_run_monolithic() { "$JAVA_MONOLITHIC_BIN" -XX:AOTCache="$MONOLITHIC_AOT" -XX:+AOTClassLinking "${BASE_ARGS[@]}" "$MAIN" "$1" "$WORK_DIR"; }
_run_merged()   { "$JAVA_MERGED_BIN"   -XX:AOTCache="$MERGED_AOT"   "${BASE_ARGS[@]}" "$MAIN" "$1" "$WORK_DIR"; }

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
    monolithic) "$JAVA_MONOLITHIC_BIN" -XX:AOTCache="$MONOLITHIC_AOT" -XX:+AOTClassLinking -Xlog:class+load:file="$logfile" "${BASE_ARGS[@]}" "$MAIN" "$op" "$WORK_DIR" >/dev/null 2>&1 ;;
    merged)     "$JAVA_MERGED_BIN"     -XX:AOTCache="$MERGED_AOT"     -Xlog:class+load:file="$logfile" "${BASE_ARGS[@]}" "$MAIN" "$op" "$WORK_DIR" >/dev/null 2>&1 ;;
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
    _measure "$op" no          "$run"
    _measure "$op" monolithic  "$run"
    _measure "$op" merged      "$run"
  done
done

# ─── results ─────────────────────────────────────────────────────────────────

echo
log "Aggregated timing over $RUNS runs (ms) — lower is better"
sep
printf "  %-14s | %9s %7s %7s %7s | %11s %7s %7s %7s | %9s %7s %7s %7s\n" \
  "Operation" "no-mean" "no-min" "no-max" "no-std" "mono-mean" "mono-min" "mono-max" "mono-std" "merged-mean" "mg-min" "mg-max" "mg-std"
sep
for op in "${OPS[@]}"; do
  printf "  %-14s | %9s %7s %7s %7s | %11s %7s %7s %7s | %9s %7s %7s %7s\n" \
    "$op" \
    "$(_mean "${op}|no")"          "${_min[${op}|no]:-n/a}"          "${_max[${op}|no]:-n/a}"          "$(_stddev "${op}|no")" \
    "$(_mean "${op}|monolithic")"  "${_min[${op}|monolithic]:-n/a}"  "${_max[${op}|monolithic]:-n/a}"  "$(_stddev "${op}|monolithic")" \
    "$(_mean "${op}|merged")"      "${_min[${op}|merged]:-n/a}"      "${_max[${op}|merged]:-n/a}"      "$(_stddev "${op}|merged")"
done

_print_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local i=0
  local tex_file="$WORK_DIR/latex-rows.tex"
  echo "\\multirow{${n}}{*}{${project}}" > "$tex_file"
  for op in "${OPS[@]}"; do
    local m_mono m_merged s_mono s_merged speedup w
    m_mono=$(_mean "${op}|monolithic")
    m_merged=$(_mean "${op}|merged")
    s_mono=$(_stddev "${op}|monolithic")
    s_merged=$(_stddev "${op}|merged")
    speedup=$(awk -v ms="$m_mono" -v mt="$m_merged" 'BEGIN {
      if (ms+0 == 0) { print "n/a" }
      else { printf "%+.1f", (ms - mt) / ms * 100 }
    }')
    if [ "$i" -eq 0 ]; then
      w="\\textbf{${op}}"
    else
      w="${op}"
    fi
    echo "  & ${w} & \$${m_mono} \\pm ${s_mono}\$ & \$${m_merged} \\pm ${s_merged}\$ & ${speedup}\\% \\\\" >> "$tex_file"
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
  for mode in no monolithic merged; do
    _classload_row "$op" "$mode"
  done
  sep
done

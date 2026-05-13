#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..68})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FAT_JAR="benchmark/target/benchmark-fat.jar"
WORK_DIR="workload-tmp"
MERGED_AOT="tree.aot"

RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_MONOLITHIC_BIN="${JAVA_MONOLITHIC_BIN:-java}"
JAVA_MERGED_BIN="${JAVA_MERGED_BIN:-java}"

OPS=(html-render text-render xml-render fragment-render)

[[ -f "$FAT_JAR" ]] || fail "$FAT_JAR not found — run: cd benchmark && mvn package -DskipTests"
for _op in "${OPS[@]}"; do
  [[ -f "single-${_op}.aot" ]] || fail "single-${_op}.aot not found — run ./create-single-aot.sh first"
done
[[ -f "$MERGED_AOT" ]] || fail "tree.aot not found — run ./orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java binaries:"
printf "  no-AOT:         %s\n" "$JAVA_NO_BIN";         "$JAVA_NO_BIN"         -version 2>&1 | head -1
printf "  monolithic-AOT: %s\n" "$JAVA_MONOLITHIC_BIN"; "$JAVA_MONOLITHIC_BIN" -version 2>&1 | head -1
printf "  merged-AOT:     %s\n" "$JAVA_MERGED_BIN";     "$JAVA_MERGED_BIN"     -version 2>&1 | head -1
echo

# ─── run helpers ─────────────────────────────────────────────────────────────

_run_no()     { "$JAVA_NO_BIN"     -jar "$FAT_JAR" "$1"; }
_run_merged() { "$JAVA_MERGED_BIN" -XX:AOTCache="$MERGED_AOT" -jar "$FAT_JAR" "$1"; }

# train_op determines which single-{op}.aot to load; test_op is the workload run.
_run_mono_cross() {
  local train_op="$1" test_op="$2"
  "$JAVA_MONOLITHIC_BIN" -XX:AOTCache="single-${train_op}.aot" -XX:+AOTClassLinking \
    -jar "$FAT_JAR" "$test_op"
}

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
    END{ if(!n){print "n/a"} else{printf "%.1f",sum/n} }'
}

_stddev() {
  printf "%s\n" ${_samples[$1]:-} | awk '
    {sum+=$1; sumsq+=$1*$1; n++}
    END{ if(n<2){print "n/a"} else{printf "%.1f",sqrt((sumsq-sum*sum/n)/(n-1))} }'
}

_measure_no() {
  local op="$1" run="$2"
  local errfile="$WORK_DIR/err-${op}-no-${run}.log"
  local t0 t1 rc=0
  t0=$(ms); _run_no "$op" >/dev/null 2>"$errfile" || rc=$?; t1=$(ms)
  if (( rc != 0 )); then echo "  WARN: op=$op mode=no run=$run exited $rc — see $errfile" >&2; return; fi
  _update "${op}|no" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

_measure_merged() {
  local op="$1" run="$2"
  local errfile="$WORK_DIR/err-${op}-merged-${run}.log"
  local t0 t1 rc=0
  t0=$(ms); _run_merged "$op" >/dev/null 2>"$errfile" || rc=$?; t1=$(ms)
  if (( rc != 0 )); then echo "  WARN: op=$op mode=merged run=$run exited $rc — see $errfile" >&2; return; fi
  _update "${op}|merged" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

_measure_mono_cross() {
  local train_op="$1" test_op="$2" run="$3"
  local errfile="$WORK_DIR/err-${train_op}-${test_op}-mono-${run}.log"
  local t0 t1 rc=0
  t0=$(ms); _run_mono_cross "$train_op" "$test_op" >/dev/null 2>"$errfile" || rc=$?; t1=$(ms)
  if (( rc != 0 )); then
    echo "  WARN: train=$train_op test=$test_op run=$run exited $rc — see $errfile" >&2; return
  fi
  _update "${train_op}|${test_op}|mono" "$(awk "BEGIN{printf \"%.1f\",$t1-$t0}")"
}

# Mean over all test ops ≠ train_op.
# mode: "no" → ${test}|no   "mono" → ${train}|${test}|mono   "merged" → ${test}|merged
_cross_mean() {
  local train_op="$1" mode="$2"
  local sum=0 n=0 test_op key m
  for test_op in "${OPS[@]}"; do
    [[ "$test_op" == "$train_op" ]] && continue
    case "$mode" in
      no)     key="${test_op}|no" ;;
      mono)   key="${train_op}|${test_op}|mono" ;;
      merged) key="${test_op}|merged" ;;
    esac
    m=$(_mean "$key")
    sum=$(awk "BEGIN{printf \"%.4f\", $sum + $m}")
    n=$(( n + 1 ))
  done
  awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.1f", s/n}'
}

# ─── main measurement loop ───────────────────────────────────────────────────

log "Running $RUNS iterations × ${#OPS[@]} ops (cross-workload)"
sep

for run in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$run" "$RUNS"
  # no-AOT and merged: one pass over all ops
  for op in "${OPS[@]}"; do
    _measure_no     "$op" "$run"
    _measure_merged "$op" "$run"
  done
  # monolithic cross-workload: for each training op, run its cache on all other ops
  for train_op in "${OPS[@]}"; do
    for test_op in "${OPS[@]}"; do
      [[ "$test_op" == "$train_op" ]] && continue
      _measure_mono_cross "$train_op" "$test_op" "$run"
    done
  done
done

# ─── results ─────────────────────────────────────────────────────────────────

echo
log "Cross-workload timing over $RUNS runs (ms) — train on X, mean of other 3 ops"
sep
printf "  %-16s | %10s | %12s %8s | %12s %8s\n" \
  "Trained on" "no-mean" "mono-mean" "su-mono" "merged-mean" "su-merged"
sep
for train_op in "${OPS[@]}"; do
  m_no=$(_cross_mean "$train_op" "no")
  m_mono=$(_cross_mean "$train_op" "mono")
  m_merged=$(_cross_mean "$train_op" "merged")
  su_mono=$(awk   -v b="$m_no" -v a="$m_mono"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  su_merged=$(awk -v b="$m_no" -v a="$m_merged" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
  printf "  %-16s | %10s | %12s %8s | %12s %8s\n" \
    "$train_op" "$m_no" "$m_mono" "$su_mono" "$m_merged" "$su_merged"
done

# ─── LaTeX rows ──────────────────────────────────────────────────────────────

_print_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local i=0
  local tex_file="$WORK_DIR/latex-rows.tex"
  local sum_su_mono=0 sum_su_merged=0
  echo "\\multirow{$(( n + 1 ))}{*}{${project}}" > "$tex_file"
  local train_op
  for train_op in "${OPS[@]}"; do
    local m_no m_mono m_merged su_mono su_merged fmt_su_mono fmt_su_merged w
    m_no=$(_cross_mean "$train_op" "no")
    m_mono=$(_cross_mean "$train_op" "mono")
    m_merged=$(_cross_mean "$train_op" "merged")
    su_mono=$(awk   -v b="$m_no" -v a="$m_mono"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    su_merged=$(awk -v b="$m_no" -v a="$m_merged" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    sum_su_mono=$(awk  "BEGIN{printf \"%.4f\", $sum_su_mono   + $su_mono}")
    sum_su_merged=$(awk "BEGIN{printf \"%.4f\", $sum_su_merged + $su_merged}")
    fmt_su_mono=$(awk   -v a="$su_mono" -v b="$su_merged" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
    fmt_su_merged=$(awk -v a="$su_mono" -v b="$su_merged" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
    if [ "$i" -eq 0 ]; then w="\\textbf{${train_op}}"; else w="${train_op}"; fi
    echo "  & ${w} & \$${m_no}\$ & \$${m_mono}\$ & ${fmt_su_mono} & \$${m_merged}\$ & ${fmt_su_merged} \\\\" >> "$tex_file"
    i=$(( i + 1 ))
  done
  local avg_mono avg_merged fmt_avg_mono fmt_avg_merged
  avg_mono=$(awk   -v s="$sum_su_mono"   -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  avg_merged=$(awk -v s="$sum_su_merged" -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  fmt_avg_mono=$(awk   -v a="$avg_mono" -v b="$avg_merged" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
  fmt_avg_merged=$(awk -v a="$avg_mono" -v b="$avg_merged" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
  echo "  & \\textit{Average} & & & ${fmt_avg_mono} & & ${fmt_avg_merged} \\\\" >> "$tex_file"
  echo "\\midrule" >> "$tex_file"
}

_print_latex_rows "thymeleaf"

# ─── class-load summary (same-workload monolithic for each op) ───────────────

_classload_row() {
  local op="$1" mode="$2"
  local logfile="$WORK_DIR/cl-${op}-${mode}.log"
  case "$mode" in
    no)         "$JAVA_NO_BIN"         -Xlog:class+load:file="$logfile" -jar "$FAT_JAR" "$op" >/dev/null 2>&1 ;;
    monolithic) "$JAVA_MONOLITHIC_BIN" -XX:AOTCache="single-${op}.aot" -XX:+AOTClassLinking \
                  -Xlog:class+load:file="$logfile" -jar "$FAT_JAR" "$op" >/dev/null 2>&1 ;;
    merged)     "$JAVA_MERGED_BIN"     -XX:AOTCache="$MERGED_AOT" \
                  -Xlog:class+load:file="$logfile" -jar "$FAT_JAR" "$op" >/dev/null 2>&1 ;;
  esac
  printf "  %-16s | %-10s | %8s | %8s\n" "$op" "$mode" \
    "$(awk '/source: file:/{c++} END{print c+0}' "$logfile")" \
    "$(awk '/source: shared object/{c++} END{print c+0}' "$logfile")"
}

echo
log "Class-load source breakdown (monolithic uses same-workload cache)"
sep
printf "  %-16s | %-10s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
sep
for op in "${OPS[@]}"; do
  _classload_row "$op" no
  _classload_row "$op" monolithic
  _classload_row "$op" merged
  sep
done

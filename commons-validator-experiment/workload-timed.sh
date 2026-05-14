#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
CP="$JAR:\
commons-validator/target/classes:\
commons-validator-deps/commons-beanutils/target/classes:\
commons-validator-deps/commons-digester/target/classes:\
commons-validator-deps/commons-logging/target/classes:\
commons-validator-deps/commons-collections/target/classes"

SINGLE_DEPS_DIR="single-aot-deps"
MONOLITHIC_CP="$JAR:\
$SINGLE_DEPS_DIR/commons-validator-1.10.1.jar:\
$SINGLE_DEPS_DIR/commons-beanutils-1.11.0.jar:\
$SINGLE_DEPS_DIR/commons-digester-2.1.jar:\
$SINGLE_DEPS_DIR/commons-logging-1.3.5.jar:\
$SINGLE_DEPS_DIR/commons-collections-3.2.2.jar"

MAIN="dev.validatorexp.Main"
WORK_DIR="workload-tmp"
MERGED_AOT="tree.aot"
RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_MONOLITHIC_BIN="${JAVA_MONOLITHIC_BIN:-java}"
JAVA_MERGED_BIN="${JAVA_MERGED_BIN:-java}"
OPS=("validate-email" "validate-url" "validate-ip" "validate-credit-card")

[[ -f "$JAR" ]] || fail "$JAR not found — run: cd benchmark && mvn package -DskipTests"
for _op in "${OPS[@]}"; do
  [[ -f "single-${_op}.aot" ]] || fail "single-${_op}.aot not found — run create-single-aot.sh first"
done
[[ -f "$MERGED_AOT" ]] || fail "tree.aot not found — run orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java version(s):"
echo "no-AOT java:         $JAVA_NO_BIN";         "$JAVA_NO_BIN"         -version
echo
echo "monolithic-AOT java: $JAVA_MONOLITHIC_BIN"; "$JAVA_MONOLITHIC_BIN" -version
echo
echo "merged-AOT java:     $JAVA_MERGED_BIN";     "$JAVA_MERGED_BIN"     -version
echo

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A minv maxv cnt samples

update_stats() {
  local key="$1" sample_ms="$2"
  cnt[$key]=$(( ${cnt[$key]:-0} + 1 ))
  samples[$key]="${samples[$key]:-} ${sample_ms}"
  if [ -z "${minv[$key]:-}" ] || awk "BEGIN {exit !(${sample_ms} < ${minv[$key]})}"; then
    minv[$key]="$sample_ms"
  fi
  if [ -z "${maxv[$key]:-}" ] || awk "BEGIN {exit !(${sample_ms} > ${maxv[$key]})}"; then
    maxv[$key]="$sample_ms"
  fi
}

mean_for_key() {
  local values="${samples[$1]# }"
  printf "%s\n" $values | awk '
    { sum += $1; n++ }
    END { if (n == 0) { print "n/a" } else { printf "%.1f", sum/n } }'
}

stddev_for_key() {
  local values="${samples[$1]# }"
  printf "%s\n" $values | awk '
    { sum += $1; sumsq += $1*$1; n++ }
    END { if (n < 2) { print "n/a" } else { printf "%.1f", sqrt((sumsq - sum*sum/n) / (n-1)) } }'
}

# ─── run helpers ─────────────────────────────────────────────────────────────

run_no() {
  local op="$1"
  "$JAVA_NO_BIN" \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.time=ALL-UNNAMED \
    --add-opens java.base/java.time.chrono=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    -cp "$CP" "$MAIN" "$op"
}

run_mono_cross() {
  local train_op="$1" test_op="$2"
  "$JAVA_MONOLITHIC_BIN" -XX:AOTCache="single-${train_op}.aot" \
    -XX:+AOTClassLinking \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.time=ALL-UNNAMED \
    --add-opens java.base/java.time.chrono=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    -cp "$MONOLITHIC_CP" "$MAIN" "$test_op"
}

run_merged() {
  local op="$1"
  "$JAVA_MERGED_BIN" -XX:AOTCache="$MERGED_AOT" \
    -XX:+AOTClassLinking \
    --add-modules java.instrument \
    --add-opens java.base/java.io=ALL-UNNAMED \
    --add-opens java.base/java.lang=ALL-UNNAMED \
    --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
    --add-opens java.base/java.time=ALL-UNNAMED \
    --add-opens java.base/java.time.chrono=ALL-UNNAMED \
    --add-opens java.base/java.util=ALL-UNNAMED \
    -cp "$CP" "$MAIN" "$op"
}

measure_ms() {
  local label_op="$1" label_mode="$2"
  shift 2
  local file_label_op="${label_op//>/-to-}"
  local err_file="$WORK_DIR/${RUN_IDX:-0}-${file_label_op}-${label_mode}.stderr.log"
  local start end rc
  start=$(ms)
  "$@" >/dev/null 2>"$err_file"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: failed (op=$label_op mode=$label_mode rc=$rc) see $err_file" >&2
    return "$rc"
  fi
  end=$(ms)
  awk "BEGIN {printf \"%.1f\", $end - $start}"
}

cross_mean() {
  local train_op="$1" mode="$2"
  local sum=0 n=0 test_op key m
  for test_op in "${OPS[@]}"; do
    [[ "$test_op" == "$train_op" ]] && continue
    case "$mode" in
      no)     key="${test_op}|no" ;;
      mono)   key="${train_op}|${test_op}|mono" ;;
      merged) key="${test_op}|merged" ;;
    esac
    m=$(mean_for_key "$key")
    sum=$(awk "BEGIN{printf \"%.4f\", $sum + $m}")
    n=$(( n + 1 ))
  done
  awk -v s="$sum" -v n="$n" 'BEGIN{printf "%.1f", s/n}'
}

# ─── main measurement loop ───────────────────────────────────────────────────

log "Running Commons Validator workload RUNS=$RUNS"
for RUN_IDX in $(seq 1 "$RUNS"); do
  printf "  run %2d/%d\n" "$RUN_IDX" "$RUNS"
  for op in "${OPS[@]}"; do
    update_stats "${op}|no"     "$(measure_ms "$op" "no"     run_no     "$op")"
    update_stats "${op}|merged" "$(measure_ms "$op" "merged" run_merged "$op")"
  done
  for train_op in "${OPS[@]}"; do
    for test_op in "${OPS[@]}"; do
      [[ "$test_op" == "$train_op" ]] && continue
      update_stats "${train_op}|${test_op}|mono" \
        "$(measure_ms "${train_op}>${test_op}" "mono" run_mono_cross "$train_op" "$test_op")"
    done
  done
done

# ─── results ─────────────────────────────────────────────────────────────────

print_summary() {
  echo
  log "Cross-workload timing over ${RUNS} runs (ms) — train on X, mean of other 3 ops"
  sep
  printf "  %-20s | %10s | %12s %8s | %12s %8s\n" \
    "Trained on" "no-mean" "mono-mean" "su-mono" "merged-mean" "su-merged"
  sep
  local train_op
  for train_op in "${OPS[@]}"; do
    local m_no m_mono m_merged su_mono su_merged
    m_no=$(cross_mean "$train_op" "no")
    m_mono=$(cross_mean "$train_op" "mono")
    m_merged=$(cross_mean "$train_op" "merged")
    su_mono=$(awk   -v b="$m_no" -v a="$m_mono"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
    su_merged=$(awk -v b="$m_no" -v a="$m_merged" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2fx",b/a}}')
    printf "  %-20s | %10s | %12s %8s | %12s %8s\n" \
      "$train_op" "$m_no" "$m_mono" "$su_mono" "$m_merged" "$su_merged"
  done
}

print_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local tex_file="$WORK_DIR/latex-rows.tex"
  local sum_su_mono=0 sum_su_merged=0
  echo "\\multirow{$(( n + 1 ))}{*}{${project}}" > "$tex_file"
  local train_op
  for train_op in "${OPS[@]}"; do
    local m_no m_mono m_merged su_mono su_merged fmt_su_mono fmt_su_merged
    m_no=$(cross_mean "$train_op" "no")
    m_mono=$(cross_mean "$train_op" "mono")
    m_merged=$(cross_mean "$train_op" "merged")
    su_mono=$(awk   -v b="$m_no" -v a="$m_mono"   'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    su_merged=$(awk -v b="$m_no" -v a="$m_merged" 'BEGIN{if(a+0==0){print "n/a"}else{printf "%.2f",b/a}}')
    sum_su_mono=$(awk  "BEGIN{printf \"%.4f\", $sum_su_mono  + $su_mono}")
    sum_su_merged=$(awk "BEGIN{printf \"%.4f\", $sum_su_merged + $su_merged}")
    fmt_su_mono=$(awk   -v a="$su_mono" -v b="$su_merged" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
    fmt_su_merged=$(awk -v a="$su_mono" -v b="$su_merged" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
    echo "  & ${train_op} & \$${m_no}\$ & \$${m_mono}\$ & ${fmt_su_mono} & \$${m_merged}\$ & ${fmt_su_merged} \\\\" >> "$tex_file"
  done
  local avg_mono avg_merged fmt_avg_mono fmt_avg_merged
  avg_mono=$(awk  -v s="$sum_su_mono"   -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  avg_merged=$(awk -v s="$sum_su_merged" -v n="$n" 'BEGIN{printf "%.2f", s/n}')
  fmt_avg_mono=$(awk   -v a="$avg_mono" -v b="$avg_merged" 'BEGIN{if(a+0>b+0) print "\\textbf{"a"x}" ; else print a"x"}')
  fmt_avg_merged=$(awk -v a="$avg_mono" -v b="$avg_merged" 'BEGIN{if(b+0>a+0) print "\\textbf{"b"x}" ; else print b"x"}')
  echo "  & \\textit{Average} & & & ${fmt_avg_mono} & & ${fmt_avg_merged} \\\\" >> "$tex_file"
  echo "\\midrule" >> "$tex_file"
}

print_summary
print_latex_rows "commons-validator"

# ─── class-load summary ──────────────────────────────────────────────────────

print_class_load_row() {
  local mode="$1" op="$2"
  local classload_log="$WORK_DIR/classload-${op}-${mode}.log"
  case "$mode" in
    no)
      "$JAVA_NO_BIN" -Xlog:class+load:file="$classload_log" \
        --add-modules java.instrument \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" >/dev/null
      ;;
    monolithic)
      "$JAVA_MONOLITHIC_BIN" -XX:AOTCache="single-${op}.aot" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        --add-modules java.instrument \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$MONOLITHIC_CP" "$MAIN" "$op" >/dev/null
      ;;
    merged)
      "$JAVA_MERGED_BIN" -XX:AOTCache="$MERGED_AOT" \
        -XX:+AOTClassLinking \
        -Xlog:class+load:file="$classload_log" \
        --add-modules java.instrument \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" >/dev/null
      ;;
  esac
  printf "  %-24s | %-10s | %8s | %8s\n" \
    "$op" "$mode" \
    "$(awk '/source: file:/{count++} END{print count+0}' "$classload_log")" \
    "$(awk '/source: shared object[s]? file/{count++} END{print count+0}' "$classload_log")"
}

echo
log "Class-load source summary per workload (monolithic uses same-workload cache)"
sep
printf "  %-24s | %-10s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
sep
for op in "${OPS[@]}"; do
  print_class_load_row "no" "$op"
  print_class_load_row "monolithic" "$op"
  print_class_load_row "merged" "$op"
  sep
done

#!/bin/bash
set -euo pipefail

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')] $*\033[0m"; }
sep()  { echo -e "\033[0;90m  $(printf '─%.0s' {1..60})\033[0m"; }
fail() { echo -e "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

JAR="benchmark/target/original-benchmark-1.0-SNAPSHOT.jar"
CP="$JAR:\
commons-configuration/target/classes:\
commons-configuration-deps/commons-lang/target/classes:\
commons-configuration-deps/commons-text/target/classes:\
commons-configuration-deps/commons-beanutils/target/classes:\
commons-configuration-deps/commons-collections/target/classes:\
commons-configuration-deps/commons-logging-workload/target/commons-logging-workload-1.0-SNAPSHOT.jar"
# single.aot was recorded against JARs (directories are rejected by stock JDKs),
# so the single mode must use the same JAR-based classpath to avoid cache rejection.
SINGLE_DEPS_DIR="single-aot-deps"
MONOLITHIC_CP="$JAR:\
$SINGLE_DEPS_DIR/commons-configuration2-2.14.0.jar:\
$SINGLE_DEPS_DIR/commons-lang3-3.20.0.jar:\
$SINGLE_DEPS_DIR/commons-text-1.15.0.jar:\
$SINGLE_DEPS_DIR/commons-logging-1.3.6.jar:\
$SINGLE_DEPS_DIR/commons-beanutils-1.11.0.jar:\
$SINGLE_DEPS_DIR/commons-collections4-4.5.0.jar"
MAIN="dev.configexp.Main"
WORK_DIR="workload-tmp"
MONOLITHIC_AOT="single.aot"
MERGED_AOT="tree.aot"
RUNS="${RUNS:-30}"
JAVA_NO_BIN="${JAVA_NO_BIN:-java}"
JAVA_MONOLITHIC_BIN="${JAVA_MONOLITHIC_BIN:-java}"
JAVA_MERGED_BIN="${JAVA_MERGED_BIN:-java}"
OPS=("properties-read" "xml-read" "composite-read" "interpolation")

[[ -f "$JAR" ]] || fail "$JAR not found — run: cd benchmark && mvn package -DskipTests"
[[ -f "$MONOLITHIC_AOT" ]] || fail "single.aot not found — run create-single-aot.sh first"
[[ -f "$MERGED_AOT" ]] || fail "tree.aot not found — run orchestrate-combine.sh first"

mkdir -p "$WORK_DIR"

log "Java version(s):"
echo "no-AOT java:     $JAVA_NO_BIN"
"$JAVA_NO_BIN" -version
echo
echo "monolithic-AOT java: $JAVA_MONOLITHIC_BIN"
"$JAVA_MONOLITHIC_BIN" -version
echo
echo "merged-AOT java:     $JAVA_MERGED_BIN"
"$JAVA_MERGED_BIN" -version
echo

"$JAVA_NO_BIN" -cp "$CP" "$MAIN" prepare "$WORK_DIR" >/dev/null

ms() { date +%s%N | awk '{printf "%.1f", $1/1000000}'; }

declare -A minv maxv cnt samples

update_stats() {
  local key="$1"
  local sample_ms="$2"
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
  local key="$1"
  local values="${samples[$key]# }"
  printf "%s\n" $values | awk '
    { sum += $1; n++ }
    END {
      if (n == 0) { print "n/a" }
      else { printf "%.1f", sum/n }
    }
  '
}

stddev_for_key() {
  local key="$1"
  local values="${samples[$key]# }"
  printf "%s\n" $values | awk '
    { sum += $1; sumsq += $1*$1; n++ }
    END {
      if (n < 2) { print "n/a" }
      else { printf "%.1f", sqrt((sumsq - sum*sum/n) / (n-1)) }
    }
  '
}

run_mode_op() {
  local mode="$1"
  local op="$2"
  case "$mode" in
    no)
      "$JAVA_NO_BIN" \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    monolithic)
      "$JAVA_MONOLITHIC_BIN" -XX:AOTCache="$MONOLITHIC_AOT" \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$MONOLITHIC_CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    merged)
      "$JAVA_MERGED_BIN" -XX:AOTCache="$MERGED_AOT" \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    *)
      fail "Unknown mode: $mode"
      ;;
  esac
}

measure_ms() {
  local op="$1"
  local mode="$2"
  shift 2
  local err_file="$WORK_DIR/${RUN_IDX:-0}-${op}-${mode}.stderr.log"
  local start end rc
  start=$(ms)
  "$@" >/dev/null 2>"$err_file"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "ERROR: failed (op=$op mode=$mode rc=$rc) see $err_file" >&2
    return "$rc"
  fi
  end=$(ms)
  awk "BEGIN {printf \"%.1f\", $end - $start}"
}

print_summary() {
  echo
  log "Aggregated timing over ${RUNS} runs (ms)"
  sep
  printf "  %-16s | %10s %6s %6s %6s | %12s %8s %8s %8s | %10s %6s %6s %6s\n" \
    "Operation" "no-mean" "no-min" "no-max" "no-std" "mono-mean" "mono-min" "mono-max" "mono-std" "merged-mean" "mg-min" "mg-max" "mg-std"
  local op
  for op in "${OPS[@]}"; do
    printf "  %-16s | %10s %6s %6s %6s | %12s %8s %8s %8s | %10s %6s %6s %6s\n" \
      "$op" \
      "$(mean_for_key "${op}|no")"          "${minv[${op}|no]:-n/a}"          "${maxv[${op}|no]:-n/a}"          "$(stddev_for_key "${op}|no")" \
      "$(mean_for_key "${op}|monolithic")"  "${minv[${op}|monolithic]:-n/a}"  "${maxv[${op}|monolithic]:-n/a}"  "$(stddev_for_key "${op}|monolithic")" \
      "$(mean_for_key "${op}|merged")"      "${minv[${op}|merged]:-n/a}"      "${maxv[${op}|merged]:-n/a}"      "$(stddev_for_key "${op}|merged")"
  done
}

print_class_load_row() {
  local mode="$1"
  local op="$2"
  local classload_log="$WORK_DIR/classload-${op}-${mode}.log"

  case "$mode" in
    no)
      "$JAVA_NO_BIN" -Xlog:class+load:file="$classload_log" \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    monolithic)
      "$JAVA_MONOLITHIC_BIN" -XX:AOTCache="$MONOLITHIC_AOT" \
        -Xlog:class+load:file="$classload_log" \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$MONOLITHIC_CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
    merged)
      "$JAVA_MERGED_BIN" -XX:AOTCache="$MERGED_AOT" \
        -Xlog:class+load:file="$classload_log" \
        --add-opens java.base/java.io=ALL-UNNAMED \
        --add-opens java.base/java.lang=ALL-UNNAMED \
        --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
        --add-opens java.base/java.time=ALL-UNNAMED \
        --add-opens java.base/java.time.chrono=ALL-UNNAMED \
        --add-opens java.base/java.util=ALL-UNNAMED \
        -cp "$CP" "$MAIN" "$op" "$WORK_DIR"
      ;;
  esac

  printf "  %-16s | %-6s | %8s | %8s\n" \
    "$op" "$mode" \
    "$(awk '/source: file:/{count++} END{print count+0}' "$classload_log")" \
    "$(awk '/source: shared object[s]? file/{count++} END{print count+0}' "$classload_log")"
}

log "Running Commons Configuration workload RUNS=$RUNS"
for RUN_IDX in $(seq 1 "$RUNS"); do
  for op in "${OPS[@]}"; do
    no_ms=$(measure_ms "$op" "no" run_mode_op "no" "$op")
    update_stats "${op}|no" "$no_ms"
    monolithic_ms=$(measure_ms "$op" "monolithic" run_mode_op "monolithic" "$op")
    update_stats "${op}|monolithic" "$monolithic_ms"
    merged_ms=$(measure_ms "$op" "merged" run_mode_op "merged" "$op")
    update_stats "${op}|merged" "$merged_ms"
  done
done

print_latex_rows() {
  local project="$1"
  local n="${#OPS[@]}"
  local i=0
  local tex_file="$WORK_DIR/latex-rows.tex"
  echo "\\multirow{${n}}{*}{${project}}" > "$tex_file"
  for op in "${OPS[@]}"; do
    local m_mono m_merged s_mono s_merged speedup w
    m_mono=$(mean_for_key "${op}|monolithic")
    m_merged=$(mean_for_key "${op}|merged")
    s_mono=$(stddev_for_key "${op}|monolithic")
    s_merged=$(stddev_for_key "${op}|merged")
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

print_summary
print_latex_rows "commons-configuration"

echo
log "Class-load source summary per workload"
sep
printf "  %-16s | %-6s | %8s | %8s\n" "Operation" "Mode" "file:" "shared"
for op in "${OPS[@]}"; do
  print_class_load_row "no" "$op"
  print_class_load_row "monolithic" "$op"
  print_class_load_row "merged" "$op"
  echo "--------------------------------"
done

# commons-compress AOT cache experiment

Steps to run once `tree.aot` is in hand (produced by `orchestrate-combine.sh`).
All commands run from **`commons-compress-experiment/`**.

---

## Prerequisites

- Java 24+ with AOT cache support
- Maven 3.9+, Python 3
- `aotp` jar at `~/Desktop/chains/aotp/aotp/target/aotp-0.0.1-SNAPSHOT.jar`
  (override with `AOTP_JAR=...`)

---

## Step 1 — Build the benchmark app

```bash
cd benchmark && mvn package && cd ..
```

Produces `benchmark/target/original-benchmark-1.0-SNAPSHOT.jar`.

---

## Step 2 — Record runtime class loads

```bash
./record-runtime-classes.sh
```

Runs the benchmark with `-Xlog:class+load=info -XX:AOTCache=tree.aot`.
Writes to `../aot-analysis/commons-compress/runtime/`:

| File | Contents |
|---|---|
| `tree-aot.classes` | Classes served from `tree.aot` at runtime |
| `tree-fs.classes` | Classes loaded from the filesystem (not in cache — hidden/generated) |

---

## Step 3 — Analyse (source class lists + treemap)

```bash
./analyse.sh
```

- Extracts per-JAR class lists → `../aot-analysis/commons-compress/source/`
- Classifies and compares AOT-served vs filesystem-loaded
- Generates treemap → `../aot-analysis/commons-compress/set-operations/viz.tex`
  and copies to `~/Desktop/papers/aotcache/figures/viz.tex`

---

## Step 4 — Coverage funnel

```bash
../aot-analysis/coverage.sh ../aot-analysis/commons-compress/coverage.conf
```

Dumps per-artifact `cache.aot` class lists via `aotp` → `../aot-analysis/commons-compress/per-cache/`
and prints:

```
Module              Source  cache.aot     %  tree.aot     %
commons-compress       589        XXX   XX%       XXX   XX%
commons-lang3          421        XXX   XX%       XXX   XX%
commons-codec          136        XXX   XX%       XXX   XX%
commons-io             387        XXX   XX%       XXX   XX%
TOTAL                 1533        XXX   XX%       XXX   XX%
```

---

## Analysis directory layout

```
../aot-analysis/commons-compress/
  source/         JAR-extracted class lists (one per dependency)
  per-cache/      aotp dumps of each cache.aot and tree.aot
  runtime/        class+load output from the benchmark run
  set-operations/ treemap inputs and intersection files
```

---

## AOT Analysis

### A1 — Extract per-cache class lists

```bash
../aot-analysis/record.sh -o ../aot-analysis/commons-compress/per-cache \
  commons-compress/cache.aot \
  commons-compress-deps/commons-lang/cache.aot \
  commons-compress-deps/commons-codec/cache.aot \
  commons-compress-deps/apache-commons-io/cache.aot \
  tree.aot
```

### A2 — Classify tree.aot (JDK / Hidden / App)

```bash
../aot-analysis/classify.sh \
  -o ../aot-analysis/commons-compress/first-classification \
  ../aot-analysis/commons-compress/per-cache/tree.classes
```

Writes `tree-jdk.classes`, `tree-hidden.classes`, `tree-app.classes` into `first-classification/`.

### A3 — Extract source class lists

```bash
BASE=$(cd .. && pwd)
../aot-analysis/source.sh \
  -o ../aot-analysis/commons-compress/source \
  "commons-compress:$BASE/commons-compress-experiment/commons-compress/target/classes" \
  "commons-lang3:$BASE/commons-compress-experiment/commons-compress-deps/commons-lang/target/classes" \
  "commons-codec:$BASE/commons-compress-experiment/commons-compress-deps/commons-codec/target/classes" \
  "commons-io:$BASE/commons-compress-experiment/commons-compress-deps/apache-commons-io/target/classes"
```

### A4 — Per-dependency contribution funnel

Shows, for each dependency: how many source classes made it into (a) the module's own `cache.aot` and (b) the final `tree-app.classes`. Classes missing from the last stage are candidates for investigation.

```bash
../aot-analysis/funnel.sh \
  ../aot-analysis/commons-compress/first-classification/tree-app.classes \
  "commons-compress:../aot-analysis/commons-compress/source/commons-compress.classes:../aot-analysis/commons-compress/per-cache/commons-compress.classes" \
  "commons-lang3:../aot-analysis/commons-compress/source/commons-lang3.classes:../aot-analysis/commons-compress/per-cache/commons-lang.classes" \
  "commons-codec:../aot-analysis/commons-compress/source/commons-codec.classes:../aot-analysis/commons-compress/per-cache/commons-codec.classes" \
  "commons-io:../aot-analysis/commons-compress/source/commons-io.classes:../aot-analysis/commons-compress/per-cache/apache-commons-io.classes"
```

---

## Ad-hoc utilities

```bash
# Classify a class list (JDK / Lambda / Hidden / App breakdown)
../aot-analysis/classify.sh ../aot-analysis/commons-compress/runtime/tree-aot.classes

# Compare two class lists
../aot-analysis/compare.sh \
  ../aot-analysis/commons-compress/per-cache/tree.classes \
  ../aot-analysis/commons-compress/runtime/tree-aot.classes

# Dump classes in any .aot file
java -jar "$AOTP_JAR" tree.aot --list-classes | wc -l
```

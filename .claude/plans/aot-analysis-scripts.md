# Plan: AOT Class-List Recording, Set Operations & Sankey Visualization

## Context

We have multiple `.aot` cache files across experiments (pdfbox, mcs, graphhopper, jetty, recursively-updating). We want a reusable set of scripts that:

1. Dump (record) class lists from `.aot` files into sorted text files ("SBOMs")
2. Perform set operations (intersection, difference, union, summary) on those files to compare caches
3. Classify classes by type (JDK, lambda, hidden, anonymous inner, app/library)
4. Generate a Sankey diagram showing a combined cache (`tree.aot`) broken down by contributing sub-cache and class type
5. Confirm at runtime which classes are actually served from the AOT cache

### aotp vs -Xlog: static vs runtime ground truth

`aotp` (third-party tool at `~/Desktop/chains/aotp/target/aotp-0.0.1-SNAPSHOT.jar`) statically inspects the binary `.aot` file and reports what classes are **stored** in it. This is useful for exploring cache contents without running the application, but it cannot tell you whether those classes are actually loaded from the cache at runtime.

The definitive confirmation is `-Xlog:class+load=info`: when the JVM loads a class from the AOT cache, the log line ends with `source: shared objects file`. If it falls back to loading from a jar, it shows the jar path instead.

**Usage pattern (already established in `check-aot.sh`):**
```bash
java -Xlog:class+load=info -XX:AOTCache=cache.aot -cp app.jar MainClass 2>&1 \
  | grep "shared objects file"   # classes actually served from AOT cache
```

Both approaches are complementary:
- Use `aotp` (→ `.classes` files) to explore and diff cache contents offline
- Use `-Xlog` to confirm at runtime which of those classes are actually used

---

## Directory

Create **`aot-analysis/`** at the project root with 8 files (7 bash scripts + 1 Python script).

Generated `.classes` files are placed **next to their source `.aot`** (same directory, `.aot` → `.classes`), not inside `aot-analysis/`.

---

## Scripts

All bash scripts follow existing project conventions:
- `#!/bin/bash` + `set -euo pipefail`
- `cd "$(dirname "${BASH_SOURCE[0]}")"` at top
- `log()` in green with timestamp
- `AOTP_JAR` env var with default `$HOME/Desktop/chains/aotp/target/aotp-0.0.1-SNAPSHOT.jar`
- `realpath` to resolve argument paths before `cd` changes the working dir

---

### `record.sh <file.aot> [file2.aot ...]`
- **Input:** one or more `.aot` file paths (uses `aotp --list-classes` — static)
- **Output:** for each input, a sorted plain-text file (`<stem>.classes` next to the `.aot`), one JVM class name per line e.g. `org/apache/pdfbox/pdmodel/PDDocument`
- Checks the aotp jar exists once up-front; checks each `.aot` exists before processing
- Loops over `"$@"`; logs class count per file

---

### `intersection.sh <a.classes> <b.classes>`
- **Input:** two pre-recorded `.classes` files (sorted — guaranteed by `record.sh`)
- **Output:** sorted list of class names in **both** A and B (stdout)
- Uses `comm -12`

### `difference.sh <a.classes> <b.classes>`
- **Input:** two pre-recorded `.classes` files
- **Output:** sorted list of class names in **A but not B** (A − B) (stdout)
- Uses `comm -23`

### `union.sh <a.classes> <b.classes>`
- **Input:** two pre-recorded `.classes` files
- **Output:** sorted, deduplicated union (stdout)
- Uses `sort -mu` (efficient merge on pre-sorted inputs)

### `compare.sh <a.classes> <b.classes>`
- **Input:** two pre-recorded `.classes` files
- **Output:** summary table (stdout):
  ```
  A:                   path/to/a.classes
  B:                   path/to/b.classes

  Classes in A:        1234
  Classes in B:        1456
  Union:               1600
  Intersection:        1090
  Only in A:            144
  Only in B:            366
  ```
- Three `comm` calls (`-12`, `-23`, `-13`); union count derived arithmetically

---

### `classify.sh <file.classes>`
- **Input:** a pre-recorded `.classes` file (static, from `aotp`)
- **Output:** classification breakdown (stdout):
  ```
  Category        Count   Pct
  JDK              1234   48%
  Lambda             42    2%
  Hidden (other)     18    1%
  Anonymous inner   145    6%
  App/Library      1123   43%
  Total            2562
  ```
- **Heuristics** (JVM internal format uses `/` as separator; checks applied in order — first match wins):
  1. **JDK** — starts with any of: `java/`, `javax/`, `sun/`, `jdk/`, `com/sun/`, `com/oracle/`, `org/xml/`, `org/w3c/`, `org/ietf/`, `org/omg/`
     _(Captures all JDK classes including their named/anonymous inners, e.g. `java/util/HashMap$Entry`)_
  2. **Lambda** — contains `$$Lambda` (covers both old `ClassName$$Lambda$N` and JDK-17+ hidden-lambda `ClassName$$Lambda/0x…`)
  3. **Hidden (non-lambda)** — contains `/0x` but did NOT match Lambda; runtime hidden classes for method handles, invokedynamic, etc.
  4. **Anonymous inner** — the simple class name (part after last `/`) ends with a purely-numeric `$`-suffix, e.g. `Foo$1`, `Bar$1$2` — compiler-generated anonymous class bodies
  5. **App/Library** — everything else, including named inner classes of libraries (e.g. `org/apache/Foo$Bar`)
- Implemented with `awk` for a single-pass O(n) count; no temp files

---

### `verify.sh <aot.classes> <log-file-or-stdin>`

Runtime confirmation script — cross-checks what `aotp` reports against what `-Xlog:class+load=info` actually observed.

- **Input:**
  - `<aot.classes>` — the `.classes` file produced by `record.sh` (static, from `aotp`)
  - A `-Xlog:class+load=info` log file (or `-` to read from stdin)
- **How to produce the log:**
  ```bash
  java -Xlog:class+load=info -XX:AOTCache=cache.aot -jar app.jar ... 2>classload.log
  ```
- **Output:** summary (stdout):
  ```
  From AOT cache (runtime):     2100   (classes where log says "shared objects file")
  From filesystem (runtime):     430   (classes loaded from jars/dirs)
  In aotp list but not AOT-loaded:  80   (stored in cache but not served at runtime)
  Loaded from AOT but not in aotp:   0   (shouldn't happen — would indicate aotp gap)
  ```
- Uses `grep` + `awk` to parse the log; extracts class names from `[class,load]` lines and compares against the `.classes` file with `comm`

---

### `sankey.py <tree.classes> <sub1.classes:Label1> [sub2.classes:Label2 ...]`

Python script (stdlib + `plotly`).

- **Input:**
  - `tree.classes` — the combined/merged cache class list (from `aotp`)
  - Two or more `<path.classes>:Label` pairs — individual sub-caches in order earliest→latest
- **Output:** `sankey.html` written next to `tree.classes` — opens in any browser

- **Attribution logic:** for each class in `tree.classes`, assign it to the first sub-cache in argument order that contains it. Classes in none → "Unknown" bucket.

- **Classification:** same 5-category heuristics as `classify.sh`.

- **Sankey structure (two-layer flow):**
  ```
  tree.aot  →  [sub, add, mul, math, Unknown]  →  [JDK, Lambda, Hidden, Anon Inner, App/Library]
  ```
  - Layer 1 → Layer 2: class count attributed to each sub-cache
  - Layer 2 → Layer 3: per-sub-cache breakdown by class type

- Uses `plotly` (install: `pip install plotly`); falls back to a plain HTML table if not available

---

## Files to Create

| File | Type |
|------|------|
| `aot-analysis/record.sh` | bash |
| `aot-analysis/intersection.sh` | bash |
| `aot-analysis/difference.sh` | bash |
| `aot-analysis/union.sh` | bash |
| `aot-analysis/compare.sh` | bash |
| `aot-analysis/classify.sh` | bash |
| `aot-analysis/verify.sh` | bash |
| `aot-analysis/sankey.py` | Python |

---

## Verification

```bash
# 1. Make executable
chmod +x aot-analysis/*.sh

# 2. Record all four caches in the recursive chain at once (static, via aotp)
./aot-analysis/record.sh \
    recursively-updating-aot-cache/sub/sub.aot \
    recursively-updating-aot-cache/add/add.aot \
    recursively-updating-aot-cache/mul/mul.aot \
    recursively-updating-aot-cache/math/math.aot \
    recursively-updating-aot-cache/tree-combined.aot

# 3. Verify sorted
sort -c recursively-updating-aot-cache/math/math.classes && echo "sorted OK"

# 4. sub ⊆ math — difference should be empty
./aot-analysis/difference.sh \
    recursively-updating-aot-cache/sub/sub.classes \
    recursively-updating-aot-cache/math/math.classes
# expect: no output

# 5. What did the math step add?
./aot-analysis/difference.sh \
    recursively-updating-aot-cache/math/math.classes \
    recursively-updating-aot-cache/mul/mul.classes

# 6. Full comparison: single vs tree in pdfbox-experiment
./aot-analysis/record.sh pdfbox-experiment/single.aot pdfbox-experiment/tree.aot
./aot-analysis/compare.sh pdfbox-experiment/single.classes pdfbox-experiment/tree.classes

# 7. Classify math.classes
./aot-analysis/classify.sh recursively-updating-aot-cache/math/math.classes

# 8. Runtime confirmation via -Xlog (user runs this; output is piped to verify.sh)
#    java -Xlog:class+load=info -XX:AOTCache=recursively-updating-aot-cache/math/math.aot \
#         -jar math/target/math-1.0-SNAPSHOT.jar 2>classload.log
./aot-analysis/verify.sh \
    recursively-updating-aot-cache/math/math.classes \
    classload.log

# 9. Generate Sankey for tree-combined.aot
python3 aot-analysis/sankey.py \
    recursively-updating-aot-cache/tree-combined.classes \
    recursively-updating-aot-cache/sub/sub.classes:sub \
    recursively-updating-aot-cache/add/add.classes:add \
    recursively-updating-aot-cache/mul/mul.classes:mul \
    recursively-updating-aot-cache/math/math.classes:math
# Produces recursively-updating-aot-cache/sankey.html

# 10. Error handling
AOTP_JAR=/nonexistent.jar ./aot-analysis/record.sh recursively-updating-aot-cache/sub/sub.aot
# must print error and exit nonzero
```

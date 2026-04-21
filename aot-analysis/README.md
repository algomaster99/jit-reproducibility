# AOT Funnel Values

This README captures the current funnel values from the generated analysis artifacts in `aot-analysis/`.

Funnel definition per module:

`source -> source ∩ cache.aot -> source ∩ tree-app`

Columns:

- `source`: total classes in the module's source JAR or `target/classes`
- `in cache`: classes from that source that appear in the module's own `cache.aot`
- `in tree`: classes from that source that survive into final `tree-app.classes`

## commons-compress

| Module | Source | In Cache | In Tree |
|---|---:|---:|---:|
| commons-compress | 589 | 514 | 514 |
| commons-lang3 | 421 | 380 | 380 |
| commons-codec | 136 | 116 | 116 |
| commons-io | 387 | 323 | 325 |
| **TOTAL** | **1533** | **1333** | **1335** |

Note: `commons-io` has 2 classes that appear in the final tree but not in `per-cache/apache-commons-io.classes`:

- `org/apache/commons/io/input/ChecksumInputStream$1`
- `org/apache/commons/io/output/UnsynchronizedByteArrayOutputStream$1`

## pdfbox

| Module | Source | In Cache | In Tree |
|---|---:|---:|---:|
| io | 20 | 19 | 20 |
| fontbox | 192 | 173 | 178 |
| pdfbox | 764 | 616 | 617 |
| tools | 38 | 32 | 31 |
| pdfbox-jbig2 | 95 | 59 | 59 |
| commons-io | 398 | 329 | 1 |
| commons-logging | 28 | 9 | 9 |
| bcprov | 4630 | 906 | 1008 |
| bcutil | 5241 | 775 | 1035 |
| bcpkix | 6172 | 1080 | 1141 |
| **TOTAL** | **17578** | **3998** | **4099** |

## Current Inputs

These values were taken from the current checked-in/generated artifacts:

- `commons-compress`: `aot-analysis/commons-compress/source/`, `per-cache/`, and `first-classification/tree-app.classes`
- `pdfbox`: `aot-analysis/pdfbox/source/`, `per-cache/`, and `first-classification/tree-app.classes`

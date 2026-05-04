# Commons Configuration AOT Experiment Plan

## Context

This picks up from the commons-compress experiment. The goal is to run the same
single.aot vs tree.aot startup-time benchmark for Apache Commons Configuration 2.x.
During the commons-compress and PDFBox experiments we learned important lessons about
workload design — recorded below — that should shape how this experiment is set up.

---

## Workload Design Lessons (from this conversation)

These findings should apply to every future experiment:

### Why single.aot almost always wins

`single.aot` (trained via `-XX:AOTMode=record` on one real invocation) captures:
1. Class-loading data for the classes it saw
2. JIT-compiled machine code for the hot paths it exercised (including JDK core)

`tree.aot` (merged from per-module test-suite caches) captures:
1. Class-loading data for the full dependency tree (~7000–8000 classes)
2. JIT-compiled code from unit tests — but all classes load **eagerly** per invocation

The structural overhead: tree.aot loads all ~8000 cached classes on every startup;
single.aot loads ~1000–2000. That ~6000-class gap costs more than saving a few hundred
cold file loads, so single.aot wins even for operations it was never trained on.

### When tree.aot can win

tree.aot beats single.aot only when **both** hold:
- single.aot's training op has LOW class overlap with the tested op
- tree.aot's test-suite training produced BETTER JIT-compiled code for those paths
  than one recording run could

Observed: PDFBox render (tree=1073ms, single=1128ms) when single was trained on fromtext.
The test suite ran many render tests, warming JIT deeply; one fromtext run did not.

### Training workload selection rule

Train single.aot on the operation with the **smallest class overlap** with the rest of
the benchmark ops. This maximises cold-file-load misses for single.aot on the other
ops, giving tree.aot's broader JIT coverage the best chance.

### When it actually works: commons-compress reference result

With single.aot trained on `gzip-roundtrip` (2026-05-04):

```
Operation        | no-med  | single-med | tree-med
zip-roundtrip    |  169.9  |    160.9   |   126.3  ← tree wins (+34ms vs single)
tar-roundtrip    |  125.7  |    116.0   |    94.7  ← tree wins (+21ms vs single)
gzip-roundtrip   |  102.8  |     53.8   |    82.0  ← single wins (trained on this)
list-archives    |  172.4  |    185.8   |   132.6  ← tree wins (+53ms vs single)
```

**tree.aot won 3 out of 4 ops.** The reason this worked where PDFBox didn't:
- commons-compress is a smaller library → tree.aot has fewer total cached classes
  → the eager-load overhead is proportionally lower relative to total startup time
- gzip-roundtrip loads so few classes that single.aot's JDK-core JIT advantage
  barely helps on zip/tar/list ops with many novel class loads

**Design rule refined:** The training op must be small enough that single.aot's
JIT-compiled JDK core does NOT carry over effectively to the benchmark ops.
For a library like commons-compress (~100ms total startup), gzip-roundtrip achieves
this. For a heavy library like PDFBox (~400–1200ms), even a minimal training op
carries enough JDK-core JIT to win everywhere.

---

## Commons Configuration Experiment

### Library

Apache Commons Configuration **2.14.0** (latest stable as of May 2026).
Source: https://github.com/apache/commons-configuration/tree/rel/commons-configuration-2.14.0

### Core dependencies (to clone and cache)

Run `mvn dependency:tree` on the cloned repo to verify exact versions, but expected:

| Artifact | Expected version |
|---|---|
| commons-lang3 | 3.20.0 |
| commons-text | 1.15.0 |
| commons-logging | 1.3.6 |

Note: commons-text is the most interesting dep — it provides `StringSubstitutor`
used by commons-configuration's variable interpolation. It exercises classes not
loaded by a basic properties read, making it good for divergence.

Exclude optional deps (commons-beanutils, vavr, YAML libs) unless they are pulled
in transitively by the workload ops we choose.

### Benchmark operations (proposed)

| Op | API exercised | Classes loaded |
|---|---|---|
| `properties-read` | `PropertiesConfiguration` | Only AbstractConfiguration + properties I/O |
| `xml-read` | `XMLConfiguration` | + JAXP/DOM parser, XML-specific config classes |
| `composite-read` | `CompositeConfiguration` + `ConfigurationBuilder` | + builder pattern, event system |
| `interpolation` | Variable substitution (`${var}` in values) | + commons-text `StringSubstitutor` |

**single.aot training op**: `properties-read`
- Loads only `PropertiesConfiguration` and the base `AbstractConfiguration` hierarchy
- xml-read (DOM parser), composite-read (builder classes), interpolation (StringSubstitutor)
  will all have cold class loads, giving tree.aot the widest possible gap.

### Directory layout

Follow commons-compress-experiment exactly:

```
commons-configuration-experiment/
├── benchmark/                      # new Maven project (groupId: dev.configexp)
│   ├── pom.xml                     # shade plugin, original jar, deps
│   └── src/main/java/dev/configexp/Main.java
├── commons-configuration/          # cloned upstream (tag 2.11.0)
├── commons-configuration-deps/
│   ├── commons-lang/               # cloned (use the same submodule as in commons-compress-experiment and both versions are 3.20.0)
│   ├── commons-text/               # cloned — new vs compress!
│   └── commons-logging-workload/   # workload jar (same pattern as pdfbox-deps)
├── single-aot-deps/                # plain JARs downloaded by create-single-aot.sh
├── workload-tmp/
├── single.aot / single.aotconf
├── tree.aot
└── *.sh
```

### Scripts to create

All follow the commons-compress template exactly. Key differences:

**create-single-aot.sh**
- Record only `properties-read`
- Comment: "loads only PropertiesConfiguration — no DOM parser, no StringSubstitutor"

**orchestrate-combine.sh**
- Base AOT: `commons-configuration/cache.aot`
- Merge inputs: all 4 per-artifact cache.aot files
- Classpath: target/classes directories (not JARs)

**workload-timed.sh**
- `OPS=("properties-read" "xml-read" "composite-read" "interpolation")`
- `SINGLE_CP` uses JAR files from single-aot-deps/ (same pattern as commons-compress)
- `CP` uses target/classes directories

### benchmark/Main.java sketch

```java
package dev.configexp;

import org.apache.commons.configuration2.*;
import org.apache.commons.configuration2.builder.fluent.*;
import org.apache.commons.configuration2.interpol.*;

public class Main {
    public static void main(String[] args) throws Exception {
        String cmd = args[0]; Path workDir = Paths.get(args[1]);
        switch (cmd) {
            case "prepare"        -> prepare(workDir);
            case "properties-read"-> propertiesRead(workDir);
            case "xml-read"       -> xmlRead(workDir);
            case "composite-read" -> compositeRead(workDir);
            case "interpolation"  -> interpolation(workDir);
        }
    }
    // prepare: write sample .properties and .xml files to workDir
    // propertiesRead: load workDir/config.properties via PropertiesConfiguration
    // xmlRead: load workDir/config.xml via XMLConfiguration
    // compositeRead: CompositeConfiguration combining both sources
    // interpolation: PropertiesConfiguration with ${var} references, force resolution
}
```

### Step-by-step execution

1. Clone commons-configuration @ 2.14.0 into experiment dir
2. Clone each dep into commons-configuration-deps/
3. Instrument the test suite to use -XX:AOTCacheOutput=cache.aot with -Ptree-merge profile
3. Run `mvn test` on each dep to generate cache.aot (user-run, per memory)
4. Create benchmark/ Maven project, `mvn package`
5. Run `create-single-aot.sh` (user-run)
6. Run `orchestrate-combine.sh`
7. Run `workload-timed.sh`
8. Analyse class-load logs to verify single.aot misses xml-read and interpolation


---

## Open questions before starting

- Verify exact transitive deps via `mvn dependency:tree` on the cloned repo
- Confirm commons-text is not pulled in by properties-read (it shouldn't be, but verify
  via `-Xlog:class+load` on a test run of properties-read before finalising the training op)
- Check if commons-logging needs a workload-jar wrapper (like pdfbox-deps pattern)
  or if its target/classes can be used directly

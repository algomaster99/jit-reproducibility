# Distributed AOT Cache Model for PDFBox

## Context

The goal is to establish a **distributed AOT cache model** analogous to how Maven distributes JARs.
Each Maven artifact (`.jar` + `.pom`) gains a companion `.aot` file — a pre-generated AOT cache for
that library. These per-artifact caches are then **merged** into a single `tree.aot` for production
use with `pdfbox-app`, mirroring how JARs are placed on a classpath.

**One-step AOT workflow** (used throughout):
```bash
# create binary cache in a single JVM run (no intermediate .aotconf)
java -XX:AOTCacheOutput=cache.aot -cp <classpath> <MainClass or -version>
```

---

## Execution model — step by step with user review

This plan is executed **one dependency at a time**, with an explicit pause after each
configuration step so the user can drive the AOT cache generation themselves. Do **not**
batch-run multiple dependencies: each one is a separate, reviewable unit.

For every missing dependency the loop is:

1. **Clone** the upstream source into `pdfbox-experiment/pdfbox-deps/`.
2. **Configure** the build (branch/tag, build flags, scripts) and verify the JAR builds locally.
3. **PAUSE for user review.** Stop here and let the user generate the per-artifact AOT cache
   themselves. The user runs the recording command and inspects the result.
4. **If the cache was created successfully** → continue to the next dependency.
5. **If the cache could not be created** (the project's own tests cannot be coaxed into
   loading enough classes, or the build is broken on Java 25) → fall back to the
   **workload pattern** (see below). Pause again after the workload is in place so the user
   can re-run the AOT generation against the workload.
6. Once all per-artifact caches exist, regenerate `tree.aot` and run verification.

The agent driving this plan must **stop and wait** between each numbered step above. Do not
proceed past a PAUSE marker without explicit user confirmation.

### Workload-pattern fallback

When a dependency's own test suite or build cannot produce an AOT cache (broken build,
no test runner, Gradle quirks, JDK incompatibility, etc.), follow the same approach already
used in `dependencies/dropwizard-experiment/`:

- Create a small standalone Maven project under `pdfbox-experiment/pdfbox-deps/<dep>-workload/`.
- Add **only** the target dependency to its `pom.xml` (pulling published JARs from Maven Central).
- Write a tiny `WorkloadApplication.java` whose `main()` exercises the public API of the
  dependency enough to load the classes that matter (instantiate the main types, call a
  representative method or two).
- Package as a fat jar via `maven-shade-plugin`.
- Run it under `-XX:AOTCacheOutput=cache.aot` to record the cache in one shot.

Reference implementation: `dependencies/picocli-experiment/` . The
same shape — `pom.xml` + `WorkloadApplication.java` + `cache.aot` — applies here.

---

## Current State

Location: `pdfbox-experiment/`

| Cache | Path | Status |
|---|---|---|
| pdfbox-io | `pdfbox/io/cache.aot` | ✓ exists |
| fontbox | `pdfbox/fontbox/cache.aot` | ✓ exists |
| xmpbox | `pdfbox/xmpbox/cache.aot` | ✓ exists |
| pdfbox | `pdfbox/pdfbox/cache.aot` | ✓ exists |
| preflight | `pdfbox/preflight/cache.aot` | ✓ exists |
| pdfbox-tools | `pdfbox/tools/cache.aot` | ✓ exists |
| pdfbox-examples | `pdfbox/examples/cache.aot` | ✓ exists |
| jbig2-imageio | `pdfbox-deps/pdfbox-jbig2/cache.aot` | ✓ exists |
| commons-io | `pdfbox-deps/apache-commons-io/cache.aot` | ✓ exists |
| **bcprov-jdk18on** | `pdfbox-deps/bc-java/prov/cache.aot` | **MISSING** |
| **bcutil-jdk18on** | `pdfbox-deps/bc-java/util/cache.aot` | **MISSING** |
| **bcpkix-jdk18on** | `pdfbox-deps/bc-java/pkix/cache.aot` | **MISSING** |
| **commons-logging** | `pdfbox-deps/commons-logging/cache.aot` | **MISSING** |

picocli (4.7.7) is **excluded** — bytecode version 49 (Java 5), automatically skipped by JVM.

Already in place:
- `build-m2.sh` — populates `local-repo/` with JAR+POM+AOT for all 13 artifacts.
- `orchestrate-combine-4.sh` — merges all per-artifact caches into `tree.aot`. References
  the four missing caches above; will fail until they exist.

---

## Dependency Inventory

From `pdfbox-app:3.0.7` dependency tree (deduped, test-scope excluded):

```
pdfbox-io:3.0.7          ← from apache/pdfbox submodule
fontbox:3.0.7            ← from apache/pdfbox submodule
xmpbox:3.0.7             ← from apache/pdfbox submodule
pdfbox:3.0.7             ← from apache/pdfbox submodule
preflight:3.0.7          ← from apache/pdfbox submodule
pdfbox-tools:3.0.7       ← from apache/pdfbox submodule
pdfbox-examples:3.0.7    ← from apache/pdfbox submodule
jbig2-imageio:3.0.4      ← pdfbox-deps/pdfbox-jbig2
commons-io:2.21.0        ← pdfbox-deps/apache-commons-io
bcprov-jdk18on:1.83      ← bcgit/bc-java  (to clone)
bcutil-jdk18on:1.83      ← bcgit/bc-java  (to clone)
bcpkix-jdk18on:1.83      ← bcgit/bc-java  (to clone)
commons-logging:1.3.5    ← apache/commons-logging  (to clone)
```

---

## Implementation Plan

### Dependency A — BouncyCastle (bcprov / bcutil / bcpkix)

#### A.1 Clone

bc-java uses tag format `r1rv<NN>` for release `1.<NN>`, so `1.83` → tag `r1rv83`.

```bash
cd pdfbox-experiment
git clone https://github.com/bcgit/bc-java.git \
  --branch r1rv83 --depth 1 pdfbox-deps/bc-java
```

If the tag does not exist, list available tags with `git ls-remote --tags
https://github.com/bcgit/bc-java.git 'r1rv8*'` and pick the closest match.

#### A.2 Configure / Build

bc-java is a **Gradle** project (not Maven). The Maven `mvn package -pl prov,util,pkix`
command from earlier drafts of this plan does not apply.

```bash
cd pdfbox-experiment/pdfbox-deps/bc-java
./gradlew -p prov jar
./gradlew -p util jar
./gradlew -p pkix jar
```

This produces JARs under `prov/build/libs/`, `util/build/libs/`, `pkix/build/libs/`.
Confirm each JAR exists before proceeding.

#### A.3 PAUSE — user generates AOT caches

Stop here. The user will attempt to generate the three per-module caches. The intended
one-step command, run from `pdfbox-experiment/pdfbox-deps/bc-java/`, is:

```bash
# bcprov — exercise via Gradle test task with AOT recording in argLine
./gradlew -p prov test \
  -Dtest.jvmargs="-XX:AOTCacheOutput=$(pwd)/prov/cache.aot"
# repeat for util and pkix
```

(Exact Gradle property name for forking JVM args may need adjustment — `test.jvmargs` vs
`org.gradle.jvmargs` vs editing `build.gradle` directly. The user decides which works.)

Expected outputs:
- `pdfbox-deps/bc-java/prov/cache.aot`
- `pdfbox-deps/bc-java/util/cache.aot`
- `pdfbox-deps/bc-java/pkix/cache.aot`

**Do not proceed past this pause without user confirmation.**

#### A.4 Fallback — workload project (only if A.3 failed)

If the Gradle test task cannot be wired up to record an AOT cache, build a workload
project under `pdfbox-experiment/pdfbox-deps/bc-java-workload/` following the
`dependencies/dropwizard-experiment/` shape:

- `pom.xml` with `bcprov-jdk18on:1.83`, `bcutil-jdk18on:1.83`, `bcpkix-jdk18on:1.83`
  as dependencies; shade plugin to build a fat jar.
- `src/main/java/com/example/WorkloadApplication.java` whose `main()` exercises
  representative API surface from each module:
  - bcprov → instantiate a `BouncyCastleProvider`, run an AES encrypt/decrypt round-trip
  - bcutil → ASN.1 encode/decode of a small structure
  - bcpkix → build a self-signed `X509Certificate` via `JcaX509v3CertificateBuilder`
- `mvn package`, then:
  ```bash
  java -XX:AOTCacheOutput=cache.aot -jar target/bc-java-workload-1.0-SNAPSHOT.jar
  ```

Because all three modules are exercised in one JVM run, the workload produces a
**single** `cache.aot`. This means we will need to either:
  - keep three separate workloads (one per module) and produce three caches, **or**
  - accept one combined `bc-java-workload/cache.aot` and update `orchestrate-combine-4.sh`
    + `build-m2.sh` to point all three BC artifacts at the same cache file.

Pause again here for the user to pick the approach before any script edits land.

---

### Dependency B — commons-logging

#### B.1 Clone

```bash
cd pdfbox-experiment
git clone https://github.com/apache/commons-logging.git \
  --branch rel/commons-logging-1.3.5 --depth 1 pdfbox-deps/commons-logging
```

#### B.2 Configure / Build

commons-logging is a Maven project:

```bash
cd pdfbox-experiment/pdfbox-deps/commons-logging
mvn package -DskipTests
```

Confirm `target/commons-logging-1.3.5.jar` exists.

#### B.3 PAUSE — user generates AOT cache

Stop here. The intended command is:

```bash
cd pdfbox-experiment/pdfbox-deps/commons-logging
mvn test -Dsurefire.argLine="-XX:AOTCacheOutput=$(pwd)/cache.aot"
```

Expected output: `pdfbox-deps/commons-logging/cache.aot`.

**Do not proceed past this pause without user confirmation.**

#### B.4 Fallback — workload project (only if B.3 failed)

Build a workload under `pdfbox-experiment/pdfbox-deps/commons-logging-workload/`:

- `pom.xml` with `commons-logging:commons-logging:1.3.5`, shade plugin for fat jar.
- `WorkloadApplication.java` whose `main()` calls
  `LogFactory.getLog(WorkloadApplication.class).info("warmup")` and a couple of other
  level methods to ensure `LogFactory`, `LogFactoryImpl`, `Jdk14Logger` etc. load.
- `mvn package`, then `java -XX:AOTCacheOutput=cache.aot -jar target/...jar`.
- Symlink or copy the resulting cache to `pdfbox-deps/commons-logging/cache.aot` so the
  existing `orchestrate-combine-4.sh` and `build-m2.sh` paths keep working unmodified.

---

### Step C — Regenerate `tree.aot` and verify

Only after **all four** per-artifact caches exist:

```bash
cd pdfbox-experiment
./orchestrate-combine-4.sh        # merges everything into tree.aot
./build-m2.sh                     # populates local-repo/ with JAR+POM+AOT
```

Then verify:

1. `tree.aot` exists and is non-empty.
2. Spot-check that BouncyCastle and commons-logging classes appear in the merged cache —
   create `pdfbox/check-aot-full.sh` extending `pdfbox/check-aot-tree.sh`:

   ```
   org.bouncycastle.crypto.*     (bcprov)
   org.bouncycastle.asn1.*       (bcutil)
   org.bouncycastle.pkcs.*       (bcpkix)
   org.apache.commons.logging.*  (commons-logging)
   ```

3. Run `./workload-timed.sh` against `tree.aot` and compare startup time vs the `single.aot`
   baseline.

---

## Files to Create / Modify

| File | Status | Notes |
|---|---|---|
| `pdfbox-deps/bc-java/` | clone | Gradle project, tag `r1rv83` |
| `pdfbox-deps/commons-logging/` | clone | Maven project, tag `rel/commons-logging-1.3.5` |
| `pdfbox-deps/bc-java-workload/` | conditional | Only if A.3 fails |
| `pdfbox-deps/commons-logging-workload/` | conditional | Only if B.3 fails |
| `build-m2.sh` | exists | Already references the four missing caches |
| `orchestrate-combine-4.sh` | exists | Already references the four missing caches |
| `pdfbox/check-aot-full.sh` | create | Verification script (Step C) |

---

## End-to-end verification sequence

1. BC caches present — `pdfbox-deps/bc-java/{prov,util,pkix}/cache.aot`
2. commons-logging cache present — `pdfbox-deps/commons-logging/cache.aot`
3. `./orchestrate-combine-4.sh` produces `tree.aot` without errors
4. `./build-m2.sh` populates `local-repo/` with 13 artifacts (`.jar` + `.pom` + `.aot` each)
5. `./pdfbox/check-aot-full.sh` confirms BC + commons-logging classes in `tree.aot`
6. `./workload-timed.sh` with `tree.aot` — startup time vs `single.aot` baseline
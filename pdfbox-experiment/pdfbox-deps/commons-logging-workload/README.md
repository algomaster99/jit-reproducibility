# commons-logging AOT workload

A tiny standalone workload whose sole purpose is to produce an AOT cache for
`commons-logging:commons-logging:1.3.5` in a single JVM run.

## Why this exists (why we did not record the cache via the upstream tests)

The plan's primary path (B.3) was:

```bash
cd pdfbox-experiment/pdfbox-deps/commons-logging
mvn test -Dsurefire.argLine="-XX:AOTCacheOutput=$(pwd)/cache.aot"
```

That does not work for commons-logging for two independent reasons, both of
which are deliberate upstream build decisions:

1. **`maven-surefire-plugin` is disabled.** `pom.xml` sets
   `<skip>true</skip>` on surefire with a comment explaining that surefire
   would "mess with the Ant build" because JCL's tests put generated JCL jars
   on the classpath in several configurations. `mvn test` therefore never runs
   a single test class — surefire just prints `Tests are skipped.` and exits.

2. **The real tests run via `maven-failsafe-plugin` with
   `<reuseForks>false</reuseForks>` and many separate executions.** Each
   execution (log4j12, log4j2, slf4j, serviceloader, …) uses a different
   classpath because JCL's test suite is specifically designed to verify
   behavior under different runtime configurations. Forcing a single reused
   JVM would defeat the point of those tests, and leaving the forks alone
   means every execution writes to the same `cache.aot` path and the last
   JVM to exit wins — so the recorded working set would be whatever a single
   classpath-specific test happens to touch, not the full library.

Wrestling failsafe into a single-JVM, jacoco-disabled, argLine-augmented
configuration would mean rewriting most of the upstream pom and still leave
us with a cache whose contents depend on JVM exit order. The plan's B.4
fallback — build a trivial standalone workload that exercises `LogFactory`
and `Log` in one JVM run — is both simpler and more predictable.

## How to build and record the cache

```bash
cd pdfbox-experiment/pdfbox-deps/commons-logging-workload
mvn package
java -XX:AOTCacheOutput=cache.aot \
     -jar target/commons-logging-workload-1.0-SNAPSHOT.jar
```

The resulting `cache.aot` is the per-artifact cache for `commons-logging`
and is consumed directly by `orchestrate-combine-4.sh` and `build-m2.sh`
at `pdfbox-deps/commons-logging-workload/cache.aot`.

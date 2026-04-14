# bc-java-prov-workload

This directory holds a standalone fat-jar workload whose sole purpose is to
exercise the public API of `bcprov-jdk18on` under `-XX:AOTCacheOutput` so we
can record a per-artifact AOT cache for BouncyCastle's provider module.

## Why a workload instead of the upstream Gradle tests?

The plan's primary path (`mvn test` / `./gradlew :prov:test` with the test task
instrumented to emit an AOT cache) does **not** work for bc-java. Concretely:

1. Gradle's `Test` task uses a child classloader to load the test and its
   implementation dependencies. HotSpot's AOT cache recording only archives
   classes loaded by the boot, platform, and application classloaders — any
   class the Gradle test worker resolves through its child loader is invisible
   to the recorder.
2. The resulting `cache.aot` therefore contained **zero** `org/bouncycastle/*`
   classes. I verified this with `aotp --list-classes` against the recorded
   cache: the output listed only JDK internals (`java/*`, `jdk/*`, `sun/*`).
   The BC classes were loaded — the tests pass — but they load through a
   loader HotSpot does not archive.
3. Even if we worked around the classloader by reshaping the Gradle build,
   bc-java's root `build.gradle` sets `test { forkEvery = 1 }` globally, so
   a single module's test run spawns many short-lived JVMs. Per-JVM cache
   files would each see only a slice of the loaded classes.

The upstream build is not a viable AOT recording host for this module, so we
fall back to the plan's workload pattern (section B.4 / A.4): a small fat-jar
project that depends on the published `bcprov-jdk18on` jar from Maven Central,
bundles everything with the maven-shade-plugin, and exercises the provider's
public API via a tight `main()`. Running that jar with `-XX:AOTCacheOutput`
records every BC class the workload touches directly into the application
classloader.

## What the workload exercises

`App.java` registers `BouncyCastleProvider`, then drives a representative slice
of the provider API:

- Message digests (`SHA-256`, `SHA3-256`)
- Symmetric ciphers (`AES/CBC/PKCS7Padding`, `AES/GCM/NoPadding`)
- MACs (`HmacSHA256`)
- Asymmetric keypair generation and signing (`RSA` / `SHA256withRSA`,
  `EC` / `SHA256withECDSA`)

These touch the JCE adapter classes, the low-level `org.bouncycastle.crypto.*`
engines, and enough of `org.bouncycastle.asn1.*` through key encoding to give
downstream pdfbox workloads a usefully warmed cache.

## Shade configuration note

BC's published jars are signed. The shade plugin strips `META-INF/*.SF`,
`META-INF/*.DSA`, and `META-INF/*.RSA` so the resulting uber jar is not
treated as a (now broken) signed jar at load time.

## How to record the cache

```
cd pdfbox-experiment/pdfbox-deps/bc-java-prov-workload
mvn -q package
java -XX:AOTCacheOutput=cache.aot -jar target/bc-java-prov-workload-1.0-SNAPSHOT.jar
```

The resulting `cache.aot` is consumed by `orchestrate-combine-4.sh` as one of
the per-artifact inputs to the merged `tree.aot`.

# bc-java-util-workload

This directory holds a standalone fat-jar workload whose sole purpose is to
exercise the public API of `bcutil-jdk18on` under `-XX:AOTCacheOutput` so we
can record a per-artifact AOT cache for BouncyCastle's util / ASN.1 module.

## Why a workload instead of the upstream Gradle tests?

The plan's primary path (`./gradlew :util:test` with the test task instrumented
to emit an AOT cache) does **not** work for bc-java. Concretely:

1. Gradle's `Test` task uses a child classloader to load the test classes and
   their implementation dependencies. HotSpot's AOT cache recording only
   archives classes loaded by the boot, platform, and application classloaders.
   Anything the Gradle test worker resolves through its child loader is
   invisible to the recorder.
2. The resulting `cache.aot` from `:util:test` contained **zero**
   `org/bouncycastle/*` classes when inspected with `aotp --list-classes`: the
   output listed only JDK internals. The tests passed and loaded BC classes,
   but through a loader HotSpot does not archive.
3. bc-java's root `build.gradle` sets `test { forkEvery = 1 }` globally, so a
   single module's test run spawns many short-lived JVMs — per-JVM cache files
   would each see only a slice of the loaded classes even if the classloader
   problem were fixed.

The upstream build is not a viable AOT recording host for this module, so we
fall back to the plan's workload pattern (section B.4 / A.4): a small fat-jar
project that depends on the published `bcutil-jdk18on` jar from Maven Central
(plus `bcprov-jdk18on` because `bcutil` needs a JCE provider to encode keys).

## What the workload exercises

`App.java` drives a representative slice of the bcutil public API:

- `X500Name` / `X500NameBuilder` with `BCStyle` RDNs and a DER encode/decode
  round-trip.
- Low-level ASN.1: `ASN1EncodableVector`, `ASN1Integer`,
  `ASN1ObjectIdentifier`, `DEROctetString`, `DERSequence`.
- X.509 / PKCS helper types: `SubjectPublicKeyInfo`, `PrivateKeyInfo`,
  `AlgorithmIdentifier`, `PKCSObjectIdentifiers`.
- Encoding helpers: `Hex`, `Base64`, `PemWriter` / `PemObject`.

These touch the classes pdfbox pulls in whenever it parses certificates or
key material during cert-based PDF encryption/signing.

## Shade configuration note

BC's published jars are signed. The shade plugin strips `META-INF/*.SF`,
`META-INF/*.DSA`, and `META-INF/*.RSA` so the resulting uber jar is not
treated as a (now broken) signed jar at load time.

## How to record the cache

```
cd pdfbox-experiment/pdfbox-deps/bc-java-util-workload
mvn -q package
java -XX:AOTCacheOutput=cache.aot -jar target/bc-java-util-workload-1.0-SNAPSHOT.jar
```

The resulting `cache.aot` is consumed by `orchestrate-combine-4.sh` as one of
the per-artifact inputs to the merged `tree.aot`.

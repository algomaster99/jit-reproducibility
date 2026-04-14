# bc-java-pkix-workload

This directory holds a standalone fat-jar workload whose sole purpose is to
exercise the public API of `bcpkix-jdk18on` under `-XX:AOTCacheOutput` so we
can record a per-artifact AOT cache for BouncyCastle's PKIX / CMS module.

## Why a workload instead of the upstream Gradle tests?

The plan's primary path (`./gradlew :pkix:test` with the test task instrumented
to emit an AOT cache) does **not** work for bc-java. Concretely:

1. Gradle's `Test` task uses a child classloader to load the test classes and
   their implementation dependencies. HotSpot's AOT cache recording only
   archives classes loaded by the boot, platform, and application classloaders.
   Any class the Gradle test worker resolves through its child loader is
   invisible to the recorder.
2. The resulting `cache.aot` from `:pkix:test` contained **zero**
   `org/bouncycastle/*` classes when inspected with `aotp --list-classes`: the
   output listed only JDK internals. The tests loaded and used BC classes but
   through a loader HotSpot does not archive.
3. bc-java's root `build.gradle` sets `test { forkEvery = 1 }` globally, so a
   single module's test run spawns many short-lived JVMs — per-JVM cache files
   would each see only a slice of the loaded classes even if the classloader
   problem were fixed.

The upstream build is not a viable AOT recording host for this module, so we
fall back to the plan's workload pattern (section B.4 / A.4): a small fat-jar
project that depends on the published `bcpkix-jdk18on` jar from Maven Central
(plus `bcutil-jdk18on` and `bcprov-jdk18on` as transitive runtime dependencies
that bcpkix needs to actually do PKIX work).

## What the workload exercises

`App.java` drives a representative slice of the bcpkix public API — the exact
surface area pdfbox touches when it encrypts or signs PDFs with certificates:

- `JcaX509v3CertificateBuilder` with extensions: `BasicConstraints`,
  `KeyUsage`, `ExtendedKeyUsage`, `SubjectKeyIdentifier`,
  `AuthorityKeyIdentifier`, `SubjectAlternativeName`.
- `JcaContentSignerBuilder` + `JcaX509CertificateConverter` to produce a real
  `X509Certificate` from the holder.
- `JcaPKCS10CertificationRequestBuilder` / `PKCS10CertificationRequest` for
  CSR generation and DER encoding.
- CMS signing (`CMSSignedDataGenerator`, `JcaSignerInfoGeneratorBuilder`,
  `JcaDigestCalculatorProviderBuilder`) — the PKCS#7 path pdfbox uses for
  signature dictionaries.
- CMS enveloping (`CMSEnvelopedDataGenerator`, `JceKeyTransRecipientInfoGenerator`,
  `JceCMSContentEncryptorBuilder` with 3DES) — the PKCS#7 path pdfbox uses for
  cert-based PDF encryption.

## Shade configuration note

BC's published jars are signed. The shade plugin strips `META-INF/*.SF`,
`META-INF/*.DSA`, and `META-INF/*.RSA` so the resulting uber jar is not
treated as a (now broken) signed jar at load time.

## How to record the cache

```
cd pdfbox-experiment/pdfbox-deps/bc-java-pkix-workload
mvn -q package
java -XX:AOTCacheOutput=cache.aot -jar target/bc-java-pkix-workload-1.0-SNAPSHOT.jar
```

The resulting `cache.aot` is consumed by `orchestrate-combine-4.sh` as one of
the per-artifact inputs to the merged `tree.aot`.

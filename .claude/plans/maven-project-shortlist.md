# Maven Project Shortlist

## Goal

Pick Maven-based projects for AOT/cache experiments.  
Constraints: Maven only, JDK > 5, no `module-info.java` (source or MR-JAR) anywhere in project or transitive deps, no instrumentation (no AspectJ/ByteBuddy/Javassist used at runtime).

> Note: `Automatic-Module-Name` in MANIFEST.MF is **not** a module descriptor — it does not trigger JPMS resolution and is safe.

---

## Verified Candidates

### 1. Apache Velocity Engine 2.3
- **Repo:** apache/velocity-engine
- **Build:** Maven
- **module-info:** None found in source tree or published JARs
- **Instrumentation:** None
- **Dep tree:** slf4j-api + binding, commons-lang3, commons-collections4 — all pre-JPMS
- **Workload idea:** Render a set of Velocity templates (`.vm` files) covering loops, macros, and conditionals
- **Notes:** Template rendering is hermetic (no network). Medium dep tree overlaps somewhat with commons-configuration.

---

## Rejected / Deferred

| Project | Reason |
|---------|--------|
| `jetty` | `module-info.java` + `--patch-module` required; AOT dump incompatible |
| `gson`, `jackson-*` | JPMS/module descriptors in newer versions (deferred) |
| Apache POI 4.1.x | MR-JAR embeds `module-info.class` in `META-INF/versions/9`; XmlBeans dep also has JPMS descriptors |
| jsoup | Only dep is `jspecify` (annotation-only, zero runtime classes); `com.google.re2j` added in 1.22.2 but declared optional — no mandatory runtime deps to distribute |
| packageurl-java 1.5.0 | Build fails: `bad class file: wrong version 69.0, should be 53.0` — JDK mismatch, not fixable without downgrading |
| picocli 4.7.7 | Gradle build system; Gradle itself fails with `Unsupported class file major version 69` |
| dagger | Gradle build system; Gradle version parsing fails |
| Commons Math (3.6.1 / 4.0-beta1) | 3.6.1 has zero deps (low AOT benefit); 4.0-beta1 adds commons-numbers-core but still low value — dropped |
| HttpClient5 5.6.1 | HTTP/1.1 vs HTTP/2 is the only class-level split (two workloads); all other paths (TLS, auth, multipart) get JIT-compiled at runtime — insufficient workload diversity |
| Guava 33.6.0-jre | All transitive compile deps are annotations only — effectively zero real dep tree, low AOT benefit |
| FreeMarker 2.3.x | Gradle build system |
| Woodstox 5.4.x | `module-info.java` injected via moditect into published JAR |
| Log4j2 2.17.x | MR-JAR `module-info` present since 2.10 in both log4j-api and log4j-core |
| XStream 1.4.21 | Dep `mxparser` compiles to Java 1.4 bytecode — AOT recorder skips its classes entirely; `aotp --list-classes` on `mxparser/cache.aot` returned only `MXParserTest`, no library classes |

---

## Decision Queue

- [ ] Confirm Velocity 2.3 as next experiment or find an additional candidate
- [ ] Create a dedicated experiment plan for chosen project

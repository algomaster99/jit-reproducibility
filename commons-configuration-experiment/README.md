# Commons Configuration AOT Cache Experiment

Measures startup-time improvement from JDK 25 AOT caching (`single.aot` vs `tree.aot`)
for Apache Commons Configuration 2.14.0.

## Dependency versions

| Artifact | Version | Notes |
|---|---|---|
| commons-configuration2 | 2.14.0 | |
| commons-lang3 | 3.20.0 | |
| commons-text | 1.15.0 | |
| commons-logging | 1.3.6 | workload-jar pattern (no test suite) |
| commons-beanutils | 1.11.0 | optional dep; required at runtime by `BasicConfigurationBuilder` |
| commons-collections4 | **4.5.0** | see note below |

### commons-collections version note

`commons-beanutils:1.11.0` declares a compile-optional dependency on
`commons-collections:commons-collections:3.2.2` (the 3.x series, package
`org.apache.commons.collections`).  
Commons Collections 3.2.2 **cannot be compiled from source on JDK 21+** because:

1. Java 8 added `Map.remove(Object key, Object value)` returning `boolean` as a default
   method, conflicting with `MultiMap.remove(Object, Object)` which returns `Object`.
2. Java 21 added `SequencedCollection.addFirst(E)` / `addLast(E)` returning `void`,
   conflicting with `AbstractLinkedList` methods of the same name returning `boolean`.

We therefore use **commons-collections4 4.5.0** (`org.apache.commons.collections4`
package) for building the per-artifact AOT cache.  
Note that the 4.x package name differs from the 3.x package name, so
commons-beanutils's own class-loading path still targets `org.apache.commons.collections.*`
(3.x). In practice, commons-beanutils does not appear to load commons-collections
classes for the operations benchmarked here (`properties-read`, `xml-read`,
`composite-read`, `interpolation`), so the mismatch has no runtime effect.

## Benchmark operations

| Op | single.aot trained on this? | Classes unique to this op |
|---|---|---|
| `properties-read` | yes (training op) | `PropertiesConfiguration`, base `AbstractConfiguration` |
| `xml-read` | no | JAXP/DOM parser, `XMLConfiguration` |
| `composite-read` | no | `CompositeConfiguration`, builder event system |
| `interpolation` | no | `StringSubstitutor` (commons-text) |

## How to run locally

```bash
# 1. Build per-artifact caches (user-run)
cd commons-configuration-deps/commons-lang   && mvn clean test -Ptree-merge -q
cd ../commons-text                            && mvn clean test -Ptree-merge -q
cd ../commons-beanutils                       && mvn clean test -Ptree-merge -q
cd ../commons-collections                     && mvn clean test -Ptree-merge -q
cd ../commons-logging-workload                && mvn package -q
java -XX:AOTCacheOutput=cache.aot \
     --add-opens java.base/java.io=ALL-UNNAMED \
     --add-opens java.base/java.lang=ALL-UNNAMED \
     --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
     --add-opens java.base/java.time=ALL-UNNAMED \
     --add-opens java.base/java.time.chrono=ALL-UNNAMED \
     --add-opens java.base/java.util=ALL-UNNAMED \
     -jar target/commons-logging-workload-1.0-SNAPSHOT.jar
cd ../../commons-configuration                && mvn clean test -Ptree-merge -q

# 2. Build benchmark jar
cd ../benchmark && mvn package -DskipTests -q

# 3. Create single.aot (stock JDK 25)
cd .. && ./create-single-aot.sh

# 4. Create tree.aot
./orchestrate-combine.sh

# 5. Run timed workload
./workload-timed.sh
```

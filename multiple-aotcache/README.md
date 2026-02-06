```shell
java -XX:AOTCacheOutput=a.aot  -jar target/A-1.0-SNAPSHOT.jar
java -XX:AOTCacheOutput=b.aot  -jar target/B-1.0-SNAPSHOT.jar
java -XX:AOTCache=../B/b.aot -XX:AOTCache=../A/a.aot -Xlog:class+load=info,aot+codecache=debug:file=production.log:level,tags  -jar target/app-1.0-SNAPSHOT.jar
```

This creates a `production.log` file and only the later cache is used.
Multiple caches are not supported.
```
[info][class,load] com.example.B source: shared objects file
[info][class,load] com.example.Main source: file:/home/aman/Desktop/experiments/jit-testing/multiple-aotcache/app/target/app-1.0-SNAPSHOT.jar
[info][class,load] com.example.A source: file:/home/aman/Desktop/experiments/jit-testing/multiple-aotcache/app/target/app-1.0-SNAPSHOT.jar
```
```
[info][class,load] com.example.A source: shared objects file
[info][class,load] java.util.zip.ZipFile$Source$$Lambda/0x0000000016000000 source: java.util.zip.ZipFile
[info][class,load] com.example.Main source: file:/home/aman/Desktop/experiments/jit-testing/multiple-aotcache/app/target/app-1.0-SNAPSHOT.jar
[info][class,load] com.example.B source: file:/home/aman/Desktop/experiments/jit-testing/multiple-aotcache/app/target/app-1.0-SNAPSHOT.jar
```
> as you can see the first log shows that only `B` is loaded from the cache and the second log shows that only `A` is loaded from the cache.
This is because the second cache specified overrides the first one.

This is verified with:
```
openjdk version "27-internal" 2026-09-15
OpenJDK Runtime Environment (build 27-internal-adhoc.aman.jdk)
OpenJDK 64-Bit Server VM (build 27-internal-adhoc.aman.jdk, mixed mode, sharing)
```
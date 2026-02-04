```shell
java -XX:AOTCache=../B/b.aot -XX:AOTCache=../A/a.aot -Xlog:class+load=info,aot+codecache=debug:file=production.log:level,tags  -jar target/app-1.0-SNAPSHOT.jar
```

This creates a `production.log` file and only the later cache is used.
Multiple caches are not supported.
1. Create AOTCache for jackson-databind

`mvn clean package -Ptree-merge`

2. Create AOTCache for pdfbox

`mvn clean package -Ptree-merge`

3. Don't bother creating AOTCache for jetty-server as it has a module-info.java which is unsupported by AOT.

4. Merge

```
java -Xlog:aot -XX:AOTMode=merge -XX:AOTCache=../jackson-databind/cache.aot -XX:AOTMergeInputs=../../pdfbox-experiment/pdfbox/pdfbox/cache.aot -XX:AOTCacheOutput=tree.aot -cp ../jackson-databind/target/classes/:../../pdfbox-experiment/pdfbox/pdfbox/target/pdfbox-3.0.7.jar -version
```

You get performance improvements is only on the first request.

#### Without AOT
```
❯ java -jar target/jetty-web-demo-1.0-SNAPSHOT.jar
SLF4J(W): No SLF4J providers were found.
SLF4J(W): Defaulting to no-operation (NOP) logger implementation
SLF4J(W): See https://www.slf4j.org/codes.html#noProviders for further details.
Server started on http://localhost:8080
Endpoints: /hello  /json  /pdf
[/hello] 0.296 ms
[/hello] 0.276 ms
[/json]  11.586 ms
[/json]  0.761 ms
[/pdf]   149.094 ms
[/pdf]   3.163 ms
```

#### With AOT
```
❯ java -XX:AOTCache=tree.aot -jar target/jetty-web-demo-1.0-SNAPSHOT.jar
SLF4J(W): No SLF4J providers were found.
SLF4J(W): Defaulting to no-operation (NOP) logger implementation
SLF4J(W): See https://www.slf4j.org/codes.html#noProviders for further details.
Server started on http://localhost:8080
Endpoints: /hello  /json  /pdf
[/hello] 0.544 ms
[/hello] 0.319 ms
[/json]  6.672 ms
[/json]  0.494 ms
[/pdf]   125.170 ms
[/pdf]   2.954 ms
```

As you can see, the performance improvement is only for the first request.

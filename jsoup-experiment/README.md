# jsoup — Dropped

jsoup's only declared dependency is `org.jspecify:jspecify`, which is a pure
annotation library with zero runtime classes. It contributes nothing to an AOT
cache and nothing to startup performance (except for class parsing overhead).

A newer version (1.22.2) added `com.google.re2j` as a dependency, but it is
declared optional, meaning it is not pulled in transitively and cannot be relied
upon as a stable distributed cache artifact.

With no mandatory runtime dependencies to distribute, jsoup does not fit the
distributed AOT cache experiment model and was removed from the experiment set.

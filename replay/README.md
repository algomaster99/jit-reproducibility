Make sure to have debug build of JDK.
```
openjdk version "27-internal" 2026-09-15
OpenJDK Runtime Environment (build 27-internal-adhoc.aman.jdk)
OpenJDK 64-Bit Server VM (build 27-internal-adhoc.aman.jdk, mixed mode, sharing)
```
First we dump replay data.
```
java -XX:+UnlockDiagnosticVMOptions  -XX:+PrintCompilation -XX:+LogCompilation  -XX:+PrintAssembly  -XX:CompileCommand=DumpReplay,\*::\* -jar pdfbox-app-3.0.4.jar
```
This creates two types of files:
1. `hotspot_pid<pid>.log`
2. `replay_pid<pid>_compid<compid>.log`

Now the goal is to see if the replay produces the same assembly as the original compilation.

We run `extract_nmethods.py` to extract the assembly from the `hotspot_pid<pid>.log` file and each file is called: `<compile_id>,<method_name>,<c1|c2>.log`.
We include compilation ID to ensure that we use the correct replay file.
We include method name to enure that we compare the correct ASM code.

Running `extract_nmethods.py` creates the files in the `replay_dump` directory.

For each file in `replay_dump`, we do a replay with the corresponding `replay_pid<pid>_compid<compid>.log` file.
This produces a temporary file called `lol.log` which contains the assembly code of the method compiled.
This replayed assembly code is saved in the `replay_individual` directory.
This is done by running `replay_and_diff.py`.
It basically runs the following command:
```
java -XX:+UnlockDiagnosticVMOptions  -XX:+PrintCompilation -XX:+LogCompilation  -XX:+PrintAssembly  -XX:+ReplayCompiles -XX:ReplayDataFile=replay_pid<pid>_compid<compid>.log -XX:+ReplayIgnoreInitErrors -XX:LogFile=lol.log -jar pdfbox-app-3.0.4.jar
```

Finally, we diff the original assembly (replay_dump) code with the replayed assembly (replay_individual) code after performing three normalizations:
1. Hex addresses -> 0x0
2. Compiled method timestamp/compile_id/level -> 0
3. Ignore whitespace-only changes

diff directory has all the diffs.
Examples:

1. [Difference in the name of runtime_call](diff/2,java.lang.String::hashCode,c1.diff)
2. [Difference in registers used](diff/691,sun.reflect.annotation.AnnotationParser::parseAnnotations,c1.diff)
3. [Difference in one of the application classes](diff/1547,picocli.CommandLine$Model$Interpolator::interpolate,c1.diff)
4. [Difference in instructions (could just be refactoring)](diff/1241,jdk.internal.classfile.impl.DirectCodeBuilder$4::generateStackMaps,c1.diff)



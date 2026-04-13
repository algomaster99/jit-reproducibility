package com.example;

import picocli.CommandLine;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;

import java.util.concurrent.Callable;

@Command(name = "greet", mixinStandardHelpOptions = true, version = "1.0",
         description = "Picocli AOT workload")
public class App implements Callable<Integer> {

    @Option(names = {"-n", "--name"}, defaultValue = "World",
            description = "Name to greet (default: ${DEFAULT-VALUE})")
    String name;

    @Option(names = {"-c", "--count"}, defaultValue = "100",
            description = "Number of greetings (default: ${DEFAULT-VALUE})")
    int count;

    @Option(names = {"--upper"}, description = "Print in uppercase")
    boolean upper;

    public static void main(String[] args) {
        System.exit(new CommandLine(new App()).execute(args));
    }

    @Override
    public Integer call() {
        for (int i = 0; i < count; i++) {
            String msg = "Hello, " + name + "! (run " + (i + 1) + ")";
            System.out.println(upper ? msg.toUpperCase() : msg);
        }
        return 0;
    }
}

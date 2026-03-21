package com.example;

public class Adder {

    public int add(int a, int b) {
        return a + b;
    }

    public long add(long a, long b) {
        return a + b;
    }

    public static void main(String[] args) {
        Adder adder = new Adder();

        // Warm up so the JIT compiles these methods.
        long result = 0;
        for (int i = 0; i < 500_000; i++) {
            result += adder.add(i, i + 1);
        }
        System.out.println("Adder warmup complete. Result: " + result);
    }
}

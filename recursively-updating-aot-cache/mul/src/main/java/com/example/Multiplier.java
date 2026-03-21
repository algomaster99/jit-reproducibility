package com.example;

public class Multiplier {

    public int multiply(int a, int b) {
        return a * b;
    }

    public long multiply(long a, long b) {
        return a * b;
    }

    public static void main(String[] args) {
        Multiplier m = new Multiplier();

        // Warm up so the JIT compiles these methods.
        long result = 0;
        for (int i = 0; i < 50_000; i++) {
            result += m.multiply(i, 3);
            result += m.multiply(i, -1);
        }
        System.out.println("Multiplier warmup complete. Result: " + result);
    }
}

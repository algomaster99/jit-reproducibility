package com.example;

import org.bouncycastle.jce.provider.BouncyCastleProvider;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.Mac;
import javax.crypto.SecretKey;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.security.Security;
import java.security.Signature;

public class App {
    public static void main(String[] args) throws Exception {
        Security.addProvider(new BouncyCastleProvider());
        String provider = BouncyCastleProvider.PROVIDER_NAME;

        byte[] data = "bc-java prov workload payload".getBytes();

        MessageDigest sha256 = MessageDigest.getInstance("SHA-256", provider);
        byte[] digest = sha256.digest(data);

        MessageDigest sha3 = MessageDigest.getInstance("SHA3-256", provider);
        sha3.digest(data);

        KeyGenerator aesKg = KeyGenerator.getInstance("AES", provider);
        aesKg.init(256);
        SecretKey aesKey = aesKg.generateKey();
        byte[] iv = new byte[16];
        new SecureRandom().nextBytes(iv);

        Cipher aesCbc = Cipher.getInstance("AES/CBC/PKCS7Padding", provider);
        aesCbc.init(Cipher.ENCRYPT_MODE, aesKey, new IvParameterSpec(iv));
        byte[] ciphertext = aesCbc.doFinal(data);

        aesCbc.init(Cipher.DECRYPT_MODE, aesKey, new IvParameterSpec(iv));
        byte[] roundTrip = aesCbc.doFinal(ciphertext);
        if (roundTrip.length != data.length) {
            throw new IllegalStateException("AES round-trip length mismatch");
        }

        Cipher aesGcm = Cipher.getInstance("AES/GCM/NoPadding", provider);
        aesGcm.init(Cipher.ENCRYPT_MODE, aesKey, new IvParameterSpec(new byte[12]));
        aesGcm.doFinal(data);

        Mac hmac = Mac.getInstance("HmacSHA256", provider);
        hmac.init(new SecretKeySpec(digest, "HmacSHA256"));
        hmac.doFinal(data);

        KeyPairGenerator rsaKpg = KeyPairGenerator.getInstance("RSA", provider);
        rsaKpg.initialize(2048);
        KeyPair rsa = rsaKpg.generateKeyPair();

        Signature rsaSig = Signature.getInstance("SHA256withRSA", provider);
        rsaSig.initSign(rsa.getPrivate());
        rsaSig.update(data);
        byte[] sig = rsaSig.sign();

        rsaSig.initVerify(rsa.getPublic());
        rsaSig.update(data);
        if (!rsaSig.verify(sig)) {
            throw new IllegalStateException("RSA signature verification failed");
        }

        KeyPairGenerator ecKpg = KeyPairGenerator.getInstance("EC", provider);
        ecKpg.initialize(256);
        KeyPair ec = ecKpg.generateKeyPair();

        Signature ecSig = Signature.getInstance("SHA256withECDSA", provider);
        ecSig.initSign(ec.getPrivate());
        ecSig.update(data);
        byte[] ecSignature = ecSig.sign();

        ecSig.initVerify(ec.getPublic());
        ecSig.update(data);
        if (!ecSig.verify(ecSignature)) {
            throw new IllegalStateException("ECDSA signature verification failed");
        }

        System.out.println("bc-java-prov-workload ok");
    }
}

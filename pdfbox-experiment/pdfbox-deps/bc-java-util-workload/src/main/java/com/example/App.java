package com.example;

import org.bouncycastle.asn1.ASN1EncodableVector;
import org.bouncycastle.asn1.ASN1Integer;
import org.bouncycastle.asn1.ASN1ObjectIdentifier;
import org.bouncycastle.asn1.DEROctetString;
import org.bouncycastle.asn1.DERSequence;
import org.bouncycastle.asn1.pkcs.PKCSObjectIdentifiers;
import org.bouncycastle.asn1.pkcs.PrivateKeyInfo;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x500.X500NameBuilder;
import org.bouncycastle.asn1.x500.style.BCStyle;
import org.bouncycastle.asn1.x509.AlgorithmIdentifier;
import org.bouncycastle.asn1.x509.SubjectPublicKeyInfo;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.util.encoders.Base64;
import org.bouncycastle.util.encoders.Hex;
import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemWriter;

import java.io.StringWriter;
import java.math.BigInteger;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Security;

public class App {
    public static void main(String[] args) throws Exception {
        Security.addProvider(new BouncyCastleProvider());

        X500Name name = new X500NameBuilder(BCStyle.INSTANCE)
                .addRDN(BCStyle.CN, "bc-util workload")
                .addRDN(BCStyle.O, "example")
                .addRDN(BCStyle.C, "US")
                .addRDN(BCStyle.EmailAddress, "workload@example.com")
                .build();
        X500Name roundTrip = X500Name.getInstance(name.getEncoded());
        if (!name.equals(roundTrip)) {
            throw new IllegalStateException("X500Name round-trip mismatch");
        }

        ASN1EncodableVector v = new ASN1EncodableVector();
        v.add(new ASN1Integer(BigInteger.valueOf(42)));
        v.add(new ASN1ObjectIdentifier("1.2.840.113549.1.1.11"));
        v.add(new DEROctetString(new byte[]{1, 2, 3, 4, 5}));
        DERSequence seq = new DERSequence(v);
        byte[] encoded = seq.getEncoded();

        KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA", BouncyCastleProvider.PROVIDER_NAME);
        kpg.initialize(2048);
        KeyPair kp = kpg.generateKeyPair();

        SubjectPublicKeyInfo spki = SubjectPublicKeyInfo.getInstance(kp.getPublic().getEncoded());
        AlgorithmIdentifier algId = spki.getAlgorithm();
        if (!PKCSObjectIdentifiers.rsaEncryption.equals(algId.getAlgorithm())) {
            throw new IllegalStateException("Unexpected public key algorithm: " + algId.getAlgorithm());
        }

        PrivateKeyInfo pki = PrivateKeyInfo.getInstance(kp.getPrivate().getEncoded());
        byte[] pkiEncoded = pki.getEncoded();

        String hex = Hex.toHexString(encoded);
        byte[] hexDecoded = Hex.decode(hex);
        if (hexDecoded.length != encoded.length) {
            throw new IllegalStateException("Hex round-trip mismatch");
        }

        String b64 = Base64.toBase64String(pkiEncoded);
        byte[] b64Decoded = Base64.decode(b64);
        if (b64Decoded.length != pkiEncoded.length) {
            throw new IllegalStateException("Base64 round-trip mismatch");
        }

        StringWriter sw = new StringWriter();
        try (PemWriter pw = new PemWriter(sw)) {
            pw.writeObject(new PemObject("PRIVATE KEY", pkiEncoded));
            pw.writeObject(new PemObject("PUBLIC KEY", spki.getEncoded()));
        }

        System.out.println("bc-java-util-workload ok");
    }
}

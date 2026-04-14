package com.example;

import org.bouncycastle.asn1.pkcs.PKCSObjectIdentifiers;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.BasicConstraints;
import org.bouncycastle.asn1.x509.ExtendedKeyUsage;
import org.bouncycastle.asn1.x509.Extension;
import org.bouncycastle.asn1.x509.GeneralName;
import org.bouncycastle.asn1.x509.GeneralNames;
import org.bouncycastle.asn1.x509.KeyPurposeId;
import org.bouncycastle.asn1.x509.KeyUsage;
import org.bouncycastle.cert.X509CertificateHolder;
import org.bouncycastle.cert.X509v3CertificateBuilder;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509ExtensionUtils;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.cms.CMSEnvelopedData;
import org.bouncycastle.cms.CMSEnvelopedDataGenerator;
import org.bouncycastle.cms.CMSProcessableByteArray;
import org.bouncycastle.cms.CMSSignedData;
import org.bouncycastle.cms.CMSSignedDataGenerator;
import org.bouncycastle.cms.CMSTypedData;
import org.bouncycastle.cms.SignerInfoGenerator;
import org.bouncycastle.cms.jcajce.JcaSignerInfoGeneratorBuilder;
import org.bouncycastle.cms.jcajce.JceCMSContentEncryptorBuilder;
import org.bouncycastle.cms.jcajce.JceKeyTransRecipientInfoGenerator;
import org.bouncycastle.jce.provider.BouncyCastleProvider;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.DigestCalculatorProvider;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.bouncycastle.operator.jcajce.JcaDigestCalculatorProviderBuilder;
import org.bouncycastle.pkcs.PKCS10CertificationRequest;
import org.bouncycastle.pkcs.PKCS10CertificationRequestBuilder;
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequestBuilder;

import java.math.BigInteger;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.Security;
import java.security.cert.X509Certificate;
import java.util.Date;

public class App {
    public static void main(String[] args) throws Exception {
        Security.addProvider(new BouncyCastleProvider());
        String provider = BouncyCastleProvider.PROVIDER_NAME;

        KeyPairGenerator kpg = KeyPairGenerator.getInstance("RSA", provider);
        kpg.initialize(2048);
        KeyPair kp = kpg.generateKeyPair();

        X500Name subject = new X500Name("CN=bc-pkix workload,O=example,C=US");
        BigInteger serial = BigInteger.valueOf(System.currentTimeMillis());
        Date notBefore = new Date(System.currentTimeMillis() - 60_000L);
        Date notAfter = new Date(System.currentTimeMillis() + 365L * 24 * 3600 * 1000);

        X509v3CertificateBuilder certBuilder = new JcaX509v3CertificateBuilder(
                subject, serial, notBefore, notAfter, subject, kp.getPublic());

        JcaX509ExtensionUtils extUtils = new JcaX509ExtensionUtils();
        certBuilder.addExtension(Extension.basicConstraints, true, new BasicConstraints(true));
        certBuilder.addExtension(Extension.keyUsage, true,
                new KeyUsage(KeyUsage.digitalSignature | KeyUsage.keyCertSign | KeyUsage.keyEncipherment));
        certBuilder.addExtension(Extension.extendedKeyUsage, false,
                new ExtendedKeyUsage(new KeyPurposeId[]{KeyPurposeId.id_kp_codeSigning, KeyPurposeId.id_kp_emailProtection}));
        certBuilder.addExtension(Extension.subjectKeyIdentifier, false,
                extUtils.createSubjectKeyIdentifier(kp.getPublic()));
        certBuilder.addExtension(Extension.authorityKeyIdentifier, false,
                extUtils.createAuthorityKeyIdentifier(kp.getPublic()));
        certBuilder.addExtension(Extension.subjectAlternativeName, false,
                new GeneralNames(new GeneralName(GeneralName.rfc822Name, "workload@example.com")));

        ContentSigner signer = new JcaContentSignerBuilder("SHA256withRSA")
                .setProvider(provider)
                .build(kp.getPrivate());

        X509CertificateHolder holder = certBuilder.build(signer);
        X509Certificate cert = new JcaX509CertificateConverter()
                .setProvider(provider)
                .getCertificate(holder);
        cert.verify(kp.getPublic(), provider);

        PKCS10CertificationRequestBuilder csrBuilder = new JcaPKCS10CertificationRequestBuilder(subject, kp.getPublic());
        PKCS10CertificationRequest csr = csrBuilder.build(signer);
        byte[] csrEncoded = csr.getEncoded();
        if (csrEncoded.length == 0) {
            throw new IllegalStateException("Empty CSR");
        }

        byte[] payload = "bc-pkix workload payload".getBytes();

        DigestCalculatorProvider digestProvider = new JcaDigestCalculatorProviderBuilder()
                .setProvider(provider)
                .build();
        SignerInfoGenerator signerInfoGen = new JcaSignerInfoGeneratorBuilder(digestProvider)
                .build(signer, holder);

        CMSSignedDataGenerator signedGen = new CMSSignedDataGenerator();
        signedGen.addSignerInfoGenerator(signerInfoGen);
        CMSTypedData typed = new CMSProcessableByteArray(payload);
        CMSSignedData signedData = signedGen.generate(typed, true);
        byte[] signedEncoded = signedData.getEncoded();
        if (signedEncoded.length == 0) {
            throw new IllegalStateException("Empty CMS SignedData");
        }

        CMSEnvelopedDataGenerator envGen = new CMSEnvelopedDataGenerator();
        envGen.addRecipientInfoGenerator(new JceKeyTransRecipientInfoGenerator(cert).setProvider(provider));
        CMSEnvelopedData envelopedData = envGen.generate(
                new CMSProcessableByteArray(payload),
                new JceCMSContentEncryptorBuilder(PKCSObjectIdentifiers.des_EDE3_CBC)
                        .setProvider(provider)
                        .build());
        byte[] envEncoded = envelopedData.getEncoded();
        if (envEncoded.length == 0) {
            throw new IllegalStateException("Empty CMS EnvelopedData");
        }

        System.out.println("bc-java-pkix-workload ok");
    }
}

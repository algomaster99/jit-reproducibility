package dev.validatorexp;

import org.apache.commons.validator.routines.CreditCardValidator;
import org.apache.commons.validator.routines.EmailValidator;
import org.apache.commons.validator.routines.InetAddressValidator;
import org.apache.commons.validator.routines.UrlValidator;

public class Main {

    static final int ITERATIONS = 10_000;

    static final String[] EMAILS = {
        "user@example.com", "firstname.lastname@domain.org", "email@subdomain.domain.com",
        "1234567890@domain.com", "email@domain-one.com", "_______@domain.com",
        "email@domain.name", "email@domain.co.jp",
        "plainaddress", "@missing-user.com", "missing-at-sign.com",
        "email@domain..com", "email..double-dot@domain.com"
    };

    static final String[] URLS = {
        "http://example.com", "https://www.example.com/path?q=1&r=2",
        "http://subdomain.example.co.uk/page", "ftp://ftp.example.com/file.txt",
        "https://example.com:8080/path", "http://user:password@example.com",
        "http://", "://missing-scheme.com", "http://.invalid.com",
        "http://example.com/path with spaces", "http://256.256.256.256"
    };

    static final String[] IPS = {
        "192.168.1.1", "10.0.0.1", "255.255.255.255", "0.0.0.0",
        "172.16.254.1", "127.0.0.1", "8.8.8.8", "8.8.4.4",
        "256.0.0.1", "192.168.1", "not-an-ip", "999.999.999.999",
        "2001:db8::1", "::1", "fe80::1%eth0"
    };

    static final String[] CREDIT_CARDS = {
        "4111111111111111", "4012888888881881", "4222222222222",
        "5500005555555559", "5105105105105100",
        "371449635398431", "378282246310005",
        "6011111111111117", "6011000990139424",
        "1234567890123456", "0000000000000000", "411111111111111"
    };

    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.err.println("Usage: Main <command>");
            System.exit(1);
        }
        String cmd = args[0];
        switch (cmd) {
            case "prepare"          -> {}
            case "validate-email"   -> validateEmail();
            case "validate-url"     -> validateUrl();
            case "validate-ip"      -> validateIp();
            case "validate-credit-card" -> validateCreditCard();
            default -> { System.err.println("Unknown command: " + cmd); System.exit(1); }
        }
    }

    static void validateEmail() {
        EmailValidator v = EmailValidator.getInstance();
        for (int i = 0; i < ITERATIONS; i++) {
            for (String email : EMAILS) {
                v.isValid(email);
            }
        }
    }

    static void validateUrl() {
        UrlValidator v = new UrlValidator(new String[]{"http", "https", "ftp"});
        for (int i = 0; i < ITERATIONS; i++) {
            for (String url : URLS) {
                v.isValid(url);
            }
        }
    }

    static void validateIp() {
        InetAddressValidator v = InetAddressValidator.getInstance();
        for (int i = 0; i < ITERATIONS; i++) {
            for (String ip : IPS) {
                v.isValid(ip);
                v.isValidInet4Address(ip);
                v.isValidInet6Address(ip);
            }
        }
    }

    static void validateCreditCard() {
        CreditCardValidator v = new CreditCardValidator();
        for (int i = 0; i < ITERATIONS; i++) {
            for (String card : CREDIT_CARDS) {
                v.isValid(card);
            }
        }
    }
}

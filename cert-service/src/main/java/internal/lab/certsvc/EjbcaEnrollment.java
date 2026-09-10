package internal.lab.certsvc;

import java.io.StringWriter;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.time.Duration;
import java.util.Base64;
import java.util.List;
import java.util.ArrayList;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import javax.net.ssl.KeyManagerFactory;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManagerFactory;

import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;
import org.bouncycastle.pkcs.PKCS10CertificationRequest;
import org.bouncycastle.pkcs.jcajce.JcaPKCS10CertificationRequestBuilder;
import org.bouncycastle.util.io.pem.PemObject;
import org.bouncycastle.util.io.pem.PemWriter;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Real certificate issuance through EJBCA — the privileged act at the end of the
 * delegation chain. There is deliberately no fallback: if EJBCA cannot issue,
 * this fails loudly. A self-signed substitute would make the whole chain a
 * theatre piece (infra/pki/README.md: never substitute silently).
 *
 * The employee key pair is generated here and never leaves this service except
 * as the certificate's public half. The lab issues a demo certificate for a
 * laptop; a production design would have the laptop generate its own key and
 * send only a CSR.
 */
@Component
public class EjbcaEnrollment {

    private static final Pattern CERT_FIELD = Pattern.compile("\"certificate\"\\s*:\\s*\"([^\"]+)\"");
    /** Present when the request says include_chain: an array of base64 DER
     *  strings, issuers upward (probed live against 9.3.7, not recalled). */
    private static final Pattern CHAIN_FIELD = Pattern.compile("\"certificate_chain\"\\s*:\\s*\\[([^\\]]*)\\]");
    private static final Pattern QUOTED = Pattern.compile("\"([^\"]+)\"");

    private final String enrollUrl;
    private final String caName;
    private final String endEntityProfile;
    private final String certificateProfile;
    private final String enrollUsername;
    private final String enrollPassword;
    private final String raKeystorePath;
    private final String raKeystorePassword;
    private final String tlsCaPath;
    private volatile HttpClient http;

    public EjbcaEnrollment(
            @Value("${cert.ejbca.enroll-url}") String enrollUrl,
            @Value("${cert.ejbca.ca-name}") String caName,
            @Value("${cert.ejbca.end-entity-profile}") String endEntityProfile,
            @Value("${cert.ejbca.certificate-profile}") String certificateProfile,
            @Value("${cert.ejbca.username}") String enrollUsername,
            @Value("${cert.ejbca.password}") String enrollPassword,
            @Value("${cert.ejbca.ra-keystore}") String raKeystorePath,
            @Value("${cert.ejbca.ra-keystore-password}") String raKeystorePassword,
            @Value("${cert.ejbca.tls-ca}") String tlsCaPath) {
        this.enrollUrl = enrollUrl;
        this.caName = caName;
        this.endEntityProfile = endEntityProfile;
        this.certificateProfile = certificateProfile;
        this.enrollUsername = enrollUsername;
        this.enrollPassword = enrollPassword;
        this.raKeystorePath = raKeystorePath;
        this.raKeystorePassword = raKeystorePassword;
        this.tlsCaPath = tlsCaPath;
    }

    /**
     * EJBCA's REST API refuses any request that does not authenticate (verified
     * empirically against 9.3.7: 403 "no client certificate or OAuth token").
     * cert-service therefore authenticates as a registered RA: client keystore
     * issued by ManagementCA, server verified against ManagementCA — EJBCA's own
     * management plane, distinct from all three SPIFFE/OIDC trust stores.
     * Lazy: the credential files exist only after the human runs
     * infra/pki/setup-employee-profile.sh; missing files fail the issuance
     * loudly, never the service boot, and never fall back to plain HTTP.
     */
    private HttpClient raClient() throws Exception {
        HttpClient client = http;
        if (client != null) {
            return client;
        }
        synchronized (this) {
            if (http == null) {
                if (!Files.isRegularFile(Path.of(raKeystorePath)) || !Files.isRegularFile(Path.of(tlsCaPath))) {
                    throw new IllegalStateException("EJBCA RA credential missing (" + raKeystorePath + ", " + tlsCaPath
                            + ") — run infra/pki/setup-employee-profile.sh (human-gated, CLAUDE.md §7)");
                }
                KeyStore keyStore = KeyStore.getInstance("PKCS12");
                try (var in = Files.newInputStream(Path.of(raKeystorePath))) {
                    keyStore.load(in, raKeystorePassword.toCharArray());
                }
                // NOT getDefaultAlgorithm(): CertServiceApplication#main overrides the
                // JVM defaults to "Spiffe" for the workload mTLS plane. This is the
                // EJBCA management plane — explicit standard PKIX managers.
                KeyManagerFactory kmf = KeyManagerFactory.getInstance("PKIX");
                kmf.init(keyStore, raKeystorePassword.toCharArray());

                KeyStore trustStore = KeyStore.getInstance(KeyStore.getDefaultType());
                trustStore.load(null, null);
                CertificateFactory cf = CertificateFactory.getInstance("X.509");
                try (var in = Files.newInputStream(Path.of(tlsCaPath))) {
                    int i = 0;
                    for (var cert : cf.generateCertificates(in)) {
                        trustStore.setCertificateEntry("ejbca-tls-ca-" + i++, cert);
                    }
                }
                TrustManagerFactory tmf = TrustManagerFactory.getInstance("PKIX");
                tmf.init(trustStore);

                SSLContext ssl = SSLContext.getInstance("TLS");
                ssl.init(kmf.getKeyManagers(), tmf.getTrustManagers(), null);
                http = HttpClient.newBuilder()
                        .sslContext(ssl)
                        .connectTimeout(Duration.ofSeconds(10))
                        .build();
            }
            return http;
        }
    }

    /**
     * The issued certificate: metadata plus the certificate PEM — and NEVER the
     * private key.
     *
     * The key is generated here for the CSR and discarded when this method
     * returns; it is never stored, returned, or logged. That is not a lab
     * shortcut being papered over: a certificate is public by construction, so
     * shipping it downstream for inspection costs nothing, while the key that
     * would make it usable does not survive issuance at all.
     *
     * (D-036 reversed the earlier "never the PEM body" line: the console needs
     * the certificate to render and offer it, and there was never a secret in
     * it. The private key remains as absent as before.)
     */
    public record Issued(String subjectDn, String issuerDn, String serial, String notBefore, String notAfter,
            String fingerprintSha256, String pem, List<String> chainPem) {
    }

    public Issued issue(String commonName) throws Exception {
        KeyPair keyPair = generateKeyPair();
        String csrPem = csrPem(keyPair, commonName);
        String body = enrollmentRequest(csrPem, commonName);

        HttpRequest request = HttpRequest.newBuilder(URI.create(enrollUrl))
                .timeout(Duration.ofSeconds(30))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8))
                .build();
        HttpResponse<String> response;
        try {
            response = raClient().send(request, HttpResponse.BodyHandlers.ofString());
        } catch (IOException e) {
            // Rethrown, not permitted. "HTTP/1.1 header parser received no bytes" /
            // "EOF reached while reading" = EJBCA closed the connection right after
            // the TLS handshake, which is how a client certificate its ManagementCA
            // never issued is refused (TLS 1.3 alerts arrive post-handshake).
            throw new IllegalStateException("EJBCA closed the connection without a response (" + e.getMessage()
                    + "): the RA keystore " + raKeystorePath + " is not accepted by the running EJBCA"
                    + " (pki/ra/ copied from another machine, or ejbca-data volume recreated after"
                    + " setup-employee-profile.sh), or EJBCA is not up. Run demo/checklist.sh.", e);
        }
        if (response.statusCode() != 200 && response.statusCode() != 201) {
            throw new IllegalStateException(
                    "EJBCA enrollment failed: HTTP " + response.statusCode() + " " + response.body());
        }
        Matcher m = CERT_FIELD.matcher(response.body());
        if (!m.find()) {
            throw new IllegalStateException("EJBCA response carries no certificate: " + response.body());
        }
        return describe(m.group(1), chainOf(response.body()));
    }

    private static KeyPair generateKeyPair() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(256);
        return generator.generateKeyPair();
    }

    private static String csrPem(KeyPair keyPair, String commonName) throws Exception {
        X500Name subject = new X500Name("CN=" + commonName + ",O=eviden");
        ContentSigner signer = new JcaContentSignerBuilder("SHA256withECDSA").build(keyPair.getPrivate());
        PKCS10CertificationRequest csr = new JcaPKCS10CertificationRequestBuilder(subject, keyPair.getPublic())
                .build(signer);
        StringWriter out = new StringWriter();
        try (PemWriter pem = new PemWriter(out)) {
            pem.writeObject(new PemObject("CERTIFICATE REQUEST", csr.getEncoded()));
        }
        return out.toString();
    }

    private String enrollmentRequest(String csrPem, String commonName) {
        return """
                {"certificate_request":"%s",\
                "certificate_profile_name":"%s",\
                "end_entity_profile_name":"%s",\
                "certificate_authority_name":"%s",\
                "username":"%s",\
                "password":"%s",\
                "include_chain":true}"""
                .formatted(csrPem.replace("\r", "").replace("\n", "\\n"),
                        certificateProfile, endEntityProfile, caName,
                        enrollUsername + "-" + commonName, enrollPassword);
    }

    /** The CA chain EJBCA returned, as PEM, issuers upward; empty if absent. */
    private static List<String> chainOf(String body) throws Exception {
        List<String> chain = new ArrayList<>();
        Matcher array = CHAIN_FIELD.matcher(body);
        if (!array.find()) {
            return chain;
        }
        Matcher entry = QUOTED.matcher(array.group(1));
        while (entry.find()) {
            byte[] der = Base64.getMimeDecoder().decode(entry.group(1));
            X509Certificate cert = (X509Certificate) CertificateFactory.getInstance("X.509")
                    .generateCertificate(new java.io.ByteArrayInputStream(der));
            chain.add(pem(cert));
        }
        return chain;
    }

    private static Issued describe(String base64Der, List<String> chainPem) throws Exception {
        byte[] der = Base64.getMimeDecoder().decode(base64Der);
        X509Certificate cert = (X509Certificate) CertificateFactory.getInstance("X.509")
                .generateCertificate(new java.io.ByteArrayInputStream(der));
        java.security.MessageDigest sha256 = java.security.MessageDigest.getInstance("SHA-256");
        byte[] fp = sha256.digest(cert.getEncoded());
        StringBuilder hex = new StringBuilder();
        for (byte b : fp) {
            hex.append(String.format("%02X", b));
        }
        return new Issued(
                cert.getSubjectX500Principal().getName(),
                cert.getIssuerX500Principal().getName(),
                cert.getSerialNumber().toString(16).toUpperCase(),
                cert.getNotBefore().toInstant().toString(),
                cert.getNotAfter().toInstant().toString(),
                hex.toString(),
                pem(cert),
                chainPem);
    }

    /** The certificate, PEM-encoded — what `openssl x509 -text -in` reads. */
    private static String pem(X509Certificate cert) throws Exception {
        String body = Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.US_ASCII))
                .encodeToString(cert.getEncoded());
        return "-----BEGIN CERTIFICATE-----\n" + body + "\n-----END CERTIFICATE-----\n";
    }
}

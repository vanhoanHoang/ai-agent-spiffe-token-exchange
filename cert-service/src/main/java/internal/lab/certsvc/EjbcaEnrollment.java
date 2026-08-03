package internal.lab.certsvc;

import java.io.StringWriter;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.time.Duration;
import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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

    private final String enrollUrl;
    private final String caName;
    private final String endEntityProfile;
    private final String certificateProfile;
    private final String enrollUsername;
    private final String enrollPassword;
    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10))
            .build();

    public EjbcaEnrollment(
            @Value("${cert.ejbca.enroll-url}") String enrollUrl,
            @Value("${cert.ejbca.ca-name}") String caName,
            @Value("${cert.ejbca.end-entity-profile}") String endEntityProfile,
            @Value("${cert.ejbca.certificate-profile}") String certificateProfile,
            @Value("${cert.ejbca.username}") String enrollUsername,
            @Value("${cert.ejbca.password}") String enrollPassword) {
        this.enrollUrl = enrollUrl;
        this.caName = caName;
        this.endEntityProfile = endEntityProfile;
        this.certificateProfile = certificateProfile;
        this.enrollUsername = enrollUsername;
        this.enrollPassword = enrollPassword;
    }

    /** Issued certificate metadata — never the private key, never the PEM body. */
    public record Issued(String subjectDn, String issuerDn, String serial, String notBefore, String notAfter,
            String fingerprintSha256) {
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
        HttpResponse<String> response = http.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200 && response.statusCode() != 201) {
            throw new IllegalStateException(
                    "EJBCA enrollment failed: HTTP " + response.statusCode() + " " + response.body());
        }
        Matcher m = CERT_FIELD.matcher(response.body());
        if (!m.find()) {
            throw new IllegalStateException("EJBCA response carries no certificate: " + response.body());
        }
        return describe(m.group(1));
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
                "include_chain":false}"""
                .formatted(csrPem.replace("\r", "").replace("\n", "\\n"),
                        certificateProfile, endEntityProfile, caName,
                        enrollUsername + "-" + commonName, enrollPassword);
    }

    private static Issued describe(String base64Der) throws Exception {
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
                hex.toString());
    }
}

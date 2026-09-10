package internal.lab.agent;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;
import java.util.Base64;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.Set;
import java.util.LinkedHashSet;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * D-036: the certificate the delegation chain produced, for the human who
 * asked for it — decoded for reading, and downloadable as PEM.
 *
 * Same shape as {@code /api/svid} so the console renders it with the existing
 * openssl-style view rather than a second one. Public certificate material
 * only; there is no key to leak, because cert-service discards it at issuance.
 */
@RestController
@Profile("web")
public class IssuedApiController {

    private final IssuedCertHolder holder;

    IssuedApiController(IssuedCertHolder holder) {
        this.holder = holder;
    }

    @GetMapping("/api/issued")
    public ResponseEntity<Map<String, Object>> issued() throws Exception {
        String pem = holder.get();
        if (pem == null) {
            return ResponseEntity.noContent().build();
        }
        X509Certificate cert = parse(pem);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("role", "employee device");
        m.put("subject", cert.getSubjectX500Principal().getName("RFC2253"));
        m.put("issuer", cert.getIssuerX500Principal().getName("RFC2253"));
        m.put("serial", cert.getSerialNumber().toString(16).toUpperCase());
        m.put("notBefore", cert.getNotBefore().toInstant().toString());
        m.put("notAfter", cert.getNotAfter().toInstant().toString());
        // Shape parity with /api/svid so the console reuses one renderer. Any
        // SANs this certificate carries already show in the extensions block.
        m.put("uriSans", List.of());
        m.put("sha256", HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(cert.getEncoded())));
        m.put("details", X509Details.of(cert));
        m.put("pem", pem);
        m.put("chain", chain(holder.chain()));
        return ResponseEntity.ok(m);
    }

    /**
     * The certificate and its ancestry as cert-service reported them: leaf
     * first, then issuers upward; a self-signed last certificate is the trust
     * anchor. Same shape as /api/svid so the console draws one chain view.
     */
    private static List<Map<String, Object>> chain(List<String> pems) throws Exception {
        List<Map<String, Object>> out = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (int i = 0; i < pems.size(); i++) {
            X509Certificate cert = parse(pems.get(i));
            boolean selfSigned = cert.getSubjectX500Principal().equals(cert.getIssuerX500Principal());
            CertJson.add(out, seen, cert, i == 0 ? "leaf" : selfSigned ? "trust-anchor" : "intermediate");
        }
        return out;
    }

    /** The same bytes, as a file — what `openssl x509 -text -in` reads. */
    @GetMapping("/api/issued/download")
    public ResponseEntity<byte[]> download() throws Exception {
        String pem = holder.get();
        if (pem == null) {
            return ResponseEntity.noContent().build();
        }
        String cn = commonName(parse(pem));
        return ResponseEntity.ok()
                .contentType(MediaType.APPLICATION_OCTET_STREAM)
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + cn + ".pem\"")
                .body(pem.getBytes(StandardCharsets.US_ASCII));
    }

    private static X509Certificate parse(String pem) throws Exception {
        String body = pem.replaceAll("-----[A-Z ]+-----", "").replaceAll("\\s", "");
        byte[] der = Base64.getDecoder().decode(body);
        return (X509Certificate) CertificateFactory.getInstance("X.509")
                .generateCertificate(new ByteArrayInputStream(der));
    }

    /** Filename only — kept boring, since it reaches a Content-Disposition. */
    private static String commonName(X509Certificate cert) {
        String dn = cert.getSubjectX500Principal().getName("RFC2253");
        for (String part : dn.split(",")) {
            String p = part.trim();
            if (p.regionMatches(true, 0, "CN=", 0, 3)) {
                String cn = p.substring(3).replaceAll("[^A-Za-z0-9._-]", "-");
                return cn.isBlank() ? "certificate" : cn;
            }
        }
        return "certificate";
    }
}

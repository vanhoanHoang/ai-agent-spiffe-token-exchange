package internal.lab.agent;

import java.security.MessageDigest;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import io.spiffe.bundle.x509bundle.X509Bundle;
import io.spiffe.svid.x509svid.X509Svid;
import io.spiffe.workloadapi.X509Source;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * P6.5: read-only view of the workload's CURRENT X.509-SVID chain for the
 * console — public certificate metadata only (subject, serial, validity,
 * URI SAN, fingerprint). Never the private key, never PEM. Reading it live
 * from the X509Source means the console shows the rotating certificate the
 * mTLS handshake will actually use, not a stale copy.
 */
@RestController
@Profile("web")
public class SvidApiController {

    private final X509Source source;

    SvidApiController(X509Source source) {
        this.source = source;
    }

    @GetMapping("/api/svid")
    public Map<String, Object> svid() throws Exception {
        X509Svid svid = source.getX509Svid();
        List<Map<String, Object>> chain = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        List<X509Certificate> certs = svid.getChain();
        for (int i = 0; i < certs.size(); i++) {
            add(chain, seen, certs.get(i), i == 0 ? "leaf" : "intermediate");
        }
        X509Bundle bundle = source.getBundleForTrustDomain(svid.getSpiffeId().getTrustDomain());
        for (X509Certificate anchor : bundle.getX509Authorities()) {
            add(chain, seen, anchor, "trust-anchor");
        }
        return Map.of("spiffeId", svid.getSpiffeId().toString(), "chain", chain);
    }

    private static void add(List<Map<String, Object>> chain, Set<String> seen,
            X509Certificate cert, String role) throws Exception {
        String fingerprint = sha256(cert);
        if (!seen.add(fingerprint)) {
            return; // the bundle may repeat a cert already in the SVID chain
        }
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("role", role);
        m.put("subject", cert.getSubjectX500Principal().getName());
        m.put("issuer", cert.getIssuerX500Principal().getName());
        m.put("serial", cert.getSerialNumber().toString(16));
        m.put("notBefore", cert.getNotBefore().toInstant().toString());
        m.put("notAfter", cert.getNotAfter().toInstant().toString());
        m.put("uriSans", uriSans(cert));
        m.put("sha256", fingerprint);
        chain.add(m);
    }

    private static List<String> uriSans(X509Certificate cert) throws Exception {
        List<String> uris = new ArrayList<>();
        var sans = cert.getSubjectAlternativeNames();
        if (sans != null) {
            for (List<?> san : sans) {
                if (san.size() >= 2 && Integer.valueOf(6).equals(san.get(0))) {
                    uris.add(String.valueOf(san.get(1)));
                }
            }
        }
        return uris;
    }

    private static String sha256(X509Certificate cert) throws Exception {
        return HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(cert.getEncoded()));
    }
}

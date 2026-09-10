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
import io.spiffe.spiffeid.TrustDomain;
import io.spiffe.workloadapi.X509Source;

/**
 * One JSON shape for every certificate the console shows — the agent's own
 * SVID (/api/svid), what a peer presented (/api/peer), the issued employee
 * certificate (/api/issued). Public metadata only: no key, no PEM.
 */
final class CertJson {

    /** SPIRE stamps a serialNumber RDN; without the keyword map it renders as
     *  "2.5.4.5=#<der-hex>", which is noise for the expert view. */
    private static final Map<String, String> OID_NAMES = Map.of("2.5.4.5", "SERIALNUMBER");

    private CertJson() {
    }

    /**
     * A presented chain (leaf first) followed by the trust domain's bundle
     * anchors, deduplicated by fingerprint — the bundle may repeat a
     * certificate already in the chain.
     */
    static List<Map<String, Object>> chain(List<X509Certificate> certs, X509Source source, TrustDomain trustDomain)
            throws Exception {
        List<Map<String, Object>> chain = new ArrayList<>();
        Set<String> seen = new LinkedHashSet<>();
        for (int i = 0; i < certs.size(); i++) {
            add(chain, seen, certs.get(i), i == 0 ? "leaf" : "intermediate");
        }
        X509Bundle bundle = source.getBundleForTrustDomain(trustDomain);
        for (X509Certificate anchor : bundle.getX509Authorities()) {
            add(chain, seen, anchor, "trust-anchor");
        }
        return chain;
    }

    /** Appends the certificate under the given role unless already listed. */
    static void add(List<Map<String, Object>> chain, Set<String> seen, X509Certificate cert, String role)
            throws Exception {
        String fingerprint = sha256(cert);
        if (!seen.add(fingerprint)) {
            return;
        }
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("role", role);
        m.put("subject", cert.getSubjectX500Principal().getName("RFC2253", OID_NAMES));
        m.put("issuer", cert.getIssuerX500Principal().getName("RFC2253", OID_NAMES));
        m.put("serial", cert.getSerialNumber().toString(16));
        m.put("notBefore", cert.getNotBefore().toInstant().toString());
        m.put("notAfter", cert.getNotAfter().toInstant().toString());
        m.put("uriSans", uriSans(cert));
        m.put("sha256", fingerprint);
        m.put("details", X509Details.of(cert));
        chain.add(m);
    }

    static List<String> uriSans(X509Certificate cert) throws Exception {
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

    static String sha256(X509Certificate cert) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(cert.getEncoded()));
    }
}

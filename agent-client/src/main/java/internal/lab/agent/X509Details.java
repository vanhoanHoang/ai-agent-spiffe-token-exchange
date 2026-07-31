package internal.lab.agent;

import java.security.cert.X509Certificate;
import java.security.interfaces.ECPublicKey;
import java.security.interfaces.RSAPublicKey;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Full X.509 breakdown for the console's expert view (P6.6) — display only,
 * never a validation path. Extensions we know are decoded into openssl-text
 * style values; anything else is shown as OID + raw hex, never omitted. A
 * per-extension decode failure degrades to the raw hex for THAT extension
 * (this is rendering, not verification — nothing is accepted or rejected here).
 */
final class X509Details {

    private static final Map<String, String> EXT_NAMES = Map.of(
            "2.5.29.14", "Subject Key Identifier",
            "2.5.29.15", "Key Usage",
            "2.5.29.17", "Subject Alternative Name",
            "2.5.29.19", "Basic Constraints",
            "2.5.29.30", "Name Constraints",
            "2.5.29.35", "Authority Key Identifier",
            "2.5.29.37", "Extended Key Usage",
            "2.5.29.31", "CRL Distribution Points",
            "1.3.6.1.5.5.7.1.1", "Authority Information Access");

    private static final Map<String, String> EKU_NAMES = Map.of(
            "1.3.6.1.5.5.7.3.1", "TLS Web Server Authentication",
            "1.3.6.1.5.5.7.3.2", "TLS Web Client Authentication");

    private static final String[] KEY_USAGE_BITS = {
            "Digital Signature", "Non Repudiation", "Key Encipherment",
            "Data Encipherment", "Key Agreement", "Certificate Sign",
            "CRL Sign", "Encipher Only", "Decipher Only" };

    private X509Details() {
    }

    static Map<String, Object> of(X509Certificate cert) {
        Map<String, Object> d = new LinkedHashMap<>();
        d.put("version", cert.getVersion());
        d.put("signatureAlgorithm", cert.getSigAlgName());
        d.put("publicKey", publicKey(cert));
        d.put("extensions", extensions(cert));
        return d;
    }

    private static String publicKey(X509Certificate cert) {
        var pk = cert.getPublicKey();
        if (pk instanceof ECPublicKey ec) {
            return "EC, " + ec.getParams().getOrder().bitLength() + " bit (P-"
                    + ec.getParams().getOrder().bitLength() + ")";
        }
        if (pk instanceof RSAPublicKey rsa) {
            return "RSA, " + rsa.getModulus().bitLength() + " bit";
        }
        return pk.getAlgorithm();
    }

    private static List<Map<String, Object>> extensions(X509Certificate cert) {
        Set<String> critical = cert.getCriticalExtensionOIDs();
        List<Map<String, Object>> out = new ArrayList<>();
        List<String> oids = new ArrayList<>();
        if (critical != null) {
            oids.addAll(critical);
        }
        if (cert.getNonCriticalExtensionOIDs() != null) {
            oids.addAll(cert.getNonCriticalExtensionOIDs());
        }
        for (String oid : oids) {
            Map<String, Object> e = new LinkedHashMap<>();
            e.put("oid", oid);
            e.put("name", EXT_NAMES.getOrDefault(oid, "Unknown extension"));
            e.put("critical", critical != null && critical.contains(oid));
            e.put("value", render(cert, oid));
            out.add(e);
        }
        return out;
    }

    private static String render(X509Certificate cert, String oid) {
        try {
            return switch (oid) {
                case "2.5.29.15" -> keyUsage(cert);
                case "2.5.29.37" -> eku(cert);
                case "2.5.29.19" -> basicConstraints(cert);
                case "2.5.29.17" -> san(cert);
                case "2.5.29.14" -> "keyid:" + hex(Der.skiKeyId(cert.getExtensionValue(oid)));
                case "2.5.29.35" -> "keyid:" + hex(Der.akiKeyId(cert.getExtensionValue(oid)));
                case "2.5.29.30" -> Der.nameConstraints(cert.getExtensionValue(oid));
                default -> "raw:" + hex(cert.getExtensionValue(oid));
            };
        } catch (Exception e) {
            return "raw:" + hex(cert.getExtensionValue(oid));
        }
    }

    private static String keyUsage(X509Certificate cert) {
        boolean[] bits = cert.getKeyUsage();
        List<String> names = new ArrayList<>();
        for (int i = 0; bits != null && i < bits.length && i < KEY_USAGE_BITS.length; i++) {
            if (bits[i]) {
                names.add(KEY_USAGE_BITS[i]);
            }
        }
        return String.join(", ", names);
    }

    private static String eku(X509Certificate cert) throws Exception {
        List<String> names = new ArrayList<>();
        for (String oid : cert.getExtendedKeyUsage()) {
            names.add(EKU_NAMES.getOrDefault(oid, oid));
        }
        return String.join(", ", names);
    }

    private static String basicConstraints(X509Certificate cert) {
        int pathLen = cert.getBasicConstraints();
        if (pathLen < 0) {
            return "CA:FALSE";
        }
        return pathLen == Integer.MAX_VALUE ? "CA:TRUE" : "CA:TRUE, pathlen:" + pathLen;
    }

    private static String san(X509Certificate cert) throws Exception {
        var sans = cert.getSubjectAlternativeNames();
        List<String> parts = new ArrayList<>();
        if (sans != null) {
            for (List<?> san : sans) {
                String kind = switch ((Integer) san.get(0)) {
                    case 1 -> "email";
                    case 2 -> "DNS";
                    case 6 -> "URI";
                    case 7 -> "IP";
                    default -> "type-" + san.get(0);
                };
                parts.add(kind + ":" + san.get(1));
            }
        }
        return String.join(", ", parts);
    }

    private static String hex(byte[] bytes) {
        return bytes == null ? "" : HexFormat.of().formatHex(bytes);
    }
}

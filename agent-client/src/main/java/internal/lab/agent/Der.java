package internal.lab.agent;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

/**
 * Minimal DER TLV walking for the three extensions the JDK exposes only as
 * raw bytes: SKI, AKI (keyid) and Name Constraints. Display-only (P6.6);
 * malformed input throws and the caller falls back to raw hex.
 */
final class Der {

    private record Tlv(int tag, byte[] value, int next) {
    }

    private Der() {
    }

    private static Tlv read(byte[] b, int off) {
        int tag = b[off] & 0xff;
        int first = b[off + 1] & 0xff;
        int len;
        int valueOff;
        if ((first & 0x80) == 0) {
            len = first;
            valueOff = off + 2;
        } else {
            int n = first & 0x7f;
            len = 0;
            for (int i = 0; i < n; i++) {
                len = (len << 8) | (b[off + 2 + i] & 0xff);
            }
            valueOff = off + 2 + n;
        }
        return new Tlv(tag, Arrays.copyOfRange(b, valueOff, valueOff + len), valueOff + len);
    }

    private static List<Tlv> children(byte[] container) {
        List<Tlv> out = new ArrayList<>();
        int off = 0;
        while (off < container.length) {
            Tlv t = read(container, off);
            out.add(t);
            off = t.next();
        }
        return out;
    }

    /** getExtensionValue wraps the extension DER in an extra OCTET STRING. */
    private static byte[] unwrap(byte[] extensionValue) {
        Tlv outer = read(extensionValue, 0);
        if (outer.tag() != 0x04) {
            throw new IllegalArgumentException("extension value is not an OCTET STRING");
        }
        return outer.value();
    }

    /** SubjectKeyIdentifier ::= OCTET STRING */
    static byte[] skiKeyId(byte[] extensionValue) {
        Tlv inner = read(unwrap(extensionValue), 0);
        return inner.value();
    }

    /** AuthorityKeyIdentifier ::= SEQUENCE { keyIdentifier [0] IMPLICIT ... } */
    static byte[] akiKeyId(byte[] extensionValue) {
        for (Tlv t : children(read(unwrap(extensionValue), 0).value())) {
            if (t.tag() == 0x80) {
                return t.value();
            }
        }
        throw new IllegalArgumentException("AKI without keyIdentifier");
    }

    /**
     * NameConstraints ::= SEQUENCE { permitted [0], excluded [1] }, each a
     * SEQUENCE of GeneralSubtree { base GeneralName ... }. Rendered in the
     * openssl style: "Permitted: URI:ai-agent.id.eviden.internal".
     */
    static String nameConstraints(byte[] extensionValue) {
        List<String> parts = new ArrayList<>();
        for (Tlv side : children(read(unwrap(extensionValue), 0).value())) {
            String label = side.tag() == 0xa0 ? "Permitted" : "Excluded";
            List<String> names = new ArrayList<>();
            for (Tlv subtree : children(side.value())) {
                names.add(generalName(read(subtree.value(), 0)));
            }
            parts.add(label + ": " + String.join(", ", names));
        }
        return String.join("; ", parts);
    }

    private static String generalName(Tlv name) {
        String text = new String(name.value(), StandardCharsets.US_ASCII);
        return switch (name.tag()) {
            case 0x81 -> "email:" + text;
            case 0x82 -> "DNS:" + text;
            case 0x86 -> "URI:" + text;
            default -> "type-" + Integer.toHexString(name.tag());
        };
    }
}

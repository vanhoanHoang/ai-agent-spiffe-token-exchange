package internal.lab.agent;

import java.util.ArrayList;
import java.util.Base64;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.springframework.stereotype.Component;

/**
 * The most recently issued employee certificate, held so the console can show
 * and offer it (D-036) — together with the chain the certificate service
 * reported for it, so the console can draw the certificate's ancestry.
 *
 * What lives here is PUBLIC material and only public material: X.509
 * certificates. The private key that would make the leaf usable was generated
 * inside cert-service for the CSR and discarded at issuance — it never crosses
 * a process boundary, let alone this one. Nothing here is a credential, so the
 * "console holds no secrets" rule is intact.
 *
 * Deliberately last-one-wins rather than a per-session store: this is a demo
 * surface for a single operator, and a certificate is not sensitive enough to
 * justify a session-keyed cache that would then need an eviction policy. If
 * this ever serves more than one human at a time, key it by session first.
 */
@Component
public class IssuedCertHolder {

    private static final String BEGIN = "-----BEGIN CERTIFICATE-----";
    private static final String END = "-----END CERTIFICATE-----";
    private static final Pattern PEM_BLOCK = Pattern.compile(BEGIN + "(.*?)" + END, Pattern.DOTALL);

    /** Escaping survives at most a couple of nestings; three passes is slack. */
    private static final int MAX_UNESCAPE_PASSES = 3;

    /** Leaf first, then the chain as reported (issuers upward). */
    private final AtomicReference<List<String>> pems = new AtomicReference<>(List.of());

    /**
     * Take the certificates out of a tool result and keep them, returning what
     * the MODEL should see instead.
     *
     * PEMs in a tool result are kilobytes of base64 the model pays for, may
     * truncate, and may echo back mangled. The human asked for a certificate,
     * not a description of one, so it goes to the console intact and the model
     * gets a one-line placeholder per block. The first block is the issued
     * certificate; cert-service lists its chain after it.
     */
    String captureFrom(String toolResult) {
        if (toolResult == null || !toolResult.contains(BEGIN)) {
            return toolResult;
        }
        List<String> found = normalizeAll(toolResult);
        if (!found.isEmpty()) {
            pems.set(found);
        }
        return PEM_BLOCK.matcher(toolResult)
                .replaceAll("(certificate delivered to the console for download)");
    }

    /** The issued certificate, or null when this session has issued none yet. */
    String get() {
        List<String> all = pems.get();
        return all.isEmpty() ? null : all.get(0);
    }

    /** The issued certificate followed by its chain; empty when none yet. */
    List<String> chain() {
        return pems.get();
    }

    /**
     * Re-derive every certificate from scratch, so no upstream formatting
     * survives, deduplicated in order of appearance.
     *
     * The escapes MUST be resolved before anything is filtered. cert-service's
     * JSON travels as a string inside agent-pki's JSON, so a line break reaches
     * us as the two characters backslash and n. Stripping "everything that is
     * not base64" first removes the backslash and leaves the n — and n is
     * itself a base64 character, so the body silently grows corrupt and the
     * decode later dies with "wrong 4-byte ending unit", nowhere near the
     * cause. That bug cost a rebuild cycle; hence the explicit unescape.
     */
    private static List<String> normalizeAll(String raw) {
        String text = raw;
        for (int pass = 0; pass < MAX_UNESCAPE_PASSES && text.indexOf('\\') >= 0; pass++) {
            text = unescape(text);
        }
        Set<String> unique = new LinkedHashSet<>();
        Matcher m = PEM_BLOCK.matcher(text);
        while (m.find()) {
            String base64 = m.group(1).replaceAll("\\s", "");
            try {
                Base64.getDecoder().decode(base64); // refuse to store something unreadable
            } catch (IllegalArgumentException e) {
                continue;
            }
            unique.add(wrap(base64));
        }
        return List.copyOf(new ArrayList<>(unique));
    }

    private static String wrap(String base64) {
        StringBuilder out = new StringBuilder(BEGIN).append('\n');
        for (int i = 0; i < base64.length(); i += 64) {
            out.append(base64, i, Math.min(i + 64, base64.length())).append('\n');
        }
        return out.append(END).append('\n').toString();
    }

    /** One layer of JSON string escaping, resolved. */
    private static String unescape(String s) {
        StringBuilder out = new StringBuilder(s.length());
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c != '\\' || i + 1 >= s.length()) {
                out.append(c);
                continue;
            }
            char next = s.charAt(++i);
            switch (next) {
                // Any of these become whitespace, which the base64 filter drops.
                case 'n', 'r', 't' -> out.append('\n');
                case '\\' -> out.append('\\');
                case '"' -> out.append('"');
                case '/' -> out.append('/');
                default -> out.append('\\').append(next);
            }
        }
        return out.toString();
    }
}

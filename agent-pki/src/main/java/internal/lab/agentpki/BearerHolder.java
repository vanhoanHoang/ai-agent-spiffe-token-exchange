package internal.lab.agentpki;

import org.springframework.stereotype.Component;

/**
 * The exchanged bearer for the CURRENT onboarding request, and nothing else.
 * Set right after the second-hop exchange, cleared in a finally block. The MCP
 * transport reads it through the SDK's sanctioned per-request channel
 * ({@code transportContextProvider} -> customizer).
 *
 * Fail closed: a cert-service call with no bearer in scope is a bug, not an
 * unauthenticated request.
 */
@Component
public class BearerHolder {

    private final ThreadLocal<String> current = new ThreadLocal<>();

    void set(String bearer) {
        if (bearer == null || bearer.isBlank()) {
            throw new IllegalStateException("refusing to set an empty bearer");
        }
        current.set(bearer);
    }

    void clear() {
        current.remove();
    }

    String required() {
        String bearer = current.get();
        if (bearer == null) {
            throw new IllegalStateException("cert-service call attempted without an exchanged bearer (fail closed)");
        }
        return bearer;
    }
}

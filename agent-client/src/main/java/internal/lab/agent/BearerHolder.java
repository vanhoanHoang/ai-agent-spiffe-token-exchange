package internal.lab.agent;

import org.springframework.stereotype.Component;

/**
 * The exchanged bearer for the CURRENT call, and nothing else. Set by the loop
 * entry point right after the per-message RFC 8693 exchange, cleared in a
 * finally block. The MCP transport reads it through the SDK's sanctioned
 * per-request channel ({@code transportContextProvider} -> customizer), so a
 * P2.5 session token later slots in by changing only who calls {@link #set}.
 *
 * Fail closed: an MCP call with no bearer in scope is a bug, not an
 * unauthenticated request.
 */
@Component
public class BearerHolder {

    /** Key under which the bearer travels in the {@code McpTransportContext}. */
    static final String CONTEXT_KEY = "internal.lab.agent.bearer";

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
            throw new IllegalStateException("MCP call attempted without an exchanged bearer (fail closed)");
        }
        return bearer;
    }
}

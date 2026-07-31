package internal.lab.mcp;

/**
 * Raised when a tool requires a scope the caller's token does not carry.
 * Named after the RFC 6750 error code the resource server would return on a
 * plain HTTP route; over MCP it surfaces as a tool error the agent can report.
 */
public class InsufficientScopeException extends RuntimeException {

    private final String requiredScope;

    public InsufficientScopeException(String requiredScope) {
        super("insufficient_scope: this call requires the '" + requiredScope + "' scope; "
                + "the presented token does not carry it");
        this.requiredScope = requiredScope;
    }

    public String getRequiredScope() {
        return requiredScope;
    }
}

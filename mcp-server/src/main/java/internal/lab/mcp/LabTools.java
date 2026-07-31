package internal.lab.mcp;

import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.mcp.annotation.McpTool;
import org.springframework.ai.mcp.annotation.McpToolParam;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/**
 * The MCP tools the demo agent may call (M10 P1). Tools are ordinary beans;
 * Spring AI's server autoconfiguration exposes them on /mcp, which sits behind
 * the same gates as every other route: audience check, SVID mTLS, allowlist,
 * and the act↔peer binding (D-009).
 *
 * {@code read_audit_log} is deliberately scope-gated: it is the fixture for the
 * P3 negative demo — the model is willing, the token is not.
 */
@Component
public class LabTools {

    private static final Logger log = LoggerFactory.getLogger(LabTools.class);
    static final String AUDIT_SCOPE = "mcp:audit";

    private final AuditLogBuffer auditLog;

    public LabTools(AuditLogBuffer auditLog) {
        this.auditLog = auditLog;
    }

    @McpTool(name = "whoami",
            description = "Returns the identities behind the current call: which human the caller acts for (sub) "
                    + "and which workload it is (act.sub / mTLS peer SPIFFE ID).")
    public Map<String, Object> whoami() {
        Jwt jwt = currentJwt();
        Object act = jwt.getClaim("act");
        Map<String, Object> result = Map.of(
                "human_sub", String.valueOf(jwt.getSubject()),
                "username", String.valueOf(jwt.getClaimAsString("preferred_username")),
                "workload_act", act == null ? Map.of() : act,
                "audience", jwt.getAudience(),
                "scopes", scopes());
        log.info("tool=whoami sub={} act={}", jwt.getSubject(), act);
        return result;
    }

    @McpTool(name = "lab_status",
            description = "Reports which identity components of the lab are reachable and what this server enforces.")
    public Map<String, Object> labStatus() {
        log.info("tool=lab_status sub={}", currentJwt().getSubject());
        return Map.of(
                "trust_domain", "spiffe://lab.internal",
                "resource_id", "https://mcp.lab.internal:8443",
                "enforced", List.of(
                        "token audience == this server (anti-passthrough)",
                        "mTLS with X509-SVID (client-auth: need)",
                        "workload allowlist",
                        "act.sub == mTLS peer SPIFFE ID (token bound to its workload)"));
    }

    @McpTool(name = "read_audit_log",
            description = "Reads the most recent audited MCP calls. Requires the mcp:audit scope.")
    public Map<String, Object> readAuditLog(
            @McpToolParam(description = "How many recent entries to return (1-50)", required = false) Integer limit) {
        Jwt jwt = currentJwt();
        if (!scopes().contains(AUDIT_SCOPE)) {
            // Enforcement is the token, not the model's willingness (P3).
            log.warn("tool=read_audit_log DENIED sub={} scopes={}", jwt.getSubject(), scopes());
            throw new InsufficientScopeException(AUDIT_SCOPE);
        }
        int n = (limit == null) ? 10 : Math.clamp(limit, 1, 50);
        log.info("tool=read_audit_log sub={} limit={}", jwt.getSubject(), n);
        return Map.of("entries", auditLog.recent(n));
    }

    private static Jwt currentJwt() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth instanceof JwtAuthenticationToken jwtAuth) {
            return jwtAuth.getToken();
        }
        throw new IllegalStateException("no authenticated JWT in context");
    }

    private static List<String> scopes() {
        String scope = currentJwt().getClaimAsString("scope");
        return (scope == null || scope.isBlank()) ? List.of() : List.of(scope.split(" "));
    }
}

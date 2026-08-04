package internal.lab.certsvc;

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
 * The one privileged tool in the lab (M12). Issuing a certificate for a person
 * is the action the whole delegation chain exists to protect.
 *
 * Four things must ALL hold before this runs, and none of them is this method's
 * doing: the caller's audience must be this service, its mTLS peer identity must
 * be on the allowlist (agent-pki alone), the outermost act.sub must equal that
 * peer, and the token must carry issue:employee-cert — a scope the assistant
 * that talks to the human is never assigned.
 *
 * The audit line records the FULL delegation chain, not just the immediate
 * caller. "Who asked for this certificate" has a complete answer: a named human,
 * through a named pair of workloads.
 */
@Component
public class CertTools {

    private static final Logger log = LoggerFactory.getLogger(CertTools.class);
    static final String ISSUE_SCOPE = "issue:employee-cert";

    private final EjbcaEnrollment ejbca;
    private final AuditLogBuffer auditLog;

    public CertTools(EjbcaEnrollment ejbca, AuditLogBuffer auditLog) {
        this.ejbca = ejbca;
        this.auditLog = auditLog;
    }

    @McpTool(name = "issue_employee_cert",
            description = "Issues one employee device certificate from the corporate CA. "
                    + "Requires the issue:employee-cert scope, which only the PKI agent can hold.")
    public Map<String, Object> issueEmployeeCert(
            @McpToolParam(description = "Device common name, e.g. john-laptop") String subject) {
        Jwt jwt = currentJwt();
        if (!scopes().contains(ISSUE_SCOPE)) {
            log.warn("tool=issue_employee_cert DENIED sub={} scopes={}", jwt.getSubject(), scopes());
            throw new InsufficientScopeException(ISSUE_SCOPE);
        }
        String cn = sanitize(subject);
        String chain = delegationChain(jwt);
        try {
            EjbcaEnrollment.Issued issued = ejbca.issue(cn);
            log.info("tool=issue_employee_cert ISSUED cn={} serial={} sub={} chain={}",
                    cn, issued.serial(), jwt.getSubject(), chain);
            auditLog.record("issued cn=%s serial=%s sub=%s chain=%s"
                    .formatted(cn, issued.serial(), jwt.getSubject(), chain));
            return Map.of(
                    "issued", true,
                    "subject_dn", issued.subjectDn(),
                    "issuer_dn", issued.issuerDn(),
                    "serial", issued.serial(),
                    "not_before", issued.notBefore(),
                    "not_after", issued.notAfter(),
                    "fingerprint_sha256", issued.fingerprintSha256(),
                    "requested_by_human", String.valueOf(jwt.getSubject()),
                    "delegation_chain", chain,
                    // The certificate itself, so the human who asked for it can
                    // actually see and keep it. Public material: the key that
                    // would make it usable was discarded at issuance.
                    "certificate_pem", issued.pem());
        } catch (Exception e) {
            // No fallback issuance. A failure here is reported as a failure.
            log.error("tool=issue_employee_cert FAILED cn={} sub={} chain={}", cn, jwt.getSubject(), chain, e);
            throw new IllegalStateException("certificate issuance failed: " + e.getMessage(), e);
        }
    }

    /**
     * The act chain, outermost first: who called us, and on whose behalf they
     * were themselves acting, all the way down to the human at the root.
     */
    static String delegationChain(Jwt jwt) {
        StringBuilder chain = new StringBuilder();
        Object node = jwt.getClaim("act");
        while (node instanceof Map<?, ?> act) {
            if (!chain.isEmpty()) {
                chain.append(" <- ");
            }
            chain.append(String.valueOf(act.get("sub")));
            node = act.get("act");
        }
        return chain.isEmpty() ? "(none)" : chain.toString();
    }

    /** CN goes into a DN and an EJBCA username; keep it boring. */
    private static String sanitize(String subject) {
        if (subject == null || subject.isBlank()) {
            throw new IllegalArgumentException("subject is required");
        }
        String cleaned = subject.trim().toLowerCase().replaceAll("[^a-z0-9-]", "-");
        if (cleaned.length() > 48) {
            cleaned = cleaned.substring(0, 48);
        }
        if (cleaned.isBlank() || cleaned.startsWith("-")) {
            throw new IllegalArgumentException("subject must contain letters or digits");
        }
        return cleaned;
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

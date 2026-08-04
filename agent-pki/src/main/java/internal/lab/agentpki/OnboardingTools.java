package internal.lab.agentpki;

import java.util.List;
import java.util.Map;

import internal.lab.delegation.DelegatedExchange;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.spec.McpSchema;
import io.spiffe.svid.jwtsvid.JwtSvid;
import io.spiffe.workloadapi.JwtSource;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.ai.mcp.annotation.McpTool;
import org.springframework.ai.mcp.annotation.McpToolParam;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;

/**
 * The second hop, in one method (M12).
 *
 * The assistant hands us an onboarding request that carries a human's identity
 * and the scope {@code onboard:initiate}. That scope is worth nothing at the
 * certificate service — it is not the scope that issues certificates, and this
 * agent's audience is not that service either. So the request cannot be
 * forwarded; it has to be exchanged, and the exchange is where this agent's own
 * identity enters the chain.
 *
 * After the exchange the token still says {@code sub = the human}. What changed
 * is the audience, the scope, and the {@code act} chain, which now records both
 * agents in order. Nobody along the way acquired an authority the human did not
 * grant.
 */
@Component
public class OnboardingTools {

    private static final Logger log = LoggerFactory.getLogger(OnboardingTools.class);
    static final String INITIATE_SCOPE = "onboard:initiate";
    static final String ISSUE_SCOPE = "issue:employee-cert";

    private final JwtSource jwtSource;
    private final McpSyncClient certService;
    private final BearerHolder bearer;
    private final AuditLogBuffer auditLog;
    private final String tokenEndpoint;
    private final String issuerIdentifier;
    private boolean initialized;

    public OnboardingTools(JwtSource jwtSource, McpSyncClient certServiceMcpClient, BearerHolder bearer,
            AuditLogBuffer auditLog,
            @Value("${pki.token-endpoint}") String tokenEndpoint,
            @Value("${pki.issuer}") String issuerIdentifier) {
        this.jwtSource = jwtSource;
        this.certService = certServiceMcpClient;
        this.bearer = bearer;
        this.auditLog = auditLog;
        this.tokenEndpoint = tokenEndpoint;
        this.issuerIdentifier = issuerIdentifier;
    }

    @McpTool(name = "onboard_employee",
            description = "Onboards a new employee by obtaining a device certificate for them. "
                    + "Requires the onboard:initiate scope.")
    public Map<String, Object> onboardEmployee(
            @McpToolParam(description = "The new employee's device name, e.g. john-laptop") String device) {
        Jwt inbound = currentJwt();
        if (!scopes().contains(INITIATE_SCOPE)) {
            log.warn("tool=onboard_employee DENIED sub={} scopes={}", inbound.getSubject(), scopes());
            throw new InsufficientScopeException(INITIATE_SCOPE);
        }
        String human = inbound.getSubject();
        log.info("tool=onboard_employee sub={} act={} device={}", human, inbound.getClaim("act"), device);

        try {
            JwtSvid svid = jwtSource.fetchJwtSvid(issuerIdentifier);
            String delegated = exchangeForCertService(svid, inbound.getTokenValue(), human);
            bearer.set(delegated);
            try {
                Map<String, Object> issued = callCertService(device);
                auditLog.record("onboarded device=%s sub=%s".formatted(device, human));
                return Map.of(
                        "onboarded", true,
                        "device", device,
                        "certificate", issued,
                        // The second hop, reported by the workload that actually
                        // performed it. The caller relays these facts to its
                        // console rather than narrating a hop it never witnessed
                        // (D-034) — a console must not describe work it cannot see.
                        "hop2", Map.of(
                                "actor", svid.getSpiffeId().toString(),
                                "scope", ISSUE_SCOPE,
                                "tool", "issue_employee_cert"),
                        "note", "issued by the certificate service, which this agent reached "
                                + "with a token exchanged for that purpose alone");
            } finally {
                bearer.clear();
            }
        } catch (RuntimeException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException("onboarding failed: " + e.getMessage(), e);
        }
    }

    /**
     * Hop two. The inbound token is the subject; this agent's JWT-SVID is the
     * client credential, which is what makes it the actor. The requested scope
     * is the one this hop needs and no more.
     */
    private String exchangeForCertService(JwtSvid svid, String inboundToken, String human) throws Exception {
        DelegatedExchange.Response res =
                DelegatedExchange.post(svid, tokenEndpoint, inboundToken, ISSUE_SCOPE);
        if (res.status() != 200) {
            log.warn("second-hop exchange refused for sub={}: HTTP {} {}", human, res.status(), res.body());
            throw new IllegalStateException("second-hop exchange refused: HTTP " + res.status() + " " + res.body());
        }
        String token = res.accessToken();
        if (token == null) {
            throw new IllegalStateException("exchange response carries no access_token");
        }
        log.info("second-hop exchange done: actor={} audience=cert-service scope={}", svid.getSpiffeId(), ISSUE_SCOPE);
        return token;
    }

    private Map<String, Object> callCertService(String device) {
        synchronized (this) {
            if (!initialized) {
                certService.initialize();
                initialized = true;
            }
        }
        McpSchema.CallToolResult result = certService.callTool(
                new McpSchema.CallToolRequest("issue_employee_cert", Map.of("subject", device)));
        if (Boolean.TRUE.equals(result.isError())) {
            throw new IllegalStateException("certificate service refused: " + textOf(result));
        }
        return Map.of("result", textOf(result));
    }

    private static String textOf(McpSchema.CallToolResult result) {
        List<McpSchema.Content> content = result.content();
        if (content == null || content.isEmpty()) {
            return "";
        }
        return content.stream()
                .filter(McpSchema.TextContent.class::isInstance)
                .map(c -> ((McpSchema.TextContent) c).text())
                .reduce((a, b) -> a + "\n" + b)
                .orElse("");
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

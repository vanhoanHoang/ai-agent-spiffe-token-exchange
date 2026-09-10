package internal.lab.agent;

import java.util.Arrays;
import java.util.Set;
import java.util.function.Consumer;
import java.util.stream.Collectors;

import internal.lab.delegation.DelegatedExchange;
import io.spiffe.svid.jwtsvid.JwtSvid;
import io.spiffe.workloadapi.JwtSource;
import org.springframework.stereotype.Component;

/**
 * Per-message RFC 8693 exchange: the human's subject token in, the delegated
 * access token (sub = human, act.sub = this workload's SPIFFE ID) out. The
 * subject token is an ARGUMENT — today the CLI passes SUBJECT_TOKEN from the
 * environment, P2.5 passes the browser session's token — so nothing here may
 * cache a token or bind one at startup.
 */
@Component
public class TokenExchange {

    /**
     * The delegated authorities this agent is allowed to carry. Alice may grant
     * more than that — since M12 her consent covers the whole chain, including
     * {@code issue:employee-cert}, which belongs to the PKI agent and not to
     * this one. Forwarding everything she granted asks for a scope this client
     * may never hold, and the authorization server answers exactly that:
     * {@code Delegation refused: 'agent-client' may not carry
     * issue:employee-cert}.
     *
     * So the request is narrowed to {@code her scopes ∩ ours} — the same
     * intersection CLAUDE.md §2 names. This is politeness, not enforcement:
     * the delegation-table executor refuses an over-broad ask regardless, and
     * that refusal is what the security model rests on (D-031).
     */
    private static final String DEFAULT_DELEGATABLE = "onboard:initiate mcp:audit";

    private final JwtSource jwtSource;
    private final String tokenEndpoint;
    private final String issuerIdentifier;
    private final Set<String> delegatable;

    TokenExchange(JwtSource jwtSource) {
        this.jwtSource = jwtSource;
        this.tokenEndpoint = System.getenv().getOrDefault("TOKEN_ENDPOINT",
                "http://keycloak:8080/realms/ai-agents/protocol/openid-connect/token");
        this.issuerIdentifier = System.getenv().getOrDefault("ISSUER", "http://keycloak:8080/realms/ai-agents");
        this.delegatable = Arrays.stream(
                        System.getenv().getOrDefault("AGENT_DELEGATABLE_SCOPES", DEFAULT_DELEGATABLE).split("[ ,]+"))
                .filter(s -> !s.isBlank())
                .collect(Collectors.toUnmodifiableSet());
    }

    /** What this agent may ask for, given what the human actually granted. */
    private String requestedScope(String subjectToken) {
        return Arrays.stream(DelegatedExchange.delegatedScope(subjectToken).split("\\s+"))
                .filter(s -> !s.isBlank())
                .filter(delegatable::contains)
                .reduce((a, b) -> a + " " + b)
                .orElse("");
    }

    String exchange(String subjectToken) throws Exception {
        return exchange(subjectToken, e -> { });
    }

    /** Same exchange, narrated: emits the REAL svid/exchange completions with
     *  identity labels only (never token material) — P6.1 live display. */
    String exchange(String subjectToken, Consumer<StepEvent> events) throws Exception {
        if (subjectToken == null || subjectToken.isBlank()) {
            throw new IllegalStateException("token exchange requires a subject token (fail closed)");
        }
        JwtSvid svid = jwtSource.fetchJwtSvid(issuerIdentifier);
        events.accept(new StepEvent("svid",
                "JWT-SVID minted for " + svid.getSpiffeId()));

        String scope = requestedScope(subjectToken);
        DelegatedExchange.Response res = DelegatedExchange.post(svid, tokenEndpoint, subjectToken, scope);
        if (res.status() != 200) {
            throw new IllegalStateException("token exchange failed: HTTP " + res.status() + " " + res.body());
        }
        String token = res.accessToken();
        if (token == null) {
            throw new IllegalStateException("token exchange response carries no access_token");
        }
        events.accept(new StepEvent("exchange",
                "RFC 8693 exchange done: act.sub=" + svid.getSpiffeId()
                        + (scope.isEmpty() ? "" : ", scope=" + scope)));
        return token;
    }
}

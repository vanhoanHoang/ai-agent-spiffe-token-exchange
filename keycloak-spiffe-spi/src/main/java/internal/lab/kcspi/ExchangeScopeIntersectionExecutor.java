package internal.lab.kcspi;

import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.stream.Collectors;

import org.keycloak.OAuthErrorException;
import org.keycloak.TokenVerifier;
import org.keycloak.models.KeycloakSession;
import org.keycloak.protocol.oidc.TokenExchangeContext;
import org.keycloak.representations.AccessToken;
import org.keycloak.services.clientpolicy.ClientPolicyContext;
import org.keycloak.services.clientpolicy.ClientPolicyException;
import org.keycloak.services.clientpolicy.context.TokenExchangeRequestContext;
import org.keycloak.services.clientpolicy.executor.ClientPolicyExecutorProvider;

import jakarta.ws.rs.core.Response;

/**
 * Enforces the architectural rule that Keycloak does not enforce on its own:
 *
 * <pre>effective permissions = user scopes ∩ agent allowed scopes</pre>
 *
 * Keycloak's standard token exchange validates the requested {@code scope}
 * against the REQUESTER CLIENT's assigned scopes and its consent only — the
 * subject token's own scopes are never consulted
 * ({@code StandardTokenExchangeProvider.getRequestedScope}). Without this
 * executor an agent can request, and receive, a scope the human never granted;
 * that was proven end to end against the running lab (a scope-gated tool
 * returned 200 for an unconsented user).
 *
 * This executor closes the delegation half: whatever a caller asks for at an
 * exchange must already be present in the subject token it presents.
 * Permissions may shrink along a delegation chain, never grow.
 *
 * <h3>Why parsing an as-yet-unverified subject token is sound here</h3>
 * Client policies run BEFORE the exchange provider verifies the subject token.
 * We therefore read claims from a token whose signature we have not checked.
 * That is safe for THIS decision, and only because of the ordering: the very
 * same token string is verified moments later by
 * {@code AuthenticationManager.verifyIdentityToken}, and a failure there aborts
 * the request. So a forged subject token cannot buy a wider scope — it buys a
 * rejected request. A parse failure here is treated as a REFUSAL, never as a
 * pass (no catch-and-permit).
 */
public class ExchangeScopeIntersectionExecutor
        implements ClientPolicyExecutorProvider<ExchangeScopeIntersectionExecutor.Configuration> {

    public static final String PROVIDER_ID = "exchange-scope-intersection";

    /**
     * Scopes Keycloak attaches structurally rather than as delegated authority.
     * {@code openid} is an OIDC request marker; the profile/email/roles family
     * and audience-carrier scopes are client configuration, not something a
     * human grants a delegate. Requiring them to appear in the subject token
     * would break every ordinary exchange while protecting nothing.
     */
    private static final Set<String> STRUCTURAL = Set.of(
            "openid", "profile", "email", "roles", "web-origins", "acr", "basic", "address", "phone");

    private final KeycloakSession session;
    private Configuration configuration = new Configuration();

    public ExchangeScopeIntersectionExecutor(KeycloakSession session) {
        this.session = session;
    }

    @Override
    public String getProviderId() {
        return PROVIDER_ID;
    }

    @Override
    public void setupConfiguration(Configuration config) {
        this.configuration = config == null ? new Configuration() : config;
    }

    @Override
    public Class<Configuration> getExecutorConfigurationClass() {
        return Configuration.class;
    }

    @Override
    public void executeOnEvent(ClientPolicyContext context) throws ClientPolicyException {
        if (!(context instanceof TokenExchangeRequestContext exchange)) {
            return;
        }
        TokenExchangeContext ctx = exchange.getTokenExchangeContext();
        String requestedScope = ctx.getParams().getScope();
        if (requestedScope == null || requestedScope.isBlank()) {
            // Nothing requested: the exchanged token inherits the requester's
            // default scopes, which are client configuration and already
            // bounded by the audience rules. Nothing to intersect.
            return;
        }

        Set<String> granted = scopesOf(ctx.getParams().getSubjectToken());
        Set<String> excess = Arrays.stream(requestedScope.trim().split("\\s+"))
                .filter(s -> !s.isBlank())
                .filter(s -> !STRUCTURAL.contains(s))
                .filter(s -> !granted.contains(s))
                .collect(Collectors.toCollection(LinkedHashSet::new));

        if (!excess.isEmpty()) {
            throw new ClientPolicyException(OAuthErrorException.INVALID_SCOPE,
                    "Requested scope exceeds the delegated authority in the subject token: "
                            + String.join(" ", excess),
                    Response.Status.BAD_REQUEST);
        }
    }

    /** Scopes carried by the subject token, or a refusal if it cannot be read. */
    private Set<String> scopesOf(String subjectToken) throws ClientPolicyException {
        if (subjectToken == null || subjectToken.isBlank()) {
            throw new ClientPolicyException(OAuthErrorException.INVALID_REQUEST,
                    "Token exchange with a requested scope requires a subject token",
                    Response.Status.BAD_REQUEST);
        }
        AccessToken token;
        try {
            token = TokenVerifier.create(subjectToken, AccessToken.class).getToken();
        } catch (Exception e) {
            // Fail closed. The provider will reject this token anyway; we must
            // not let an unreadable token read as "grants everything".
            throw new ClientPolicyException(OAuthErrorException.INVALID_REQUEST,
                    "Subject token could not be parsed for scope evaluation",
                    Response.Status.BAD_REQUEST);
        }
        String scope = token.getScope();
        if (scope == null || scope.isBlank()) {
            return Set.of();
        }
        return Arrays.stream(scope.trim().split("\\s+"))
                .filter(s -> !s.isBlank())
                .collect(Collectors.toSet());
    }

    public static class Configuration
            extends org.keycloak.representations.idm.ClientPolicyExecutorConfigurationRepresentation {
    }
}

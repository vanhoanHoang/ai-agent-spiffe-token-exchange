package internal.lab.kcspi;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.keycloak.OAuthErrorException;
import org.keycloak.TokenVerifier;
import org.keycloak.models.KeycloakSession;
import org.keycloak.protocol.oidc.TokenExchangeContext;
import org.keycloak.representations.AccessToken;
import org.keycloak.representations.idm.ClientPolicyExecutorConfigurationRepresentation;
import org.keycloak.services.clientpolicy.ClientPolicyContext;
import org.keycloak.services.clientpolicy.ClientPolicyException;
import org.keycloak.services.clientpolicy.context.TokenExchangeRequestContext;
import org.keycloak.services.clientpolicy.executor.ClientPolicyExecutorProvider;

import com.fasterxml.jackson.annotation.JsonProperty;

import jakarta.ws.rs.core.Response;

/**
 * The delegation table (M13): who may delegate to whom, carrying what, and how
 * far down the chain.
 *
 * Keycloak has no notion of a delegation chain — it will happily exchange a
 * token any number of times as long as each individual request is well formed.
 * The chain's shape is therefore something this lab has to state and enforce
 * itself, and this executor is where that statement lives. It runs on every
 * exchange request, before the provider does any work.
 *
 * <h3>Depth cannot be forged</h3>
 * Depth is counted from the {@code act} chain inside the subject token, and
 * only the authorization server ever writes {@code act}. A caller cannot make
 * a third hop look like a first one by asking nicely; it would have to forge a
 * token the server is about to verify.
 *
 * <p>Configuration is a list of rows, each naming an actor client, the
 * audiences it may address, the scopes it may carry, and the maximum chain
 * depth it may participate in. An exchange by a client with no row is refused
 * when {@code refuseUnlistedActors} is set, which is how the lab keeps the
 * table exhaustive rather than advisory.
 */
public class DelegationTableExecutor
        implements ClientPolicyExecutorProvider<DelegationTableExecutor.Configuration> {

    public static final String PROVIDER_ID = "delegation-table";

    // no session state needed: every input arrives on the exchange context
    private Configuration configuration = new Configuration();

    public DelegationTableExecutor(KeycloakSession session) {
        // session intentionally unused: every input arrives on the context
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
        String actor = ctx.getClient() == null ? null : ctx.getClient().getClientId();
        List<Row> rows = configuration.rows();

        Row row = rows.stream().filter(r -> r.actorMatches(actor)).findFirst().orElse(null);
        if (row == null) {
            if (configuration.isRefuseUnlistedActors()) {
                throw refuse("client '" + actor + "' has no delegation rule");
            }
            return;
        }

        // Depth: how many actors are already in the chain, plus the one this
        // request would add.
        int depth = chainDepth(ctx.getParams().getSubjectToken()) + 1;
        if (depth > row.maxDepth()) {
            throw refuse("delegation depth " + depth + " exceeds the limit of " + row.maxDepth()
                    + " for '" + actor + "'");
        }

        List<String> audiences = ctx.getParams().getAudience();
        if (audiences != null && !row.audiences().isEmpty()) {
            List<String> forbidden = audiences.stream()
                    .filter(a -> !row.audiences().contains(a))
                    .toList();
            if (!forbidden.isEmpty()) {
                throw refuse("'" + actor + "' may not delegate to " + String.join(" ", forbidden));
            }
        }

        String requestedScope = ctx.getParams().getScope();
        if (requestedScope != null && !requestedScope.isBlank() && !row.scopes().isEmpty()) {
            Set<String> allowed = row.scopes();
            List<String> excess = Arrays.stream(requestedScope.trim().split("\\s+"))
                    .filter(s -> !s.isBlank())
                    .filter(ExchangeScopeIntersectionExecutor::isDelegatedAuthority)
                    .filter(s -> !allowed.contains(s))
                    .toList();
            if (!excess.isEmpty()) {
                throw refuse("'" + actor + "' may not carry " + String.join(" ", excess));
            }
        }
    }

    /** Number of actors already recorded in the subject token's act chain. */
    private static int chainDepth(String subjectToken) throws ClientPolicyException {
        if (subjectToken == null || subjectToken.isBlank()) {
            return 0;
        }
        AccessToken token;
        try {
            token = TokenVerifier.create(subjectToken, AccessToken.class).getToken();
        } catch (Exception e) {
            // Same reasoning as the scope executor: the provider verifies this
            // very token immediately after, so an unreadable one buys a
            // refusal, never a pass.
            throw refuse("subject token could not be parsed for depth evaluation");
        }
        int depth = 0;
        Object node = token.getOtherClaims().get("act");
        while (node instanceof Map<?, ?> act) {
            depth++;
            node = act.get("act");
        }
        return depth;
    }

    private static ClientPolicyException refuse(String message) {
        return new ClientPolicyException(OAuthErrorException.ACCESS_DENIED,
                "Delegation refused: " + message, Response.Status.FORBIDDEN);
    }

    /** One row of the table. */
    public record Row(String actor, Set<String> audiences, Set<String> scopes, int maxDepth) {

        boolean actorMatches(String clientId) {
            return actor != null && actor.equals(clientId);
        }
    }

    public static class Configuration extends ClientPolicyExecutorConfigurationRepresentation {

        @JsonProperty("rows")
        private List<Map<String, Object>> rows;

        @JsonProperty("refuse-unlisted-actors")
        private boolean refuseUnlistedActors;

        public void setRows(List<Map<String, Object>> rows) {
            this.rows = rows;
        }

        public List<Map<String, Object>> getRows() {
            return rows;
        }

        public void setRefuseUnlistedActors(boolean refuseUnlistedActors) {
            this.refuseUnlistedActors = refuseUnlistedActors;
        }

        public boolean isRefuseUnlistedActors() {
            return refuseUnlistedActors;
        }

        List<Row> rows() {
            if (rows == null) {
                return List.of();
            }
            List<Row> parsed = new ArrayList<>();
            for (Map<String, Object> raw : rows) {
                parsed.add(new Row(
                        str(raw.get("actor")),
                        set(raw.get("audiences")),
                        set(raw.get("scopes")),
                        raw.get("max-depth") instanceof Number n ? n.intValue() : Integer.MAX_VALUE));
            }
            return parsed;
        }

        private static String str(Object value) {
            return value == null ? null : String.valueOf(value);
        }

        /** Accepts either a JSON array or a space-separated string. */
        private static Set<String> set(Object value) {
            if (value instanceof List<?> list) {
                return list.stream()
                        .map(String::valueOf)
                        .collect(Collectors.toCollection(LinkedHashSet::new));
            }
            if (value instanceof String s && !s.isBlank()) {
                return Arrays.stream(s.trim().split("\\s+"))
                        .collect(Collectors.toCollection(LinkedHashSet::new));
            }
            return Set.of();
        }
    }
}

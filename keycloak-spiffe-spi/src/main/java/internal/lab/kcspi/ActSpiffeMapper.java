package internal.lab.kcspi;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.ws.rs.core.MultivaluedMap;

import org.keycloak.OAuth2Constants;
import org.keycloak.TokenVerifier;
import org.keycloak.authentication.authenticators.client.FederatedJWTClientAuthenticator;
import org.keycloak.http.HttpRequest;
import org.keycloak.models.ClientModel;
import org.keycloak.models.ClientSessionContext;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.ProtocolMapperModel;
import org.keycloak.models.UserModel;
import org.keycloak.models.UserSessionModel;
import org.keycloak.protocol.oidc.mappers.AbstractOIDCProtocolMapper;
import org.keycloak.protocol.oidc.mappers.OIDCAccessTokenMapper;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.representations.AccessToken;

/**
 * RFC 8693 §4.1 {@code act} claim for the SPIFFE-authenticated agent (M7,
 * BUILD-PLAN as revised: Keycloak's standard token exchange has no actor_token
 * — the actor IS the authenticated requester client, whose identity was proven
 * by its JWT-SVID and is recorded on the client as jwt.credential.sub).
 *
 * Stamps {@code act.sub = <SPIFFE ID>} on access tokens issued to a
 * federated-JWT client, but only when the token's subject is a real human
 * (service-account subjects get no act — there is no delegation to assert).
 * SPIFFE ID never becomes user authorization: this claim is audit/identity
 * only (the one architectural rule).
 */
public class ActSpiffeMapper extends AbstractOIDCProtocolMapper implements OIDCAccessTokenMapper {

    public static final String PROVIDER_ID = "act-spiffe-mapper";

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public String getDisplayType() {
        return "act (SPIFFE actor) claim";
    }

    @Override
    public String getDisplayCategory() {
        return TOKEN_MAPPER_CATEGORY;
    }

    @Override
    public String getHelpText() {
        return "Adds act.sub with the requesting client's SPIFFE ID (jwt.credential.sub) "
                + "to access tokens whose subject is a human user (RFC 8693 delegation semantics).";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return List.of();
    }

    @Override
    public String getProtocol() {
        return "openid-connect";
    }

    @Override
    public AccessToken transformAccessToken(AccessToken token, ProtocolMapperModel mappingModel,
            KeycloakSession session, UserSessionModel userSession, ClientSessionContext clientSessionCtx) {
        ClientModel requester = clientSessionCtx.getClientSession().getClient();
        String spiffeId = requester.getAttribute(FederatedJWTClientAuthenticator.JWT_CREDENTIAL_SUBJECT_KEY);
        if (spiffeId == null || spiffeId.isBlank()) {
            return token;
        }
        UserModel user = userSession.getUser();
        if (user == null || user.getServiceAccountClientLink() != null) {
            // no human subject -> no delegation -> no act
            return token;
        }
        // RFC 8693 §4.1: when the party we are acting for was ITSELF acting for
        // someone, the previous chain nests inside ours. Reading it from the
        // inbound subject token is what turns a flat actor into a delegation
        // history: act = {sub: me, act: {sub: whoever called me}}.
        Map<String, Object> act = new LinkedHashMap<>();
        act.put("sub", spiffeId);
        AccessToken subject = subjectToken(session);
        Map<String, Object> inbound = actOf(subject);
        if (inbound != null) {
            act.put("act", inbound);
        }
        token.getOtherClaims().put("act", act);

        // The ceiling for the WHOLE chain: what the human actually granted at
        // consent. Each hop narrows its own token to what that hop needs, so by
        // hop two the inbound scope no longer describes the human's authority
        // — only this claim still does. Stamped once at the first hop and
        // carried unchanged afterwards, it is what lets a later hop ask for a
        // scope its caller never held without letting it exceed the human.
        String ceiling = delegationCeiling(subject);
        if (ceiling != null && !ceiling.isBlank()) {
            token.getOtherClaims().put(DELEGATION_CEILING, ceiling);
        }
        return token;
    }

    /** Claim carrying the human's original grant down the delegation chain. */
    public static final String DELEGATION_CEILING = "del_scope";

    private static Map<String, Object> actOf(AccessToken subject) {
        if (subject == null) {
            return null;
        }
        Object existing = subject.getOtherClaims().get("act");
        return (existing instanceof Map<?, ?> map) ? castChain(map) : null;
    }

    /**
     * An existing ceiling is authoritative and travels unchanged; without one
     * this is the first hop, and the subject token IS the human's grant.
     */
    private static String delegationCeiling(AccessToken subject) {
        if (subject == null) {
            return null;
        }
        Object carried = subject.getOtherClaims().get(DELEGATION_CEILING);
        if (carried instanceof String s && !s.isBlank()) {
            return s;
        }
        return subject.getScope();
    }

    /**
     * The subject token presented at this exchange, if this is an exchange at
     * all. Read from the request's own form parameters: at mapper time the
     * exchange has already VERIFIED that token (the provider validates it
     * before generating a response), so this is not a trust decision — it is
     * reading claims from a token the server has already accepted.
     *
     * Null on a first-party grant, which is exactly when no chain should exist.
     */
    private static AccessToken subjectToken(KeycloakSession session) {
        try {
            HttpRequest request = session.getContext().getHttpRequest();
            if (request == null) {
                return null;
            }
            MultivaluedMap<String, String> form = request.getDecodedFormParameters();
            if (form == null) {
                return null;
            }
            String subjectToken = form.getFirst(OAuth2Constants.SUBJECT_TOKEN);
            if (subjectToken == null || subjectToken.isBlank()) {
                return null;
            }
            return TokenVerifier.create(subjectToken, AccessToken.class).getToken();
        } catch (Exception e) {
            // A chain we cannot read is not a chain we may invent. Emitting a
            // flat act here would silently shorten the audit trail, so the
            // failure is loud rather than lossy.
            throw new IllegalStateException("cannot read the inbound delegation state", e);
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castChain(Map<?, ?> map) {
        return (Map<String, Object>) map;
    }
}

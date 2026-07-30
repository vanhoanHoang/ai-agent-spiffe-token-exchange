package internal.lab.kcspi;

import java.util.List;
import java.util.Map;

import org.keycloak.authentication.authenticators.client.FederatedJWTClientAuthenticator;
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
        token.getOtherClaims().put("act", Map.of("sub", spiffeId));
        return token;
    }
}

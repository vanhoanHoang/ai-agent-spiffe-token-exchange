package internal.lab.kcspi;

import java.util.List;

import org.keycloak.Config.Scope;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.services.clientpolicy.executor.ClientPolicyExecutorProvider;
import org.keycloak.services.clientpolicy.executor.ClientPolicyExecutorProviderFactory;

/**
 * Factory for {@link DelegationTableExecutor}. The table itself is realm
 * configuration (client-policy JSON), not code, so the rows can change without
 * a rebuild — but the shape of the rule cannot.
 */
public class DelegationTableExecutorFactory implements ClientPolicyExecutorProviderFactory {

    @Override
    public ClientPolicyExecutorProvider<?> create(KeycloakSession session) {
        return new DelegationTableExecutor(session);
    }

    @Override
    public void init(Scope config) {
    }

    @Override
    public void postInit(KeycloakSessionFactory factory) {
    }

    @Override
    public void close() {
    }

    @Override
    public String getId() {
        return DelegationTableExecutor.PROVIDER_ID;
    }

    @Override
    public String getHelpText() {
        return "Enforces a delegation table on token exchange: which actor may address which audience, "
                + "carrying which scopes, up to which chain depth.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return List.of();
    }
}

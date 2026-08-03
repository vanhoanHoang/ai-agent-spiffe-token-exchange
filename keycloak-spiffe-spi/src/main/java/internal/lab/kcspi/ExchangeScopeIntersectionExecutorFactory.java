package internal.lab.kcspi;

import java.util.List;

import org.keycloak.Config.Scope;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.services.clientpolicy.executor.ClientPolicyExecutorProvider;
import org.keycloak.services.clientpolicy.executor.ClientPolicyExecutorProviderFactory;

/**
 * Factory for {@link ExchangeScopeIntersectionExecutor}. No configuration: the
 * rule it enforces is architectural (CLAUDE.md §2), not a per-realm preference.
 */
public class ExchangeScopeIntersectionExecutorFactory implements ClientPolicyExecutorProviderFactory {

    @Override
    public ClientPolicyExecutorProvider<?> create(KeycloakSession session) {
        return new ExchangeScopeIntersectionExecutor(session);
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
        return ExchangeScopeIntersectionExecutor.PROVIDER_ID;
    }

    @Override
    public String getHelpText() {
        return "Refuses a token exchange whose requested scope is not already carried by the subject token "
                + "(permissions shrink along a delegation chain, never grow).";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return List.of();
    }
}

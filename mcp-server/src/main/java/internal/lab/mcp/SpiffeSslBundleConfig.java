package internal.lab.mcp;

import java.security.GeneralSecurityException;
import java.security.KeyStore;
import org.jspecify.annotations.Nullable;

import io.spiffe.provider.SpiffeProviderConstants;
import org.springframework.boot.autoconfigure.ssl.SslBundleRegistrar;
import org.springframework.boot.ssl.SslBundle;
import org.springframework.boot.ssl.SslStoreBundle;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Registers the "spiffe" SSL bundle referenced by {@code server.ssl.bundle}.
 * Boot's Tomcat integration consumes the bundle's STORES (verified in
 * spring-boot-tomcat 4.1.0 SslConnectorCustomizer#configureSslStores), so this
 * provides the provider's "Spiffe" KeyStore for both key and trust store; the
 * matching managers come from the default KMF/TMF algorithm override done in
 * {@link McpServerApplication#main}. The KeyManager serves the current
 * X509-SVID per handshake (rotation-safe) and the TrustManager validates peers
 * against the lab.internal SPIFFE bundle — never the system trust store
 * (three-trust-store table, ARCHITECTURE.md).
 */
@Configuration
public class SpiffeSslBundleConfig {

    @Bean
    SslBundleRegistrar spiffeSslBundleRegistrar() {
        return registry -> {
            try {
                KeyStore spiffeKeyStore = KeyStore.getInstance(SpiffeProviderConstants.ALGORITHM);
                spiffeKeyStore.load(null, null);
                KeyStore spiffeTrustStore = KeyStore.getInstance(SpiffeProviderConstants.ALGORITHM);
                spiffeTrustStore.load(null, null);
                SslStoreBundle stores = new SslStoreBundle() {
                    @Override
                    public KeyStore getKeyStore() {
                        return spiffeKeyStore;
                    }

                    @Override
                    public @Nullable String getKeyStorePassword() {
                        return null;
                    }

                    @Override
                    public KeyStore getTrustStore() {
                        return spiffeTrustStore;
                    }
                };
                registry.registerBundle("spiffe", SslBundle.of(stores));
            } catch (GeneralSecurityException | java.io.IOException e) {
                // fail closed: without the SPIFFE stores there is no server to run
                throw new IllegalStateException("cannot initialize SPIFFE SSL bundle", e);
            }
        };
    }
}

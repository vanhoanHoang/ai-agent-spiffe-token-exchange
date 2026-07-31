package internal.lab.agent;

import java.util.Collections;
import java.util.Set;
import java.util.function.Supplier;
import javax.net.ssl.SSLContext;

import io.spiffe.provider.SpiffeSslContextFactory;
import io.spiffe.provider.SpiffeSslContextFactory.SslContextOptions;
import io.spiffe.spiffeid.SpiffeId;
import io.spiffe.workloadapi.DefaultJwtSource;
import io.spiffe.workloadapi.DefaultX509Source;
import io.spiffe.workloadapi.JwtSource;
import io.spiffe.workloadapi.X509Source;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * The workload's identity material, from the Workload API only (never files,
 * never a default trust store — ARCHITECTURE.md three-trust-store rules).
 * The model layer has no access to anything defined here.
 */
@Configuration
public class SpiffeIdentityConfig {

    static final SpiffeId MCP_SERVER_ID = SpiffeId.parse("spiffe://ai-agent.id.eviden.internal/mcp-server");

    @Bean(destroyMethod = "close")
    X509Source x509Source() throws Exception {
        return DefaultX509Source.newSource();
    }

    @Bean(destroyMethod = "close")
    JwtSource jwtSource() throws Exception {
        return DefaultJwtSource.newSource();
    }

    /**
     * mTLS to the MCP server: our SVID as client cert, the SPIFFE bundle as
     * trust anchor, peer accepted only if it IS the mcp-server SPIFFE ID.
     * SVIDs carry URI SANs only, so DNS hostname verification cannot apply;
     * the accepted-ID check is strictly stronger (D-006 §4).
     */
    @Bean
    SSLContext spiffeSslContext(X509Source source) throws Exception {
        Supplier<Set<SpiffeId>> accepted = () -> Collections.singleton(MCP_SERVER_ID);
        return SpiffeSslContextFactory.getSslContext(SslContextOptions.builder()
                .x509Source(source)
                .acceptedSpiffeIdsSupplier(accepted)
                .build());
    }
}

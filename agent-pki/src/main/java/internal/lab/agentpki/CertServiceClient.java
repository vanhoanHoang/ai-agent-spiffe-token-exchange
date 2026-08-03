package internal.lab.agentpki;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.Collections;
import java.util.Map;
import java.util.Set;
import java.util.function.Supplier;
import javax.net.ssl.SSLContext;

import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.HttpClientStreamableHttpTransport;
import io.modelcontextprotocol.common.McpTransportContext;
import io.spiffe.provider.SpiffeSslContextFactory;
import io.spiffe.provider.SpiffeSslContextFactory.SslContextOptions;
import io.spiffe.spiffeid.SpiffeId;
import io.spiffe.workloadapi.DefaultJwtSource;
import io.spiffe.workloadapi.DefaultX509Source;
import io.spiffe.workloadapi.JwtSource;
import io.spiffe.workloadapi.X509Source;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Outbound identity and transport for the second hop.
 *
 * Same three-trust-store discipline as every other client in the lab: the
 * X509-SVID is the client certificate, the SPIFFE bundle is the only trust
 * anchor, and the peer is accepted only if it IS the certificate service's
 * SPIFFE ID. SVIDs carry URI SANs only, so DNS hostname verification cannot
 * apply and the accepted-ID check replaces it (D-006 §4).
 *
 * The bearer travels per request through the SDK's transport context, exactly
 * as agent-client does it, and a call with no bearer in scope fails closed
 * rather than going out unauthenticated.
 */
@Configuration
public class CertServiceClient {

    static final String BEARER_KEY = "delegated.bearer";

    @Bean(destroyMethod = "close")
    X509Source x509Source() throws Exception {
        return DefaultX509Source.newSource();
    }

    @Bean(destroyMethod = "close")
    JwtSource jwtSource() throws Exception {
        return DefaultJwtSource.newSource();
    }

    @Bean
    SSLContext certServiceSslContext(X509Source source,
            @Value("${pki.cert-service.spiffe-id}") String certServiceId) throws Exception {
        Supplier<Set<SpiffeId>> accepted = () -> Collections.singleton(SpiffeId.parse(certServiceId));
        return SpiffeSslContextFactory.getSslContext(SslContextOptions.builder()
                .x509Source(source)
                .acceptedSpiffeIdsSupplier(accepted)
                .build());
    }

    @Bean(destroyMethod = "close")
    McpSyncClient certServiceMcpClient(SSLContext certServiceSslContext, BearerHolder bearer,
            @Value("${pki.cert-service.base-url}") String baseUrl) {
        var transport = HttpClientStreamableHttpTransport.builder(baseUrl)
                .endpoint("/mcp")
                .clientBuilder(HttpClient.newBuilder()
                        .version(HttpClient.Version.HTTP_1_1)
                        .sslContext(certServiceSslContext))
                .httpRequestCustomizer((builder, method, endpoint, body, context) -> {
                    Object token = context.get(BEARER_KEY);
                    if (token == null) {
                        throw new IllegalStateException(
                                "cert-service call without an exchanged bearer (fail closed)");
                    }
                    builder.header("Authorization", "Bearer " + token);
                })
                .build();

        return McpClient.sync(transport)
                .requestTimeout(Duration.ofSeconds(60))
                .transportContextProvider(() -> McpTransportContext
                        .create(Map.of(BEARER_KEY, bearer.required())))
                .build();
    }
}

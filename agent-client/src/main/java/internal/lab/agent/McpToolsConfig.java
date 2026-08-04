package internal.lab.agent;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.Map;
import javax.net.ssl.SSLContext;

import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.HttpClientStreamableHttpTransport;
import io.modelcontextprotocol.common.McpTransportContext;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * The hand-built MCP clients (D-010, BUILD-PLAN M10): Spring AI never
 * constructs a transport here. The java-spiffe SSLContext enters through
 * {@code clientBuilder(...)}; the exchanged bearer enters PER REQUEST through
 * {@code transportContextProvider} + {@code httpRequestCustomizer(...)} — the
 * SDK's sanctioned channel for exactly this ("do not rely on thread-locals"
 * in the customizer; the provider supplier runs on the calling thread and
 * hands over what {@link BearerHolder} holds for the current message).
 *
 * Since M12 there are TWO targets, and one exchanged token serves both: the
 * agent's Keycloak client carries mcp-audience AND pki-audience as default
 * client scopes, so a single hop-1 token is addressed to each. What differs
 * per target is the peer identity, which is why each client gets its own
 * SSLContext rather than sharing one that would accept either.
 */
@Configuration
public class McpToolsConfig {

    @Bean(destroyMethod = "close")
    McpSyncClient mcpSyncClient(@Qualifier("spiffeSslContext") SSLContext ssl, BearerHolder bearer) {
        return client(System.getenv().getOrDefault("MCP_BASE_URL",
                "https://mcp.ai-agent.id.eviden.internal:8443"), ssl, bearer);
    }

    /**
     * The PKI agent — the workload that holds {@code issue:employee-cert} and
     * that this agent must delegate to, because it holds no such scope itself.
     */
    @Bean(destroyMethod = "close")
    McpSyncClient pkiMcpClient(@Qualifier("pkiSslContext") SSLContext ssl, BearerHolder bearer) {
        return client(System.getenv().getOrDefault("PKI_BASE_URL",
                "https://pki-agent.ai-agent.id.eviden.internal:8445"), ssl, bearer);
    }

    private static McpSyncClient client(String baseUrl, SSLContext ssl, BearerHolder bearer) {
        var transport = HttpClientStreamableHttpTransport.builder(baseUrl)
                .endpoint("/mcp")
                // Peer authentication is the SpiffeTrustManager's accepted-ID
                // check inside this SSLContext, which replaces DNS hostname
                // verification (D-006 §4). Each client accepts one peer only.
                .clientBuilder(HttpClient.newBuilder()
                        .version(HttpClient.Version.HTTP_1_1)
                        .sslContext(ssl))
                .httpRequestCustomizer((builder, method, endpoint, body, context) -> {
                    Object token = context.get(BearerHolder.CONTEXT_KEY);
                    if (token == null) {
                        throw new IllegalStateException(
                                "MCP request without an exchanged bearer (fail closed)");
                    }
                    builder.header("Authorization", "Bearer " + token);
                })
                .build();

        return McpClient.sync(transport)
                .requestTimeout(Duration.ofSeconds(120))
                .transportContextProvider(() -> McpTransportContext
                        .create(Map.of(BearerHolder.CONTEXT_KEY, bearer.required())))
                .build();
    }
}

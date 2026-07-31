package internal.lab.agent;

import java.net.http.HttpClient;
import java.time.Duration;
import java.util.Map;
import javax.net.ssl.SSLContext;

import io.modelcontextprotocol.client.McpClient;
import io.modelcontextprotocol.client.McpSyncClient;
import io.modelcontextprotocol.client.transport.HttpClientStreamableHttpTransport;
import io.modelcontextprotocol.common.McpTransportContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * The hand-built MCP client (D-010, BUILD-PLAN M10): Spring AI never
 * constructs a transport here. The java-spiffe SSLContext enters through
 * {@code clientBuilder(...)}; the exchanged bearer enters PER REQUEST through
 * {@code transportContextProvider} + {@code httpRequestCustomizer(...)} — the
 * SDK's sanctioned channel for exactly this ("do not rely on thread-locals"
 * in the customizer; the provider supplier runs on the calling thread and
 * hands over what {@link BearerHolder} holds for the current message).
 */
@Configuration
public class McpToolsConfig {

    @Bean(destroyMethod = "close")
    McpSyncClient mcpSyncClient(SSLContext spiffeSslContext, BearerHolder bearer) {
        String baseUrl = System.getenv().getOrDefault("MCP_BASE_URL", "https://mcp.ai-agent.id.eviden.internal:8443");

        var transport = HttpClientStreamableHttpTransport.builder(baseUrl)
                .endpoint("/mcp")
                // Peer authentication is the SpiffeTrustManager's accepted-ID
                // check inside this SSLContext (mcp-server's SPIFFE ID), which
                // replaces DNS hostname verification (D-006 §4).
                .clientBuilder(HttpClient.newBuilder()
                        .version(HttpClient.Version.HTTP_1_1)
                        .sslContext(spiffeSslContext))
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
                .requestTimeout(Duration.ofSeconds(30))
                .transportContextProvider(() -> McpTransportContext
                        .create(Map.of(BearerHolder.CONTEXT_KEY, bearer.required())))
                .build();
    }
}

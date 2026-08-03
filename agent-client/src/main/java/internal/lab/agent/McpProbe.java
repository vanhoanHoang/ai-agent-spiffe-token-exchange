package internal.lab.agent;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Collections;
import java.util.Set;
import java.util.function.Supplier;
import javax.net.ssl.SSLContext;

import io.spiffe.provider.SpiffeSslContextFactory;
import io.spiffe.provider.SpiffeSslContextFactory.SslContextOptions;
import io.spiffe.spiffeid.SpiffeId;
import io.spiffe.workloadapi.DefaultX509Source;
import io.spiffe.workloadapi.X509Source;

/**
 * Raw MCP protocol probe over SVID mTLS (M10 P1 exit check): performs
 * initialize / tools/list / tools/call against the streamable-HTTP endpoint
 * with the exchanged bearer token. Deliberately hand-rolled JSON-RPC — the
 * check must exercise the protocol and the security stack, not a client
 * library's conveniences.
 *
 * Usage: McpProbe mcp <endpoint> <method> [toolName]  (TOKEN from env)
 */
final class McpProbe {

    private static final SpiffeId MCP_SERVER_ID = SpiffeId.parse("spiffe://ai-agent.id.eviden.internal/mcp-server");

    private McpProbe() {
    }

    static void run(String endpoint, String method, String toolName) throws Exception {
        String token = System.getenv().getOrDefault("TOKEN", "");
        // Which peer this probe will accept. Defaults to the MCP server; the
        // two-hop checks point it at the PKI agent or the certificate service.
        // Still an explicit accepted-ID check, never a relaxed one — pointing
        // it elsewhere changes WHO is trusted, not WHETHER anyone is.
        SpiffeId peerId = SpiffeId.parse(
                System.getenv().getOrDefault("PEER_SPIFFE_ID", MCP_SERVER_ID.toString()));
        try (X509Source source = DefaultX509Source.newSource()) {
            Supplier<Set<SpiffeId>> accepted = () -> Collections.singleton(peerId);
            SSLContext ssl = SpiffeSslContextFactory.getSslContext(SslContextOptions.builder()
                    .x509Source(source)
                    .acceptedSpiffeIdsSupplier(accepted)
                    .build());
            HttpClient http = HttpClient.newBuilder().sslContext(ssl)
                    .connectTimeout(Duration.ofSeconds(10)).build();

            String initBody = """
                    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{\
                    "protocolVersion":"2025-06-18","capabilities":{},\
                    "clientInfo":{"name":"lab-probe","version":"0.1.0"}}}""";
            HttpResponse<String> init = send(http, endpoint, token, initBody, null);
            String sessionId = init.headers().firstValue("mcp-session-id").orElse(null);
            if ("initialize".equals(method)) {
                print(init);
                return;
            }

            // Tool arguments come from TOOL_ARGS (raw JSON object) when a tool
            // needs them; the M9-era probes call argument-less tools and are
            // unaffected.
            String toolArgs = System.getenv().getOrDefault("TOOL_ARGS", "{}");
            String body = "tools/call".equals(method)
                    ? """
                      {"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"%s","arguments":%s}}"""
                            .formatted(toolName, toolArgs)
                    : """
                      {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}""";
            print(send(http, endpoint, token, body, sessionId));
        }
    }

    private static HttpResponse<String> send(HttpClient http, String endpoint, String token, String body,
            String sessionId) throws Exception {
        HttpRequest.Builder req = HttpRequest.newBuilder(URI.create(endpoint))
                .header("Content-Type", "application/json")
                .header("Accept", "application/json, text/event-stream")
                .POST(HttpRequest.BodyPublishers.ofString(body));
        if (!token.isEmpty()) {
            req.header("Authorization", "Bearer " + token);
        }
        if (sessionId != null) {
            req.header("Mcp-Session-Id", sessionId);
        }
        return http.send(req.build(), HttpResponse.BodyHandlers.ofString());
    }

    private static void print(HttpResponse<String> res) {
        System.out.println("HTTP " + res.statusCode());
        System.out.println(res.body());
    }
}

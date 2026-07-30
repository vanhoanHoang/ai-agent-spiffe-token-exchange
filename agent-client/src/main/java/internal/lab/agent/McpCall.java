package internal.lab.agent;

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.util.Collections;
import java.util.Set;
import java.util.function.Supplier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;

import io.spiffe.provider.SpiffeSslContextFactory;
import io.spiffe.provider.SpiffeSslContextFactory.SslContextOptions;
import io.spiffe.spiffeid.SpiffeId;
import io.spiffe.workloadapi.DefaultX509Source;
import io.spiffe.workloadapi.X509Source;

/**
 * M5 caller: fetch this workload's SVID from the Workload API, open mTLS to the
 * MCP server, present the bearer token, print "HTTP <code>" + body.
 *
 * Usage: java -jar agent-client.jar <url>   (token in env TOKEN, may be empty)
 */
public final class McpCall {

    private static final SpiffeId MCP_SERVER_ID = SpiffeId.parse("spiffe://lab.internal/mcp-server");

    private McpCall() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length >= 1 && "token".equals(args[0])) {
            // M6 mode: token <token-endpoint> — env: ISSUER (aud, sole value).
            // M7 mode: same + env SUBJECT_TOKEN -> RFC 8693 token exchange.
            // client_id is the workload's own SPIFFE ID, taken from its JWT-SVID.
            TokenRequest.run(
                    args[1],
                    System.getenv().getOrDefault("ISSUER", "http://keycloak:8080/realms/lab"),
                    System.getenv().get("SUBJECT_TOKEN"));
            return;
        }
        if (args.length != 1) {
            System.err.println("usage: McpCall <url> | McpCall token <token-endpoint>");
            System.exit(2);
        }
        String token = System.getenv().getOrDefault("TOKEN", "");

        try (X509Source source = DefaultX509Source.newSource()) {
            Supplier<Set<SpiffeId>> accepted = () -> Collections.singleton(MCP_SERVER_ID);
            SSLContext sslContext = SpiffeSslContextFactory.getSslContext(SslContextOptions.builder()
                    .x509Source(source)
                    .acceptedSpiffeIdsSupplier(accepted)
                    .build());

            HttpsURLConnection conn = (HttpsURLConnection) URI.create(args[0]).toURL().openConnection();
            conn.setSSLSocketFactory(sslContext.getSocketFactory());
            // SVIDs carry URI SANs only — DNS hostname matching cannot apply. Peer
            // authentication is the SpiffeTrustManager's accepted-ID check above
            // (MCP_SERVER_ID), which is strictly stronger than a DNS name (D-006 §4).
            conn.setHostnameVerifier((hostname, session) -> true);
            if (!token.isEmpty()) {
                conn.setRequestProperty("Authorization", "Bearer " + token);
            }

            int code = conn.getResponseCode();
            System.out.println("HTTP " + code);
            System.out.println(readBody(conn, code));
        }
    }

    private static String readBody(HttpsURLConnection conn, int code) throws IOException {
        InputStream stream = (code >= 400) ? conn.getErrorStream() : conn.getInputStream();
        if (stream == null) {
            return "";
        }
        try (stream) {
            return new String(stream.readAllBytes());
        }
    }
}

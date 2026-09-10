package internal.lab.agent;

import java.net.URI;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSocket;

import io.spiffe.spiffeid.SpiffeId;
import io.spiffe.workloadapi.X509Source;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The other side of the mTLS handshake, for the console's identity cards:
 * the certificate chain a peer presents, read from a real TLS session.
 *
 * The session is opened with the SAME SSLContext the agent's calls use for
 * that peer — our SVID as client certificate, the SPIFFE bundle as trust
 * anchor, exactly one accepted SPIFFE ID — so what is reported here is what a
 * real call would have accepted, and a wrong peer fails the handshake instead
 * of being displayed. Nothing is validated differently, nothing is relaxed;
 * this endpoint only reads the session and closes it. Metadata only.
 */
@RestController
@Profile("web")
public class PeerApiController {

    private static final int HANDSHAKE_TIMEOUT_MS = 5000;

    private record Target(SSLContext ssl, URI baseUrl) {
    }

    private final X509Source source;
    private final Map<String, Target> targets = new LinkedHashMap<>();

    PeerApiController(@Qualifier("spiffeSslContext") SSLContext mcp,
            @Qualifier("pkiSslContext") SSLContext pki, X509Source source) {
        this.source = source;
        targets.put("mcp-server", new Target(mcp, URI.create(System.getenv().getOrDefault("MCP_BASE_URL",
                "https://mcp.ai-agent.id.eviden.internal:8443"))));
        targets.put("agent-pki", new Target(pki, URI.create(System.getenv().getOrDefault("PKI_BASE_URL",
                "https://pki-agent.ai-agent.id.eviden.internal:8445"))));
    }

    @GetMapping("/api/peer")
    public ResponseEntity<Map<String, Object>> peer(@RequestParam("target") String target) throws Exception {
        Target t = targets.get(target);
        if (t == null) {
            return ResponseEntity.badRequest().body(Map.of("error", "unknown target; one of " + targets.keySet()));
        }
        int port = t.baseUrl().getPort() == -1 ? 443 : t.baseUrl().getPort();
        List<X509Certificate> presented = new ArrayList<>();
        try (SSLSocket socket = (SSLSocket) t.ssl().getSocketFactory().createSocket(t.baseUrl().getHost(), port)) {
            socket.setSoTimeout(HANDSHAKE_TIMEOUT_MS);
            socket.startHandshake();
            for (Certificate c : socket.getSession().getPeerCertificates()) {
                presented.add((X509Certificate) c);
            }
        }
        // The accepted-ID check already ran inside the handshake; the leaf's URI
        // SAN is therefore the peer's SPIFFE ID, reported as the session saw it.
        String spiffeId = CertJson.uriSans(presented.get(0)).stream().findFirst().orElse("");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("target", target);
        out.put("spiffeId", spiffeId);
        out.put("chain", CertJson.chain(presented, source, SpiffeId.parse(spiffeId).getTrustDomain()));
        return ResponseEntity.ok(out);
    }
}

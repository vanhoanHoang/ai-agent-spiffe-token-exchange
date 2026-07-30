package internal.lab.mcp;

import java.security.Security;

import io.spiffe.provider.SpiffeProvider;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class McpServerApplication {

    public static void main(String[] args) {
        // M5 (D-006): provider's documented Tomcat recipe (specs/java-spiffe/
        // java-spiffe-provider_README.md) — register the provider and make "Spiffe"
        // the default KMF/TMF algorithm so Tomcat's JSSE layer builds managers that
        // read the X509Source configured by SPIFFE_ENDPOINT_SOCKET. acceptAll only
        // skips the per-ID check at the TLS handshake — chain validation against the
        // lab.internal bundle still applies, and the SPIFFE-ID allowlist is enforced
        // with a 403 in SpiffeAllowlistFilter.
        SpiffeProvider.install();
        Security.setProperty("ssl.KeyManagerFactory.algorithm", "Spiffe");
        Security.setProperty("ssl.TrustManagerFactory.algorithm", "Spiffe");
        System.setProperty("ssl.spiffe.acceptAll", "true");
        SpringApplication.run(McpServerApplication.class, args);
    }
}

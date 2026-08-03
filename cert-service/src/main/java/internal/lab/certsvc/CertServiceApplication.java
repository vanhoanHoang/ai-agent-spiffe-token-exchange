package internal.lab.certsvc;

import java.security.Security;

import io.spiffe.provider.SpiffeProvider;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * The privileged end of the two-hop delegation chain (M12): the only service in
 * the lab that can cause a certificate to be issued for a person.
 *
 * Its allowlist contains agent-pki and nothing else. The assistant that talks to
 * the human cannot reach this service at all — not because it would be refused
 * politely, but because it is not an allowed peer, its tokens carry a different
 * audience, and it does not hold issue:employee-cert. That is the point of the
 * second hop.
 *
 * Same M5/D-006 provider recipe as the MCP server: register SpiffeProvider and
 * make "Spiffe" the default KMF/TMF algorithm so Tomcat builds managers backed
 * by the Workload API.
 */
@SpringBootApplication
public class CertServiceApplication {

    public static void main(String[] args) {
        SpiffeProvider.install();
        Security.setProperty("ssl.KeyManagerFactory.algorithm", "Spiffe");
        Security.setProperty("ssl.TrustManagerFactory.algorithm", "Spiffe");
        System.setProperty("ssl.spiffe.acceptAll", "true");
        SpringApplication.run(CertServiceApplication.class, args);
    }
}

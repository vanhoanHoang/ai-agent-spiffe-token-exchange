package internal.lab.agentpki;

import java.security.Security;

import io.spiffe.provider.SpiffeProvider;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * The PKI agent: the second hop of the delegation chain (M12).
 *
 * It receives an onboarding request that already carries a human's identity,
 * proves its own identity to the authorization server with its JWT-SVID,
 * exchanges the inbound token for one addressed to the certificate service, and
 * makes exactly one call.
 *
 * <h3>This service holds no language model, deliberately</h3>
 * The assistant next to the model is the weakest actor in the lab precisely so
 * that prompt injection buys as little as possible. That argument only holds
 * while the privileged hop stays deterministic. If a future change adds a
 * ChatClient here, the security story is broken even if every test still passes.
 */
@SpringBootApplication
public class AgentPkiApplication {

    public static void main(String[] args) {
        SpiffeProvider.install();
        Security.setProperty("ssl.KeyManagerFactory.algorithm", "Spiffe");
        Security.setProperty("ssl.TrustManagerFactory.algorithm", "Spiffe");
        System.setProperty("ssl.spiffe.acceptAll", "true");
        SpringApplication.run(AgentPkiApplication.class, args);
    }
}

package internal.lab.agent;

import java.util.Map;

import io.spiffe.svid.x509svid.X509Svid;
import io.spiffe.workloadapi.X509Source;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The agent's CURRENT X.509-SVID chain, straight from the Workload API, for
 * the console's expert view (P6). Public metadata per certificate, every
 * extension decoded ({@link X509Details}); no key, no PEM. Fetched fresh on
 * each call so rotation is visible. Shape shared with /api/peer and
 * /api/issued through {@link CertJson}.
 */
@RestController
@Profile("web")
public class SvidApiController {

    private final X509Source source;

    SvidApiController(X509Source source) {
        this.source = source;
    }

    @GetMapping("/api/svid")
    public Map<String, Object> svid() throws Exception {
        X509Svid svid = source.getX509Svid();
        return Map.of(
                "spiffeId", svid.getSpiffeId().toString(),
                "chain", CertJson.chain(svid.getChain(), source, svid.getSpiffeId().getTrustDomain()));
    }
}

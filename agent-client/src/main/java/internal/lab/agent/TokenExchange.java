package internal.lab.agent;

import java.util.function.Consumer;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import io.spiffe.svid.jwtsvid.JwtSvid;
import io.spiffe.workloadapi.JwtSource;
import org.springframework.stereotype.Component;

/**
 * Per-message RFC 8693 exchange: the human's subject token in, the delegated
 * access token (sub = human, act.sub = this workload's SPIFFE ID) out. The
 * subject token is an ARGUMENT — today the CLI passes SUBJECT_TOKEN from the
 * environment, P2.5 passes the browser session's token — so nothing here may
 * cache a token or bind one at startup.
 */
@Component
public class TokenExchange {

    private static final Pattern ACCESS_TOKEN = Pattern.compile("\"access_token\"\\s*:\\s*\"([^\"]+)\"");

    private final JwtSource jwtSource;
    private final String tokenEndpoint;
    private final String issuerIdentifier;

    TokenExchange(JwtSource jwtSource) {
        this.jwtSource = jwtSource;
        this.tokenEndpoint = System.getenv().getOrDefault("TOKEN_ENDPOINT",
                "http://keycloak:8080/realms/lab/protocol/openid-connect/token");
        this.issuerIdentifier = System.getenv().getOrDefault("ISSUER", "http://keycloak:8080/realms/lab");
    }

    String exchange(String subjectToken) throws Exception {
        return exchange(subjectToken, e -> { });
    }

    /** Same exchange, narrated: emits the REAL svid/exchange completions with
     *  identity labels only (never token material) — P6.1 live display. */
    String exchange(String subjectToken, Consumer<StepEvent> events) throws Exception {
        if (subjectToken == null || subjectToken.isBlank()) {
            throw new IllegalStateException("token exchange requires a subject token (fail closed)");
        }
        JwtSvid svid = jwtSource.fetchJwtSvid(issuerIdentifier);
        events.accept(new StepEvent("svid",
                "JWT-SVID minted for " + svid.getSpiffeId() + " (aud=" + issuerIdentifier + ")"));

        TokenRequest.Response res = TokenRequest.post(svid, tokenEndpoint, subjectToken);
        if (res.status() != 200) {
            throw new IllegalStateException("token exchange failed: HTTP " + res.status() + " " + res.body());
        }
        Matcher m = ACCESS_TOKEN.matcher(res.body());
        if (!m.find()) {
            throw new IllegalStateException("token exchange response carries no access_token");
        }
        events.accept(new StepEvent("exchange",
                "RFC 8693 exchange done: sub=alice's subject, act.sub=" + svid.getSpiffeId()));
        return m.group(1);
    }
}

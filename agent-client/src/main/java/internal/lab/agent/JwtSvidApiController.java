package internal.lab.agent;

import java.util.LinkedHashMap;
import java.util.Map;

import com.nimbusds.jwt.JWT;
import com.nimbusds.jwt.JWTParser;
import io.spiffe.svid.jwtsvid.JwtSvid;
import io.spiffe.workloadapi.JwtSource;
import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The agent's JWT-SVID, decoded — for the console's identity cards, in the
 * shape its token card already renders (header, claims, signature redacted).
 *
 * The token itself never leaves this method: it is minted for exactly the
 * audience the real client authentication uses (the AS issuer identifier, the
 * sole value — CLAUDE.md §3), decoded, and dropped. What goes out is the same
 * class of material the console shows for every other token: claims only.
 */
@RestController
@Profile("web")
public class JwtSvidApiController {

    private final JwtSource jwtSource;
    private final String issuerIdentifier;

    JwtSvidApiController(JwtSource jwtSource) {
        this.jwtSource = jwtSource;
        this.issuerIdentifier = System.getenv().getOrDefault("ISSUER", "http://keycloak:8080/realms/ai-agents");
    }

    @GetMapping("/api/jwt-svid")
    public Map<String, Object> jwtSvid() throws Exception {
        JwtSvid svid = jwtSource.fetchJwtSvid(issuerIdentifier);
        JWT jwt = JWTParser.parse(svid.getToken());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("name", "JWT-SVID");
        out.put("description", "The same workload as a signed claim set: sub is its SPIFFE ID, aud is the "
                + "authorization server's issuer identifier as the sole value. Decoded only — the token "
                + "itself is never shown.");
        out.put("header", new LinkedHashMap<>(jwt.getHeader().toJSONObject()));
        out.put("claims", new LinkedHashMap<>(jwt.getJWTClaimsSet().toJSONObject()));
        out.put("signature", "REDACTED");
        return out;
    }
}

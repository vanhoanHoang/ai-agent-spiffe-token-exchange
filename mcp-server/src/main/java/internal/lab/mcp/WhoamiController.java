package internal.lab.mcp;

import java.util.Map;
import java.util.Objects;

import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Minimal protected endpoint. From M7 on, `act.sub` is logged on every call
 * (M9 chain-of-custody check greps for it); the claim is echoed already so the
 * shape doesn't change later.
 */
@RestController
public class WhoamiController {

    @GetMapping("/api/whoami")
    public Map<String, Object> whoami(@AuthenticationPrincipal Jwt jwt) {
        return Map.of(
                "sub", jwt.getSubject(),
                "aud", jwt.getAudience(),
                "act", Objects.requireNonNullElse(jwt.getClaim("act"), Map.of()));
    }
}

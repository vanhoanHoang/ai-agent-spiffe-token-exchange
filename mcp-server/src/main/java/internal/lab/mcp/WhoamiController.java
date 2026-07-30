package internal.lab.mcp;

import java.util.Map;
import java.util.Objects;

import jakarta.servlet.http.HttpServletRequest;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
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

    private static final Logger log = LoggerFactory.getLogger(WhoamiController.class);

    @GetMapping("/api/whoami")
    public Map<String, Object> whoami(@AuthenticationPrincipal Jwt jwt, HttpServletRequest request) {
        Object act = Objects.requireNonNullElse(jwt.getClaim("act"), Map.of());
        // M7/M9 chain-of-custody: sub AND act on every call (acceptance greps "act")
        log.info("call sub={} act={} aud={} peer={}",
                jwt.getSubject(), act, jwt.getAudience(), request.getAttribute("mcp.peer.spiffeId"));
        return Map.of(
                "sub", jwt.getSubject(),
                "aud", jwt.getAudience(),
                "act", act);
    }
}

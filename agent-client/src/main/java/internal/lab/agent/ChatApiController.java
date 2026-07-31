package internal.lab.agent;

import java.util.List;
import java.util.Map;

import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientService;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

/**
 * P6: the JSON surface the live console talks to — same origin, session
 * cookie, CSRF via header. Same rules as the page: alice's token stays in the
 * server-side session; the response carries an ANSWER, never a token.
 */
@RestController
@Profile("web")
public class ChatApiController {

    record ChatRequest(String message) {
    }

    private final AgentLoop loop;
    private final OAuth2AuthorizedClientService clients;

    ChatApiController(AgentLoop loop, OAuth2AuthorizedClientService clients) {
        this.loop = loop;
        this.clients = clients;
    }

    /** Who is logged in (401-shaped when nobody), plus the CSRF token the
     *  console must echo back in X-CSRF-TOKEN. */
    @GetMapping("/api/me")
    public ResponseEntity<Map<String, Object>> me(Authentication auth, CsrfToken csrf) {
        if (!(auth instanceof OAuth2AuthenticationToken token)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "not_authenticated"));
        }
        OAuth2AuthorizedClient client = clients.loadAuthorizedClient(
                token.getAuthorizedClientRegistrationId(), token.getName());
        List<String> scopes = client == null ? List.of() : List.copyOf(client.getAccessToken().getScopes());
        return ResponseEntity.ok(Map.of(
                "username", String.valueOf(token.getPrincipal().getAttributes().getOrDefault("preferred_username", "?")),
                "scopes", scopes,
                "csrf", csrf.getToken()));
    }

    @PostMapping("/api/chat")
    public ResponseEntity<Map<String, Object>> chat(@RequestBody ChatRequest body,
            OAuth2AuthenticationToken auth) {
        OAuth2AuthorizedClient client = clients.loadAuthorizedClient(
                auth.getAuthorizedClientRegistrationId(), auth.getName());
        if (client == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "session_expired"));
        }
        String question = body.message() == null ? "" : body.message().strip();
        if (question.isEmpty()) {
            return ResponseEntity.badRequest().body(Map.of("error", "empty_message"));
        }
        try {
            // Per message: session token -> RFC 8693 exchange -> loop (D-012).
            return ResponseEntity.ok(Map.of("answer",
                    loop.ask(client.getAccessToken().getTokenValue(), question)));
        } catch (Exception e) {
            // UI surface: report the failure; enforcement already happened and
            // was logged server-side.
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                    .body(Map.of("error", String.valueOf(e.getMessage())));
        }
    }
}

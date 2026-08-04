package internal.lab.agent;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.client.OAuth2AuthorizeRequest;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClientManager;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

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
    private final OAuth2AuthorizedClientManager clients;
    private final ExecutorService streams = Executors.newVirtualThreadPerTaskExecutor();

    ChatApiController(AgentLoop loop, OAuth2AuthorizedClientManager clients) {
        this.loop = loop;
        this.clients = clients;
    }

    /** Alice's authorized client with a CURRENTLY VALID access token — the
     *  manager refreshes via the stored refresh token when the access token
     *  expired mid-session (Keycloak default: 5 min). Null when the session
     *  can no longer be refreshed: the caller answers 401, re-login required. */
    private OAuth2AuthorizedClient freshClient(OAuth2AuthenticationToken auth,
            HttpServletRequest request, HttpServletResponse response) {
        try {
            return clients.authorize(OAuth2AuthorizeRequest
                    .withClientRegistrationId(auth.getAuthorizedClientRegistrationId())
                    .principal(auth)
                    .attributes(attrs -> {
                        attrs.put(HttpServletRequest.class.getName(), request);
                        attrs.put(HttpServletResponse.class.getName(), response);
                    })
                    .build());
        } catch (Exception e) {
            // refresh grant rejected (session revoked / SSO idle exceeded)
            return null;
        }
    }

    /** Who is logged in (401-shaped when nobody), plus the CSRF token the
     *  console must echo back in X-CSRF-TOKEN. */
    @GetMapping("/api/me")
    public ResponseEntity<Map<String, Object>> me(Authentication auth, CsrfToken csrf,
            HttpServletRequest request, HttpServletResponse response) {
        if (!(auth instanceof OAuth2AuthenticationToken token)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).body(Map.of("error", "not_authenticated"));
        }
        OAuth2AuthorizedClient client = freshClient(token, request, response);
        List<String> scopes = client == null ? List.of() : List.copyOf(client.getAccessToken().getScopes());
        return ResponseEntity.ok(Map.of(
                "username", String.valueOf(token.getPrincipal().getAttributes().getOrDefault("preferred_username", "?")),
                "scopes", scopes,
                "csrf", csrf.getToken()));
    }

    @PostMapping("/api/chat")
    public ResponseEntity<Map<String, Object>> chat(@RequestBody ChatRequest body,
            OAuth2AuthenticationToken auth, HttpServletRequest request, HttpServletResponse response) {
        OAuth2AuthorizedClient client = freshClient(auth, request, response);
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

    /** P6.1 (D-018): same chat, streamed — each REAL chain event (svid,
     *  exchange, every tool call) is sent the moment it completes, then the
     *  answer. The subject token is resolved on the request thread; the loop
     *  runs on a virtual thread so the emitter can flush as events land. */
    @PostMapping(value = "/api/chat/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter chatStream(@RequestBody ChatRequest body, OAuth2AuthenticationToken auth,
            HttpServletRequest request, HttpServletResponse response) {
        OAuth2AuthorizedClient client = freshClient(auth, request, response);
        String question = body.message() == null ? "" : body.message().strip();
        if (client == null || question.isEmpty()) {
            throw new IllegalArgumentException(client == null ? "session_expired" : "empty_message");
        }
        String subjectToken = client.getAccessToken().getTokenValue();
        // A tool-calling turn is at least two model round-trips, and the demo
        // default is a small local model on CPU (~5 tok/s). Five minutes ran
        // out mid-turn and the browser saw a dead stream with no explanation;
        // the ceiling exists to bound a hang, not to race the model.
        SseEmitter emitter = new SseEmitter(900_000L);
        streams.execute(() -> {
            try {
                String answer = loop.ask(subjectToken, question,
                        e -> emit(emitter, e.step(), e.detail()));
                emit(emitter, "answer", answer);
                emitter.complete();
            } catch (Exception e) {
                emit(emitter, "error", String.valueOf(e.getMessage()));
                emitter.complete();
            }
        });
        return emitter;
    }

    private static void emit(SseEmitter emitter, String event, String data) {
        try {
            emitter.send(SseEmitter.event().name(event).data(data));
        } catch (Exception ignored) {
            // client went away mid-stream; the loop finishes server-side
        }
    }
}

package internal.lab.agent;

import java.util.ArrayList;
import java.util.List;

import jakarta.servlet.http.HttpSession;
import org.springframework.context.annotation.Profile;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.client.OAuth2AuthorizedClient;
import org.springframework.security.oauth2.client.annotation.RegisteredOAuth2AuthorizedClient;
import org.springframework.security.oauth2.core.user.OAuth2User;
import org.springframework.security.web.csrf.CsrfToken;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.util.HtmlUtils;

/**
 * P2.5: minimal server-rendered chat page (deliberately no template engine —
 * DEMO-PLAN says "no framework"). Per message: alice's SESSION token is the
 * subject token -> RFC 8693 exchange -> {@link AgentLoop}. The browser never
 * sees a token; transcripts live in the HTTP session.
 */
@Controller
@Profile("web")
public class ChatPageController {

    /** One question/answer pair of the session transcript. */
    record Turn(String question, String answer, boolean error) {
    }

    private final AgentLoop loop;

    ChatPageController(AgentLoop loop) {
        this.loop = loop;
    }

    @GetMapping(value = "/", produces = "text/html")
    @ResponseBody
    public String home(@AuthenticationPrincipal OAuth2User user, HttpSession session, CsrfToken csrf) {
        StringBuilder h = page();
        if (user == null) {
            h.append("<h1>Lab agent</h1>")
                    .append("<p>The agent acts <em>for you</em> — log in and consent to delegate.</p>")
                    .append("<p><a class=\"btn\" href=\"/oauth2/authorization/keycloak\">Log in</a> ")
                    .append("<a class=\"btn alt\" href=\"/oauth2/authorization/keycloak-audit\">")
                    .append("Log in granting audit scope</a></p>");
        } else {
            h.append("<h1>Lab agent</h1>")
                    .append("<p>Acting for <strong>")
                    .append(HtmlUtils.htmlEscape(String.valueOf(user.getAttributes().getOrDefault("preferred_username", "?"))))
                    .append("</strong> — every MCP call carries your <code>sub</code> and the agent's ")
                    .append("<code>act.sub</code>; the server logs both.</p>");
            for (Turn t : transcript(session)) {
                h.append("<div class=\"q\">").append(HtmlUtils.htmlEscape(t.question())).append("</div>")
                        .append("<div class=\"").append(t.error() ? "err" : "a").append("\">")
                        .append(HtmlUtils.htmlEscape(t.answer())).append("</div>");
            }
            h.append("<form method=\"post\" action=\"/chat\">")
                    .append(csrfField(csrf))
                    .append("<input name=\"message\" autofocus placeholder=\"Ask the agent...\" required>")
                    .append("<button>Send</button></form>")
                    .append("<form method=\"post\" action=\"/logout\">").append(csrfField(csrf))
                    .append("<button class=\"alt\">Log out</button></form>");
        }
        return h.append("</body></html>").toString();
    }

    @PostMapping("/chat")
    public String chat(@RequestParam("message") String message,
            @RegisteredOAuth2AuthorizedClient OAuth2AuthorizedClient client,
            HttpSession session) {
        // Subject token = alice's session token, fresh from the login this
        // browser performed. Fail-closed inside: no token, no MCP call.
        String question = message.strip();
        try {
            String answer = loop.ask(client.getAccessToken().getTokenValue(), question);
            transcript(session).add(new Turn(question, answer, false));
        } catch (Exception e) {
            // UI surface only: show the refusal/failure instead of a 500. The
            // enforcement already happened server-side and is logged there.
            transcript(session).add(new Turn(question, String.valueOf(e.getMessage()), true));
        }
        return "redirect:/";
    }

    @SuppressWarnings("unchecked")
    private static List<Turn> transcript(HttpSession session) {
        List<Turn> t = (List<Turn>) session.getAttribute("transcript");
        if (t == null) {
            t = new ArrayList<>();
            session.setAttribute("transcript", t);
        }
        return t;
    }

    private static String csrfField(CsrfToken csrf) {
        return "<input type=\"hidden\" name=\"" + HtmlUtils.htmlEscape(csrf.getParameterName())
                + "\" value=\"" + HtmlUtils.htmlEscape(csrf.getToken()) + "\">";
    }

    private static StringBuilder page() {
        return new StringBuilder("""
                <!doctype html><html><head><meta charset="utf-8"><title>Lab agent</title><style>
                body{font-family:system-ui,sans-serif;max-width:44rem;margin:2rem auto;padding:0 1rem;
                     background:#0f3552;color:#e8eef4}
                h1{font-size:1.3rem} a.btn,button{display:inline-block;background:#4fb3a4;color:#06222e;
                     border:0;border-radius:6px;padding:.5rem 1rem;font-weight:600;text-decoration:none;cursor:pointer}
                .alt{background:#7fb6e0} code{background:#123f63;padding:0 .3rem;border-radius:4px}
                .q{margin-top:1rem;font-weight:600} .q::before{content:"you — "}
                .a{white-space:pre-wrap;background:#123f63;border-radius:6px;padding:.6rem;margin-top:.3rem}
                .err{white-space:pre-wrap;background:#5c2b2e;border-radius:6px;padding:.6rem;margin-top:.3rem}
                input[name=message]{width:70%;padding:.5rem;border-radius:6px;border:0;margin-right:.4rem}
                form{margin-top:1rem}</style></head><body>
                """);
    }
}

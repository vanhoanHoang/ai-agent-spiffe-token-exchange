package internal.lab.delegation;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Base64;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import io.spiffe.svid.jwtsvid.JwtSvid;

/**
 * One RFC 8693 hop: present a human's token as the subject, authenticate as
 * this workload with its JWT-SVID, and receive a token that still says
 * {@code sub = the human} while recording this workload in {@code act}.
 *
 * Shared by every workload in a delegation chain (M12: agent-client hop 1,
 * agent-pki hop 2). The chain grows by adding callers of this class, never by
 * copying the assertion type or the request shape around.
 *
 * What this class does NOT do is decide anything. The audience comes from
 * client scopes, the actor from client authentication, and the scope ceiling
 * from the authorization server's exchange-scope-intersection policy. Asking
 * for more here buys a refusal, not permission.
 */
public final class DelegatedExchange {

    private static final Pattern ACCESS_TOKEN = Pattern.compile("\"access_token\"\\s*:\\s*\"([^\"]+)\"");
    private static final Pattern SCOPE_CLAIM = Pattern.compile("\"scope\"\\s*:\\s*\"([^\"]*)\"");

    /** Raw token-endpoint outcome, so callers can report the real failure. */
    public record Response(int status, String body) {

        public String accessToken() {
            Matcher m = ACCESS_TOKEN.matcher(body);
            return m.find() ? m.group(1) : null;
        }
    }

    private DelegatedExchange() {
    }

    /**
     * Perform the exchange. {@code requestedScope} may be null, in which case
     * the delegated authority carried by the subject token is forwarded.
     */
    public static Response post(JwtSvid svid, String tokenEndpoint, String subjectToken, String requestedScope)
            throws Exception {
        String scope = (requestedScope == null) ? delegatedScope(subjectToken) : requestedScope;
        String grant = (subjectToken == null)
                ? "grant_type=client_credentials"
                : "grant_type=" + enc("urn:ietf:params:oauth:grant-type:token-exchange")
                        + "&subject_token=" + enc(subjectToken)
                        + "&subject_token_type=" + enc("urn:ietf:params:oauth:token-type:access_token")
                        + (scope.isEmpty() ? "" : "&scope=" + enc(scope));

        // Keycloak requires client_id == the assertion's sub (the SPIFFE ID);
        // it looks the client up by its jwt.credential.sub attribute (D-001 #5).
        String form = grant
                + "&client_id=" + enc(svid.getSpiffeId().toString())
                + "&client_assertion_type=" + enc(SpiffeClientAuth.ASSERTION_TYPE)
                + "&client_assertion=" + enc(svid.getToken());

        HttpURLConnection conn = (HttpURLConnection) URI.create(tokenEndpoint).toURL().openConnection();
        conn.setRequestMethod("POST");
        conn.setDoOutput(true);
        conn.setRequestProperty("Content-Type", "application/x-www-form-urlencoded");
        try (OutputStream out = conn.getOutputStream()) {
            out.write(form.getBytes(StandardCharsets.UTF_8));
        }
        int code = conn.getResponseCode();
        InputStream stream = (code >= 400) ? conn.getErrorStream() : conn.getInputStream();
        String body = "";
        if (stream != null) {
            try (stream) {
                body = new String(stream.readAllBytes(), StandardCharsets.UTF_8);
            }
        }
        return new Response(code, body);
    }

    /**
     * The delegated-authority scopes of a token: by convention in this lab a
     * scope naming an authority is written {@code ns:verb}
     * ({@code mcp:audit}, {@code issue:employee-cert}), while a bare scope
     * ({@code profile}, {@code mcp-audience}) is client configuration — an
     * audience carrier or an OIDC claim set, not something a human delegates.
     *
     * Forwarding the latter does not merely waste bytes, it FAILS: Keycloak
     * validates a requested scope against the requester client's own assigned
     * scopes, and audience carriers belong to the user's client, not the
     * agent's (acceptance caught exactly this: "Invalid scopes: agent-audience
     * mcp-audience").
     *
     * Read-only claim extraction to build a request parameter — deliberately
     * NOT a validation path.
     */
    public static String delegatedScope(String token) {
        if (token == null) {
            return "";
        }
        String[] parts = token.split("\\.");
        if (parts.length < 2) {
            return "";
        }
        String payload;
        try {
            payload = new String(Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException e) {
            return "";
        }
        Matcher m = SCOPE_CLAIM.matcher(payload);
        if (!m.find()) {
            return "";
        }
        return Arrays.stream(m.group(1).trim().split("\\s+"))
                .filter(s -> !s.isBlank())
                .filter(DelegatedExchange::isDelegatedAuthority)
                .reduce((a, b) -> a + " " + b)
                .orElse("");
    }

    /** ns:verb names an authority; a bare scope is client configuration. */
    public static boolean isDelegatedAuthority(String scope) {
        int colon = scope.indexOf(':');
        return colon > 0 && colon < scope.length() - 1;
    }

    private static String enc(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }
}

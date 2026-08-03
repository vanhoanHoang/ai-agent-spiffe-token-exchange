package internal.lab.agent;

import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

import io.spiffe.svid.jwtsvid.JwtSvid;
import io.spiffe.workloadapi.DefaultJwtSource;
import io.spiffe.workloadapi.JwtSource;

/**
 * M6: obtain a token from the AS using ONLY this workload's JWT-SVID as the
 * client credential (draft §3.1 via Keycloak's federated client auth).
 * The JWT-SVID audience is the AS ISSUER IDENTIFIER as the sole value —
 * normative text; token-endpoint-as-aud anywhere in this repo is a bug
 * (CLAUDE.md §3).
 *
 * The request itself is reusable ({@link #request}): the CLI mode prints it,
 * the M10 chassis ({@link TokenExchange}) runs it per chat message with the
 * subject token as an argument — never baked into a singleton.
 */
final class TokenRequest {

    record Response(int status, String body) {
    }

    private TokenRequest() {
    }

    static void run(String tokenEndpoint, String issuerIdentifier, String subjectToken) throws Exception {
        try (JwtSource source = DefaultJwtSource.newSource()) {
            Response res = request(source, tokenEndpoint, issuerIdentifier, subjectToken);
            System.out.println("HTTP " + res.status());
            System.out.println(res.body());
        }
    }

    static Response request(JwtSource source, String tokenEndpoint, String issuerIdentifier, String subjectToken)
            throws Exception {
        // subject-less fetch: the Workload API mints for the CALLER's attested
        // identity — the negative test relies on exactly that.
        JwtSvid svid = source.fetchJwtSvid(issuerIdentifier);
        return post(svid, tokenEndpoint, subjectToken);
    }

    static Response post(JwtSvid svid, String tokenEndpoint, String subjectToken) throws Exception {
        // M7 (RFC 8693, Keycloak standard token exchange): subject_token = the
        // human's token; the actor is this authenticated client — no actor_token
        // parameter exists, the act claim is stamped by workstream B's mapper.
        //
        // The scope is asked for EXPLICITLY, carried over from the subject
        // token. Without it Keycloak grants the requester's default scopes and
        // silently drops whatever the human additionally consented to, which
        // made the consent screen decorative. Asking is not authorization:
        // the exchange-scope-intersection policy refuses anything wider than
        // this token already carries, so a tampered value here cannot buy
        // permissions the human did not grant.
        String delegated = delegatedScope(subjectToken);
        String grant = (subjectToken == null)
                ? "grant_type=client_credentials"
                : "grant_type=" + URLEncoder.encode("urn:ietf:params:oauth:grant-type:token-exchange", StandardCharsets.UTF_8)
                        + "&subject_token=" + URLEncoder.encode(subjectToken, StandardCharsets.UTF_8)
                        + "&subject_token_type=" + URLEncoder.encode("urn:ietf:params:oauth:token-type:access_token", StandardCharsets.UTF_8)
                        + (delegated.isEmpty() ? ""
                                : "&scope=" + URLEncoder.encode(delegated, StandardCharsets.UTF_8));

        // Keycloak requires client_id == the assertion's sub (the SPIFFE ID);
        // it looks the client up by its jwt.credential.sub attribute (D-001 #5).
        String form = grant
                + "&client_id=" + URLEncoder.encode(svid.getSpiffeId().toString(), StandardCharsets.UTF_8)
                + "&client_assertion_type=" + URLEncoder.encode(SpiffeClientAuth.ASSERTION_TYPE, StandardCharsets.UTF_8)
                + "&client_assertion=" + URLEncoder.encode(svid.getToken(), StandardCharsets.UTF_8);

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
                body = new String(stream.readAllBytes());
            }
        }
        return new Response(code, body);
    }

    /**
     * The DELEGATED-AUTHORITY scopes of the subject token: by convention in
     * this lab a scope that names an authority is written {@code ns:verb}
     * ({@code mcp:audit}, {@code issue:employee-cert}), while a bare scope
     * ({@code profile}, {@code mcp-audience}) is client configuration — an
     * audience carrier or an OIDC claim set, not something a human delegates.
     *
     * Only the former are worth carrying across an exchange. Forwarding the
     * latter is not merely pointless, it FAILS: Keycloak validates a requested
     * scope against the requester client's own assigned scopes, and the
     * audience carriers belong to the user's client, not the agent's
     * (acceptance caught exactly this: "Invalid scopes: agent-audience
     * mcp-audience").
     *
     * Read-only claim extraction to build a request parameter — deliberately
     * NOT a validation path. Asking is not authorization: the AS decides, and
     * the exchange-scope-intersection policy refuses anything wider than the
     * subject token already carries.
     */
    private static String delegatedScope(String subjectToken) {
        if (subjectToken == null) {
            return "";
        }
        String[] parts = subjectToken.split("\\.");
        if (parts.length < 2) {
            return "";
        }
        String payload;
        try {
            payload = new String(java.util.Base64.getUrlDecoder().decode(parts[1]), StandardCharsets.UTF_8);
        } catch (IllegalArgumentException e) {
            return "";
        }
        java.util.regex.Matcher m = java.util.regex.Pattern
                .compile("\"scope\"\\s*:\\s*\"([^\"]*)\"").matcher(payload);
        if (!m.find()) {
            return "";
        }
        return java.util.Arrays.stream(m.group(1).trim().split("\\s+"))
                .filter(s -> !s.isBlank())
                .filter(TokenRequest::isDelegatedAuthority)
                .collect(java.util.stream.Collectors.joining(" "));
    }

    /** ns:verb names an authority; a bare scope is client configuration. */
    private static boolean isDelegatedAuthority(String scope) {
        int colon = scope.indexOf(':');
        return colon > 0 && colon < scope.length() - 1;
    }
}

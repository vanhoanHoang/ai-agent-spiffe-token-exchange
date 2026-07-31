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
        String grant = (subjectToken == null)
                ? "grant_type=client_credentials"
                : "grant_type=" + URLEncoder.encode("urn:ietf:params:oauth:grant-type:token-exchange", StandardCharsets.UTF_8)
                        + "&subject_token=" + URLEncoder.encode(subjectToken, StandardCharsets.UTF_8)
                        + "&subject_token_type=" + URLEncoder.encode("urn:ietf:params:oauth:token-type:access_token", StandardCharsets.UTF_8);

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
}

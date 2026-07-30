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
 */
final class TokenRequest {

    private TokenRequest() {
    }

    static void run(String tokenEndpoint, String issuerIdentifier) throws Exception {
        try (JwtSource source = DefaultJwtSource.newSource()) {
            // subject-less fetch: the Workload API mints for the CALLER's attested
            // identity — the negative test relies on exactly that.
            JwtSvid svid = source.fetchJwtSvid(issuerIdentifier);

            // Keycloak requires client_id == the assertion's sub (the SPIFFE ID);
            // it looks the client up by its jwt.credential.sub attribute (D-001 #5).
            String form = "grant_type=client_credentials"
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
            System.out.println("HTTP " + code);
            InputStream stream = (code >= 400) ? conn.getErrorStream() : conn.getInputStream();
            if (stream != null) {
                try (stream) {
                    System.out.println(new String(stream.readAllBytes()));
                }
            }
        }
    }
}

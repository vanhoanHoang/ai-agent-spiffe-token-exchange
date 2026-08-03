package internal.lab.agent;

import internal.lab.delegation.DelegatedExchange;
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
 *
 * Since M12 the wire format lives in {@link DelegatedExchange}, shared with the
 * second hop; this class is agent-client's CLI-facing surface over it.
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
        // RFC 8693 as Keycloak implements it: subject_token = the human's
        // token; the actor is this authenticated client — no actor_token
        // parameter exists, the act claim is stamped by workstream B's mapper.
        // Scope defaults to the delegated authority the subject token carries.
        DelegatedExchange.Response res = DelegatedExchange.post(svid, tokenEndpoint, subjectToken, null);
        return new Response(res.status(), res.body());
    }
}

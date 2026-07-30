package internal.lab.agent;

/**
 * The ONE place the draft-ietf-oauth-spiffe-client-auth assertion type exists
 * in this repo (CLAUDE.md §5, CONVENTIONS.md). Draft revision bumps touch this
 * file and the validation interface — nothing else.
 */
public final class SpiffeClientAuth {

    /** draft-ietf-oauth-spiffe-client-auth-02 §3.1. */
    public static final String ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-spiffe";

    private SpiffeClientAuth() {
    }
}

package internal.lab.delegation;

/**
 * The ONE place the draft-ietf-oauth-spiffe-client-auth assertion type exists
 * in this repo (CLAUDE.md §5, CONVENTIONS.md). Draft revision bumps touch this
 * file and the validation interface — nothing else.
 *
 * It moved here from agent-client when the second hop arrived (M12): two
 * workloads now authenticate to the AS with a JWT-SVID, and a constant copied
 * into the second one would have been exactly the isolation failure §5 forbids.
 */
public final class SpiffeClientAuth {

    /** draft-ietf-oauth-spiffe-client-auth-02 §3.1. */
    public static final String ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-spiffe";

    private SpiffeClientAuth() {
    }
}

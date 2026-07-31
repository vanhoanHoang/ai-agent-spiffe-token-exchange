# DEMO.md — the demo, in three acts

Stage narration for the M10/M11 demo. Before going on: `bash demo/checklist.sh`
(clock skew is checked first for a reason). If anything wobbles mid-demo:
`bash demo/reset.sh --soft` (~1–2 min, keeps all CA state). The recorded
fallback is the console itself — `console/` renders the captured run offline,
so the *story* survives even if the stack doesn't.

**Browser prerequisite** (live login only): the issuer is `http://keycloak:8080`
(D-005), so the presenter's machine needs a hosts line: `127.0.0.1 keycloak`.
The scripted checks don't need it (`curl --resolve`).

---

## Act I — the problem (2 min, no terminal)

> "AI agents act *for* people. Almost every deployment today gives the agent a
> bearer token and hopes. Two questions become unanswerable the moment
> something goes wrong: **which human** authorized this call, and **which
> software** actually made it?
>
> This lab answers both, in one token, with nothing invented: SPIFFE answers
> *which workload*, OIDC answers *for which human*, and RFC 8693 token
> exchange is the only bridge. The agent holds **no client secret** — its
> credential is its attested identity. And the model never touches a token."

Open the console (`console/` build, or `npm start` in `console/`) on the
architecture header — three chips: trust domain, issuer, resource.

## Act II — the happy path (5 min)

1. **alice logs in and consents** — browser at `http://localhost:8090`. The
   Keycloak consent screen IS the delegation moment: a human granting an agent
   permission to act for her. (Scripted equivalent: `scripts/check-p25.sh`.)
2. **Chat**: ask *"Use the whoami tool — who are you acting for?"* While the
   model thinks, say: the browser holds a session cookie; alice's token lives
   server-side; the exchanged token exists per message only.
3. **The log line lands** (`docker compose logs -f mcp-server`):
   `tool=whoami sub=<alice> act={sub=spiffe://lab.internal/agent-client}` —
   one line, both identities, forever auditable.
4. In the console, walk the five steps: login token (aud=agent-client — useless
   at the resource), the SVID chain of custody (name-constrained intermediate,
   EJBCA root), the exchanged token (act.sub — the whole idea), the four server
   checks, the recorded conversation.

## Act III — the attacks (5 min)

> "Everything so far is the polite path. The system is defined by what it
> refuses."

Run `./infra/acceptance.sh` live (or show the console's rejection grid):

| # | Attack | Stopped by | One-liner |
|---|---|---|---|
| 1 | No client cert | TLS handshake | Never reaches application code. |
| 2 | Token for another service | `aud` check | Passing tokens through is not delegation. |
| 3 | JWT-SVID as bearer | issuer/JWKS | Identity is not authorization. |
| 4 | Unlisted workload | allowlist | Valid identity still needs an invitation. |
| 5 | Token replayed by another workload | `act.sub == mTLS peer` | The token is bound to its workload — the point of `act`. |

Then the finale, live: ask the agent *"Read the audit log."*

> "Watch: the model **tries**. The server says `insufficient_scope` — alice
> never consented to audit access. **Enforcement is tokens, not model
> behavior. The model was willing; the token said no.**"

(With P2.5: log out, log back in via *"Log in granting audit scope"*, consent,
ask again — same model, same question, now it works. Authorization changed
with *consent*, not code.)

---

## Failure cheat-sheet

| Symptom | First move |
|---|---|
| Any JWT rejection out of nowhere | `demo/checklist.sh` — clock skew first (CLAUDE.md §8) |
| `unable to find valid certification path` | Two hypotheses max, then `openssl s_client -showcerts` and read the chain |
| Model rambles / never calls the tool | Re-ask verbatim from this script; temperature is 0, the prompts here are tested |
| Model slow (CPU inference) | Talk through the console panels while it thinks — the wait is script material |
| Login redirect fails in browser | hosts line `127.0.0.1 keycloak` missing |
| Anything else | `demo/reset.sh --soft`, keep talking over the console |
| Total stack loss | The console renders the captured run offline — finish the story there |

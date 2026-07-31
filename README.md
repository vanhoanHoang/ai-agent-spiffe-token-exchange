# spiffe-mcp-lab

A lab wiring four things that rarely meet in one stack:

- **Workload identity** — SPIFFE/SPIRE, trust domain `spiffe://lab.internal`
- **User identity** — OAuth 2.1 / OIDC via Keycloak (the only real AS here)
- **An MCP server** — Spring Boot resource server with proper audience discipline
- **A real PKI** — EJBCA issuing a name-constrained intermediate above SPIRE

The point: an AI agent workload calls an MCP server with a token that proves **which human** it acts for (`sub`) *and* **which workload** it is (`act.sub` = SPIFFE ID), bridged exclusively by RFC 8693 token exchange, with the workload authenticating to Keycloak using **only its JWT-SVID** (`draft-ietf-oauth-spiffe-client-auth`) — no client secrets anywhere.

> SPIFFE answers *which workload*. OIDC answers *on behalf of which human*. Never substitute one for the other.

Not a WIMSE implementation.

## Layout

```
infra/                # SPIRE, EJBCA, compose, acceptance.sh   [C — human-led]
mcp-server/           # Spring Boot resource server            [A]
keycloak-spiffe-spi/  # ClientAuthenticator fallback (M0b)     [B]
agent-client/         # SVID → token exchange → MCP call
specs/                # Pinned truth. Read-only. fetch-specs.sh populates.
docs/                 # ARCHITECTURE · SPEC-REGISTRY · BUILD-PLAN · CONVENTIONS · DECISIONS · VERSIONS
```

Start with `docs/ARCHITECTURE.md` (topology, the three-trust-store table), then `docs/BUILD-PLAN.md` (milestones M0–M9, each with an executable exit criterion). All version pins live in `docs/VERSIONS.md`; all resolved questions live in `docs/DECISIONS.md`.

Done means `./infra/acceptance.sh` exits 0: the happy path **plus all four rejections** (no client cert, wrong audience, JWT-SVID as bearer, unlisted SPIFFE ID).

## Quickstart on a fresh machine

Prerequisites: Docker Desktop (compose v2), bash (Git Bash on Windows), Node.js + npm
(console build only — Java builds happen inside Docker). On Windows, clone into a path
**without special characters** (`&` in a path breaks npm's cmd shims).

```bash
# 1. one-time gitignored artifacts (never leave a machine)
bash infra/spire/gen-bootstrap.sh        # node-attestation bootstrap CA
bash infra/pki/setup-ejbca.sh            # EJBCA hierarchy + name-constrained intermediate (minutes)

# 2. build the console UI (agent-web serves console/dist via volume mount)
(cd console && npm ci && npm run build)

# 3. everything else: services, SPIRE registrations, Keycloak realm, demo profile, model pull
bash demo/reset.sh --full

# 4. verify before demoing (clock skew, health, model, full acceptance)
bash demo/checklist.sh --full
```

Add `127.0.0.1 keycloak` to the hosts file (browser demos resolve the issuer by its
in-network name). The demo is then http://localhost:8090 — log in as `alice`.
First run is the slowest: image builds plus the ~2–3 GB Ollama model download.

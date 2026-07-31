# CLAUDE.md

Operating instructions for Claude Code on this repository. Non-negotiable.

---

## 1. Project

A lab wiring **workload identity (SPIFFE/SPIRE)**, **user identity (OAuth 2.1 via Keycloak)**, **an MCP server (Spring Boot)**, and **a real PKI (EJBCA)** into one stack.

Tier-1 specs plus one deliberate Tier-3 bet (`docs/SPEC-REGISTRY.md`). It is **not** a WIMSE implementation — never describe it as one.

Trust domain: `spiffe://ai-agent.id.eviden.internal`

## 2. The one architectural rule

> SPIFFE answers **which workload**. OIDC answers **on behalf of which human**. Never substitute one for the other. The only bridge is RFC 8693 token exchange.

Forbidden, regardless of whether it compiles:

- JWT-SVID used as the MCP bearer token (no consent, no scopes)
- User authorization derived from a SPIFFE ID
- Accepting a token whose `aud` is not this MCP server (no passthrough)
- Effective permissions wider than `user scopes ∩ agent allowed scopes`

## 3. Pinned ground truth — never write these from recall

Your training data contains wrong or outdated variants of several of these. If you notice yourself *recalling* one instead of reading it here: stop.

| Fact | Value | Source |
|---|---|---|
| SPIFFE client assertion type | `urn:ietf:params:oauth:client-assertion-type:jwt-spiffe` | `draft-ietf-oauth-spiffe-client-auth` §3.1 |
| JWT-SVID `aud` for client auth | The AS **issuer identifier**, as the sole value | ibid. §3.1 (rfc7523bis) |
| X.509-SVID client auth | RFC 8705 mTLS; `client_id` MUST carry the SPIFFE ID and match the URI SAN | ibid. §3.2 |
| X509-SVID anchoring | **MUST NOT** validate via the system trust store | ibid. §5.2.3 |
| Server certs (client side) | System trust store, **not** the SPIFFE bundle | ibid. §3.2 |
| Key discovery | SPIFFE Bundle Endpoint (`https_web`), JWKS with `use: "x509-svid"`/`"jwt-svid"`, `spiffe_sequence`, `spiffe_refresh_hint` | ibid. §5 |
| Bundle endpoint URL | **Not derivable from the SVID.** Configured out of band, keyed by trust domain | ibid. §5 |
| JWT-SVID `iss` + OIDC Discovery for keys | NOT RECOMMENDED — `iss` is not part of the JWT-SVID spec | ibid. §5.2.4 |

**Known wart:** the draft's example shows the token endpoint as `aud`; the normative text says issuer identifier. Follow the normative text. Token-endpoint-as-`aud` anywhere in this repo is a bug.

**Two unrelated "OIDC"s — never conflate:** (1) SPIRE's OIDC Discovery Provider = cloud IAM federation shim, **not used here**; (2) Keycloak = the real AS, the only OIDC in this stack.

## 4. Knowledge discipline

This stack is worst-case for model memory: a renamed WG draft, a preview feature, version-sensitive plugin config.

- SPIRE plugin config keys → read `specs/spire/` at the pinned tag
- Keycloak SPI class names → read the source of the exact version in `docker-compose.yml`
- java-spiffe API → pinned javadoc in `specs/`
- EJBCA profile semantics → `specs/ejbca/`

**If a fact is not in `specs/`, `docs/`, or the table above, it is not known.** Fetch it or ask. Anything unverified gets a `// VERIFY: <what> against <source>` marker. Zero markers is a milestone gate.

## 5. Isolation of the moving part

`draft-ietf-oauth-spiffe-client-auth` is the only load-bearing draft. Containment:

- The assertion-type URN exists as exactly **one** constant
- JWT-SVID validation sits behind **one** interface
- No draft-specific logic anywhere else

A draft revision bump must touch two files. More means the isolation failed — fix that first.

## 6. Session protocol

Every session, in order:

1. Read `docs/BUILD-PLAN.md`; state which milestone you are on and its exit criterion.
2. Read `docs/DECISIONS.md`; honor prior decisions — do not relitigate them silently.
3. Confirm the specs the milestone depends on exist in `specs/` (human runs `specs/fetch-specs.sh` if the sandbox can't reach ietf.org). Missing and unfetchable → stop and ask.
4. **Write the exit-criterion check first** (script or test), watch it fail, then implement.
5. Run it. Green → update `docs/DECISIONS.md` if anything contradicted the docs, then stop and report.
6. Blocked → stop and report using §8. Never mark a milestone done with a failing exit criterion; a half-working milestone marked done is worse than a blocked one.

One milestone per session. One branch per milestone (`m4-mcp-resource-server`). Parallel workstreams A (`mcp-server/`), B (`keycloak-spiffe-spi/`), C (`infra/`) run in separate git worktrees — they share no state.

## 7. Autonomy boundaries

**Allowed without asking:** editing code in your workstream; running builds and tests; `docker compose up/down` of lab services; fetching specs from ietf.org/rfc-editor/github into `specs/`.

**Ask first:** deleting docker volumes (SPIRE/EJBCA state lives there); changing any pinned version in `docs/VERSIONS.md` (the only place versions live); editing `CLAUDE.md`, `docs/ARCHITECTURE.md`, or `docs/VERSIONS.md` (if code contradicts a doc, the resolution goes through `docs/DECISIONS.md`, not a silent doc edit); anything touching EJBCA CA hierarchy (prepare scripts, the human runs them; issued artifacts land per the file contract in `infra/pki/README.md` — if a file there is missing, ask, never substitute a self-signed cert silently); changing the trust domain; edits outside your workstream.

**Never:** modify `specs/` contents; commit a secret, token, or private key; extend an SVID TTL or token lifetime to make a test pass; weaken a validation check to unblock a milestone; `catch`-and-permit in any validation path.

## 8. Debugging and reporting

- Cross-container TLS failures (`unable to find valid certification path`): **two hypotheses maximum**, then `openssl s_client -showcerts`, read the actual chain, report.
- Any JWT validation failure: check container clock skew **before** touching code.
- Blocked report format: *milestone / exit criterion / what passes / exact failing command + output / hypotheses tested / what you need.*

## 9. Map

```
infra/                # SPIRE, EJBCA, compose          [C — human-led critical path]
mcp-server/           # Spring Boot resource server     [A]
keycloak-spiffe-spi/  # ClientAuthenticator provider    [B]
agent-client/         # SVID → token exchange → MCP call
console/              # M11 demo console (Angular)  [demo track]
specs/                # Pinned truth. Read-only.
docs/                 # ARCHITECTURE, SPEC-REGISTRY, BUILD-PLAN, CONVENTIONS, DECISIONS
```

Read `docs/ARCHITECTURE.md` for topology and the three-trust-store table before touching any TLS or validation code. Read `docs/CONVENTIONS.md` before writing Java. Read `console/CLAUDE.md` + `docs/CONVENTIONS-ANGULAR.md` before touching `console/` — those conventions are enforced (lint limits fail the console's exit check), not advisory.

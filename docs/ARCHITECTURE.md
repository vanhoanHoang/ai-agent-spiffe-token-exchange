# Architecture

Lab wiring **workload identity (SPIFFE/SPIRE)**, **user identity (OAuth 2.1 via Keycloak)**, an **MCP server (Spring Boot)**, and a **real PKI (EJBCA)** into one stack.

Trust domain: `spiffe://ai-agent.id.eviden.internal`

> **The one rule:** SPIFFE answers *which workload*. OIDC answers *on behalf of which human*. Never substitute one for the other. The only bridge is RFC 8693 token exchange.

## Non-goals

- **Not a WIMSE implementation.** Never describe it as one.
- **SPIRE's OIDC Discovery Provider is not used.** It is a cloud-IAM federation shim. The only OIDC in this stack is Keycloak, the real authorization server. Never conflate the two.

## Topology

```
 human ──(1) OIDC login──────────────► Keycloak (AS)
                                          ▲   │
                    (3) RFC 8693 exchange │   │ (5) JWKS (realm keys)
                        + jwt-spiffe      │   ▼
 agent-client ────────────────────────────┘  mcp-server
   │  ▲                                       ▲    (Spring Boot
   │  └(2) SVIDs via Workload API             │     resource server)
   │       (SPIRE agent, unix socket)         │
   └──(4) mTLS with X509-SVIDs + exchanged access token

 SPIRE server ──UpstreamAuthority (disk)──► EJBCA-issued,
                                            name-constrained intermediate
                                            (permitted: URI:spiffe://ai-agent.id.eviden.internal/)

 Keycloak ◄──SPIFFE bundle endpoint (https_web), configured OUT OF BAND──
             (bundle URL is NOT derivable from any SVID; keyed by trust domain)
```

## Token flow (the happy path M9 asserts)

1. Human authenticates at Keycloak → **user token** (`sub` = human).
2. `agent-client` obtains its X509-SVID and JWT-SVID from the SPIRE agent Workload API.
3. `agent-client` calls the Keycloak token endpoint: **RFC 8693 token exchange** — `subject_token` = user token, client authentication = JWT-SVID with assertion type `urn:ietf:params:oauth:client-assertion-type:jwt-spiffe`, `resource` = MCP server URI. The JWT-SVID `aud` is the **AS issuer identifier, as the sole value** (normative text of the draft; the draft's token-endpoint example is a known wart — token-endpoint-as-`aud` anywhere in this repo is a bug).
4. Keycloak validates the JWT-SVID against trust-domain keys from the bundle endpoint and issues an access token: `sub` = human, `act.sub` = `spiffe://ai-agent.id.eviden.internal/...`, `aud` = MCP server.
5. `agent-client` calls `mcp-server` over **mTLS with X509-SVIDs**, presenting the exchanged token as bearer.
6. `mcp-server` enforces, in order: peer SPIFFE ID is allowlisted; token signature via Keycloak JWKS; `aud` == this server (anti-passthrough); effective scopes = `user scopes ∩ agent allowed scopes`. It logs `sub` and `act.sub` on every call.

Forbidden regardless of whether it compiles: JWT-SVID as the MCP bearer token; user authorization derived from a SPIFFE ID; accepting a token whose `aud` isn't this server; permissions wider than the intersection.

## The three trust stores

Three unrelated validation roots coexist. Every TLS/JWT bug in this lab starts with confusing two of them. Read this table before touching any TLS or validation code.

| Trust store | Contents | Who uses it, for what | Explicitly NOT |
|---|---|---|---|
| **SPIFFE trust bundle** (`ai-agent.id.eviden.internal`) | SPIRE-distributed CA keys; upstream-chained to EJBCA via name-constrained intermediate | `mcp-server` validates client X509-SVIDs in mTLS; `agent-client` validates `mcp-server`'s SVID; Keycloak validates JWT-SVID client assertions (keys fetched from the SPIFFE bundle endpoint, `https_web`) | **MUST NOT** be the system trust store, and X509-SVIDs **MUST NOT** validate via the system store (draft §5.2.3) |
| **System / Web PKI store** | OS default CA set | Clients validating the AS's HTTPS server cert (draft §3.2); Keycloak validating the bundle-endpoint server cert (`https_web` profile) | Never used to validate any SVID |
| **Keycloak realm keys (JWKS)** | The realm's OIDC signing keys, via OIDC discovery of the Keycloak realm | `mcp-server` validates user/exchanged access tokens | Not the SPIFFE bundle; not SPIRE's OIDC Discovery Provider (unused here) |

Key discovery for the SPIFFE side follows draft §5: bundle endpoint JWKS entries carry `use: "x509-svid"` / `"jwt-svid"`, `spiffe_sequence`, `spiffe_refresh_hint`. Pairing JWT-SVID `iss` with OIDC Discovery is NOT RECOMMENDED — `iss` is not part of the JWT-SVID spec.

## Isolation of the moving part

`draft-ietf-oauth-spiffe-client-auth` (Tier 3, see `SPEC-REGISTRY.md`) is the only load-bearing draft:

- The assertion-type URN exists as **exactly one constant** in our code (`agent-client`; a second location may exist only if the M0(b) fallback SPI is built, recorded in `DECISIONS.md`).
- JWT-SVID validation sits behind **one interface**.
- No draft-specific logic anywhere else. A draft revision bump must touch two files; more means the isolation failed — fix that first.

## Components and workstreams

| Path | Component | Workstream |
|---|---|---|
| `infra/` | SPIRE server+agent, Keycloak, EJBCA (profile `pki`), compose | C — human-led critical path |
| `mcp-server/` | Spring Boot OAuth resource server, SVID mTLS | A |
| `keycloak-spiffe-spi/` | Custom `ClientAuthenticator` — **only if** M0 finds the 26.6.0 preview unusable | B |
| `agent-client/` | SVID → token exchange → MCP call | — |

Workstreams share no state and run in separate git worktrees, one branch per milestone.

## PKI chain of custody

EJBCA root → name-constrained intermediate (`permittedSubtrees: URI:spiffe://ai-agent.id.eviden.internal/`) → SPIRE server (`disk` UpstreamAuthority) → SVIDs. Issuance is human-run per the file contract in `infra/pki/README.md`; if a file there is missing, stop and ask — never substitute a self-signed cert. Whether each verifier in the stack actually *enforces* the URI name constraint is an open question tracked as D-002; until proven, the constraint is governance value, not a technical control.

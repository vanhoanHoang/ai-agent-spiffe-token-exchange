# Build Plan

Milestones are ordered by **risk**, not dependency. The pieces most likely to not exist are proven first, so a dead end costs Saturday morning rather than Sunday night.

Every milestone has an **exit criterion**: a command that passes or fails. Write it before the implementation. No milestone is complete without it green.

---

## M0 — Spike: does Keycloak actually support this?

**Do this first. Before any code.** This is the only step with genuine "the feature may not exist" risk.

- Pull the Keycloak version you intend to run.
- Determine whether `jwt-spiffe` client authentication is present, behind which feature flag, or absent.
- Read the **source of that exact version**. Do not trust release notes, blog posts, or model recall.

**Exit criterion:** a written statement in `docs/DECISIONS.md` naming the Keycloak version and one of:
- (a) supported, enabled via flag `X`; or
- (b) absent — implement workstream B as a custom `ClientAuthenticator` SPI.


### M0 search strategy (do this, don't wander)

Known already (see `docs/VERSIONS.md`): the capability shipped as **preview** in Keycloak 26.4 under *Federated Client Authentication* and remains preview in 26.6.0. So M0 is not "does it exist" but "how exactly is it enabled and does it match the draft". Against the 26.6.0 source tree:

1. `grep -r "jwt-spiffe" --include="*.java"` — finds the assertion-type constant and its authenticator.
2. `grep -rl "spiffe" services/ | head` — locates the federated client auth provider classes.
3. Find the feature flag: grep the `Profile.Feature` enum for the SPIFFE/federated entry; record the exact `--features=` string (avoid blanket `preview` in compose once known).
4. Read the `aud` validation in that authenticator: issuer identifier or token endpoint? Record in D-001 — mismatch with rfc7523bis is upstream-reportable.
5. Locate the admin config model for the SPIFFE identity provider (trust domain + bundle/JWKS URL fields) and note the config path.

Community repos (CarrettiPro/keycloak-spiffe, christian-posta/spiffe-svid-client-authenticator) predate the built-in feature — background reading only, never a source of config keys.

If (b), that is fine and expected. It is roughly 200 lines of Java against Nimbus, and it is the five validation checks from the draft's §3.1. Budget for it deliberately rather than discovering it later.

---

## M1 — Skeleton up

Repo layout, `docker-compose.yml` with pinned image tags, all services reaching healthy.

**Exit:** `docker compose up -d && docker compose ps` shows every service healthy.

---

## M2 — SPIRE issues SVIDs

SPIRE server + agent, registration entries for `agent-client` and `mcp-server` using unix/docker selectors.

**Exit:** `spire-agent api fetch x509 -socketPath ...` returns a valid SVID with the expected SPIFFE ID for both workloads.

*Expect to lose time on selector mismatches. This is normal; read the agent logs, do not guess.*

---

## M3 — EJBCA as upstream CA

Issue a name-constrained intermediate from EJBCA **once, by hand or by CLI**, and feed it to SPIRE's `disk` UpstreamAuthority. No live integration — that is a later weekend.

VERIFY: `disk` plugin config key names against `specs/spire/` at your pinned tag.

**Exit:** two commands.
1. `openssl verify` shows a fresh SVID chaining to the EJBCA root.
2. A **negative test**: attempt to issue outside `spiffe://lab.internal/` and confirm the verifier rejects it. If it does not reject, your verifier does not enforce URI name constraints — record that in `DECISIONS.md`.

*Do not let an agent drive EJBCA CA hierarchy setup. Prepare scripts, run them yourself.*

---

## M4 — MCP server as a plain OAuth resource server

Spring Boot, `spring-boot-starter-oauth2-resource-server`, Keycloak JWKS validation, RFC 9728 metadata endpoint. Boring bearer tokens only — no SPIFFE yet.

**Exit:**
- `curl` with no token → `401` carrying `WWW-Authenticate` with `resource_metadata`.
- `curl /.well-known/oauth-protected-resource` → valid JSON pointing at Keycloak.
- `curl` with a token minted for a *different* audience → rejected.

That third check is the anti-passthrough test. It matters more than the happy path.

---

## M5 — mTLS with SVIDs

Wire `java-spiffe` into both `agent-client` and `mcp-server`. The `java-spiffe-provider` module supplies an `X509Source` and a JSSE `SSLContext` directly — no Envoy sidecar, no `spiffe-helper` file watching.

VERIFY: java-spiffe API surface against pinned javadoc.

**Exit:** MCP server accepts a call from the allowlisted SPIFFE ID over mTLS, and rejects a valid-token call from a workload whose SPIFFE ID is not allowlisted.

---

## M6 — SPIFFE client authentication to Keycloak

Configure the SPIFFE bundle endpoint (`https_web`) and point Keycloak at it out of band. Then either enable the preview feature or ship the SPI from M0(b).

Validation checks required by §3.1: well-formed JWT-SVID; `sub`/`aud`/`exp` present; not expired; `aud` contains only the AS issuer identifier; signature verified against trust-domain keys; `sub` maps to a registered client.

**Exit:** `agent-client` obtains a token from Keycloak using **only** its JWT-SVID as client credential. No client secret exists anywhere in the repo or environment.

*This is the milestone worth having. It is the actual IETF draft, and the reference implementation is preview maturity.*

---

## M7 — Token exchange with `act`

RFC 8693 **as Keycloak 26.x actually implements it** (verified against the 26.x securing-apps token-exchange docs, D-007): standard token exchange supports `subject_token`/`audience`/`scope` only — **no `actor_token`, no `resource` parameter, and no native `act` claim**. So the request is: `subject_token` = user token, client authentication = JWT-SVID (`…:jwt-spiffe`), `audience` = the MCP server's client.

`act.sub` comes from a **custom protocol mapper** (workstream B wakes up for this, not for client auth): the actor is the *authenticated client*, whose identity is already the SPIFFE ID via `jwt.credential.sub`. Semantically faithful to RFC 8693 — the agent is the acting party, and its client authentication already proved who it is.

**Exit:** decoded access token shows `sub` = human, `act.sub` = `spiffe://lab.internal/...`, `aud` = MCP server. The MCP server logs both on every call.

*The mapper is mandatory, not a contingency. Budget half a day for it plus the audience wiring.*

---

## M8 — Stretch: certificate-bound tokens — **SKIPPED by decision (D-009)**: replaced by the act↔peer binding check enforced at the MCP server; M9 gained a fifth rejection for it.

RFC 8705 `cnf.x5t#S256`. Binds the access token to the workload's SVID, closing the stolen-bearer-token hole in the plain MCP model.

**Exit:** replaying a captured token from a different client certificate is rejected.

---

## M9 — Terminal acceptance

The goal, as one script: `infra/acceptance.sh`. Happy path (login → jwt-spiffe exchange → mTLS MCP call with correct `sub`/`act`/`aud`) **plus all four rejections**: no client cert; wrong-audience token; JWT-SVID presented as bearer; unlisted SPIFFE ID. Plus chain-of-custody: SVID chains to the EJBCA root with the name constraint enforced, and `act.sub` appears in the MCP server log.

**Exit:** `./infra/acceptance.sh` exits 0.

M8 green without M9 green means the pieces work and the system doesn't. The project is done at M9, not M8.

---

# Demo track (post-M9, optional)

Presentation layer only. Nothing here gates M0–M9, touches `acceptance.sh`, or enters any validation path. Feasibility, verified library facts, and pins-owed recorded in D-010.

## M10 — AI agent in front of agent-client

A thin agentic loop inside `agent-client`'s Spring Boot chassis, written against **Spring AI's provider-neutral `ChatClient`/`ChatModel` abstraction** (D-010 — no vendor SDK): the model decides *what* MCP tool to call; the existing SVID → exchange → mTLS path decides *as whom*. The model never touches an SVID, a token, or the exchange.

**Provider is a deployment detail, not code.** Default demo provider: **Ollama, local — free, no API key exists at all.** Any OpenAI-compatible endpoint (Groq, OpenRouter, Gemini's compat layer, …) is a swap of starter dependency + `application.properties` only. Containment rule, mirroring §5 of CLAUDE.md: no `org.springframework.ai.<provider>.*` type appears outside the one Spring configuration class; the loop depends only on `ChatClient`/`ToolCallback`. A provider switch that touches more than the build file and properties means the isolation failed — fix that first.

MCP calls still go through the official MCP Java client, with the java-spiffe `SSLContext` injected via the transport's `clientBuilder(...)` and the exchanged bearer via `httpRequestCustomizer(...)` — the three-trust-store rules survive the library (builder methods verified in D-010). The hand-built `McpSyncClient` is handed to the LLM layer via Spring AI's `SyncMcpToolCallbackProvider` (verified in D-010); Spring AI never constructs its own MCP transport.

VERIFY: Spring AI and MCP Java SDK pins against VERSIONS.md rows before writing code (pinned under standing delegation; verified facts in D-010). The demo model must support tool calling (e.g. an Ollama tools-capable model); model choice recorded in D-010: qwen3.5:4b.

**Exit:**
1. A natural-language request produces an MCP call whose server log shows `sub` = human and `act.sub` = the agent's SPIFFE ID.
2. Negative demo: the agent is asked to do something outside `user ∩ agent` scopes; the model attempts it and the MCP server rejects it — enforcement is tokens, not model behavior.
3. The default demo runs with **zero LLM credentials** (local Ollama); if a hosted provider is configured instead, its key lives in the environment only, never the repo. `./infra/acceptance.sh` still exits 0, untouched.

## M11 — Demo console

Read-only visualizer (mockup already exists): act rail, chain-of-custody panel, token cards, four rejection cards, live log tail. Fed by JSON captured from a demo run. Holds no secrets, stores no tokens, validates nothing.

**Exit:** the console renders a complete demo run offline from captured JSON; killing it changes nothing about the stack.

---

## Realistic scoping

A weekend gets you M0–M5 comfortably, and one of M6/M7. All of M0–M8 including live EJBCA integration is two to three weeks of evenings.

M6 is the one to prioritise if you have to choose. It is the piece that produces something worth sending to the OAuth working group.

---

## Known time sinks

| Trap | Mitigation |
|---|---|
| EJBCA crypto tokens, CA hierarchy, profiles | Offline issuance once (M3). Do not automate on weekend one. |
| Cross-container TLS trust failures | Two hypotheses maximum, then `openssl s_client -showcerts` and read. Do not iterate blindly. |
| Container clock skew | Check first on any JWT failure. It is the cause more often than the code. |
| Fighting a real MCP client early | Use `curl` until M4 passes. Give the server its own hostname. |
| SPIRE trust bundle into Keycloak | Manual paste is fine for the lab. Automate later or never. |

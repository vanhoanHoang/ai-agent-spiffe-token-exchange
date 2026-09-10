# Decisions Log

Append-only. Every entry that contradicts `ARCHITECTURE.md`, `SPEC-REGISTRY.md`, or `CLAUDE.md` triggers an update of that doc in the same commit.

Format:

```
## D-NNN — <title>
Date / Milestone / Author (human | claude-code)
Decision:
Evidence:      (exact version, spec section, command output — not "the docs say")
Consequences:
```

---

## D-001 — Keycloak SPIFFE client-auth support status

Date: _pending_ · Milestone: M0 · Author: _pending_

Decision: **RESOLVED (2026-07-30, from the 26.6.0 source tree — tarball `keycloak/keycloak` tag `26.6.0`).**
Keycloak 26.6.0: outcome **(a) supported**, enabled via flag **`--features=spiffe`**. Workstream B (`keycloak-spiffe-spi/`) stays dormant — configuration, not implementation. M6 is configuration.

Findings, each from source:

1. **Feature flag.** `common/.../org/keycloak/common/Profile.java:102` — `SPIFFE("SPIFFE trust relationship provider", Type.PREVIEW)`; key derivation `name().toLowerCase().replaceAll("_","-")` → CLI string `spiffe`. The client authenticator itself gates on `CLIENT_AUTH_FEDERATED` (Profile.java:100, `Type.DEFAULT` — on by default, no flag). So compose needs exactly `--features=spiffe`, not blanket `preview`.
2. **Assertion type.** `services/.../broker/spiffe/SpiffeConstants.java:5` — `urn:ietf:params:oauth:client-assertion-type:jwt-spiffe`, matching the draft. (Javadoc on `SpiffeIdentityProvider` still cites the pre-adoption name `draft-schwenkschuster-oauth-spiffe-client-auth`.)
3. **`aud` validation: issuer identifier, sole value — matches rfc7523bis normative text, NOT the draft's stale token-endpoint example.** `SpiffeIdentityProvider.verifyClientAssertion` builds `FederatedJWTClientValidator` with no explicit audiences → `getExpectedAudiences()` returns `Urls.realmIssuer(...)` = `{base}/realms/{realm}` (`Urls.java:166`); `isMultipleAudienceAllowed()` = false; enforced in `AbstractBaseJWTValidator.validateTokenAudience:119` (any-match + reject >1 audience). Nothing to report upstream; our client sets `aud` = realm issuer, sole value.
4. **Admin config model.** Realm-level identity provider, `providerId` **`spiffe`** (`SpiffeIdentityProviderFactory.PROVIDER_ID`), config keys **`trustDomain`** (regex `spiffe://[a-z0-9.\-_]*`, no trailing slash; enforced as prefix `trustDomain + "/"` on the assertion `sub`) and **`bundleEndpoint`** (URL) — `SpiffeIdentityProviderConfig.java:12-15`. Standard admin REST path: `POST /admin/realms/{realm}/identity-provider/instances`.
5. **Client registration model.** The agent's Keycloak client uses `clientAuthenticatorType` = **`federated-jwt`** with client attributes **`jwt.credential.issuer`** = IdP alias and **`jwt.credential.sub`** = the SPIFFE ID (`FederatedJWTClientAuthenticator.java:35-38`); lookup is by `sub` attribute (`SpiffeClientAssertionStrategy`).
6. **Validation semantics worth knowing for M6 tests:** `iss` optional and unchecked (`expectedTokenIssuer` = null); token reuse permitted (`reusePermitted` = true — SPIFFE agents cache JWT-SVIDs); max assertion lifetime 300 s default (configurable per IdP); bundle endpoint JWKS honors `use: "jwt-svid"` (falls back to `sig`) and `spiffe_refresh_hint` (`SpiffeBundleEndpointLoader.java:22-27`) — consistent with draft §5.

Evidence: file paths and line numbers above, read 2026-07-30 from the extracted 26.6.0 source tarball.

Consequences: M6 is configuration (identity provider + client attributes + `--features=spiffe`); the SPI fallback is not built. `infra/docker-compose.yml` narrowed from `--features=preview` to `--features=spiffe` in the same commit. `docs/VERSIONS.md` "what M0 must still confirm" section is now satisfied by this entry (human may prune it — VERSIONS.md edits are human-gated).

---

## D-002 — URI name-constraint enforcement in our verifiers

Date: _pending_ · Milestone: M3 · Author: _pending_

Decision: **RESOLVED (2026-07-31) — per-verifier results:**

| Verifier | Result | Evidence |
|---|---|---|
| OpenSSL CLI 1.1.1s (Git-for-Windows host build) | **ENFORCES** | `scripts/check-m3.sh` negative test: leaf with URI SAN `spiffe://evil.example/impostor` signed by the constrained intermediate → `openssl verify` FAILS; in-domain control `spiffe://lab.internal/neg-test-control`, same signer and extensions → verifies OK. So the rejection is the constraint, not setup noise. |
| JDK PKIX (Temurin 21, the runtime under mcp-server/agent-client) | **ENFORCES** | `scripts/test-jdk-nameconstraints.sh` (M5): `CertPathValidator PKIX` — in-domain control `ACCEPT`; out-of-domain leaf `REJECT: name constraints check failed`. |
| Go (SPIRE internal) | n/a as verifier of issued leaves in our flows | — |

Constraint form actually issued (EJBCA `nameConstraintsPermitted = uniformResourceIdentifier:lab.internal`): `X509v3 Name Constraints: critical / Permitted: URI:lab.internal`. Per RFC 5280 §4.2.1.10 URI constraints match the **host** of the URI, so this permits `spiffe://lab.internal/*` only — the pki README's shorthand "URI:spiffe://lab.internal/" denotes exactly this.

Consequences: both verifiers actually used in this stack enforce the URI constraint — the EJBCA chain is a real technical control, not governance theater. No ARCHITECTURE.md caveat needed.

---

## D-003 — M1 skeleton scoping: node-attestation bootstrap and compose profiles

Date: 2026-07-30 · Milestone: M1 · Author: claude-code

Decision:
1. **Node attestation = x509pop** (the attestor whose doc was pinned in `specs/`), against a local bootstrap CA generated once by `infra/spire/gen-bootstrap.sh` into gitignored `infra/spire/bootstrap/`. This bootstrap PKI is deliberately outside the EJBCA `infra/pki` contract — it answers "which node is the agent", not workload chain-of-custody. Agent ID: `spiffe://lab.internal/spire/agent/x509pop/<fingerprint>` — M2 registration entries parent to it.
2. **Agent `insecure_bootstrap = true` for M1 only.** SPIRE images are scratch-based (no shell — verified by running `--entrypoint sh`, exec 127), so the server's self-generated CA bundle cannot be exported to the agent from inside compose, and until M3 there is no stable root to pre-share. At M3 the EJBCA root (`/opt/spire/pki/`) becomes the agent's `trust_bundle_path` and this flag is removed; the M3 exit check must assert its absence. Recorded here precisely so it is not a silent weakening.
3. **Compose default profile at M1** = spire-server, spire-agent, keycloak. `mcp-server` sits behind profile `app` until M4 (nothing to build yet); `ejbca` stays behind profile `pki` until M3 (image pin human-gated in VERSIONS.md).
4. **Keycloak healthcheck**: `KC_HEALTH_ENABLED=true`, probe `HEAD /health/ready` on management port 9000 via bash `/dev/tcp`.

Evidence: SPIRE config keys from `specs/spire/*.md` at v1.15.2 (server/agent reference, x509pop both sides, datastore sql, keymanager disk, docker workload attestor — fetched additions recorded in `specs/fetch-specs.sh`). Keycloak probe is verbatim from 26.6.0 `docs/guides/observability/health.adoc:103`; health endpoint/port from `containers.adoc:189`.

Consequences: M2 uses docker/unix workload selectors with the x509pop agent alias as parent. M3 inherits two obligations: remove `insecure_bootstrap`, and wire `UpstreamAuthority "disk"`.

---

## D-004 — M3 executed by claude-code under explicit user delegation; EJBCA CE pinned 9.3.7; offline disk UpstreamAuthority kept

Date: 2026-07-31 · Milestone: M3 · Author: claude-code (delegated by human)

Decision:
1. The human explicitly instructed ("continue with M3 to see whether you can do it and do not need me", 2026-07-31) that claude-code perform the EJBCA CA hierarchy setup and pin the EJBCA version — both normally human-gated. The CA setup is delivered as a re-runnable script (`infra/pki/setup-ejbca.sh`) so the human can reproduce it solo later, per their request.
2. **EJBCA CE pinned `9.3.7`** — newest CE tag on hub.docker.com/r/keyfactor/ejbca-ce (2025-12-17). Compose host port 8083 (8080/8082 taken).
3. **M3 stays offline** per BUILD-PLAN: intermediate issued once, fed to SPIRE's `disk` UpstreamAuthority. Noted for a later weekend: SPIRE ≥1.11 ships a native `ejbca` UpstreamAuthority plugin and Keyfactor publishes an EJBCA↔SPIRE tutorial (docs.keyfactor.com "tutorial-integrate-ejbca-with-spiffe-spire-server", written against CE 8.3.2). That tutorial's recommended `spireIntermediateCA` certificate profile carries **no name constraints** — our lab deliberately adds `permittedSubtrees URI` per the `infra/pki` contract, which is stricter than the vendor path.

Evidence: hub.docker.com/v2 tags API output (9.3.7 / 9.1.1 / 9.0.0...); Keyfactor tutorial fetched 2026-07-31; user instruction in session transcript.

Consequences: EJBCA CLI semantics for 9.3.7 are established live from the container's own `ejbca.sh` help output (recorded below in D-005 once the hierarchy lands); migration to the live `ejbca` plugin is a candidate for a post-M9 weekend.

---

## D-005 — M4 pins: Spring Boot 4.1.0 on Java 21; canonical resource identifier

Date: 2026-07-31 · Milestone: M4 · Author: claude-code (delegated by human; Boot line chosen explicitly by human — "use latest spring boot")

Decision:
1. **Spring Boot pinned `4.1.0`** — the actual latest release per `repo1.maven.org` `maven-metadata.xml` (`<latest>4.1.0</latest>`). Note: search.maven.org's index was stale (reported 3.5.3 as latestVersion); the human caught this. repo1 metadata is the authority for future pins. Java 21. Build images: `maven:3.9-eclipse-temurin-21` / `eclipse-temurin:21-jre`. The prior "3.x" constraint in VERSIONS.md is superseded by the human's instruction.
2. **Canonical resource identifier (and required token `aud`): `https://mcp.lab.internal:8443`** from M4 onward, even while M4 transport is plain HTTP (TLS arrives with SVID mTLS at M5). Keeps `aud`, RFC 9728 `resource`, and Keycloak audience-mapper config stable across M4→M9.
3. **Keycloak issuer fixed to `http://keycloak:8080` (KC_HOSTNAME)** so tokens minted from the host (localhost:8080) and validated in-network carry the same `iss`.

Evidence: repo1.maven.org maven-metadata.xml (latest/release = 4.1.0, versions through 4.1.0); RFC 9728 §2/§3.2/§5.1 read from specs/rfc9728.txt (fields `resource`, `authorization_servers`, `bearer_methods_supported`; `WWW-Authenticate: Bearer resource_metadata="..."`).

Consequences: VERSIONS.md row updated in this commit. Boot 4 / Spring Security 7 API drift vs model recall is expected — any API used that fails to compile gets resolved against the 4.1.0 build output, not memory. M5 terminates TLS on 8443 without changing the identifier. M6/M7 audience config references the same URI.

---

## D-006 — M5: java-spiffe 0.8.17; mTLS enforcement split; hostname verification stance

Date: 2026-07-31 · Milestone: M5 · Author: claude-code (standing delegation)

Decision:
1. **java-spiffe pinned `0.8.17`** (latest GitHub release = repo1 `<latest>` for io.spiffe:java-spiffe-provider). API ground truth fetched at tag into `specs/java-spiffe/` (root/core/provider READMEs). Linux gRPC transport is bundled; only macOS needs extra artifacts.
2. **Enforcement split for the M5/M9 semantics.** TLS handshake requires a valid `lab.internal` SVID (SpiffeTrustManager validates against the SPIFFE bundle; `ssl.spiffe.acceptAll=true` skips only the per-ID handshake check). The SPIFFE-ID **allowlist** is enforced in a servlet filter → **403** for a valid-SVID-but-unlisted caller. Rationale: M9's acceptance expects `403` for the unlisted-workload case, which a handshake-level accept list cannot produce (it would be a connection reset). No client cert at all → rejected at handshake (`client-auth: need`).
3. **Server TLS via Boot SslBundle** ("spiffe" bundle): `SslManagerBundle.of(KeyManagerFactory.getInstance("Spiffe"), TrustManagerFactory.getInstance("Spiffe"))` after registering `SpiffeProvider`; factories read the default `X509Source` from `SPIFFE_ENDPOINT_SOCKET`. Rotation-safe: managers pull the current SVID per handshake.
4. **Hostname verification is replaced, not skipped silently**: SVIDs carry URI SANs only, so the agent-client uses an explicit HostnameVerifier that defers to the SpiffeTrustManager's accepted-ID check (`spiffe://lab.internal/mcp-server`). SPIFFE-ID authentication is strictly stronger than DNS-name matching here; documented in code at the verifier.

Evidence: `specs/java-spiffe/java-spiffe-provider_README.md` (SslContextOptions/acceptedSpiffeIdsSupplier, provider algorithm "Spiffe", programmatic SpiffeKeyManager/SpiffeTrustManager); Boot 4.1.0 sources jar (`SslManagerBundle.of`, `SslBundle.of(..., managers)`).

Consequences: M9's four rejections map cleanly (no-cert = handshake refusal, unlisted = 403). If the JWT-SVID JWKS path later needs per-ID handshake enforcement, revisit §2.

---

## D-007 — Post-M9 demo track added; Keycloak token-exchange reality check corrects M7

Date: 2026-07-31 · Milestone: planning · Author: claude-code

Decision:

1. **M7 corrected in BUILD-PLAN.md.** Keycloak 26.x **standard token exchange** supports `subject_token`, `audience`, `scope`, `requested_token_type` only. It does **not** support `actor_token`, does **not** support the `resource` parameter ("does not yet have support"), and emits **no `act` claim** natively (`may_act` exists only in an experimental delegation feature behind `parameterized-scopes`). Therefore: the M7 exchange request uses `audience` (not `resource`), and `act.sub` is populated by a **custom protocol mapper** that derives the actor from the *authenticated client* — whose identity is already the SPIFFE ID via `jwt.credential.sub` (D-001 finding 5). The mapper is mandatory, not the contingency BUILD-PLAN previously hedged on. Workstream B (`keycloak-spiffe-spi/`) hosts it — it wakes up for a protocol mapper, not a client authenticator. Consistent with D-005: the canonical identifier `https://mcp.lab.internal:8443` stays the required token `aud`; only the request parameter carrying it changes.
2. **Post-M9 demo track (M10 AI agent, M11 demo console) added to BUILD-PLAN.md.** Presentation-only; adds no gates to M0–M9 and never enters `acceptance.sh` or any validation path. `agent-client` uses a Spring Boot chassis (Boot 4.1.0 / Java 21 per D-005; author familiarity) under three standing rules: TLS contexts are wired explicitly from java-spiffe material (D-006's SslBundle/SpiffeProvider pattern — never a default trust store deciding a trust root), the token exchange is hand-rolled (Spring's OAuth2 client machinery cannot produce a `jwt-spiffe` assertion), and the assertion-type URN stays exactly one constant per CLAUDE.md §5.
3. **AI layer holds no workload credentials.** The LLM chooses *what* to call; `agent-client` alone is *who*. The Anthropic API key lives in an environment variable only, never in the repo; the demo narrative must state that the "no client secret exists" claim covers OAuth client authentication — the vendor API key is an unrelated credential outside the trust domain.

Evidence (all fetched 2026-07-31):

- **keycloak.org/securing-apps/token-exchange** (26.x): parameter list; actor_token unsupported; no `resource` support; no `act` claim in standard exchange.
- **github.com/anthropics/anthropic-sdk-java**: latest v2.52.0 (2026-07-24); tool-runner support present.
- **github.com/modelcontextprotocol/java-sdk**: official MCP Java SDK, Java 17+ (compatible with D-005's Java 21), coordinates `io.modelcontextprotocol.sdk`; maintained with Spring AI. `mcp-core` `HttpClientStreamableHttpTransport.Builder` exposes `clientBuilder(HttpClient.Builder)` / `customizeClient(Consumer<HttpClient.Builder>)` (→ custom `SSLContext` injectable — the SPIFFE-bundle context can be enforced through the library) and `requestBuilder(...)` / `httpRequestCustomizer(McpSyncHttpClientRequestCustomizer)` (→ Authorization bearer injectable). Verified in source, main branch.
- java-spiffe 0.8.17 independently confirmed latest on GitHub releases — matches the D-006 pin.

Consequences:

1. **ARCHITECTURE.md needs a human-gated amendment**: §Token flow step 3 says `resource` = MCP server URI — contradicted. Proposed wording: "`audience` = the MCP server's client (Keycloak implements `audience`; it has no `resource` support)". This entry is the record until applied; the `docs/diagrams/` files mirror ARCHITECTURE and get the same one-word fix then.
2. **VERSIONS.md rows still owed (human-gated):** MCP Java SDK pin + which MCP revision the demo client speaks (satisfies the existing VERIFY row); anthropic-java `2.52.0` (demo track only — not needed before M10). java-spiffe and Spring Boot are already pinned via D-005/D-006.
3. M9 remains the finish line; the demo track is explicitly optional and cost-bounded (~a weekend after M9).

---

## D-008 — M10 LLM layer reworked: provider-neutral Spring AI abstraction, free/local default (Ollama); Anthropic SDK dropped

Date: 2026-07-31 · Milestone: planning (demo track) · Author: claude-code (user-directed: "I don't have the money for Anthropic API… prefer free LLM… build an abstraction… don't tie to any provider")

Decision:

1. **M10 no longer uses the Anthropic Java SDK.** The agentic loop is written against **Spring AI 2.0's `ChatClient`/`ChatModel` abstraction** — the provider is selected by starter dependency + `application.properties`, never by code. Containment mirrors CLAUDE.md §5: no provider-specific type outside the single Spring configuration class; the loop depends only on `ChatClient`/`ToolCallback`. A provider switch must touch only the build file and properties.
2. **Default demo provider: Ollama, run locally.** Free, and strictly stronger for the demo narrative than D-007's "API key in env only": **no LLM credential exists anywhere** in the default configuration. Free hosted alternatives (Groq, OpenRouter, Gemini OpenAI-compat) work through Spring AI's OpenAI-compatible client with a `base-url` override — Ollama itself also exposes `http://localhost:11434/v1` OpenAI-compat, per Spring AI's own docs. The demo model must be tool-calling-capable; exact model recorded at M10 implementation, not pinned now.
3. **D-007's MCP wiring is unchanged and still load-bearing.** The MCP Java client is still built by hand (`clientBuilder(...)` for the java-spiffe `SSLContext`, `httpRequestCustomizer(...)` for the exchanged bearer). It is exposed to the LLM layer via Spring AI's **`SyncMcpToolCallbackProvider`**, which wraps an existing `McpSyncClient` into `ToolCallback`s — Spring AI's MCP auto-configuration is NOT used, so Spring AI never constructs a transport and the three-trust-store rules cannot be bypassed by the framework. (Spring AI's MCP client starter supports supplying your own `McpSyncClient` bean; auto-config backs off via `@ConditionalOnMissingBean`.)
4. **Supersessions of D-007:** the owed VERSIONS.md row for anthropic-java `2.52.0` is dropped, replaced by an owed row for **Spring AI `2.0.0`** (BOM). D-007 point 3's sentence about the Anthropic API key is superseded by the zero-credential default above. D-007's standing rules (TLS contexts wired explicitly from java-spiffe material; token exchange hand-rolled; assertion-type URN one constant) are unaffected. The MCP Java SDK pin remains owed and must be consistent with the version Spring AI 2.0.0 manages.

Evidence (all fetched 2026-07-31):

- **repo1.maven.org** `org/springframework/ai/spring-ai-bom/maven-metadata.xml`: `<latest>2.0.0</latest>`, `<release>2.0.0</release>`, lastUpdated 2026-06-12 (repo1 is the pin authority per D-005).
- **spring.io blog 2026-06-12** "Spring AI 2.0.0 GA": built on Spring Boot 4.0 baseline / Spring Framework 7 — compatible with our Boot 4.1.0 pin (D-005). Spring AI 1.x is the Boot 3.x line and is not eligible.
- **docs.spring.io Spring AI reference** (MCP client starter + Ollama chat pages): `SyncMcpToolCallbackProvider` wraps `McpSyncClient`s into `ToolCallback`s; custom `McpSyncClient` bean overrides auto-config (`@ConditionalOnMissingBean`); `McpClientCustomizer` exists but transport-level SSLContext control still argues for the hand-built client; Ollama is OpenAI-API-compatible (`spring.ai.openai.chat.base-url=http://localhost:11434/v1`) and Spring AI documents cross-provider portability without code changes.

Consequences:

1. BUILD-PLAN.md M10 rewritten in the same commit (abstraction, Ollama default, zero-LLM-credential exit criterion).
2. **VERSIONS.md rows owed (human-gated):** Spring AI `2.0.0` (BOM); MCP Java SDK pin (unchanged obligation from D-007, now constrained to match Spring AI's managed version); demo model name (recorded at M10, config not pin).
3. M10's cost profile drops to zero for the LLM leg; hardware capable of running a local tools-capable model becomes the practical prerequisite, with a free hosted OpenAI-compatible endpoint as the fallback path (key in env only).

---

## D-007 — M6 landed: jwt-spiffe against Keycloak preview works; lab findings

Date: 2026-07-31 · Milestone: M6 · Author: claude-code (standing delegation)

Decision / findings, all proven by `scripts/check-m6.sh` (green):
1. **The exit criterion holds**: agent-client obtains a token with its JWT-SVID as the only credential (`azp=agent-client`). `aud` = realm issuer identifier, sole value, per the normative text.
2. **`client_id` MUST be the SPIFFE ID** (`spiffe://lab.internal/agent-client`), not the Keycloak clientId: the authenticator rejects otherwise with `client_id parameter does not match sub claim`. The client derives it from its own JWT-SVID — zero client-side identity config.
3. **Bundle endpoint TLS = lab's web-PKI stand-in.** https_web serves a cert (DNS:spire-server, EKU serverAuth) signed by the SpireIntermediate key; Keycloak validates it via `--truststore-paths=ejbca-root.pem`. The URI name constraint doesn't restrict DNS SANs (RFC 5280 constraints are per-name-type) — deliberate and fine for serverAuth. Issued by `infra/pki/issue-bundle-endpoint-cert.sh`.
4. **Keycloak auto-generates a secret row for every confidential client**, including federated-jwt ones; it cannot be deleted/blanked via kcadm. "No client secret exists" is enforced in the meaningful sense: none in repo/env, and the check proves the auto-generated value is NOT an accepted credential (401 on client_secret auth).
5. **SPIRE 1.15.2 doc bug**: `serving_cert_file.file_sync_interval` claims default 1h but empty value crashes the server (`time: invalid duration ""`) — set explicitly. Upstream-reportable.
6. Negative proven: a valid JWT-SVID whose `sub` is a different workload (mcp-server) is rejected for this client (400 invalid_client).

Evidence: check output in session transcript; Keycloak truststore option from 26.6.0 `keycloak-truststore.adoc`; federation config from `specs/spire/spire_server.md`.

Consequences: M7 rides the same client auth; workstream B builds only the `act` protocol mapper (per the human's revised BUILD-PLAN M7). Two upstream-reportable items so far: none for Keycloak aud (matches normative), one for SPIRE doc default.

---

## D-008 — M7 landed: standard token exchange + act-spiffe mapper (workstream B's actual job)

Date: 2026-07-31 · Milestone: M7 · Author: claude-code (standing delegation; design per the human's revised BUILD-PLAN M7)

Decision / findings, proven by `scripts/check-m7.sh` (green):
1. **Exit criterion holds**: exchanged token carries `sub` = alice, `act.sub` = `spiffe://lab.internal/agent-client`, `aud` = `https://mcp.lab.internal:8443`; the MCP server accepts it over SVID mTLS and logs `sub` + `act` on every call.
2. **No `audience` parameter needed, no resource client needed**: 26.6.0's `audience` parameter only FILTERS audiences (securing-apps/token-exchange.adoc: "will not add more audiences"); the exchanged token inherits `aud` from the requester's client scopes — agent-client's `mcp-audience` scope supplies the canonical resource id.
3. **Subject-token rule**: `StandardTokenExchangeProvider` rejects exchange when the requester is not in the subject token's `aud` ("reject if the requester-client is not in the audience of the subject token"). Hence the `agent-audience` client scope on `test-caller`: tokens alice hands to the agent carry `aud=agent-client`. This is a real security property — a token minted for some other consumer cannot be laundered through the agent (negative test green).
4. **Exchange enablement** is per-client: attribute `standard.token.exchange.enabled=true` (`OIDCConfigAttributes:95`); requester must be confidential (public clients rejected in source).
5. **`act` mapper (workstream B, `keycloak-spiffe-spi/`)**: `act-spiffe-mapper` stamps `act.sub` from the *authenticated requester client's* `jwt.credential.sub` attribute (the identity its JWT-SVID proved at client auth) — faithful RFC 8693 §4.1 semantics without an `actor_token` parameter, which Keycloak's standard exchange does not support. No `act` on service-account-subject tokens (no human → no delegation). Reuses Keycloak's own `FederatedJWTClientAuthenticator.JWT_CREDENTIAL_SUBJECT_KEY` constant — no string duplication; the assertion-type URN still exists exactly once (agent-client).
6. **Keycloak compose service is now a built image**: pinned `quay.io/keycloak/keycloak:26.6.0` base + the SPI jar (multi-stage in `keycloak-spiffe-spi/Dockerfile`). The base pin remains governed by VERSIONS.md; pom's `keycloak.version` must match it.

Evidence: 26.6.0 token-exchange.adoc; StandardTokenExchangeProvider.java:160-180; OIDCConfigAttributes.java:95; check-m7.sh output in transcript.

Consequences: M8 (cert-bound tokens) is optional garnish per the M7 scope discussion; M9 acceptance can now assert the full happy path plus all four rejections. Draft-isolation intact: a draft rev bump still touches only SpiffeClientAuth.java + Keycloak's own validator (upstream).

---

## D-009 — M8 skipped; replaced by act↔peer binding enforced at the MCP server

Date: 2026-07-31 · Milestone: M8/M9 · Author: claude-code (user decision: "our own idea is use certificate x509 spiffe for agent … ok do it")

Decision:
1. **M8 (RFC 8705 cert-bound tokens) is not built.** In this architecture the classic stolen-bearer-token attacker is already stopped at the MCP mTLS handshake (M5): no allowlisted SVID, no connection. Full RFC 8705 would additionally require Keycloak TLS with client-cert request and would bind tokens to hourly-rotating X509-SVIDs (tokens dying mid-lifetime on rotation) — cost without proportional lab value.
2. **The residual gap is closed instead**: token and transport were not cryptographically tied to EACH OTHER, so with ≥2 allowlisted workloads, workload B could replay workload A's token while the audit trail (act.sub=A) lied. The MCP server now enforces `act.sub == mTLS peer SPIFFE ID` → 403 "actor/peer mismatch". Issuance-time proof (JWT-SVID client auth stamped act.sub) is thereby chained to call-time proof (X509-SVID key possession).
3. **Caveats, stated plainly**: this is policy in the resource server, not a `cnf` claim in the token — it does not travel with the token and protects nothing if transport client auth were ever removed. Tokens WITHOUT an act claim are currently allowed through (audited with sub+peer) so pre-M7 flows keep working; a strict delegation-only mode would reject them.
4. **Provable, not theoretical**: a second workload `spiffe://lab.internal/test-agent` is registered and allowlisted as a permanent test fixture; the M9 acceptance asserts that test-agent replaying agent-client's exchanged token gets 403 via the binding check (a DIFFERENT code path than the allowlist 403, which the unlisted-workload rejection covers).

Consequences: BUILD-PLAN M8 annotated as skipped-by-decision; M9 gains a fifth rejection. If the lab later wants real sender-constrained tokens, revisit RFC 8705 or DPoP against the SVID-rotation tension.

---

## D-010 — Demo-track pins and verified library facts (M10 P0)

Date: 2026-07-31 · Milestone: M10 · Author: claude-code (standing delegation; BUILD-PLAN's "human-gated" flag on these rows noted — veto window open)

Pins (all from repo1 maven-metadata / hub tags, per the D-005 lesson):
| Component | Pin | Evidence |
|---|---|---|
| Spring AI | `2.0.0` | repo1 `<latest>`; starter poms depend on **Spring Boot 4.1.0 exactly** — matches our D-005 pin |
| MCP Java SDK | `io.modelcontextprotocol.sdk` `2.0.0` | repo1 `<latest>`; GitHub tag `v2.0.0`. 2.0.0 split the artifacts: `mcp-core` + `mcp-json-jackson2/3` (+ `mcp` aggregator) |
| Ollama image | `ollama/ollama:0.32.5` | hub.docker.com newest stable (non-rc) |
| Demo model | `qwen3.5:4b` | ollama.com tools-capable catalog; small enough for CPU-only inference |

Verified APIs (file:line from tag sources):
1. **The two load-bearing hooks exist** — `HttpClientStreamableHttpTransport.Builder` (mcp-core, v2.0.0): `clientBuilder(HttpClient.Builder)` :744 (java-spiffe `SSLContext` injection) and `httpRequestCustomizer(McpSyncHttpClientRequestCustomizer)` :835 (exchanged-bearer injection). Also `asyncHttpRequestCustomizer` :851.
2. `SyncMcpToolCallbackProvider(List<McpSyncClient>)` — spring-ai-mcp 2.0.0, `org.springframework.ai.mcp` :96.
3. `ChatClient.builder(ChatModel)` + `Builder.defaultToolCallbacks(ToolCallbackProvider...)` — spring-ai-client-chat 2.0.0 :80/:585.
4. Starters exist at 2.0.0: `spring-ai-starter-model-ollama`, `spring-ai-starter-mcp-client`, `spring-ai-starter-mcp-server-webmvc` (server side runs as normal servlet routes → our security filters apply).

Consequences: BUILD-PLAN M10's stale references to D-007/D-008 corrected to this entry. P1 may begin. VERSIONS.md rows added in this commit.

---

## D-011 — M10 P1: MCP protocol surface; scope gate; SIGPIPE bug in setup guards

Date: 2026-07-31 · Milestone: M10 (demo track) · Author: claude-code

1. **mcp-server now speaks MCP** (Spring AI `spring-ai-starter-mcp-server-webmvc` 2.0.0, streamable HTTP at `/mcp` — defaults verified in `McpServerStreamableHttpProperties:36`, `McpServerProperties:100`). Tools are `@McpTool`-annotated beans (`org.springframework.ai.mcp.annotation.McpTool`), auto-discovered by `McpServerSpecificationFactoryAutoConfiguration`. **Every existing gate applies unchanged** to `/mcp` — audience, SVID mTLS, allowlist, act↔peer — because it is an ordinary servlet route.
2. **Tools**: `whoami` (returns both identities), `lab_status` (what this server enforces), `read_audit_log` (**scope-gated on `mcp:audit`** — the P3 fixture; refusal is `InsufficientScopeException`, surfaced to the agent as a tool error). `AuditLogBuffer` records identities and verdicts only — never tokens.
3. **`mcp:audit` is an OPTIONAL Keycloak client scope**, deliberately not default: alice's demo token does not carry it, so the refusal is real rather than staged.
4. **Bug found and fixed (was corrupting idempotency): `K get … | grep -q` under `set -o pipefail`.** `grep -q` exits on first match → SIGPIPE to the upstream `docker exec` → non-zero pipeline → an *existing* object reads as missing → the script re-creates it and dies ("Protocol mapper exists with same name"). Timing-dependent, hence intermittent. All such guards in `setup-realm.sh` / `setup-spiffe-idp.sh` now capture output first, then match (`has()` helper). Verified: three consecutive runs clean.

Evidence: `scripts/check-p1.sh` green — initialize / tools/list / tools/call over SVID mTLS, scope-gated tool refused, server logged `sub`+`act`, and `./infra/acceptance.sh` still exits 0 untouched.

Consequences: P2 (agentic loop) may begin; the protocol layer it needs is proven. The `has()` pattern is the house style for kcadm existence checks from now on.

---

## D-012 — M10 P2: agentic loop landed; per-request bearer via the SDK's transport-context channel; Angular console groundwork

Date: 2026-07-31 · Milestone: M10 (demo track) · Author: claude-code

Decision / findings, proven by `scripts/check-p2.sh` (green):

1. **The loop is exactly the M10 shape**: `ChatClient` (provider-neutral) + `SyncMcpToolCallbackProvider` over a hand-built `McpSyncClient`; java-spiffe `SSLContext` in via `clientBuilder(...)`, exchanged bearer in via `httpRequestCustomizer(...)`. Spring AI constructs no transport. Containment is executable: `check-p2.sh` fails on any non-neutral `org.springframework.ai.*` reference outside one config class — currently **zero provider types exist in code at all** (the Ollama starter autoconfigures `ChatModel`; the provider lives in the build file + properties only).
2. **Per-request bearer (P2.5-proofing, human-directed mid-session)**: the exchange is a component taking the subject token as an argument, run per message; the bearer travels through the MCP SDK's sanctioned channel — `SyncSpec.transportContextProvider` (supplier runs on the calling thread; `McpSyncClient.java:453`) → `McpTransportContext` → customizer (`McpSyncHttpClientRequestCustomizer` javadoc: "Do not rely on thread-locals... use transportContextProvider"). Fail closed both sides: no bearer in scope → `IllegalStateException`, never an unauthenticated call. Known cosmetic: the SDK's session-cleanup DELETE at shutdown runs outside a bearer scope and trips exactly that check; logged at error-only (`logging.level.io.modelcontextprotocol=error`).
3. **"sub = alice" precised**: Keycloak subs are UUIDs, not usernames. The check asserts the logged `sub` equals the `sub` decoded from alice's own subject token — the human survived the exchange as the same subject, which is stronger than a name match. (BUILD-PLAN/DEMO-PLAN wording "sub=alice" means this.)
4. **Property-key recall hazard dodged**: Spring AI 2.0.0 Ollama keys verified from `spring-ai-autoconfigure-model-ollama-2.0.0.jar` `spring-configuration-metadata.json` (`spring.ai.ollama.base-url`, `chat.options.model`, `chat.options.temperature`, `init.pull-model-strategy`). Runtime never pulls (`pull-model-strategy=never`); `infra/ollama/pull-model.sh` is the only pull path. Ollama publishes no host port — lab-network only.
5. **MCP JSON mapper**: the `mcp` aggregator (via `spring-ai-mcp`) brings `mcp-core` + `mcp-json-jackson3`; the transport's default `McpJsonDefaults.getMapper()` discovers it via ServiceLoader — no explicit wiring.
6. **CLI compatibility preserved**: Boot-repackaged jar with `AgentMain` dispatcher; `url|token|mcp|svid` modes bypass Spring entirely (M5–M9 checks unaffected; `acceptance.sh` untouched, exit 0 re-verified inside check-p2).
7. **Angular console groundwork (human-directed: "latest Angular", "conventions Claude Code must enforce, referenced by CLAUDE.md")**: Angular CLI `22.1.2`/core `22.1` pinned from npm registry `latest` (D-005 lesson; VERSIONS.md row added under the D-010 standing delegation — veto window open). Conventions in `docs/CONVENTIONS-ANGULAR.md` (lint-enforced size/complexity/token rules) + `console/CLAUDE.md` (binding); root `CLAUDE.md` map/reference line added **on explicit user instruction this session** (normally ask-first). Mockup arrived at `mockup/identity-demo-console.html` (P4 input, read-only reference).

Evidence: check output in transcript; SDK facts from mcp-core 2.0.0 / spring-ai-mcp 2.0.0 sources jars (repo1); npm registry metadata for Angular pins.

Consequences: P2.5 reuses `TokenExchange`/`BearerHolder`/`AgentLoop` unchanged (adds oauth2-client + a page). P3's fixture is already live (alice's token lacks `mcp:audit`). P4 starts from `console/CLAUDE.md`. Standing user directive this session: continue through the remaining demo phases in one run.

---

## D-013 — M10 P3: negative demo green; DEMO_RUN capture format (M11 input) fixed at v1

Date: 2026-07-31 · Milestone: M10 (demo track) · Author: claude-code

1. **BUILD-PLAN M10 exit #2 proven** (`scripts/check-p3.sh` green): asked to read the audit log, the model attempts the tool (server logs `tool=read_audit_log DENIED` for alice's sub), the server refuses with `insufficient_scope`, no successful read occurs, and the agent reports the refusal in its answer. The check also asserts the fixture is real (alice's token demonstrably lacks `mcp:audit`) so the refusal can never be staged.
2. **DEMO_RUN v1** (`demo/demo-run.schema.json`): the M11 console's single input. `demo/capture-run.sh` captures happy chat + scope refusal + the five M9 rejections + chain of custody into `demo/demo-run.json`; `demo/assemble-run.py` decodes claims, forces `signature: REDACTED`, and **refuses to write** if any JWT-shaped string (three base64url segments) survives — the "holds no secrets" property is enforced at capture time, not by console politeness.
3. The capture reuses acceptance.sh verbatim as the source of rejection verdicts (`deny-as-designed` only if the corresponding PASS line is present) — the console can never show a rejection the stack didn't actually perform.

Evidence: check-p3 and capture output in transcript; demo/demo-run.json in-repo (committed as the console fixture).

Consequences: P4 renders this file; P2.5 will extend the capture's login step (kind: consent) when it lands.

---

## D-014 — M10 P2.5: browser OIDC login + chat UI; consent is the delegation moment

Date: 2026-07-31 · Milestone: M10 (demo track) · Author: claude-code

Proven by `scripts/check-p25.sh` (green):
1. **The flow**: alice logs in at the agent's page via authorization code + **PKCE** (public client `demo-web`, `client-authentication-method=none` → Spring Security auto-PKCE, S256 enforced client-side by Keycloak attribute), **consents** (`consentRequired=true`; the check force-revokes prior consent every run so the moment is always real and FAILS if the screen does not appear), chats; per message her session token is the subject of the RFC 8693 exchange (`AgentLoop`/`TokenExchange`/`BearerHolder` from D-012, unchanged — the P2 per-request design paid off exactly as intended).
2. **Token hygiene enforced, not claimed**: the check greps every browser-visible response for JWT-shaped strings (3 dot-separated base64url segments) — none may appear; alice's token lives in the server-side session, the browser holds a cookie.
3. **Scope toggle wired for the interactive P3**: two login links — `/oauth2/authorization/keycloak` and `.../keycloak-audit` (adds optional `mcp:audit`) — what alice grants at consent decides what the agent may do.
4. **oauth2-client is alice's login leg only.** The agent's own credential remains the JWT-SVID; the exchange remains hand-rolled (D-007 standing rule intact). `demo-web` config lives in `infra/keycloak/setup-demo-web.sh` (idempotent, D-011 has() pattern); acceptance.sh does not know it exists.
5. **Host-browser note**: issuer is `http://keycloak:8080` (D-005), so the check maps that name to 127.0.0.1 via `curl --resolve`; a human browser needs the equivalent hosts-file line — goes into the P5 checklist.
6. Scripting findings: Keycloak 26.6.0 renders the consent form action **relative** (qualify against the issuer), and the consent POST needs the `accept` param present (value irrelevant) plus the hidden `code` field replayed.

Consequences: the on-stage story is now end-to-end human: login → consent → chat → server log with sub+act. P5's checklist gains the hosts-file line; the capture's login step can be upgraded to kind=consent later without schema change (kind enum already includes it).

---

## D-015 — M11 P4: Angular 22 console renders the captured run offline; conventions enforced by lint

Date: 2026-07-31 · Milestone: M11 (demo track) · Author: claude-code

Proven by `scripts/check-console.sh` (green):
1. **The console** (`console/`, Angular CLI 22.1.2 / core 22.1 per the VERSIONS pin): standalone components, signals, zoneless (the v22 scaffold default), OnPush everywhere, selector prefix `dc`. It renders `demo-run.json` (DEMO_RUN v1, D-013) **offline** — the check asserts no external origin in the bundle, fonts shipped locally, and the capture present. Fail-closed input: `parseDemoRun` rejects malformed captures, wrong trust domain, unredacted signatures, or ANY JWT-shaped string, and the app then shows an error state — never a partial run (tested).
2. **Design system**: tokens extracted from the mockup's "Classical" system into `src/styles/tokens.css` (primitive + semantic layers); components consume semantic tokens only. The mockup's colour language is semantic (human `#17557f`, workload `#12706a`, bridge `#e0552b`) and encoded as `--id-*` tokens. CONVENTIONS-ANGULAR's earlier "dark-first" guess was corrected against the actual mockup (light, serif; the ink-navy band is header/log only).
3. **Presentation copy vs captured fact**: narration/stories live in `core/narrative.ts` (authored, from the approved mockup); every verdict, claim, identity, and log line comes from the capture. A rejection card can show "NOT REFUSED" (alarm styling) only if the capture says the stack failed to deny — tested with a negative fixture.
4. **Conventions are enforced, not advisory**: eslint flat config carries max-lines 300 / max-lines-per-function 40 / complexity 10 / OnPush-required / `dc` selectors; the check runs it as a blocking gate. The rules bit their own author twice during this build (parse complexity, fixture length) — refactored, not weakened.
5. **Dependencies beyond the scaffold** (recorded per CONVENTIONS-ANGULAR): `@fontsource/cormorant-garamond` + `@fontsource/lora` (offline fonts), `eslint`/`angular-eslint`/`typescript-eslint` (the enforcement mechanism). npm 11's `allowScripts` approvals for `@parcel/watcher`/`esbuild` are pinned in package.json.
6. **Windows path wart**: the repo path contains `&`, which breaks npm's cmd `.bin` shims; package.json scripts call the node entry points directly (`node node_modules/@angular/cli/bin/ng.js ...`). Also: the Angular build cache does not survive a fresh `node_modules` — the check clears `.angular` after `npm ci`.

Consequences: BUILD-PLAN M11 exit is met (complete run rendered offline from captured JSON; killing it changes nothing — it is static files). P5 remains: stage resilience + DEMO.md narration. Re-capture (`demo/capture-run.sh`) then `cp demo/demo-run.json console/public/` refreshes what the console shows.

---

## D-016 — M10/M11 P5: stage resilience, narration, rehearsal; SIGPIPE pattern promoted repo-wide

Date: 2026-07-31 · Milestone: demo track P5 · Author: claude-code

1. **Stage kit**: `demo/reset.sh` (`--soft` restarts the app layer + idempotent setup, measured **83–84s**, under the <2 min target; `--full` = compose down/up with volumes kept, ~3 min; `--cold` destroys SPIRE/EJBCA volumes and ASKS first per CLAUDE.md §7). `demo/checklist.sh` checks clock skew FIRST (§8), then service health, model presence, ports, and the hosts-file line; `--full` adds the terminal acceptance. `docs/DEMO.md` carries the three-act narration and the failure cheat-sheet; the offline console is the recorded fallback.
2. **Rehearsal evidence**: soft reset + checklist green twice (83s, 84s); third pass with `--full` checklist green including acceptance (all five rejections). The **cold** rehearsal is deliberately left to the human: it requires volume deletion (ask-first) and the EJBCA re-setup is the human-led critical path.
3. **D-011's SIGPIPE bug had a second instance**: `infra/spire/register-workloads.sh` used `srv entry show | grep -q` under pipefail — an existing entry intermittently read as missing, the re-create then died ("failed to create one or more entries"; surfaced during rehearsal 2). Fixed with the same capture-first helper. **Ruling extended: the D-011 has() pattern is house style for ALL container-CLI existence checks (kcadm, spire-server, anything docker-exec'd), not just kcadm.**
4. Session-scope note: P2→P5 were executed in one overnight run under an explicit user directive ("build everything left while I'm sleeping"), overriding the one-milestone-per-session default; each phase kept its own exit check and commit.

Consequences: demo track complete — M10 exits #1/#2/#3 and M11 exit all green (D-012..D-015); `./infra/acceptance.sh` exits 0 untouched throughout. Remaining human items: hosts-file line for the live browser demo, and one cold-start rehearsal.

---

## D-017 — P6 (user-directed): live chat inside the console; the no-stack-calls rule amended for the agent's own API

Date: 2026-07-31 · Milestone: demo track P6 · Author: claude-code (user chose "live chat in console" over playback-only)

Proven by `scripts/check-p6.sh` (green):
1. **agent-web serves the built console** at `/console/` (compose mounts `console/dist/console/browser` read-only; built on host — no node in the Java image; `<base href="./">` makes the bundle subpath-agnostic). Same origin, so alice's session cookie and CSRF work unchanged.
2. **JSON surface**: `GET /api/me` (public; 401-shaped when logged out; returns username, consented scopes, and the CSRF token the console echoes in `X-CSRF-TOKEN`) and `POST /api/chat` (authenticated; per message runs the D-012 chain: session token → RFC 8693 exchange → mTLS MCP call). Responses carry answers and identity labels — never a token (the check greps every browser-visible body for JWT shapes).
3. **CSRF switched to the plain `CsrfTokenRequestAttributeHandler`** for the web profile: the console reads the raw token from /api/me; the default XOR handler rejects raw tokens, and BREACH masking protects nothing in this lab.
4. **The console's rule amendment is scoped and self-degrading**: live mode exists only when `/api/me` answers; on 401 the console shows the two login links (plain / with `mcp:audit` — the consent toggle); anywhere else (file://, ng serve, static host) it falls back to the recorded capture. `check-console.sh` (offline M11 exit) and `check-p25.sh` surfaces remain green; `CONVENTIONS-ANGULAR.md` amended in this commit.
5. **The animated flow is labeled illustration, honest about what is real**: hop chips animate in order while a message is in flight; verdicts (answer/refusal) and the log lines are the captured/live facts. The model's per-hop timing is not instrumented — the proof remains the server log line.

Consequences: the on-stage surface is now ONE page — http://localhost:8090/console/ — with live chat on top and the recorded anatomy below it. The plain chat page at `/` remains for P2.5's check. Console rebuilds: `npm run build` in `console/`, no container restart needed (volume mount).

---

## D-018 — P6.1 (user-directed): the live flow is now REAL — per-message chain events streamed to the console

Date: 2026-07-31 · Milestone: demo track P6.1 · Author: claude-code (user: "all process must be reflected in real time")

Proven by the extended `scripts/check-p6.sh` (green):
1. **The chain is instrumented, not simulated.** `AgentLoop.ask(subject, msg, Consumer<StepEvent>)` narrates the per-message chain with REAL completions: `svid` (JWT-SVID minted — emitted between the Workload API fetch and the token POST; `TokenRequest` split into `fetchSvid`-then-`post` for exactly this seam), `exchange` (RFC 8693 done), and `tool` (every actual tool invocation — each `ToolCallback` is wrapped in a delegating narrator, so the event fires when the MODEL decides to call, not on a timer). Details are identity labels and tool names only — never token material.
2. **`POST /api/chat/stream`** (SSE, `SseEmitter`, loop on a virtual thread; subject token resolved on the request thread) streams each event the moment it happens, then `answer`/`error`. The plain `/api/chat` JSON endpoint stays for compatibility.
3. **The console consumes the stream** (`LiveClient.chatStream`, hand-rolled SSE reader over `fetch`): hop chips advance on real events (`02 fetch JWT-SVID → 03 exchange · act.sub → 04 mTLS tool call · <name> → 05 answer`), a monospace feed shows each event line as it arrives, and a refusal marks the in-flight hop failed. The previous timer-based illustration is gone — D-017's "labeled illustration" caveat is retired.
4. The check asserts the events arrive **in order**, carry the tool name, correlate with a fresh `act.sub` log line on the MCP server, and that nothing JWT-shaped reaches the browser; offline console (M11 exit) and acceptance.sh remain green.
5. SSE wire format note: `SseEmitter` writes `event:name` with no space — check greps and the client parser accept both forms.

Consequences: what the audience sees animate IS the security chain executing. Remaining honest caveat: hop *start* moments are inferred (previous hop's completion); completions are real.

---

## D-019 — P6.2 (user-reported + user-requested): login stays on the console; the mockup's animated architecture diagram ported

Date: 2026-07-31 · Milestone: demo track P6.2 · Author: claude-code

1. **Login returns to the console** (user-reported: authentication dumped them on the plain page): `defaultSuccessUrl("/console/")` and logout success likewise; the live panel gains a "log out · switch scopes" button (CSRF-protected POST /logout via fetch) so the P3 consent toggle is doable without ever leaving the console. check-p6 now asserts the login flow's final URL contains /console.
2. **The mockup's animated architecture diagram is in** (user-noticed it was missing): `dc-flow-diagram` ports the SVG verbatim in structure — six nodes, SMIL `animateMotion` packet dots, per-edge arrowheads — restyled onto the token palette (no raw hex). Edges/packets/labels light per selected stage; a **play** button walks the five stages (the mockup's play behavior). Tested: nodes render, edges follow the stage, packets toggle.
3. **Angular build cache disabled for this project** (`cli.cache.enabled=false`): the cache repeatedly corrupted when `ng test`/`ng serve`/`ng build` interleaved ("contents must be a string or a Uint8Array"), the third occurrence today. Deterministic builds beat the saved seconds; the check's `rm -rf .angular` guards remain for older clones.

Evidence: `scripts/check-p6.sh` green end-to-end (including the new console-return assertion); console suite 25 tests green.

Consequences: the console is now the single demo surface — diagram + live chat + recorded anatomy on one page. Full check runtime grew past 10 minutes (two model inferences + nested offline check, uncached builds); acceptable for an exit criterion, not for a smoke test — `demo/checklist.sh` remains the fast pre-flight.

---

## D-020 — P6.3 (user-directed, emphatic): ONE interface — the console at /; the plain page deleted

Date: 2026-07-31 · Milestone: demo track P6.3 · Author: claude-code

1. **The console is the only surface.** `ChatPageController` (the P2.5 server-rendered page) is deleted; the built Angular console is served at the ROOT (`/**` resource fallback + `/` → index.html; `/console` redirects home for old bookmarks). Controllers keep precedence for `/api/**`, `/oauth2/**`, `/login/**`, `/logout`, `/error`.
2. **Login lands on the console, unconditionally**: `defaultSuccessUrl("/", true)` — alwaysUse. Root cause of the twice-reported bug: a saved request in the session outranks a plain defaultSuccessUrl, and curl-based verification (clean jar, no saved request) could not reproduce what a real browser session hit. Lesson recorded: verify redirect behavior with poisoned session state, not only clean state.
3. **check-p25.sh re-targeted** at the real surface, all its essence preserved and re-proven green: forced-fresh consent, login ends at `/` (asserted on url_effective), chat POST → server log `sub=alice` + `act.sub=agent`, no token-shaped string browser-visible, acceptance untouched/green. Security config now: only `/api/chat` + `/api/chat/stream` require auth; everything else (console shell, assets, `/api/me`) is public and honest.
4. check-p6.sh updated for root serving (console at `/`, login-landing equality assert). Its full ~10-min run was NOT re-executed after this refactor (P25 covers the changed paths; the stream endpoint is untouched) — **next session should run `bash scripts/check-p6.sh` once for the record.**

Consequences: http://localhost:8090 is the demo, full stop. Handoff state: all demo-track checks (m0–m7, p1, p2, p25, p3, p6, console, acceptance) green as of their last runs this session; stack up with demo profile; hosts-file line present on this host.

---

## D-021 — P6.4 (user-directed): audience-ready console — copy sweep, tabs, chat-window live panel; D-020's owed check-p6 run recorded green

Date: 2026-07-31 · Milestone: demo track P6.4 · Author: claude-code

1. **D-020's owed item is closed**: `scripts/check-p6.sh` full run executed this session against the P6.3 build — **P6 PASS, exit 0**, all legs green including nested check-console and acceptance.
2. **Copy sweep (user: page must read clean for an audience, nothing AI-flavored)**: colour-language legend deleted; section kickers ("same chain, running now", "Every rejection is the design working", "Click a step") removed; headings renamed to feature labels (Architecture, Request flow); rejection-card "lesson" aphorism line dropped (story + mechanism stay — both factual); live-panel footnote/explainers removed; em-dash asides in narration flattened to plain sentences; internal jargon ("(M3)") removed from visible copy. All verdict/identity/log content untouched — the capture remains the only source of facts.
3. **Tabs**: "Rejections" and "MCP server log" now share one tabbed section (default: Rejections); app.spec covers default tab + switch. Rationale: page length and feature focus; both panels are secondary anatomy under the live demo.
4. **Live panel is now a chat window** (user-directed): sender-labeled bubbles (username right in `--id-human`, agent left neutral), sent message echoed immediately via a `draft` signal, three-dot typing indicator, auto-scrolling thread (effect + `scrollTop`; jsdom has no `scrollTo`), pill composer. New primitive token `--radius-lg: 10px` for bubble/composer radii. Hop rail and event feed unchanged — the real-time chain evidence (D-018) is untouched.
5. Housekeeping: `.claude/scheduled_tasks.lock` (runtime artifact accidentally committed at M4) untracked; `.claude/*.lock` gitignored.

Evidence: check-p6 PASS output in transcript; `scripts/check-console.sh` green post-change (26 tests, lint, offline assertions); served-bundle grep confirms removed strings absent and new UI strings present at http://localhost:8090.

Consequences: console suite is 26 tests. Copy in `core/narrative.ts` is now the audience script — future copy edits stay factual-first per D-015 point 3.

---

## D-022 — P6.5 (user-directed): live X.509-SVID chain view; mid-session token expiry fixed with the refresh grant; diagram + copy polish

Date: 2026-07-31 · Milestone: demo track P6.5 · Author: claude-code

1. **`GET /api/svid`** (agent-web, public per D-020's split): the agent's CURRENT X.509-SVID chain as certificate METADATA only — subject/issuer DN, serial, validity window, URI SANs, SHA-256 fingerprint; never a private key, never PEM. Read live from the `X509Source` (API verified by `javap` against the pinned java-spiffe-core 0.8.17 jar: `getX509Svid().getChain()`, `getBundleForTrustDomain(...).getX509Authorities()`), bundle deduped against the chain by fingerprint. Console: `dc-cert-panel` renders it on stage 02 when live (refresh button re-fetches — rotation is visible: the leaf's serial/validity change, the SPIFFE ID doesn't); offline mode shows only the captured custody panel, M11 exit untouched. check-p6 asserts: SPIFFE ID + leaf metadata present, nothing key/PEM-shaped served.
2. **User-reported live bug fixed: after ~5 min logged in, every chat failed** `token exchange failed: HTTP 400 invalid_token`. Diagnosis per §8: clock skew ruled out first (≤2s); Keycloak event log showed `reason="subject_token validation failure"` with client auth (jwt-spiffe) still succeeding — alice's ACCESS token had expired in the server-side session while her login session lived on; the P6 controllers used `OAuth2AuthorizedClientService` (login-time token, never refreshed). Fix: `DefaultOAuth2AuthorizedClientManager` with `authorizationCode().refreshToken()` providers; all three endpoints obtain a fresh access token per request (`freshClient`, fail-closed to 401/session_expired when the refresh grant is rejected). Proven by check-p25 green post-fix; the expiry path itself is not check-automated (would need a 5-min wait or a shortened lifetime, and shortening realm token lifetimes for a test is config distortion we decline).
3. **Stage-card copy rewritten in plain English** (user: "simple english, not AI traced") — all five narration/proves pairs in `core/narrative.ts`; facts unchanged. **Architecture diagram decluttered** (user-reported overlap): node kickers 14→11px, third-line mono labels removed from all six nodes.
4. Note for the record: the earlier full check-p6 run this session (pre-P6.5 code) was green; this entry's changes re-ran it green again (evidence below).

Evidence: Keycloak `TOKEN_EXCHANGE_ERROR` log lines + clock check in transcript; javap output in transcript; `/api/svid` live response (leaf TTL 1h) in transcript; check-p25 PASS and check-p6 PASS outputs in transcript; console suite 31 tests green.

Consequences: the console can now show the actual rotating certificate on stage — the "auto loaded" story is demonstrable, not narrated. Sessions survive access-token expiry for the length of Keycloak's SSO session (idle 30 min default); past that, the API answers 401 and the console shows the login banner.

---

## D-023 — P6.6 (user-directed, PKI-expert audience): full X.509 detail view + rotation countdown

Date: 2026-07-31 · Milestone: demo track P6.6 · Author: claude-code

1. **`/api/svid` now carries a complete per-certificate breakdown** (`X509Details`): version, signature algorithm, public key (type + size), and EVERY extension — decoded where the JDK or a ~100-line DER TLV walker (`Der.java`) can render it (Key Usage, EKU, Basic Constraints, SAN, SKI/AKI keyids, **Name Constraints** — the EJBCA intermediate shows `critical, Permitted: URI:lab.internal`), raw hex + OID otherwise, never omitted. Display-only code, explicitly NOT a validation path (per-extension decode failure degrades to hex — documented in the class javadoc so nobody mistakes it for catch-and-permit). DN rendering maps OID 2.5.4.5 → `SERIALNUMBER` (SPIRE stamps that RDN; the default rendering is `2.5.4.5=#<hex>` noise). Still metadata-only: no key, no PEM (check-p6 asserts absence, plus presence of details and the name-constraint string).
2. **Console presentation for experts without clutter (progressive disclosure)**: the compact chain rows stay; each certificate gains a "▸ full certificate" expander (`dc-cert-detail`) rendering the openssl `x509 -text` layout PKI people already read. One expanded at a time.
3. **Rotation countdown (user-requested)**: pure functions in `rotation.ts` — SPIRE renews at ~half TTL (lab config `default_x509_svid_ttl = 1h`, read from `infra/spire/server.conf`), so the panel ticks "leaf expires in X · rotation expected in Y", labeled as an estimate. When the estimate comes due the panel auto-refetches every 30s until the new leaf lands — rotation appears on stage without touching the page.
4. Console suite 36 tests; countdown math unit-tested clock-free.

Evidence: live `/api/svid` output in transcript (all five chain certs decoded; AKI→SKI links visible across the chain); check-p6 PASS (run of record below); JDK `X500Principal.getName(format, oidMap)` used for DN keywords.

Consequences: the stage-02 panel is now sufficient for a PKI-literate audience end-to-end: chain-of-custody story (captured), the real chain (live), the name constraint readable, and rotation observable within a ~30-min session. The `Der` walker is deliberately minimal — if a future cert renders `raw:` hex for something worth decoding, extend the walker, don't reach for BouncyCastle without a decision entry.

---

## D-024 — Console build moved into the agent image (user-directed); supersedes D-017's host-build point

Date: 2026-07-31 · Milestone: demo track · Author: claude-code (user: "shouldn't we have angular as a docker container in docker compose?")

1. **The Angular console is now built inside `agent-client/Dockerfile`** (stage `console-build`, `node:22.23.2-alpine` — newest 22-alpine on hub at pin time; VERSIONS.md row owed, human-gated) and baked into the runtime image at `/app/console-ui`. The compose build context for both agent services widened to the **repo root** (`context: ..`) so the Dockerfile can see `console/`; a root `.dockerignore` allowlists only `agent-client/` + `console/` and keeps key material (infra/pki, spire bootstrap) out of any build context. A fresh machine now needs **only Docker + bash** — the README quickstart dropped the Node prerequisite and the host build step.
2. **Not a separate frontend container, deliberately**: at runtime the console is static files, and it must be served by agent-web itself — same origin is what makes alice's session cookie and CSRF work (D-017). Only the BUILD moved into Docker; D-017's serving model, D-020's one-interface rule, and the console's offline M11 exit are unchanged.
3. **The fast-iteration path survives as an explicit overlay**: `infra/docker-compose.dev.yml` mounts a host-built `console/dist/console/browser` over the baked copy (`npm run build` → visible without image rebuild). Default compose has no console mount — a fresh clone can never shadow the baked UI with an empty host dir.
4. Trade acknowledged: routine `docker compose build agent-web` now includes `npm ci` + `ng build` (~1–2 min warm, longer cold). Accepted for the portability win; the overlay exists precisely so UI work doesn't pay it per edit.

Evidence: image built from root context; running agent-web shows a single mount (spire socket) and serves `<dc-root>` + `/api/svid` from the baked files (transcript); node tag list from hub.docker.com/v2 (22.23.2-alpine).

Consequences: README quickstart is 3 steps; `check-p6`/`check-p25` unchanged (they assert the SERVED surface, agnostic of where it was built); console exit check (`check-console.sh`) still builds on host by design — it is the console's own gate, not the image's. VERSIONS.md row owed: `node:22.23.2-alpine` (build image, agent Dockerfile).

---

## D-025 — P6.7 (user-directed): routed app — /login landing page, guarded console, shell top bar

Date: 2026-07-31 · Milestone: demo track P6.7 · Author: claude-code (user: single page "looks not serious"; wants a separate login page)

1. **Angular Router introduced** (still ONE surface served by agent-web — D-020's law is about surfaces, not client-side routes): `/login` = branded sign-in page (two consent variants, i.e. the P3 scope toggle, plus "browse the recorded evidence" guest path); `/` = the console behind a functional guard (anonymous & not guest → redirected to /login; **offline serving bypasses the guard** so the M11 offline exit still renders the capture with zero login). `SessionService` is the one session truth (state signal + guest flag), loaded once.
2. **App shell**: ink top bar — brand ("Identity Console"), trust domain, signed-in user + scopes + logout. Session controls moved out of the chat panel into the chrome; `dc-live-chat` no longer knows how to log out.
3. **Server-side wrinkle found and fixed**: Spring Security's `DefaultLoginPageGeneratingFilter` owns `GET /login` ahead of MVC (the console's /login initially served "Please sign in"). Fix: `oauth2Login.loginPage("/login")` — declaring the SPA page as THE login page disables the generated one; MVC forwards `/login` → `index.html`. check-p6 now asserts /login serves `<dc-root>` and NOT the generated page.
4. Console suite 40 tests (console-page spec carries the old app tests; new shell + login-page specs). Old `/console` bookmark redirects kept.

Evidence: curl transcript (login route served Spring's page before the fix, `<dc-root>` after); check-p25 + check-p6 runs of record this session.

Consequences: the browser flow is now login page → Keycloak → consent → console, which reads like a product rather than a scrolling demo sheet. The P2.5-era direct links (`/oauth2/authorization/…`) are unchanged — checks and muscle memory keep working. Candidate follow-ups deliberately not done: separate /evidence route, favicon/branding pass, 404 page.

---

## D-026 — P6.8 (user-directed): live session and recorded run are separate views; capture copy scrubbed

Date: 2026-07-31 · Milestone: demo track P6.8 · Author: claude-code (user: recorded artifacts rendering by default "look hardcoded"; wants a history tab; no em dashes, no semicolons, no internal references in visible copy)

1. **The console has a view switcher**: "Live session" (default when signed in) and "Recorded run · date". The live view renders ONLY what is real right now — chat, architecture, request-flow narration, the live X.509 chain — with a dashed "awaiting" note where a captured artifact would otherwise sit. The recorded view carries the full captured anatomy (token cards, custody, call checks, rejections, log) under an explicit provenance banner ("captured by a scripted test client, not your session, every verdict was actually enforced"). Signed out or offline defaults to the recorded view, which keeps the M11 offline exit rendering with zero login.
2. **Copy rules from the user, now standing for all visible text**: no em dashes, no semicolons, no internal reference codes (D-nnn, P-n, M-n, grant names). Applied to the console templates AND the capture pipeline (`demo/assemble-run.py` note strings held "D-008", "P2/P2.5", "password grant"); the capture was re-run so the shipped JSON is clean. Code comments and docs are exempt, the rendered page is not.
3. Console suite 41 tests. The old always-rendered anatomy is gone from the live view by test ("logged in: ... NO captured artifacts").

Evidence: check runs of record this session; jargon grep of demo-run.json before/after in transcript.

Consequences: a signed-in viewer can no longer mistake the exhibit for their session. The capture keeps its role as verifiable evidence, now explicitly labeled as such. Future visible-copy edits follow the rule set in point 2.

---

## D-027 — demo track (user-directed): console typography goes corporate sans (Montserrat); Windows mono fallback fixed

Date: 2026-07-31 · Milestone: demo track · Author: claude-code (user: serif headings render "not clean, not continuous" on their Windows screen; showed eviden.com and asked for that style — "corporate")

1. **The classical serif pair is gone.** `@fontsource/cormorant-garamond` + `@fontsource/lora` are replaced by `@fontsource-variable/montserrat` (wght + italic axes) — the same face eviden.com uses (verified by fetching their CSS, not recalled). `--font-heading` and `--font-body` both point to `'Montserrat Variable', 'Segoe UI', Arial, sans-serif`; heading weight is 700. The offline rule is unchanged: fonts are still bundled locally, `check-console.sh`'s no-CDN and local-woff2 assertions still pass.
2. **Root cause of the original complaint was two-fold**: (a) Cormorant Garamond is a display serif whose hairline strokes drop out below ~24px on low-DPI Windows screens; (b) `--font-mono` was a Mac-only stack (`ui-monospace, 'SF Mono', Menlo`) that fell back to Courier New on Windows for every serial/SAN/validity line. The mono stack now includes `'Cascadia Mono', Consolas` before the generic fallback.
3. An intermediate step this session (Cormorant for large titles only, Lora elsewhere via a `--font-display` token) was built, verified, then superseded by the full sans switch in the same session; the extra token was removed rather than left dangling. The global heading `letter-spacing: -0.015em` (a serif-era tweak) went with it.
4. This deviates from the mockup's design language deliberately — the mockup remains the layout/structure reference, but its type palette is no longer the visual target.

Evidence: eviden.com stylesheet references `Montserrat-VariableFont_wght.woff2`; lint + 41/41 tests + production build green after the swap; dist media/ holds 10 Montserrat woff2 subsets and zero Lora/Cormorant files.

Consequences: token-only change surface (tokens.css, styles.css imports, two component overrides removed) — no template edits. Future font taste changes stay one-token edits. `package.json` dependency set changed accordingly.

---

## D-028 — demo track (user-directed): trust domain, realm, and PKI rebranded — "lab" removed from every viewer-visible surface

Date: 2026-07-31 · Milestone: demo track · Author: claude-code (user: "I dont like lab", chose ai-agent.id.eviden.internal; then "remove lab everywhere")

1. **Trust domain**: `spiffe://lab.internal` → `spiffe://ai-agent.id.eviden.internal` (user picked from candidates; hierarchy reads org → id platform → environment, workload specifics stay in the path). Swept across 51 tracked files: SPIRE confs, registration, Keycloak setup, EJBCA setup (name constraint now `uniformResourceIdentifier:ai-agent.id.eviden.internal`), MCP server + agent-client code/config, all check scripts, docs, diagrams, console. The MCP hostname/audience moved with it: `https://mcp.ai-agent.id.eviden.internal:8443`.
2. **Keycloak realm**: `lab` → `ai-agents` (issuer `http://keycloak:8080/realms/ai-agents`). Keycloak has no volume, so the realm rebuild is free on reset; alice's lastName Lab → Demo.
3. **PKI rebrand — cold rebuild required**: root is now `CN=Eviden Root CA,O=eviden` (EJBCA CA name EvidenRoot), intermediate `CN=SPIRE Intermediate CA,O=eviden`, SPIRE ca_subject org `eviden`. DN changes cannot be renewed in place, so the EJBCA volume is destroyed and the hierarchy re-created (`reset.sh --cold`); old contract files under infra/pki/ are deleted first (setup-ejbca.sh early-exits if they exist).
4. **MCP tool rename**: `lab_status` → `stack_status` (tool names are viewer-visible in the demo chat and tools/list; check-p1 updated).
5. **Deliberately kept**: Java packages `internal.lab.*`, compose project name `spiffe-mcp-lab`, docker network `lab` — never rendered in the UI; renaming the compose project would orphan all volumes. `docs/DECISIONS.md` history and `mockup/` are untouched; both captured demo-run.json files are NOT hand-edited — the capture is regenerated from the migrated stack (until then the console's fail-closed parser rejects the old capture by design, and its schema/validator now pin the new trust domain).
6. CLAUDE.md's trust-domain line updated as part of this decision (not silently).

Evidence: `git grep` residual sweeps clean (escape-tolerant pattern, exclusions as above); console lint + tests + build green post-sweep; shell syntax checks pass on all swept scripts.

Consequences: milestone/check scripts assert the new domain end-to-end. Migration runbook: delete infra/pki/*.pem → rebuild images → `demo/reset.sh --cold` (human runs; wipes SPIRE+EJBCA+ollama volumes, re-issues hierarchy, re-registers, rebuilds realm) → re-capture demo run → full check suite. The name-constraints milestone evidence (JDK rejection test) must be re-verified against the new constraint.

---

## D-029 — post-migration check corrections: m2 verified against a polluted bundle; m4 transport was stale since D-006

Date: 2026-08-01 · Milestone: demo track · Author: claude-code (found by running the FULL suite after the D-028 migration)

1. **check-m2 was validating the leaf directly against the trust bundle** and only passed because the old datastore's bundle still contained a legacy self-signed SPIRE CA anchor. The fresh post-migration bundle correctly holds ONLY the upstream root (Eviden Root CA), which exposed the bug. Fixed to proper X509-SVID chain validation: leaf verified with the SVID's delivered intermediates as untrusted links against the bundle anchor. Strictly stronger; no assertion removed.
2. **check-m4 still spoke plain HTTP** from before D-006 made the server mTLS-only (client-auth: need); Tomcat answers plain HTTP on a TLS port with 400, and check-m5 explicitly asserts the no-client-cert handshake is REFUSED — so m4 could not have passed since M5; it simply had not been re-run. Fixed by presenting the fetched agent-client SVID for every probe (curl --cert/--key, -k because the server cert is an SVID, not a localhost cert). The four OAuth assertions (401+resource_metadata, RFC 9728 metadata, wrong-aud rejection, right-aud control) are byte-for-byte the same.
3. Also fixed during the migration run: setup-ejbca.sh cleanup of key files copied into the container now runs as root (docker compose cp writes root-owned files; the ejbca user's rm failed and set -e killed the cold reset mid-hierarchy).

Evidence: full suite scoreboard in transcript (m2/m4 red pre-fix, green post-fix; failure outputs quoted); fresh bundle shown to contain exactly one anchor.

Consequences: milestone checks are now all runnable against the evolved stack, not just the milestone-era stack. p2/p25/p3/p6 additionally require a clean working copy of acceptance.sh, so they gate on the migration commit.

---

## D-030 — Two-hop delegation use case adopted (M12–M14); Keycloak exchange internals verified from source; suspected gap in the consent-toggle positive path

Date: 2026-08-03 · Milestone: planning (post-M11) · Author: claude-code

Decision:

1. **The employee-onboarding two-hop use case is adopted as `docs/USE-CASE-ONBOARDING.md`** (milestones M12 second hop / M13 delegation table / M14 acceptance). The draft arrived from a Claude chat with no access to this repo; it was rewritten against the stack as built: trust domain per D-028, existing `agent-client` as the assistant, new `agent-pki` (no LLM) and `cert-service` workloads, exchange mechanics per the source findings below. Its original "scope not inside the inbound token" rejection mechanism was **dropped as unimplementable** (finding 3) and replaced by the three-layer scope rule in the use-case doc.

2. **Keycloak 26.6.0 token-exchange internals, read from source** (files fetched at tag into `specs/keycloak/`, fetch-specs.sh extended):
   - **Client-policy hook exists on every exchange**: `TokenExchangeGrantType.process` fires `TokenExchangeRequestContext` through `session.clientPolicy()` before any provider runs (`TokenExchangeGrantType.java:83`). A custom client-policy executor is the sanctioned enforcement point for the M13 delegation table (actor→audience, scope caps, depth via the subject token's `act` chain) — no fork of the exchange provider.
   - **Chained exchange is handled natively**: when the subject token was itself produced by exchange, the provider copies `TOKEN_EXCHANGE_SUBJECT_CLIENT*` client-session notes forward and records the new subject client (`StandardTokenExchangeProvider.java:263-281`) — the session accumulates the delegation chain. Basis for nesting `act` in the mapper (primary mechanism: parse the `subject_token` form param during the exchange request; VERIFY items in the use-case doc).
   - **Scope narrowing is requester-side only**: `getRequestedScope` validates the `scope` param against the requester client's assigned scopes (`TokenManager.isValidScope(session, scope, client, null)`), `validateConsents` checks consent for the requester client, and **nothing in the standard path sets `restrictedScopes`** (context constructed without it in `TokenExchangeGrantType`; no setter call anywhere in the path; when null, `DefaultClientSessionContext.isAllowed` applies no restriction). **The subject token's scopes are never consulted.** "Permissions shrink along the chain" must be enforced by the M13 executor or it does not exist.
   - Confirmed from the same files (already known from D-008): requester must be in the subject token's `aud` (`validateAudience` → `forbiddenIfClientIsNotWithinTokenAudience`); the `audience` param resolves target clients and `checkRequestedAudiences` only verifies the requested audience is present in the generated token — it adds nothing.

3. **CONFIRMED LIVE — the one architectural rule is currently violated (CLAUDE.md §2: "effective permissions wider than `user scopes ∩ agent allowed scopes`" is forbidden).** Predicted from finding 2, then proven against the running stack (2026-08-03, post-migration --full reset). Three probes, alice via `test-caller`:

   | Probe | Subject token scope | `scope` param at exchange | Exchanged token scope |
   |---|---|---|---|
   | A | **with** `mcp:audit` (consented) | none (current code) | `mcp-audience profile email` — **`mcp:audit` LOST** |
   | B | **without** `mcp:audit` (not consented) | `mcp:audit` | `… mcp:audit` — **GAINED** |
   | C | with `mcp:audit` | `mcp:audit` | `… mcp:audit` |

   Probe A: the consent toggle's positive direction is dead — consenting changes nothing about what the agent can do, because the exchange sends no `scope`. Only the refusal was ever check-proven (check-p3), so this shipped unnoticed.

   Probe B is the security bug: the agent obtains a scope **the human never granted**, and it is not theoretical — presenting that token to the MCP server, `read_audit_log` returned **HTTP 200 with real audit entries**. The subject token's scopes are never consulted (finding 2), so the effective permission set is the *agent's* assigned scopes alone. The intersection in CLAUDE.md §2 is not enforced anywhere today.

   Not a Keycloak defect: `mcp:audit` is an optional scope legitimately assigned to agent-client, and agent-client has `consentRequired=false` (a service client), so `validateConsents` has nothing to check. The lab's model assumed an intersection the AS was never asked to compute.

   **Fix is item zero, before M12.** Two layers, both wanted: (i) agent-client requests `scope` explicitly at the exchange, derived from the subject token's own `scope` claim (fixes probe A, makes consent load-bearing); (ii) the M13 client-policy executor enforces requested ⊆ subject-token scopes for real (fixes probe B — a client-side fix alone is not enforcement, since the escalating request is exactly what a compromised agent would send). Until (ii) lands, item (i) plus removing `mcp:audit` from agent-client's optional scopes is the containment. The M14 acceptance gains a rejection for probe B, and check-p3 gains the missing positive-direction assertion.

Evidence: pinned sources in `specs/keycloak/` (file:line cites above); `agent-client/.../TokenRequest.java:53-64` (no scope param); `infra/keycloak/setup-spiffe-idp.sh:86-97` (mcp:audit optional on agent-client); check-p3.sh:35-59 (negative-only assertions); probe transcript this session, including the HTTP 200 audit-log read with alice unconsented.

Consequences: BUILD-PLAN gains M12–M14 when the human folds them in (BUILD-PLAN edit deliberately left to the human alongside the veto window on this adoption). Workstream B grows a second component class (client-policy executor), now load-bearing rather than a niceity — it is the only place the §2 intersection can actually be enforced. The EJBCA enrollment leg makes the human-led PKI path critical again at M12. The demo narrative must not claim scope intersection until the fix lands.

---

## D-031 — Item zero landed: the scope intersection is now enforced at the AS (fixes the D-030 finding-3 escalation)

Date: 2026-08-04 · Milestone: pre-M12 · Author: claude-code (user-directed: "okay build")

Proven by `scripts/check-scope-intersection.sh` (green) with `./infra/acceptance.sh` re-run **PASS**:

1. **New client-policy executor `exchange-scope-intersection`** (`keycloak-spiffe-spi/`, workstream B's second component). It refuses any token exchange whose requested `scope` is not already carried by the subject token. This is the only place the CLAUDE.md §2 intersection can be enforced: Keycloak validates a requested scope against the *requester client's* assigned scopes and consent, never against the subject token (D-030 finding 2). Registered via the client-policies SPI, which fires on every exchange (`TokenExchangeGrantType.java:83`).

2. **The executor parses an as-yet-unverified subject token, and that is sound here** — documented at the class, because it looks like a violation and is not. Policies run *before* `AuthenticationManager.verifyIdentityToken`; the same token string is verified moments later and a failure aborts the request. So a forged subject token cannot buy a wider scope, only a rejected request. A parse failure is a REFUSAL (no catch-and-permit).

3. **`conditions: []` means the policy matches NOTHING.** `DefaultClientPolicyManager.isSatisfied:88-91` returns false for an empty condition list, so the first registration enforced nothing while looking correct in the admin API — the check caught it. The `any-client` condition is now mandatory and commented as such in `setup-spiffe-idp.sh`.

4. **agent-client now requests the delegated scope explicitly**, derived from the subject token's own `scope` claim, which is what makes alice's consent load-bearing (before: consenting changed nothing, because no `scope` was sent). Asking is not authorization — the executor still bounds it.

5. **Scope naming convention, forced by a real failure**: only `ns:verb` scopes travel across an exchange. Acceptance failed with `Invalid scopes: agent-audience mcp-audience` — audience-carrier scopes belong to the *user's* client, not the agent's, and Keycloak refuses a scope the requester is not assigned. Bare scopes are client configuration (audience carriers, OIDC claim sets); `ns:verb` names delegated authority. This convention is now load-bearing for M12/M13, whose scopes are `onboard:initiate` and `issue:employee-cert`.

6. **Both directions are asserted**, deliberately: the check fails if consent does NOT reach the exchanged token, and fails if an unconsented scope DOES. The original bug shipped precisely because only the refusal was ever checked.

Evidence: check-scope-intersection.sh green (4 sections); acceptance.sh PASS post-change; Keycloak `KC-SERVICES0047` line confirming the executor factory loaded; source cites above from `specs/keycloak/`.

Consequences: the M13 delegation-table executor extends this class rather than introducing a second enforcement point. The demo narrative may now claim scope intersection truthfully. `check-p3`'s fixture still holds (alice's default token lacks `mcp:audit`), and its positive direction is now covered here.

---

## D-032 — M12 green: the second hop exists and is required; EJBCA issuance is real, authenticated RA over mTLS

Date: 2026-08-04 · Milestone: M12 · Author: claude-code (EJBCA setup script run agent-side with explicit human authorization this session)

Proven by `scripts/check-m12.sh` (**M12 PASS**), with `./infra/acceptance.sh` **PASS** and `scripts/check-scope-intersection.sh` **PASS** re-run after, untouched:

1. **The chain**: alice consents to `onboard:initiate` + `issue:employee-cert` → hop 1 gives agent-client a token with `scope=onboard:initiate` only (`act.sub`=agent-client) → agent-pki exchanges again and calls cert-service → a real certificate for `john-laptop` is issued by EJBCA (EvidenRoot) → cert-service logs `sub=alice` with the nested chain `agent-pki <- agent-client`. The assistant cannot reach cert-service directly (not allowlisted, wrong audience) and cannot obtain the issuing scope (DelegationTableExecutor: "'agent-client' may not carry issue:employee-cert") — neither agent can finish alone.

2. **`del_scope` is a CEILING, not a permission — and the check must read the claims accordingly.** The hop-1 token carries alice's full consented set in `del_scope` (so hop 2 can still request `issue:employee-cert` under the consent ceiling) while the exercisable `scope` claim stays attenuated. Resource servers enforce `scope` alone. check-m12's original no-issuing-power assertion grepped the whole payload and false-failed on the ceiling claim; it now extracts the `scope` claim. Rule for future checks: assert on the claim a verifier actually consumes.

3. **EJBCA 9.3.7's REST API authenticates every call** (probed, not recalled: plain 8080 → 302; 8443 without client cert → 403 "no client certificate or OAuth token received"). Design chosen: cert-service enrolls as a **registered RA** — end entity `ra-cert-service` on ManagementCA, P12 client keystore, role "Cert Service RA" with a minimal rule set modeled on the instance's own Public Access Role rules (read live, not recalled). No weakened EJBCA auth, no public-access shortcut. New human-run script `infra/pki/setup-employee-profile.sh` creates all of it plus the `employeeDevice` certificate/end-entity profiles (same generate-with-EJBCA's-own-classes technique as setup-ejbca.sh; there is still no CLI to create profiles). Contract files: `pki/ra/ra-cert-service.p12` + `pki/ra/ejbca-tls-ca.pem` (gitignored), mounted as a directory so the demo stack boots before the script has run — issuance fails loudly until then, never silently.

4. **The EJBCA management plane is a fourth, separate trust relationship.** cert-service's outbound client builds explicit `PKIX` key/trust managers over the RA keystore + ManagementCA anchor — deliberately NOT `getDefaultAlgorithm()`, which CertServiceApplication overrides to "Spiffe" for the workload mTLS plane. First attempt used the defaults and java-spiffe's trust manager rejected EJBCA's cert ("does not contain SPIFFE ID in the URI SAN") — exactly the three-trust-store discipline doing its job; the fix is scoping, not weakening.

5. **Two container warts found and fixed, both now guarded in the setup script**:
   - The 8443 TLS keystore is minted per container hostname; compose now pins `hostname: ejbca` so the SAN is `DNS:ejbca` (Java hostname verification would otherwise fail against a random container id). The script verifies the SAN before exporting trust.
   - Recreating the container raced init's `ca createtruststore` against the DB and left a 32-byte EMPTY `truststore.jks` — every TLS client cert then dies as a silent connection close with nothing in the application log. The script detects the empty store, rebuilds it in place with the password read from standalone.xml, and does a WildFly `:reload`.

6. **Restart ordering matters for MCP sessions**: restarting cert-service kills agent-pki's MCP session ("MCP session with server terminated"); agent-pki must restart after. Existing compose `depends_on` encodes this for cold starts; for manual restarts, restart both.

Evidence: check outputs in transcript; EJBCA audit log lines (CERTPROFILE_CREATION employeeDevice, RA_ADDENDENTITY/CERT_CREATION ra-cert-service, ROLE_ACCESS_RULE_CHANGE); curl/s_client probes for findings 3 and 5; cert-service FAILED stacks for finding 4.

Consequences: M12's exit is met — the console sentence can issue a real certificate once the M13/M14 surface is wired to the UI. check-m13 (delegation-table rejections: audience, scope, depth) remains to be written; the executor it will test is already live and produced this session's escalation refusal. A cold reset now requires `setup-employee-profile.sh` after `setup-ejbca.sh`; README quickstart row owed when M12–M14 land in BUILD-PLAN (human-gated edit).

---

## D-033 — M13 green: the table is law; the client-policy document made single-owner after a live loss

Date: 2026-08-04 · Milestone: M13 · Author: claude-code (user-directed continuation past the one-milestone default: "finish m13")

Proven by `scripts/check-m13.sh` (**M13 PASS**), with `check-m12.sh`, `check-scope-intersection.sh`, and `./infra/acceptance.sh` all re-run **PASS** after the changes below:

1. **The exit, asserted directly on the token**: a manually driven hop-2 exchange (agent-pki attested via the docker label selector, using the agent-client image's `svid` mode) yields `act = {sub: …/agent-pki, act: {sub: …/agent-client}}` with no deeper nesting, `sub` = alice, `aud` ∋ the cert-service resource URI, and scope attenuated to `issue:employee-cert` (hop-1's `onboard:initiate` gone). M12 proved the chain via cert-service's log; this proves the claim shape itself, parsed as JSON rather than grepped.

2. **All three off-table classes are refused by the TABLE, not by coincidence** — every refusal must carry the executor's "Delegation refused" prefix or the check fails, which distinguishes table enforcement from Keycloak's generic errors:
   - audience: agent-client requesting `audience=cert-service` → "may not delegate to cert-service";
   - scope, isolated from the intersection layer: agent-pki requesting `onboard:initiate` with the hop-1 token as subject — alice consented it and the subject's ceiling carries it, so the D-031 intersection executor alone would allow it; only the table row forbids it → "may not carry onboard:initiate";
   - depth, both actors: agent-pki re-exchanging the hop-2 token ("depth 3 exceeds the limit of 2") and agent-client re-exchanging the hop-1 token ("depth 2 exceeds the limit of 1"). Chains end.

3. **Live failure found mid-milestone: the client-policies document had two owners.** kcadm `update realms/<realm>/client-policies/{profiles,policies}` replaces the WHOLE document. setup-spiffe-idp.sh (D-031, intersection only) and setup-two-hop.sh (intersection + table) each carried their own variant, so whichever ran last silently deleted the other's executor. Observed for real: Keycloak was rebuilt mid-session (container recreated; volume-less by design, D-028) and re-provisioned by a path that does not know setup-two-hop — the task scopes vanished ("Invalid scopes") and the delegation table was gone while the admin API still looked healthy. Fix: the JSON now lives in `infra/keycloak/delegation-{profiles,policies}.json` and both scripts apply the identical files; either order converges. This is the D-011/D-016 lesson in a new costume: realm-level documents, like `grep -q` pipelines, punish scripts that look idempotent per-script but interfere across scripts.

4. **reset.sh now provisions the two-hop world**: `--soft`/`--full` run setup-two-hop.sh and bring up the `pki` profile alongside `demo` (EJBCA must run for the issuance leg; cert-service reads its RA credential lazily so ordering is forgiving); `--cold` chains `setup-employee-profile.sh --force` after setup-ejbca.sh — the script is human-gated, and --cold is itself human-run.

5. Script wart for the record: the shared `decode()` helper ends in a guarded printf whose false branch (`[ $pad -gt 0 ] && …`) exits nonzero when padding is zero — piping `decode` output directly under `set -o pipefail` fails the pipeline even when the consumer succeeds. Capture into a variable first. check-m13 hit it; check-m12 dodged it by accident (command substitution swallows the status).

Evidence: check outputs in transcript; the three refusal `error_description` strings above quoted from live responses; Keycloak container created-at timestamp vs. session timeline for finding 3.

Consequences: M14 (acceptance grows the six use-case rejections) is the remaining two-hop milestone; check-m13's sections 2–4 are its rejection material for the exchange layer, and check-m12's direct-call/escalation sections cover the resource layer. The delegation table's content now changes in exactly one file.

---

## D-034 — The console can tell the second hop; hop attribution is derived, not awaited

Date: 2026-08-04 · Milestone: demo track (post-M13) · Author: claude-code (user-directed: "build it")

Proven by `scripts/check-console.sh` (**CONSOLE PASS**, 56 tests, lint clean).

1. **The architecture diagram is extended, not replaced** (user-directed, after a from-scratch "delegation ladder" was built and rejected). `flow-diagram` keeps its edge/packet/label/node classes and its SMIL `animateMotion`, and gains `agent-pki`, `cert-service`, the hop-2 exchange arc, per-node **scope pills** (so the non-overlap is visible in the picture rather than asserted in prose), and node dimming for workloads a given run never touched. Existing edge ids (`p-exch`, `p-call`) were deliberately kept so the prior spec still asserts something true.

2. **The refused path is DRAWN, always.** `agent-client → cert-service` is a dashed `--verdict-deny` edge with an ✗, present from first paint and lit at the `refused` stage. Rationale, now an exit assertion: an edge nobody can see proves nothing to an audience — omission and refusal look identical on screen.

3. **Hop attribution is derived from the event sequence** (`core/hops.ts`), so the console did not have to wait on a server change. The invariant it rests on is real, not assumed: `TokenExchange.exchange` emits `svid` then `exchange`, in that order, exactly once per call (`agent-client/.../TokenExchange.java:45-56`). So **an `svid` opens a hop**. Single-hop runs stay entirely in hop 1; the two-hop stream splits 1/1/1/2/2/2. Derivation is a **fallback only** — `RawChainEvent.hop` is honored when present and wins outright, because the server is the authority on its own chain.

4. **The live trace is grouped by hop, replacing the flat five-chip rail.** A flat list can show that *more* happened; only the grouping shows that *somebody else* happened. Hop 2's group is indented and rule-marked — the nesting on screen mirrors the nesting in the `act` claim.

5. **`check-console.sh` gained section 6**: the second hop's workloads must reach the bundle, and `forbidden` must be drawn. Written before the implementation and watched fail (zero occurrences of `agent-pki`, `cert-service`, `forbidden` anywhere in `console/src`).

**Owed, and NOT done here — the chat cannot yet drive the two-hop flow.** `McpToolsConfig` builds a single `McpSyncClient` bound to `MCP_BASE_URL` (`agent-client/.../McpToolsConfig.java:29`), so the LLM cannot reach `onboard_employee` on agent-pki; only `check-m12.sh` can. Three things close it, and only the second is real work: (i) a second `McpSyncClient` for agent-pki handed to `SyncMcpToolCallbackProvider`; (ii) **`BearerHolder` becoming per-tool-target rather than per-message** — the two targets need different `aud`, so the exchange must move inside the tool-call boundary; (iii) `StepEvent` gaining a hop field, at which point item 3's derivation steps aside. Until (i)/(ii) land, the console renders two hops correctly but will only ever *receive* one.

Evidence: `scripts/check-console.sh` CONSOLE PASS; `console/src/app/core/hops.spec.ts` (7 cases incl. explicit-hop override and mid-flight stream); `flow-diagram.spec.ts` (refused path present-but-unlit, then lit); `live-chat.spec.ts` (two groups, second named `agent-pki`); `console-page.spec.ts` (diagram follows the chain to the issuance edge, and a single-hop run does not light it).

Consequences: console surfaces for the second hop no longer block on the backend. The demo narrative may show the delegation chain truthfully from a real stream the moment agent-pki's events are forwarded. Nothing in `agent-client/`, `keycloak-spiffe-spi/`, or `infra/` was touched — the seam is exactly the three items above.

---

## D-035 — The chatbox drives the two-hop use case; the per-target token turned out to be unnecessary

Date: 2026-08-04 · Milestone: demo track (post-M13) · Author: claude-code (user-directed: "we said we use chatbot to drive this use case")

Proven by `scripts/check-m12-chat.sh` (**M12-CHAT PASS**), with `infra/acceptance.sh` **PASS**, `check-m12.sh` **PASS** and `check-console.sh` **PASS** alongside.

Alice types one sentence into the console. The model picks `onboard_employee` itself, the assistant delegates to the PKI agent, and a real `john-laptop` certificate comes back with the nested chain — all visible as two hops in the live trace.

1. **D-034's "the real work is a per-tool-target bearer" was WRONG, and pleasantly so.** One exchanged token already addresses both targets: `pki-audience` and `mcp-audience` are both **default** client scopes on agent-client (`setup-two-hop.sh:101`), so a single hop-1 token carries both audiences. `BearerHolder` is unchanged. What genuinely differs per target is the *peer*, so each MCP client gets its own `SSLContext` accepting exactly one SPIFFE ID — a misrouted call then fails the handshake instead of arriving somewhere valid with a good token.

2. **The agent must ask for what it may carry, not for everything the human granted.** Since alice now consents to both task scopes at login, `DelegatedExchange.delegatedScope` forwarded `issue:employee-cert` too, and the AS refused exactly as designed: `Delegation refused: 'agent-client' may not carry issue:employee-cert`. The fix narrows the request to **her scopes ∩ ours** (`AGENT_DELEGATABLE_SCOPES`, default `onboard:initiate mcp:audit`). This is politeness, not enforcement — the delegation-table executor refuses an over-broad ask regardless, and that refusal is what the model rests on (D-031). The failure is worth keeping in mind: *widening consent broke the agent*, because the agent forwarded consent verbatim.

3. **The second hop is reported, never narrated.** agent-pki returns a `hop2` block (`actor`, `scope`, `tool`) describing the exchange it performed; agent-client relays those facts as a fresh svid/exchange/tool triple and emits **nothing** when the block is absent. agent-client cannot witness an exchange happening inside another workload, and a console that narrated one would be showing a plausible lie — the same rule as the fail-closed capture parser.

4. **The console needed zero changes.** D-034's derivation ("an `svid` opens a hop") does the work: two svid+exchange pairs arrive and the trace splits 1/1/1/2/2/2 with the diagram following to the issuance edge. The forward-compatible design paid off exactly as intended.

5. **Login now requests the two task scopes** so the consent screen offers them (`application-web.properties`). Without that the use case is unreachable from a browser: the agent could ask for `onboard:initiate` forever and the AS would refuse, because the human never granted it.

6. **The system prompt now forbids describing unperformed steps.** Before this change the model answered "Onboard John" with a fluent, invented procedure — create a SPIFFE identity for John, add him to the workload allowlist — which inverts the one architectural rule (§2: John is a human; SPIFFE is workload identity). It had only mcp-server's tools and no way to act, so it narrated. Reachable tools plus an explicit instruction replaced the hallucination with a real call.

Two warts for whoever writes the next check:
- The `hop2` JSON arrives with **escaped quotes** (`\"actor\":\"…\"`) — tool output is JSON travelling inside a JSON text content. The relay regex tolerates both forms rather than depending on how many layers the SDK peeled.
- **`MSYS2_ARG_CONV_EXCL='*'` breaks the scripted browser login** on Git Bash: the flow silently ends unauthenticated. Run browser-flow checks without it. A relative form action must also resolve against `keycloak:8080`, not `localhost:8080`, or the consent POST drops its session cookies.

Evidence: check-m12-chat.sh PASS (5 sections); the live stream showing `svid → exchange → tool(onboard_employee) → svid → exchange → tool(issue_employee_cert) → answer`; cert-service `ISSUED cn=john-laptop … chain=…/agent-pki <- …/agent-client`; acceptance/M12/console suites re-run green after the change.

Consequences: BUILD-PLAN M10's exit criterion #2 is now demonstrable through the console rather than only by script — the model can attempt the escalation and be refused in front of an audience. D-034's owed item is closed except for the optional `StepEvent` hop field, which is no longer needed: the relay produces the sequence the console already reads correctly.

---

## D-036 — The issued certificate is visible and downloadable; the private key still does not exist

Date: 2026-08-04 · Milestone: demo track (post-D-035) · Author: claude-code (user-directed: "download and view certificates with openssl style")

Proven by `check-m12-chat.sh` **PASS**, `check-console.sh` **PASS**, and `openssl x509` reading the downloaded file end to end.

1. **`EjbcaEnrollment.Issued` now carries the certificate PEM.** This reverses that record's explicit "never the PEM body" — deliberately, and recorded here rather than edited away silently. There was never a secret in a certificate: it is public by construction. The line it shared with "never the private key" still holds absolutely, and for a stronger reason than policy — cert-service generates the EC keypair for the CSR and **discards it at issuance**, so there is no key left to leak, expose, or accidentally serve.

2. **A p12 with the key was considered and rejected** (user asked). Not because a throwaway lab key is dangerous in itself, but because of where it would travel: cert-service → agent-pki → agent-client is the tool-result path that feeds an LLM. A private key crossing an AI agent's context is the exact thing this project argues against, and the first PKI-literate viewer would notice. Real PKI has the device generate its own key and the CA never see it; our shortcut is the only reason the question arises. If a usable p12 is ever wanted, it goes direct from cert-service with a per-issuance random passphrase — never a constant like `1234`, which makes the wrapper decorative.

3. **The certificate is taken OUT of what the model sees.** `IssuedCertHolder.captureFrom` stores it and hands the model a one-line placeholder. A kilobyte of base64 in a tool result is context the model pays for, may truncate, and may echo back mangled as if it were prose. The human asked for a certificate, not a description of one.

4. **`/api/issued` returns the same shape as `/api/svid`**, so the console renders it with the existing openssl `x509 -text` component rather than a second one. `/api/issued/download` serves it as `<cn>.pem` with a Content-Disposition filename.

5. **Two failures worth keeping**, both hit live:
   - **Escapes must be resolved before filtering.** The PEM arrives nested (cert-service's JSON inside agent-pki's JSON), so a line break is the two characters `\` and `n`. Stripping "everything not base64" first removes the backslash and leaves the `n` — which IS a base64 character — so the body corrupts silently and dies much later as `Input byte array has wrong 4-byte ending unit`. Regex over escaped text was the wrong tool; the fix unescapes explicitly, then re-derives the body from scratch and refuses to store anything that will not decode.
   - **Jackson is NOT on agent-client's classpath** despite `spring-boot-starter-web` (Boot 4 starter layout). The parser-based version failed to compile; the shipped version uses no new dependency.

6. **MCP sessions do not survive a peer restart.** Restarting cert-service left agent-pki holding a dead session, and the SDK re-initialised it on a background worker thread where the per-call bearer ThreadLocal is unset — surfacing as `cert-service call without an exchanged bearer (fail closed)`. The guard behaved correctly; the caching did not. Restarting the caller clears it. `mcpInitialized` being a one-shot boolean is the root cause and is now a known wart: **restart callers after restarting a callee**, or make initialisation recoverable.

7. **The SSE emitter ceiling moved 300s → 900s.** A tool-calling turn is at least two model round-trips and the demo default is a small local model on CPU (~5 tok/s); five minutes ran out mid-turn and the browser saw a dead stream with no explanation. The ceiling exists to bound a hang, not to race the model.

Evidence: `openssl x509 -in john-laptop.pem` printing subject `CN=john-laptop`, issuer `CN=Eviden Root CA`, serial and both dates; `/api/issued` → HTTP 200 with decoded claims and zero `PRIVATE KEY` occurrences; console test asserting the panel, the `openssl`-style child renderer, the download filename, and the absence of anything key-shaped.

Consequences: the demo now ends on an artifact a human can keep and verify, which is the payoff the two-hop chain existed to produce. The "no key" line is now a talking point rather than a gap — *the private key never left the device* is the correct PKI story, and the console says so on the panel.

---

## D-037 — Console design system v2 ("Plex"): the Classical/Montserrat system is replaced

Date: 2026-09-01 · Milestone: demo track (console) · Author: claude-code (user-directed: "cần một design system propre, không phải AI leak")

Proven by `check-console.sh` **PASS** after the swap (lint, tests, build, offline-render, hygiene all unchanged in meaning).

1. **The mockup-derived "Classical" token values are replaced wholesale** by the v2 system drafted and approved on the redesign canvas (artifact "Identity Console Redesign"). The user's verdict on the shipped page was that it read as generated filler: hero band, caps microlabels everywhere (0.14–0.22em tracking), orange as decoration, five type levels, everything boxed. v2: IBM Plex Sans/Mono, near-monochrome neutrals (#f5f6f8/#ffffff/#e4e7ec/#1a1d23), a 3-level type ramp (title 600 / 13–14px body / 11px mono for identifiers only), 4-base spacing, radii 6/10, hairline borders, no hero.

2. **What survives from Classical is its one good idea, tightened**: the colour language (human `#35618e`, workload `#1f7a70`, bridge `#c2551f`, verdict `#2e7d4f`/`#b3362a`) — same semantics, re-harmonised values. New discipline recorded as token comments: bridge orange appears ONLY on an RFC 8693 hop; red means denied (the play button is ink, the focus ring is ink, the login card's top border is ink — all three were orange).

3. **Dependency change (the rule that additions go through DECISIONS):** `@fontsource-variable/montserrat` is REMOVED; `@fontsource/ibm-plex-sans` + `@fontsource/ibm-plex-mono` are ADDED (static 400/500/600 + mono 400/500). Same offline mechanism as before — fonts ride the bundle, `check-console.sh`'s no-CDN/woff2 assertions unchanged.

4. **Semantic token names did not move** (`--surface-*`, `--id-*`, `--verdict-*`, `--log-*`); only primitive values, fonts, spacing, and radii did — so this was a token swap plus shell edits (app top bar and run-header became one light bar language; the dark band survives only where it means something: the log). CONVENTIONS-ANGULAR §Design system's description of "Classical" (serif headings, `#fbfaf9` paper, navy band) is superseded; the section is updated to point here rather than silently rewritten around the old palette. `mockup/identity-demo-console.html` stays as historical reference; it is no longer the visual starting point.

5. **Caps microlabels were normalised, not deleted**: tracking capped at 0.08em, and labels that name identifiers (step kind, token kicker) moved to mono — per the v2 rule that mono marks identifiers, never sentences.

Consequences: a theme change remains a token swap (proved by this one); the redesign canvas replaces the mockup as the visual source of truth for future console styling; the cockpit layout restructure (chat as persistent rail, swimlane sequence diagram, merged stepper) is drafted on the same canvas and remains open as a separate phase.

---

## D-038 — M15 consent-on-demand: authority is granted at the point of use, not at the front door

Date: 2026-09-01 · Milestone: demo track (M15, cross-workstream A+console) · Author: claude-code (user-directed: "delegation cần được bắt đầu khi bắt đầu chat; nếu cần thì trigger auth")

Proven by `check-m15-consent.sh` **PASS** (new exit check, written first and watched fail on the old flow), `check-m12-chat.sh` **PASS** (amended, below), `check-console.sh` **PASS**.

1. **Login now grants identity only** (`demo-web` registration scope → `openid,profile`). The task scopes moved to a new step-up registration **`keycloak-elevate`** (same public client, same PKCE) that the console triggers only when a task actually needs the authority. What alice ticks at step-up remains the ceiling for the whole chain (M12/D-032); only the MOMENT of consent moved. Rationale: the old flow demanded both task scopes before the user typed a word, disconnecting the authorization moment from the action it authorizes — the same disease D-035 recorded from the other side (widening consent at login broke the agent, because consent and task had no relationship).

2. **The gate sits at the tool, not at the door — and it is UX, not enforcement.** First cut gated every chat message in `ChatApiController` when `CHAIN_REQUIRED_SCOPES` were missing; `check-p25.sh` caught that as a regression within the hour: "who am I?" needs no task scope and must keep working on an identity-only session (an exchange with an EMPTY scope is legitimate — it yields a delegated token with no authority, which is the model working, not failing). The shipped gate lives in `AgentLoop`'s tool wrapper: only when the model actually picks the chain-opening tool (`CHAIN_TOOL`, default `onboard_employee`) with `CHAIN_REQUIRED_SCOPES` (default `onboard:initiate issue:employee-cert`) missing from the subject token does the wall fire — BEFORE the tool executes, so no half-done side effects. It emits the `consent` step for the console and returns an honest refusal string for the model to relay ("report the refusal honestly" was already the system prompt's law). Running the chain to let the AS refuse mid-way was rejected for the same side-effect reason. Enforcement is unmoved: the intersection executor (D-031) and the delegation table (D-033) refuse an unconsented exchange server-side regardless of any UI — `check-m15-consent.sh` §2 also proves no cert is issued from an unconsented session.

3. **The console renders the wall and walks through it.** A `consent` SSE event renders a card in the chat thread (missing scopes as chips + "Approve in Keycloak" → `/oauth2/authorization/keycloak-elevate`); the prompt that hit the wall is stashed in `sessionStorage` (`dc-pending-prompt` — prompt text, never anything credential-shaped) and re-sent automatically when the step-up lands back, so the human never retypes. Keycloak skips the login form (SSO) and shows only the consent screen for the newly requested scopes.

4. **`check-m12-chat.sh` amended** (the D-029 precedent: a check whose preconditions moved): its first step asserted the LOGIN consent screen offers `onboard:initiate` — under M15 that screen must NOT offer it, so the assertion moved to the step-up leg. Everything it asserts about the chain itself (two svid+exchange pairs, nested custody chain at cert-service, assistant still refused `issue:employee-cert`) is byte-for-byte unchanged. `check-p25.sh`/`check-p6.sh` needed no changes (they assert a consent screen appears and is accepted; identity-only login still shows one for a consent-required client).

5. **Known wart:** `/api/me` reports the scopes of the CURRENT registration's authorized client; after step-up that is `keycloak-elevate`. A later plain re-login through `keycloak` would show identity-only scopes again even while Keycloak still remembers alice's stored consent — harmless here (the preflight triggers a step-up that consents instantly), but it is the kind of asymmetry worth remembering when reading `/api/me` output.

Consequences: the demo's authorization moment now happens in front of the audience, attached to the sentence that needs it — refuse first, human approves, then the chain runs. The `mcp:audit` consent toggle (P3) is untouched (`keycloak-audit` registration remains). BUILD-PLAN gains M15 with `check-m15-consent.sh` as its exit criterion.

## D-039 — LLM provider is selected by environment: local Ollama stays the default, a hosted OpenAI-wire endpoint (Groq) is opt-in; P2's zero-credential criterion amended from words to values

Date: 2026-09-10 · Milestone: demo track (M10 provider abstraction, exercised) · Author: claude-code (user-directed: demo moves to another laptop; "ko muốn dùng con ollama nặng"; "tao tưởng có abstraction rồi; thích switch provider nào cũng dc qua env")

Proven by `scripts/check-llm-provider.sh` **PASS** (new static exit check, written first and watched fail; §4 hosted checks green with the human's key), host `mvn package` with both starters, image rebuild of `agent-web`/`agent-client`, and **`scripts/check-p2.sh` PASS on Groq** (`.env` selecting `openai`: natural language → `whoami` over SVID mTLS, mcp-server logged `sub=alice act.sub=spiffe://…/agent-client`, `acceptance.sh` byte-identical and green). **Not proven on this machine: the same gate with `LLM_PROVIDER=ollama`.** The run reached Ollama with the right provider and model (the ChatModel existed, the request went out), and Ollama answered `500 llama-server process has terminated: signal: killed` on every retry — the 4B model is OOM-killed with the full demo+pki stack resident under this laptop's 5.8 GiB Docker memory cap, which is a resource limit, not a regression of the switch (the local path was last green before the pki profile and the two-hop services existed). Re-run on a machine with ≥ 8 GiB for Docker, or with the pki profile down, before claiming the default path; until then the default configuration is asserted static-only (§1 of the check).

1. **The abstraction held, at the level it was built for; the missing half was the wire.** Zero provider types exist in Java (check-p2 §3, unchanged). But "provider" has two layers: the *selection* (Spring AI's `spring.ai.model.chat`) and the *wire protocol* (the starter on the classpath). Only the Ollama starter shipped, and Groq speaks the OpenAI wire (`/v1/chat/completions`), not Ollama's native `/api/chat` — so a second starter, `spring-ai-starter-model-openai`, joins the build. From here on the switch is purely environmental: `LLM_PROVIDER=ollama|openai`, `LLM_BASE_URL`, `LLM_MODEL`, `LLM_API_KEY`, single source `infra/llm-env.sh` (also read by compose from the gitignored `infra/.env`).

2. **Selector verified from the jars, not recalled** (D-010's property-key hazard): `OllamaChatAutoConfiguration` and `OpenAiChatAutoConfiguration` each carry `@ConditionalOnProperty(name="spring.ai.model.chat", havingValue=<name>, matchIfMissing=true)`; `SpringAIModelProperties.CHAT_MODEL = "spring.ai.model.chat"`, `SpringAIModels.OLLAMA/OPENAI = "ollama"/"openai"`. Exactly one `ChatModel` exists per value; with the default `ollama` the OpenAI autoconfiguration never instantiates, so a blank key is never even read.

3. **Base-URL form verified from the SDK.** Spring AI 2.0.0's `spring-ai-openai` no longer has its own `OpenAiApi`; it wraps the official `com.openai:openai-java-core` 4.39.1. `ClientOptions.PRODUCTION_URL = "https://api.openai.com/v1"` and `ChatCompletionServiceImpl` adds the path segments `chat`/`completions`; `OpenAiSetup.calculateBaseUrl` passes a configured URL through (it only strips a trailing `/`, and never appends `/v1`). Therefore `LLM_BASE_URL=https://api.groq.com/openai/v1`. A host `curl` to that `/models` returned 401 (auth), not 404 (path) — the endpoint exists. Property keys from `spring-ai-autoconfigure-model-openai-2.0.0.jar` metadata: `spring.ai.openai.base-url`, `.api-key`, `.chat.options.model`, `.chat.options.temperature`.

4. **The P2 exit criterion is amended, not weakened.** D-008 made "zero LLM credentials exist anywhere" a grep over the *words* `openai|api-key|GROQ|...`, which the second starter's artifactId would trip on. The criterion always meant *values*: `check-p2.sh` §2 now fails on a key-shaped literal (`gsk_…`, `sk-…`, or any key assignment whose value is not an env placeholder) and additionally asserts the default provider is the credential-free local one and that the hosted key binds to the environment with an EMPTY default. The claim "the default configuration holds zero credentials" is therefore still executable — and now also true of the repo on any provider, because a key can only ever live in `infra/.env` (gitignored) or the process environment. The argument from the demo narrative is unchanged and worth restating: the LLM key is a vendor credential outside the trust domain; the model picks *what* tool, SVID → exchange → mTLS decides *as whom*. "No client secret exists" was always about OAuth client authentication (D-007 §3).

5. **Ollama leaves the `demo` profile for its own `llm-local` profile, and `agent-web` drops `depends_on: ollama`.** Startup never contacts the model (`pull-model-strategy=never`), so the dependency was never load-bearing; keeping it would force the container to exist on a machine that will never use it. `infra/ollama/pull-model.sh` is the single place the profile is enabled: on the local provider it starts the container and pulls; on a hosted one it exits 0 without either. Every launcher already called it after `compose up`, so `reset.sh`, `check-p2/p25/p3/p6.sh`, `capture-run.sh` got the right shape without further edits; only `reset.sh`'s `down` gained the profile so a `--full` also stops ollama. `checklist.sh` and `up.sh` ask the same question either way — "is the pinned model reachable before the audience arrives" — against the volume locally, against `GET $LLM_BASE_URL/models` with the key when hosted. Ad-hoc `docker run` chats (`check-p2`, `check-p3`, `capture-run`) receive the four variables via `llm_docker_env`.

6. **Trust-store shape (ARCHITECTURE three-store table).** The hosted call is outbound TLS to `api.groq.com` by the OpenAI SDK's OkHttp client, which uses the JDK default — the *system* trust store of `eclipse-temurin:21-jre` — exactly as the table demands for non-SPIFFE peers. Nothing in `agent-client` sets a process-wide `SSLContext`; the java-spiffe context is bound only to the hand-built MCP client (D-007), so the two stores cannot leak into each other. The lab network is a plain bridge (no `internal: true`), so egress exists.

7. **Model pin: `openai/gpt-oss-120b`, from the catalog, not from recall.** The first default written here was `llama-3.3-70b-versatile` from memory, marked `# VERIFY`; the real key's `GET /openai/v1/models` (2026-09-10) does not list it at all — Groq's docs page now shows the Llama 3.x rows as Enterprise/Contact Sales. The catalog's tools-capable production model is `openai/gpt-oss-120b` (131K context, developer-plan limits 250K TPM / 1K RPM per the docs table). Exactly the failure mode D-010 warned about, caught by the marker and by `check-llm-provider.sh` §4 / the `up.sh` preflight, which refuse to start if the configured model is absent from the endpoint's catalog — a stale pin fails loudly before the demo, never during it. Proposed `docs/VERSIONS.md` row (human-gated): `| Hosted demo model (opt-in) | Groq \`openai/gpt-oss-120b\` via \`https://api.groq.com/openai/v1\` | console.groq.com/docs/models; /models catalog with a real key. Demo track only. | Pinned 2026-09-10 |`.

8. **The exit check must not grep the gitignored `.env`.** Its first version walked the working tree and, on finding the human's key in `infra/.env`, printed the offending line — i.e. the check itself echoed a credential into a terminal log. Fixed the same hour: the credential grep runs over `git ls-files --cached --others --exclude-standard` (tracked or stageable files only, the thing "in the repo" actually means), asserts `infra/.env` is gitignored, and reports file:line without the matched text. The echoed key should be rotated at console.groq.com (a terminal log is not the repo, but it is not nothing).

9. **A Windows-edited `.env` carries CRLF, and one carriage return is enough to select no provider at all.** The first hosted run of `check-p2.sh` failed with `No qualifying bean of type ChatModel`, reproducibly under the scripts and never under a manual `docker compose up`. Cause: `infra/.env` was written by an editor on Windows (CRLF); `llm-env.sh` read `LLM_PROVIDER` as `openai` plus a carriage return, exported it, and compose interpolation carried it into the container — `spring.ai.model.chat=openai<CR>` matches neither `openai` nor `ollama`, so no chat autoconfiguration fires. Compose's own `.env` parser strips the CR, which is why the manual path worked. Fix: the parser strips a trailing CR, surrounding whitespace and matching quotes. Recorded because the demo laptop is exactly a Windows machine with a hand-written `.env`; the symptom ("no ChatModel") points nowhere near the cause.

10. **Reasoning models need one extra request field on the OpenAI wire.** With the environment fixed, the hosted chat failed at the second turn of the tool loop: Groq `400 — 'messages.2' role:assistant: property 'reasoning_content' is unsupported`. `openai/gpt-oss-120b` returns a `reasoning` field on the assistant message; Spring AI 2.0.0 carries it into the conversation history and re-sends it as `reasoning_content`, which Groq does not accept as input. Probed against the live endpoint with the tool-call request: the default reply carries `reasoning`; `reasoning_format: "hidden"` and `include_reasoning: false` are both accepted and both remove it. Shipped as `spring.ai.openai.chat.extra-body.reasoning_format=${LLM_REASONING_FORMAT:hidden}` (the `extra-body` key exists in the 2.0.0 autoconfigure metadata) — properties only, no code, Groq-shaped default consistent with the base-url default. Verified end to end before the properties change by injecting the same value through `SPRING_APPLICATION_JSON`: the chat called `whoami` and mcp-server logged `sub=alice act={sub=spiffe://…/agent-client}` — the M10 exit assertion, on a hosted model, in seconds rather than the minute CPU inference took.

Consequences: a demo laptop needs Docker plus a two-line `infra/.env`; no GPU, no 2-3 GB pull, no ollama container. The hosted path adds a wifi dependency and a free-tier rate limit (Groq: ~30 RPM) — acceptable for one presenter, and the local profile remains one env change away as the fallback if the model is pre-pulled. README fresh-machine guide gained step 3 "Choose the LLM". D-008's consequence 3 ("hosted OpenAI-compatible endpoint as the fallback path, key in env only") is now built rather than described.

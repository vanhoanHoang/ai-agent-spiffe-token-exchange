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

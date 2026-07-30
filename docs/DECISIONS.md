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

Decision: **PARTIALLY RESOLVED (2026-07-31) — per-verifier results:**

| Verifier | Result | Evidence |
|---|---|---|
| OpenSSL CLI 1.1.1s (Git-for-Windows host build) | **ENFORCES** | `scripts/check-m3.sh` negative test: leaf with URI SAN `spiffe://evil.example/impostor` signed by the constrained intermediate → `openssl verify` FAILS; in-domain control `spiffe://lab.internal/neg-test-control`, same signer and extensions → verifies OK. So the rejection is the constraint, not setup noise. |
| JDK PKIX (java-spiffe path) | pending — record at M5 when Java enters the stack | — |
| Go (SPIRE internal) | n/a as verifier of issued leaves in our flows | — |

Constraint form actually issued (EJBCA `nameConstraintsPermitted = uniformResourceIdentifier:lab.internal`): `X509v3 Name Constraints: critical / Permitted: URI:lab.internal`. Per RFC 5280 §4.2.1.10 URI constraints match the **host** of the URI, so this permits `spiffe://lab.internal/*` only — the pki README's shorthand "URI:spiffe://lab.internal/" denotes exactly this.

Consequences: for the openssl path the EJBCA chain is a real technical control. If the JDK result at M5 differs, ARCHITECTURE.md must be updated per this entry's rule.

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

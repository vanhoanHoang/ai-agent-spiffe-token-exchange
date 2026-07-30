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

RFC 8693: `subject_token` = user token, `actor_token` = JWT-SVID, `resource` = MCP server URI.

**Exit:** decoded access token shows `sub` = human, `act.sub` = `spiffe://lab.internal/...`, `aud` = MCP server. The MCP server logs both on every call.

*Expect a custom protocol mapper to get `act` populated correctly. Budget half a day.*

---

## M8 — Stretch: certificate-bound tokens

RFC 8705 `cnf.x5t#S256`. Binds the access token to the workload's SVID, closing the stolen-bearer-token hole in the plain MCP model.

**Exit:** replaying a captured token from a different client certificate is rejected.

---

## M9 — Terminal acceptance

The goal, as one script: `infra/acceptance.sh`. Happy path (login → jwt-spiffe exchange → mTLS MCP call with correct `sub`/`act`/`aud`) **plus all four rejections**: no client cert; wrong-audience token; JWT-SVID presented as bearer; unlisted SPIFFE ID. Plus chain-of-custody: SVID chains to the EJBCA root with the name constraint enforced, and `act.sub` appears in the MCP server log.

**Exit:** `./infra/acceptance.sh` exits 0.

M8 green without M9 green means the pieces work and the system doesn't. The project is done at M9, not M8.

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

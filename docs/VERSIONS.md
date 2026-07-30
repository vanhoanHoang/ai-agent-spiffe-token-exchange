# Version Matrix — single source of truth for all pins

Rule: nothing in this repo references an image, dependency, or spec revision not listed here. Changing a row = a DECISIONS.md entry. Claude Code never changes this file autonomously.

| Component | Pinned | Evidence | Status |
|---|---|---|---|
| Keycloak | `26.6.0` | SPIFFE client auth landed as part of Federated Client Authentication in 26.4 (preview); in 26.6 federated client auth for OIDC/K8s is promoted to supported while SPIFFE **remains preview** because the draft isn't final. | Verified via release notes 2026-07-30 |
| SPIRE server/agent | `1.15.2` | Current release; images `ghcr.io/spiffe/spire-server:1.15.2`, `ghcr.io/spiffe/spire-agent:1.15.2`. | Verified via spiffe.io downloads 2026-07-30 |
| EJBCA CE | `9.3.7` | Newest CE tag on hub.docker.com/r/keyfactor/ejbca-ce (pushed 2025-12-17; next-older 9.1.1). Pinned by claude-code under explicit user delegation for M3 — see D-004. | Pinned 2026-07-31 |
| java-spiffe | `x.y.z` | — | **VERIFY: pin from github.com/spiffe/java-spiffe releases before M5** |
| Java / Spring Boot | 21 / 3.x | — | **VERIFY: pin exact Boot version before M4** |
| spiffe-client-auth draft | `-02` | June 2026 revision | Pinned; watch datatracker for -03 |
| MCP spec | `2025-11-25` + July 2026 update | — | **VERIFY: confirm which revision your target client speaks** |

## Keycloak SPIFFE feature — what M0 must still confirm

Known from release notes: the capability exists as **preview** in 26.6.0 under Federated Client Authentication, configured as a realm-level identity provider carrying the trust domain and a JWKS/bundle URL. Reference material: the two community implementations (CarrettiPro/keycloak-spiffe, christian-posta/spiffe-svid-client-authenticator) predate the built-in feature — do not copy from them without checking against 26.6 source.

M0 still owes DECISIONS.md D-001:
1. The exact feature flag string to pass (`--features=...`) in 26.6.0
2. The exact admin/config path for the SPIFFE identity provider type
3. Whether the preview validates `aud` per rfc7523bis (issuer identifier) or the draft's stale example (token endpoint) — **this decides our client's aud value and is worth reporting upstream either way**

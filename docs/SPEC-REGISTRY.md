# Spec Registry

Every normative document this lab depends on, its tier, and where the pinned copy lives. If a fact is not in `specs/`, `docs/`, or CLAUDE.md's pinned table, it is not known — fetch it or ask.

**Tiers**

- **Tier 1** — published RFC or stable standard. Safe to build on; cite section numbers.
- **Tier 2** — mature WG draft near last call. *(None load-bearing in this lab.)*
- **Tier 3** — early/volatile draft. At most **one** may be load-bearing, and it must be isolated per `ARCHITECTURE.md`.

`specs/` is populated by `specs/fetch-specs.sh` (human runs it if the sandbox can't reach ietf.org). `specs/` contents are read-only — never modify them.

## Tier 1

| Spec | Role here | Pinned copy |
|---|---|---|
| RFC 7521 | Assertion framework for client auth | `specs/rfc7521.txt` |
| RFC 7523 | JWT profile for client auth (base the draft profiles) | `specs/rfc7523.txt` |
| RFC 8414 | AS metadata (issuer identifier discovery) | `specs/rfc8414.txt` |
| RFC 8693 | **Token exchange — the only SPIFFE↔OIDC bridge** (`act` claim) | `specs/rfc8693.txt` |
| RFC 8705 | mTLS client auth + certificate-bound tokens (M8) | `specs/rfc8705.txt` |
| RFC 8707 | Resource indicators (`resource` parameter) | `specs/rfc8707.txt` |
| RFC 8725 | JWT BCP (validation discipline) | `specs/rfc8725.txt` |
| RFC 9728 | Protected resource metadata (M4 endpoint) | `specs/rfc9728.txt` |
| SPIFFE ID / X509-SVID / JWT-SVID / Trust Domain & Bundle / Federation | Workload identity model | `specs/spiffe/*.md` |
| SPIRE 1.15.2 plugin/config docs | The only source for plugin config keys | `specs/spire/*.md` (pinned tag v1.15.2) |
| MCP spec `2025-11-25` (+ July 2026 update) | The protected resource's protocol | fetch manually — VERIFY revision against target client (`docs/VERSIONS.md`) |

## Tier 3 — the one deliberate bet

| Spec | Pinned | Role | Containment |
|---|---|---|---|
| `draft-ietf-oauth-spiffe-client-auth` | `-02` (June 2026) | SPIFFE SVIDs as OAuth client credentials — the substance of M6 | One URN constant, one validation interface, a rev bump touches exactly two files. Watch datatracker for `-03`. |

Ground truth extracted from `-02` (the recall-hazard facts) lives in CLAUDE.md §3 — never write those from memory. Known wart: the draft's *example* shows the token endpoint as JWT-SVID `aud`; the *normative text* says AS issuer identifier. Normative text wins.

## Explicitly out of scope

- **WIMSE** drafts — this lab is not a WIMSE implementation.
- **SPIRE OIDC Discovery Provider** docs — that component is unused here.
- Community Keycloak SPIFFE repos (CarrettiPro, christian-posta) — predate the built-in feature; background reading only, never a source of config keys.

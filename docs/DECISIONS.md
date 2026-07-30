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

Decision: **PARTIALLY RESOLVED (2026-07-30, from release notes — not yet from source).**
Keycloak pinned at 26.6.0. SPIFFE client auth exists as **preview** under Federated Client Authentication (landed 26.4; OIDC/K8s variants promoted to supported in 26.6, SPIFFE stays preview while the draft is unfinalised). Workstream B is therefore configuration-first; the custom SPI is fallback only if the preview proves broken.

Still owed, from the 26.6.0 **source** (strategy in BUILD-PLAN M0):
- exact feature flag string (replace blanket `--features=preview` in compose)
- admin config path for the SPIFFE identity provider (trust domain + bundle URL)
- whether its `aud` check expects issuer identifier (rfc7523bis) or token endpoint (draft's stale example)

Evidence: must cite the source tree of the exact version, not release notes or recall.

Consequences: determines whether M6 is configuration or implementation.

---

## D-002 — URI name-constraint enforcement in our verifiers

Date: _pending_ · Milestone: M3 · Author: _pending_

Decision: **UNRESOLVED.** M3's negative test determines whether each verifier in the stack (JDK, OpenSSL CLI, Go if used) actually rejects issuance outside `spiffe://lab.internal/`. Record per-verifier results here.

Consequences: if a verifier does not enforce URI constraints, the EJBCA chain is governance value only for that path, not a technical control — architecture doc must say so.

# Diagrams — end-to-end system

Rendered views of what this lab builds. Source of truth stays in [ARCHITECTURE.md](../ARCHITECTURE.md), [BUILD-PLAN.md](../BUILD-PLAN.md), and [DECISIONS.md](../DECISIONS.md) — if a diagram and a doc disagree, the doc wins and the diagram gets fixed.

An editable canvas version lives in [architecture.excalidraw](architecture.excalidraw).

**Status legend** (as of branch `m3-ejbca`): green/solid = built · gray/dashed = planned.

| Milestone | Status |
|---|---|
| M0 Keycloak SPIFFE support spike | ✅ done — D-001: supported in 26.6.0 via `--features=spiffe` |
| M1 Skeleton up | ✅ done |
| M2 SPIRE issues SVIDs (docker label selectors) | ✅ done |
| M3 EJBCA upstream CA (`disk` UpstreamAuthority) | 🔄 in progress on this branch — exit check: `scripts/check-m3.sh` |
| M4 MCP resource server · M5 SVID mTLS · M6 jwt-spiffe client auth · M7 token exchange w/ `act` · M8 cert-bound tokens · M9 acceptance | ⏳ planned |

---

## 1. Component topology

> The one rule: SPIFFE answers **which workload**, OIDC answers **on behalf of which human**. The only bridge is RFC 8693 token exchange. SPIRE's OIDC Discovery Provider is **not** used — the only OIDC here is Keycloak.

```mermaid
flowchart TB
    HUMAN(["Human"])

    subgraph LAB["docker compose · network 'lab' · trust domain spiffe://ai-agent.id.eviden.internal"]
        direction TB
        subgraph CORE["default profile — built (M1–M3)"]
            KC["Keycloak 26.6.0 — the only OIDC / AS<br/>start-dev --features=spiffe (D-001)<br/>SPIFFE identity provider: trustDomain + bundleEndpoint<br/>client auth: federated-jwt (jwt.credential.sub = SPIFFE ID)"]
            SS["SPIRE server 1.15.2<br/>trust_domain = ai-agent.id.eviden.internal<br/>UpstreamAuthority 'disk' (M3):<br/>EJBCA intermediate + ejbca-root bundle"]
            SA["SPIRE agent 1.15.2<br/>Workload API on unix socket<br/>workload attestor: docker labels (M2)<br/>node attestor: x509pop (bootstrap CA, D-003)"]
        end
        subgraph PKI["profile 'pki' — built (M3)"]
            EJBCA["EJBCA CE 9.3.7 (D-004)<br/>offline issuance: infra/pki/setup-ejbca.sh"]
        end
        subgraph APP["profile 'app' — planned (M4+)"]
            MCP["mcp-server · Spring Boot resource server<br/>mcp.ai-agent.id.eviden.internal:8443<br/>enforces: ① peer SPIFFE ID allowlisted<br/>② sig via Keycloak JWKS ③ aud == this server<br/>④ scopes = user ∩ agent · logs sub + act.sub"]
        end
        AC["agent-client — planned (M6–M7)<br/>SVID → token exchange → MCP call<br/>assertion-type URN = exactly ONE constant"]
    end

    HUMAN -- "(1) OIDC login → user token (sub = human)" --> KC
    SA -- "(2) X509-SVID + JWT-SVID<br/>via Workload API" --> AC
    AC -. "(3) RFC 8693 token exchange —<br/>client auth = JWT-SVID, type …:jwt-spiffe<br/>aud = AS issuer identifier, sole value" .-> KC
    AC -. "(4) mTLS with X509-SVIDs +<br/>exchanged access token" .-> MCP
    MCP -. "(5) fetch JWKS (realm keys)" .-> KC
    EJBCA -- "name-constrained intermediate, issued offline (M3)<br/>permittedSubtrees: URI spiffe://ai-agent.id.eviden.internal/" --> SS
    SS -- "node attestation (x509pop) · SVID minting" --> SA
    SA -. "mcp-server's own SVID (M5)" .-> MCP
    SS -. "SPIFFE bundle endpoint (https_web, M6)<br/>URL configured OUT OF BAND — not derivable from any SVID" .-> KC

    classDef built fill:#ebfbee,stroke:#2f9e44,color:#1e1e1e;
    classDef planned fill:#f8f9fa,stroke:#868e96,stroke-dasharray:5 5,color:#495057;
    classDef human fill:#e7f5ff,stroke:#1971c2,color:#1e1e1e;
    class KC,SS,SA,EJBCA built;
    class MCP,AC planned;
    class HUMAN human;
```

## 2. End-to-end token flow (the happy path M9 asserts)

```mermaid
sequenceDiagram
    autonumber
    actor H as Human
    participant KC as Keycloak (AS)<br/>realm issuer = base URL + /realms/name
    participant AC as agent-client
    participant SA as SPIRE agent<br/>(Workload API)
    participant MCP as mcp-server<br/>(Spring Boot RS)

    H->>KC: OIDC login (Authorization Code)
    KC-->>H: user token — sub = human

    AC->>SA: fetch over unix socket
    SA-->>AC: X509-SVID + JWT-SVID<br/>JWT-SVID aud = AS issuer identifier, SOLE value<br/>(normative text — token-endpoint-as-aud is a bug)

    AC->>KC: POST /token — RFC 8693 token exchange<br/>subject_token = user token<br/>client_assertion_type = urn:ietf:params:oauth:client-assertion-type:jwt-spiffe<br/>client_assertion = JWT-SVID · resource = MCP URI
    Note over KC: validates JWT-SVID against trust-domain keys<br/>from the SPIFFE bundle endpoint (https_web),<br/>configured out of band — NOT the system store.<br/>sub prefix-matched to trustDomain, mapped to the<br/>registered client via jwt.credential.sub (federated-jwt)
    KC-->>AC: access token — sub = human,<br/>act.sub = spiffe://ai-agent.id.eviden.internal/agent-client,<br/>aud = mcp-server

    AC->>MCP: MCP call over mTLS (X509-SVIDs both sides)<br/>Authorization: Bearer exchanged token
    Note over MCP: enforces, in order:<br/>1. peer SPIFFE ID allowlisted<br/>2. token signature via Keycloak realm JWKS<br/>3. aud == this server (anti-passthrough)<br/>4. effective scopes = user ∩ agent-allowed
    MCP-->>AC: response · logs sub + act.sub

    Note over H,MCP: M9 also asserts four rejections: no client cert · wrong-audience token ·<br/>JWT-SVID presented as bearer · unlisted SPIFFE ID
```

## 3. PKI chain of custody (M3)

```mermaid
flowchart TB
    subgraph EJBCACHAIN["EJBCA hierarchy — infra/pki file contract, issued offline by setup-ejbca.sh"]
        ROOT["EJBCA Root CA<br/>ejbca-root.pem"]
        INT["Name-constrained intermediate<br/>spire-intermediate.pem (+ key, never committed)<br/>permittedSubtrees: URI spiffe://ai-agent.id.eviden.internal/"]
    end
    subgraph SPIRE["SPIRE server"]
        SCA["SPIRE server CA<br/>UpstreamAuthority 'disk':<br/>cert = intermediate · bundle = ejbca-root"]
        X509["X509-SVIDs (TTL 1h)<br/>spiffe://ai-agent.id.eviden.internal/agent-client<br/>spiffe://ai-agent.id.eviden.internal/mcp-server"]
        JWTK["JWT-SVID signing keys (TTL 5m)<br/>NOT part of the X.509 chain —<br/>published via bundle endpoint JWKS,<br/>use: jwt-svid (M6)"]
    end
    subgraph BOOT["separate, deliberately outside the EJBCA contract (D-003)"]
        BCA["bootstrap CA (gen-bootstrap.sh)"]
        AGC["agent cert → x509pop node attestation<br/>agent ID spiffe://ai-agent.id.eviden.internal/spire/agent/x509pop/…"]
    end

    ROOT --> INT --> SCA --> X509
    SCA -.-> JWTK
    BCA --> AGC

    classDef built fill:#ebfbee,stroke:#2f9e44,color:#1e1e1e;
    class ROOT,INT,SCA,X509,BCA,AGC built;
    classDef planned fill:#f8f9fa,stroke:#868e96,stroke-dasharray:5 5,color:#495057;
    class JWTK planned;
```

M3's exit check (`scripts/check-m3.sh`) verifies a fresh SVID chains to `ejbca-root.pem` **and** runs the negative test: a leaf with URI SAN outside `spiffe://ai-agent.id.eviden.internal/` must be rejected. Whether *each* verifier in the stack (openssl, JDK, …) enforces the URI name constraint is tracked in D-002 — until proven per verifier, the constraint is governance value, not a technical control.

## 4. The three trust stores

Three unrelated validation roots coexist; every TLS/JWT bug in this lab starts with confusing two of them (full table in [ARCHITECTURE.md](../ARCHITECTURE.md)).

```mermaid
flowchart LR
    subgraph V["Verifier — what it checks"]
        MCP1["mcp-server"]
        AC1["agent-client"]
        KC1["Keycloak"]
    end
    subgraph S["Trust root"]
        BUNDLE["SPIFFE trust bundle (ai-agent.id.eviden.internal)<br/>SPIRE-distributed, EJBCA-chained<br/>MUST NOT be the system store (draft §5.2.3)"]
        SYS["System / Web PKI store<br/>never validates any SVID"]
        JWKS["Keycloak realm keys (JWKS)<br/>not the SPIFFE bundle; not SPIRE's<br/>OIDC Discovery Provider (unused)"]
    end

    MCP1 -- "client X509-SVIDs in mTLS" --> BUNDLE
    AC1 -- "mcp-server's X509-SVID" --> BUNDLE
    KC1 -- "JWT-SVID client assertions<br/>(keys from bundle endpoint, https_web)" --> BUNDLE
    AC1 -- "Keycloak's HTTPS server cert" --> SYS
    KC1 -- "bundle endpoint's HTTPS server cert" --> SYS
    MCP1 -- "user / exchanged access tokens" --> JWKS

    classDef store fill:#fff9db,stroke:#f08c00,color:#1e1e1e;
    class BUNDLE,SYS,JWKS store;
```

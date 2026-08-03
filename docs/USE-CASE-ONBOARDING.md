# Use case — employee onboarding (two-hop delegation)

This is the concrete task the two-hop build implements (milestones M12–M14, after the
M10/M11 demo track). It exists so the second hop has a real reason to exist. Do not
simplify it away.

Adapted from a draft written without access to this repo. Everything below is aligned
with the stack as built (D-001..D-029) and with the Keycloak 26.6.0 source pinned in
`specs/keycloak/` — the exchange mechanics here are what that code does, not what
RFC 8693 sketches.

## The one rule that must not be broken

**The two agents have non-overlapping scopes, and no single scope can complete the
whole task.**

If a change would let one agent finish the task alone with a wider token, that change
is wrong — even if every test stays green. The hop is the specification, not an
implementation detail.

## The story

Alice works in HR. She types one sentence into the console chat:

> "Onboard John. He starts Monday."

Completing this needs two powers that must not live in the same place:

1. Understanding the request and driving the process (planning, delegation).
2. Issuing a certificate for John's laptop by calling the certificate service.

## The two agents

**The assistant — the existing `agent-client`.** The entry point; the console talks to it.
- SPIFFE ID: `spiffe://ai-agent.id.eviden.internal/agent-client`
- Scope it may hold: `onboard:initiate`
- May: understand Alice's request, delegate to the PKI agent.
- May NOT: call the certificate service, hold `issue:employee-cert`.
- This is the weakest agent on purpose. It holds the LLM, so it sits closest to prompt
  injection. It keeps almost no power.

**The PKI agent — new workload `agent-pki`.** Does the privileged step.
- SPIFFE ID: `spiffe://ai-agent.id.eviden.internal/agent-pki`
- Scope it may hold: `issue:employee-cert`
- May: call the certificate service to issue one employee certificate.
- May NOT: initiate onboarding, act without an inbound delegated request, hold
  `onboard:initiate`.
- **Holds no LLM.** It is deterministic code: validate inbound, exchange, one outbound
  call. If a refactor ever puts a model inside agent-pki, the injection story ("the
  model-adjacent agent is powerless") is broken — stop and flag it.

Neither agent can finish the task alone. That is what forces two hops instead of one
hop with a bigger token.

## The protected service

A **new** `cert-service` workload (SPIFFE ID
`spiffe://ai-agent.id.eviden.internal/cert-service`), *not* a tool on the existing
mcp-server — deliberately: rejection 1 below requires that agent-client is **not on the
service's allow-list**, and mcp-server already allowlists agent-client. Same
enforcement stack as mcp-server (SVID mTLS, audience, allow-list, act↔peer binding),
its own canonical resource identifier (`https://cert.ai-agent.id.eviden.internal:8444`).

One tool: `issue_employee_cert(subject)`. Real output: an actual certificate for
`john-laptop`, issued by EJBCA and chaining to the Eviden root.

Honest scoping: today EJBCA is SPIRE's **upstream CA only** — nothing in the stack
calls an EJBCA issuance API. This leg is new work: an employee end-entity/certificate
profile (prepare scripts, the human runs them — CLAUDE.md §7) and an enrollment call
from cert-service to EJBCA.

## The flow — as Keycloak 26.6.0 actually implements it

The current single-hop flow extended by exactly one hop. The console stays the entry
point. Reminders from D-007/D-008, all confirmed in the pinned source: there is **no
`actor_token` parameter** — the actor is the *authenticated client*, stamped into
`act` by workstream B's mapper; the `audience` request parameter only **filters**
audiences — `aud` values come from audience client scopes; the exchange natively
**rejects a requester not present in the subject token's `aud`**
(`StandardTokenExchangeProvider.validateAudience`) — that rule is what makes each hop
unforgeable, and we get it for free.

1. Alice signs in (authorization code + PKCE) and **consents** — the consent screen
   lists `onboard:initiate` and `issue:employee-cert`. Consent is the delegation
   moment (D-014): what Alice grants here bounds the whole chain. Her token:
   `aud=agent-client` (existing `agent-audience` scope pattern), scope carries both
   task scopes.
2. agent-client interprets the request and fetches its JWT-SVID from SPIRE.
3. **Hop 1 exchange** — subject = Alice's token, client auth = `jwt-spiffe`
   (agent-client), `scope=onboard:initiate`, exchanged `aud=agent-pki` via an audience
   client scope on agent-client's client. The delegation-policy executor (below)
   checks the table. The mapper stamps `act={sub: spiffe://…/agent-client}`.
   Result: `sub=alice`, `act.sub=agent-client`, `aud=agent-pki`,
   `scope=onboard:initiate`.
4. agent-client calls agent-pki over mTLS with its X.509-SVID and that token. **It
   does not call the certificate service. It cannot:** its token's audience is
   agent-pki, its client is not assigned `issue:employee-cert`, and cert-service does
   not allowlist it.
5. agent-pki validates the inbound call exactly the way mcp-server does today:
   `aud=agent-pki`, mTLS peer allowlisted (agent-client only), outermost
   `act.sub` == mTLS peer SPIFFE ID (D-009 binding). Then it fetches its own SVID.
6. **Hop 2 exchange** — subject = the hop-1 token, client auth = `jwt-spiffe`
   (agent-pki), `scope=issue:employee-cert`, exchanged `aud=cert-service`. Keycloak's
   native check: agent-pki must be in the subject token's `aud` — it is, because hop 1
   put it there. The policy executor checks the table row and the delegation depth
   (it parses the subject token's `act` chain). The mapper **nests**:
   `act={sub: spiffe://…/agent-pki, act:{sub: spiffe://…/agent-client}}`.
7. agent-pki calls cert-service over mTLS with its X.509-SVID and the hop-2 token.
8. cert-service checks audience, scope, allow-list (agent-pki only), and outermost
   `act.sub` == mTLS peer; calls EJBCA; issues one certificate for `john-laptop`;
   logs the full chain: `sub=alice act=[agent-pki, agent-client]`.
9. The answer flows back to Alice in the console.

## The scope model — decided, because Keycloak decides nothing here

Verified in the pinned source and recorded in D-030: **standard token exchange never
intersects the requested scope with the subject token's scopes.** The `scope`
parameter is validated against the *requester client's assigned scopes* and consent
(`StandardTokenExchangeProvider.getRequestedScope`, `validateConsents`);
`restrictedScopes` is set by nothing in this path. "Permissions shrink along the
chain" is therefore **not a property Keycloak gives us** — it must be enforced by the
delegation-policy executor, or it does not exist.

The rule for this use case: a hop's granted scope must satisfy **all three** of
- the delegation table's cap for that actor,
- the requester client's assigned scopes in Keycloak (agent-client's client is simply
  never assigned `issue:employee-cert` — non-overlap is literal),
- Alice's original consent (the executor verifies the requested scope against the
  consent she granted at login; the lookup mechanism is a VERIFY item below).

## The delegation table (M13)

Enforced by a **client-policy executor** in `keycloak-spiffe-spi/` — Keycloak fires
`TokenExchangeRequestContext` through the client-policies SPI on every exchange
request *before* the provider runs (`TokenExchangeGrantType.java:83`, pinned). The
executor sees the requester client, requested audience/scope, and the raw subject
token; a violation throws `ClientPolicyException` → clean 400. No fork of the
exchange provider. The table is executor configuration (realm client-policy JSON),
not code.

| Actor (client) | May delegate to (audience) | Max scope | Depth precondition |
|---|---|---|---|
| agent-client | agent-pki | `onboard:initiate` | subject token has **no** `act` (depth 0 → 1) |
| agent-pki | cert-service | `issue:employee-cert` | subject token's `act` chain is exactly `[agent-client]` (depth 1 → 2) |

Everything not listed is refused. Depth is read from the subject token's `act` chain,
so it cannot be spoofed by a caller — only the AS writes `act`.

## The rejections (M14 acceptance)

Each maps to a real line in `infra/acceptance.sh`. Each refusal is the security model
working. Rejections 1–4 are the original design; 5 and 6 fell out of reading the
Keycloak source.

1. **agent-client calls cert-service directly.** Refused three ways: not on
   cert-service's allow-list, token `aud` is not cert-service, no
   `issue:employee-cert`. *(The assistant cannot issue certificates, no matter who
   asked.)*
2. **agent-pki requests a bigger scope than the chain allows** (e.g.
   `issue:ca-admin`). Refused by the policy executor (table cap) **and** by client
   scope assignment — two independent layers. *(Note the mechanism: not
   "scope ⊄ inbound token" — Keycloak has no such check; see the scope model.)*
3. **A third allowlisted workload replays agent-pki's hop-2 token** (the `test-agent`
   fixture from D-009). Refused at cert-service: outermost `act.sub` is agent-pki,
   the mTLS peer is not. *(A token is bound to the workload it was issued to.)*
4. **The agents run with no request from Alice.** No subject token → the standard
   exchange provider refuses the grant outright (`supports()` requires
   `subject_token`). *(No delegation without a delegator.)*
5. **Depth violation.** agent-pki (or anyone) tries to exchange the hop-2 token one
   hop further. The subject token's `act` chain is already at max depth for every
   table row → executor refuses. *(Chains end.)*
6. **Consent violation.** Alice logs in but does not grant `issue:employee-cert`;
   the flow runs; hop 2 is refused at the exchange. *(The human's grant bounds the
   chain — and this one must be a real consent-screen toggle, like the `mcp:audit`
   fixture, never staged.)*

## Milestones

- **M12 — the second hop exists.** agent-pki workload (SPIRE entry, federated-jwt
  Keycloak client, mTLS server with the D-006 pattern) + cert-service (same chassis +
  EJBCA enrollment; profile prep human-gated) + the happy path end-to-end.
  Exit: one console sentence issues a real `john-laptop` certificate; cert-service's
  log shows `sub=alice` and the **nested** act chain.
- **M13 — the table is law.** Client-policy executor + nested-`act` mapper extension
  in `keycloak-spiffe-spi/`. Exit: decoded hop-2 token carries the nested `act`;
  every off-table exchange (audience, scope, depth) is refused.
- **M14 — terminal acceptance.** `infra/acceptance.sh` gains the six rejections above
  and stays green end-to-end. Console surfaces for the new hop are garnish after this,
  never before.

Isolation discipline unchanged (CLAUDE.md §5): the assertion-type URN remains exactly
one constant; the executor and mapper live in workstream B's jar; agent-pki reuses the
existing `TokenExchange`/`TokenRequest` components (they already take the subject
token as an argument — the P2 design pays off again).

## VERIFY before implementing (M12/M13 gate)

- VERIFY: mapper access to the exchange request's `subject_token` form parameter at
  token-generation time (for `act` nesting) against the 26.6.0 source — expected via
  `session.getContext().getHttpRequest()`; the fallback mechanism is the
  `TOKEN_EXCHANGE_SUBJECT_CLIENT` client-session notes Keycloak already copies across
  chained exchanges (`StandardTokenExchangeProvider.java:263-281`, pinned).
- VERIFY: server-side consent lookup for the executor's consent check (Alice's grant
  was recorded against the web client, not the requester) — exact
  `UserProvider`/consent API against the 26.6.0 source.
- VERIFY: client-policy condition/executor registration path for the token-exchange
  event (provider factory IDs, realm JSON shape) against the 26.6.0 source.
- Runtime confirmation owed (predates this use case, found while reading the source):
  the `mcp:audit` consent toggle's **positive** path. Our exchange sends no `scope`
  parameter, so the exchanged token plausibly never carries `mcp:audit` even when
  Alice consents — only the negative path is check-proven (check-p3). Test on the
  live stack; if confirmed, the fix (request the scope at exchange, gated by consent)
  is a prerequisite for rejection 6's mechanism.

## Instruction to keep the hop real

When implementing or refactoring: do not merge the two agents, do not give one agent
both scopes, do not let agent-client reach cert-service, and do not put a model in
agent-pki. If a change would make the task completable in one hop, stop and flag it.
The non-overlapping scopes are the specification, not an implementation detail.

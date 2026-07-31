# Demo Track — execution plan for BUILD-PLAN M10/M11

BUILD-PLAN defines the demo track: **M10** (AI agent in front of agent-client, Spring AI provider-neutral, Ollama default) and **M11** (read-only demo console). This file is the execution plan. Same discipline as everything else: phases ordered by risk, executable exit criteria, and the M10 containment rules are law — the model never touches an SVID, a token, or the exchange; no provider type outside one configuration class; `acceptance.sh` stays green and untouched.

**Bookkeeping note:** BUILD-PLAN M10 cites D-007/D-008 for library feasibility — those numbers are the M6/M7 records. The facts owed land in **D-010** (pins + API evidence) and **D-011** (model choice); BUILD-PLAN references to be corrected in the same commit.

---

## P0 — Verify & pin (the recall-hazard phase; nothing compiles before this)

Everything here is post-cutoff or version-sensitive; every fact from pinned sources only:

1. **Spring AI**: latest GA from repo1 `maven-metadata.xml` (not search index — D-005 lesson). Verify from the tag's sources: `ChatClient`/`ChatModel`, `ToolCallback`, `SyncMcpToolCallbackProvider` (artifact + package), `spring-ai-starter-model-ollama`, and Boot 4.1.0 compatibility.
2. **MCP Java SDK** (`io.modelcontextprotocol.sdk`): latest from repo1; verify the streamable-HTTP transport's `clientBuilder(...)` (inject the java-spiffe `SSLContext`) and `httpRequestCustomizer(...)` (inject the exchanged bearer) from the tag's sources — these two builder hooks are the load-bearing assumption of M10.
3. **Spring AI MCP *server* starter** (webmvc): verify our security stack (oauth2 resource server filters, allowlist/act filters) applies to its endpoint like any servlet route.
4. **Ollama**: compose-able image pin + a tools-capable small model that runs CPU-only (candidates to test, not assume: qwen3 / llama3.x class, ≤4B). Model choice + pull size + cold latency → **D-011**.
5. VERSIONS.md rows: Spring AI, MCP Java SDK, Ollama image, model tag. *(BUILD-PLAN marks these human-gated; proposal is to pin under the same standing delegation as D-004/D-005/D-006 — flagged for veto.)*

**Exit:** D-010 written with file/line evidence for every API named above; VERSIONS rows added; the word VERIFY absent from this plan.

## P1 — mcp-server speaks actual MCP

Today the server is REST-only (`/api/whoami`). M10 needs the real protocol behind the *existing* security stack:

- Add the MCP server (streamable HTTP) exposing 2–3 read-only demo tools (e.g. `whoami` — echoes sub/act/peer; `lab-status` — compose service healths; `read-audit-log` — last N `act=` lines).
- One tool is **scope-gated** (e.g. `read-audit-log` requires scope `mcp:audit`) — the fixture for M10's negative demo. Per-tool enforcement = token scopes (which are already `user ∩ agent` by construction of the exchange); insufficient scope → 403 with `insufficient_scope`.
- All existing gates apply unchanged to the MCP endpoint: aud check, SVID mTLS, allowlist, act↔peer.

**Exit:** scripted MCP `initialize`/`tools-list`/`tools-call` with the exchanged token over mTLS succeeds and logs `sub`+`act`; the scope-gated tool alone returns 403; `./infra/acceptance.sh` still exits 0 untouched.

## P2 — The agentic loop (M10 core)

- agent-client grows a Spring Boot chassis (the CLI modes stay for the milestone checks): `ChatClient` + tools from `SyncMcpToolCallbackProvider` over a hand-built `McpSyncClient` — java-spiffe `SSLContext` via `clientBuilder`, exchanged bearer via `httpRequestCustomizer`. Spring AI never constructs its own transport.
- Provider containment enforced by grep: no `org.springframework.ai.<provider>.` import outside the single config class; a check script asserts it (the M10 isolation rule, executable).
- Ollama as compose service (profile `demo`), model pre-pulled by a script — **zero LLM credentials anywhere**.
- Interface for now: minimal chat endpoint/CLI; the *show* surface is M11.

**Exit:** BUILD-PLAN M10 exits #1 and #3 — a natural-language request produces an MCP call whose server log shows `sub`=alice and `act.sub`=agent SPIFFE ID, with no LLM key in existence; containment grep green.

## P2.5 — Browser login + chat UI *(added 2026-07-31 on human decision)*

Additive presentation layer: **M10's exit criteria are unchanged**, and `acceptance.sh` keeps using the password grant. This exists so the audience *feels* the delegation instead of reading it from a script: alice logs in herself, consents, and chats.

- **Keycloak client `demo-web`**: public, standard flow (authorization code + **PKCE**), no secret, redirect URI on the agent. Two settings carry the demo:
  - `consentRequired=true` — Keycloak shows the consent screen. **This screen is the delegation moment**: the human granting an agent permission to act for her, immediately before `act.sub` proves which workload did.
  - default scope `agent-audience` — alice's token must carry `aud=agent-client` or the exchange is refused (D-008 subject-token rule). The rule that protects the flow also shapes the login.
- **agent-client** gains `spring-boot-starter-oauth2-client` + a minimal chat page (server-rendered, no framework). Per message: take alice's session token → RFC 8693 exchange (jwt-spiffe client auth) → `ChatClient` with MCP tools over SVID mTLS.
- **Token hygiene, demonstrated not just claimed**: alice's token lives **server-side in the session**; the browser holds an ordinary session cookie and never sees a token. The exchanged token exists only for the duration of the call. Stated on stage — it is the pattern people usually get wrong.
- **Optional scope toggle (feeds P3)**: `mcp:audit` is an optional scope, so the login link can request it or not. Log in without it → the audit tool is refused; log in again granting it → the same request succeeds. The audience watches authorization change with *consent*, not with code.

**Exit:** `scripts/check-p25.sh` — scripted authorization-code login (curl through the Keycloak login form, cookie jar), then a chat POST — produces an MCP call whose server log shows `sub`=alice and `act.sub`=agent SPIFFE ID; the check asserts **no access token appears in any browser-visible response**; `./infra/acceptance.sh` still exits 0.

## P3 — The negative demo (M10 exit #2)

Ask the agent to read the audit log (scope alice's token doesn't carry). The model *tries*; the MCP server refuses with 403; the agent reports the refusal. One sentence on stage: **enforcement is tokens, not model behavior** — the model was willing, the token said no.

With P2.5 in place this becomes interactive: run it once with a consent that withholds `mcp:audit` (refused), then re-login granting it (allowed) — same question, same model, different token.

**Exit:** BUILD-PLAN M10 exit #2, plus the flow captured in the demo transcript for M11.

## P4 — M11 demo console

Read-only visualizer per BUILD-PLAN M11: act rail, chain-of-custody panel, token cards, rejection cards, live log tail — fed by JSON captured from a demo run; holds no secrets, validates nothing, killing it changes nothing.

- Demo runs (P2/P2.5/P3 + the five acceptance rejections) emit a structured `demo-run.json` (decoded claims, verdicts, log lines; signatures redacted). The login/consent step is a step in the capture too, so the console can show the human's grant next to the workload's proof.
- Static page (no backend) renders it offline. **The referenced mockup is not in the repo** — either supply it, or the console gets designed fresh in its style section.

**Exit:** BUILD-PLAN M11 exit — complete run rendered offline from captured JSON.

## P5 — Stage resilience + storyline

- `demo/reset.sh --soft` (<2 min, keeps volumes) / `--cold` (asks first — SPIRE/EJBCA state); pre-demo checklist (clock skew first, ports, model pulled, acceptance green); failure cheat-sheet; recorded `--auto` fallback.
- `docs/DEMO.md` narration in three acts: the problem → the happy path (**alice logs in and consents**, agent chats, tokens shown, log line lands) → the attacks (five rejections + the consent-driven scope refusal, one story-line each).

**Exit:** from cold: checklist → full demo green under a rehearsal timer, twice.

---

## Sequencing & risk

| Phase | Risk retired | Effort |
|---|---|---|
| P0 verify & pin | post-cutoff APIs, the two builder hooks | 1–2h |
| P1 MCP-ify server | protocol × security-stack composition | 2–4h |
| P2 agentic loop | Spring AI ↔ hand-built MCP client wiring; CPU model latency | 2–4h |
| P2.5 login + chat UI | browser OIDC ↔ exchange wiring; session token hygiene | 3–4h |
| P3 negative demo | scope plumbing end-to-end | ~1h |
| P4 console | none (offline, read-only) | 2–3h |
| P5 resilience | stage failure | 1–2h |

P0→P1→P2 is the critical path; P2.5 follows P2 (it needs the loop it puts a face on); P4 can start once P2/P2.5 emit JSON. If P0 falsifies a load-bearing assumption (either builder hook missing), stop and re-plan against what the sources actually offer — recorded in DECISIONS, per house rules.

**Concurrency note (2026-07-31):** P2 is being built in a parallel session. Whoever implements P2.5 records its DECISIONS entry under the next free D-number at that time — this plan deliberately does not reserve one, to avoid two sessions claiming the same number in an append-only log.

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

## P3 — The negative demo (M10 exit #2)

Ask the agent to read the audit log (scope alice's token doesn't carry). The model *tries*; the MCP server refuses with 403; the agent reports the refusal. One sentence on stage: **enforcement is tokens, not model behavior** — the model was willing, the token said no.

**Exit:** BUILD-PLAN M10 exit #2, plus the flow captured in the demo transcript for M11.

## P4 — M11 demo console

Read-only visualizer per BUILD-PLAN M11: act rail, chain-of-custody panel, token cards, rejection cards, live log tail — fed by JSON captured from a demo run; holds no secrets, validates nothing, killing it changes nothing.

- Demo runs (P2/P3 + the five acceptance rejections) emit a structured `demo-run.json` (decoded claims, verdicts, log lines; signatures redacted).
- Static page (no backend) renders it offline. **The referenced mockup is not in the repo** — either supply it, or the console gets designed fresh in its style section.

**Exit:** BUILD-PLAN M11 exit — complete run rendered offline from captured JSON.

## P5 — Stage resilience + storyline

- `demo/reset.sh --soft` (<2 min, keeps volumes) / `--cold` (asks first — SPIRE/EJBCA state); pre-demo checklist (clock skew first, ports, model pulled, acceptance green); failure cheat-sheet; recorded `--auto` fallback.
- `docs/DEMO.md` narration in three acts: the problem → the happy path (agent chats, tokens shown, log line lands) → the attacks (five rejections + the scope refusal, one story-line each).

**Exit:** from cold: checklist → full demo green under a rehearsal timer, twice.

---

## Sequencing & risk

| Phase | Risk retired | Effort |
|---|---|---|
| P0 verify & pin | post-cutoff APIs, the two builder hooks | 1–2h |
| P1 MCP-ify server | protocol × security-stack composition | 2–4h |
| P2 agentic loop | Spring AI ↔ hand-built MCP client wiring; CPU model latency | 2–4h |
| P3 negative demo | scope plumbing end-to-end | ~1h |
| P4 console | none (offline, read-only) | 2–3h |
| P5 resilience | stage failure | 1–2h |

P0→P1→P2 is the critical path; P4 can start once P2 emits JSON. If P0 falsifies a load-bearing assumption (either builder hook missing), stop and re-plan against what the sources actually offer — recorded in DECISIONS, per house rules.

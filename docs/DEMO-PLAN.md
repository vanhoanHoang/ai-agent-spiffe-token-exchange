# Demo Track

The build is done (`./infra/acceptance.sh` exits 0, M0–M9). This track turns it into something you can *show*. Same discipline as BUILD-PLAN: milestones ordered by risk, each with an executable exit criterion. No demo step may weaken or bypass anything the acceptance asserts — the demo drives the real stack.

**One open input (DT0) decides the optional tail.** Everything DT1–DT4 is audience-independent and can be built now.

---

## DT0 — Audience & format decision *(human input)*

Pick one primary (others can follow later):

| Option | Shape | Extra deliverable (DT5) |
|---|---|---|
| (a) Live technical demo (team / meetup / conference) | 15–20 min live run + slides-light | recorded fallback |
| (b) Written walkthrough (blog / README showcase) | narrative + copy-pasteable commands + screenshots | polished article draft |
| (c) OAuth WG / spiffe community write-up | findings-focused (D-001..D-009, the two upstream-reportables, the aud/normative-text verification) | datatracker-style mail / issue drafts |

**Exit:** a line in `DECISIONS.md` (D-010) naming the choice. Default if unspecified: **(a)**, since its assets subsume most of (b).

---

## DT1 — Storyline (`docs/DEMO.md`)

Three acts, written to be spoken:

1. **The problem (2 min).** An AI agent calls tools with a human's bearer token. Two invisible identities: *which human* is fine (OIDC), *which workload* is folklore. Stolen token = full impersonation; audit logs lie. One slide: the forbidden patterns table from CLAUDE.md.
2. **The happy path (8 min).** Live, each step shows its artifact:
   - alice logs in → decoded user token (`sub`, `aud: agent-client` — *consent to delegate*).
   - agent fetches its SVIDs from the Workload API → show X509-SVID URI SAN + chain to the **EJBCA root**, show JWT-SVID (`aud` = issuer identifier, sole value — the normative-text detail).
   - token exchange with **jwt-spiffe client auth, no secret anywhere** → decoded token: `sub`=alice, `act.sub`=SPIFFE ID, `aud`=MCP.
   - mTLS MCP call → server log line: `sub + act + peer` — the audit trail that cannot lie.
3. **The attacks (5 min).** Run the five rejections live, one line of story each: no cert (thief without identity) · wrong audience (token laundering) · JWT-SVID as bearer (identity ≠ authorization) · unlisted workload (rogue service) · **replay by another workload** (the M8-replacement, D-009 — the crowd-pleaser: an *allowlisted* workload still refused because `act≠peer`).

**Exit:** full read-through against the running stack; every claim in the text backed by a command that will be run in DT2.

---

## DT2 — Presenter driver (`demo/demo.sh`)

A step-runner over the real stack — *not* a new code path:

- `demo/demo.sh` — numbered steps, pause-on-Enter, `--auto` for unattended runs; every step prints the command it runs before running it (audience sees no magic).
- Pretty-printing helpers: decoded JWTs (header+payload, highlighted `sub`/`act`/`aud`), cert chain summaries (`subject ← issuer` per hop, name-constraint line highlighted), HTTP verdict lines.
- Second-terminal companion: `demo/watch-logs.sh` (follow mcp-server log, grep-highlight `act=`).
- Steps map 1:1 to DT1's acts; the five attacks are steps 8–12.

**Exit:** `demo/demo.sh --auto` completes green twice in a row from a running stack, and `infra/acceptance.sh` still exits 0 afterwards (demo left no residue).

---

## DT3 — Visuals

- Finish `docs/diagrams/` (yours): status table → all ✅ M0–M9 (M8 "skipped by D-009"); add the **token-flow sequence** (the one from ARCHITECTURE.md, with the three trust stores color-coded) as a second canvas/frame.
- Export PNG/SVG for slides; one "architecture on a slide" and one "the five rejections" visual.
- Optional: 30-second pre-demo slide with the trust-domain / issuer / resource-id triple so the audience can parse the tokens they're about to see.

**Exit:** exported images render legibly at projector resolution; diagram claims cross-checked against ARCHITECTURE.md (doc wins).

---

## DT4 — Resilience (the part that saves you on stage)

- `demo/reset.sh`: two modes — `--soft` (restart stack, re-run setup scripts, keep volumes; target < 2 min) and `--cold` (asks before deleting volumes — SPIRE/EJBCA state — then full rebuild; measured, expected 10–15 min). Never run `--cold` on stage.
- Pre-demo checklist in `docs/DEMO.md`: images pre-pulled/pre-built, `acceptance.sh` green, **clock skew checked** (the #1 JWT gotcha per CLAUDE.md §8), ports 8080/8443 free, second terminal ready.
- Failure cheat-sheet: symptom → one-liner (agent not attested → restart agent; realm wiped → setup scripts; bundle endpoint 404 → spire-server restart).
- Recorded fallback: `--auto` run captured (asciinema or terminal recording) — plays if the live stack misbehaves.

**Exit:** from a *cold* machine (fresh clone + `--cold` reset): checklist → demo `--auto` green. From a warm stack: `--soft` reset → live demo green, under the rehearsal clock.

---

## DT5 — Audience-specific tail (after DT0 decision)

- (a): rehearsal twice with a timer; recording as fallback; 5-slide deck max (problem, architecture, three trust stores, rejections, findings).
- (b): DEMO.md expanded into a standalone article with output screenshots; README gets a "run the demo" section.
- (c): drafts for the two upstream-reportables (Keycloak javadoc draft-name; SPIRE `file_sync_interval` default crash) + a short "implementation report" of draft-ietf-oauth-spiffe-client-auth-02 against Keycloak 26.6.0 (what the preview does on `aud`, `iss`, reuse, `client_id`=sub — D-001/D-007 condensed). This is the artifact "worth sending to the OAuth working group".

**Exit:** per choice — (a) rehearsal under time; (b) article renders and commands reproduce; (c) drafts reviewed by you before anything leaves the machine (outward-facing — never sent without your explicit go).

---

## Sequencing & effort

| Step | Depends on | Effort |
|---|---|---|
| DT1 storyline | — | ~1h |
| DT2 driver | DT1 | ~2–3h |
| DT4 resilience | DT2 | ~1–2h |
| DT3 visuals | — (parallel; diagrams are yours) | ~1–2h |
| DT5 tail | DT0 | 1–3h by option |

DT1+DT2+DT4 make the demo *exist and survive*; DT3 makes it *land*; DT5 makes it *travel*. Recommended order: DT1 → DT2 → DT4 → DT3 → (DT0 answer) → DT5.

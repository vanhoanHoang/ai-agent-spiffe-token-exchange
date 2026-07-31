# CLAUDE.md — console workstream (M11 demo console)

Operating instructions for sessions working under `console/`. The root `CLAUDE.md` still applies; this file adds the frontend-specific rules. Read `docs/CONVENTIONS-ANGULAR.md` before writing any code here.

## What this is

BUILD-PLAN **M11** / DEMO-PLAN **P4**: a read-only visualizer for the demo track — act rail, chain-of-custody panel, token cards, rejection cards, live log tail — rendered **offline** from a captured `DEMO_RUN` JSON. It validates nothing, holds no secrets, and killing it changes nothing about the stack. It is presentation; the truth lives in the tokens and logs it displays.

## Session protocol (frontend variant)

1. Read `docs/BUILD-PLAN.md` (M11) and `docs/DEMO-PLAN.md` (P4); state the exit criterion: *the console renders a complete demo run offline from captured JSON.*
2. Read `docs/DECISIONS.md` for demo-track decisions; honor them.
3. **Re-read the mockup** `mockup/identity-demo-console.html` at the start of console work. It is the visual starting point only: static HTML, no login flow, no real data wiring. Extract its design language (palette, spacing, type, panel layout) into design tokens; do **not** transplant its markup or inline styles.
4. Write the exit check first (`scripts/check-console.sh`: install, lint, build, tests, offline-render assertion), watch it fail, then implement.
5. Green → update `docs/DECISIONS.md` if anything contradicted the docs → stop and report. One phase per session.

## Hard rules

`docs/CONVENTIONS-ANGULAR.md` is **binding, not advisory**: its code rules (file/function size, complexity, template limits, tokens-only styling) are wired into ESLint at scaffold time and fail `scripts/check-console.sh`. Claude Code does not commit console code that violates them, and never weakens a lint rule to get green — same law as "never widen a validation check" in the root file.

- **Angular pinned in `docs/VERSIONS.md`** (CLI 22.1.2 / core 22.1). Angular 22 is post-cutoff: every API fact from angular.dev or the installed sources, never recall. v17-era patterns (NgModules, `*ngIf`, constructor DI by habit) are defects here.
- **One input**: the `DEMO_RUN` JSON capture. Typed model in `core/`, fail-closed parsing, panels never touch raw JSON. No calls to Keycloak / MCP server / SPIRE — ever.
- **No token ever appears whole.** Decoded claims only; captures arrive pre-redacted. Nothing credential-shaped in the repo, bundle, or browser storage.
- **Design tokens or nothing**: components use semantic CSS custom properties from `src/styles/tokens.css`; raw hex/px/font values in components are review-blocking (`docs/CONVENTIONS-ANGULAR.md` §Design system).
- Dependencies = Angular + `ng new` scaffold output. Anything else goes through `docs/DECISIONS.md` first.
- Scope: edits stay inside `console/` (plus `scripts/check-console.sh`); `mockup/` is read-only reference material.

## Working style ("vibe coding" with guardrails)

Iterate fast on look and feel — that is the point of this workstream — but inside the rails: tokens before styling, model before panels, exit check before implementation, and every panel gets a fixture-driven test (one happy, one negative: rejection card / malformed capture). When a visual decision is taste, take it and move on; when it is structure (new dependency, new data field, schema change), it is a decision — record it.

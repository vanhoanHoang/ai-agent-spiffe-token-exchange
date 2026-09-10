# Conventions — Angular (M11 demo console, `console/`)

Read before writing any frontend code, together with `console/CLAUDE.md`. Same spirit as `docs/CONVENTIONS.md`: short, non-negotiable, executable where possible. The console is BUILD-PLAN M11: a **read-only visualizer** — it holds no secrets, stores no tokens, validates nothing, and killing it changes nothing about the stack.

## Versions

- Angular CLI `22.1.2` / core `22.1` — pinned in `docs/VERSIONS.md` (npm registry `latest`, 2026-07-31). Node per the CLI's engines: `^22.22.3 || ^24.15.0 || >=26.0.0`.
- **Angular 22 is post-cutoff.** Model recall of Angular is v17-era and wrong here. Any API fact comes from angular.dev, the scaffolded code, or the installed package sources — never memory. Unverified facts get `// VERIFY: <what> against <source>`; zero markers is part of the console's exit gate.
- Dependencies: Angular + what `ng new` scaffolds. Every addition beyond that needs a reason recorded in `docs/DECISIONS.md`. No component libraries — the design system is ours (see tokens below).

## Architecture

- Standalone components only; no NgModules anywhere.
- Signals first: `signal`/`computed`/`input()`/`output()` for component state; `inject()` over constructor parameters. RxJS only where a signal genuinely cannot express it (streams over time), and convert at the edge.
- Native control flow (`@if`/`@for`/`@switch`); `@for` always with `track`.
- `ChangeDetectionStrategy.OnPush` on every component; set it as the schematics default in `angular.json`.
- Structure:
  ```
  console/src/app/
    core/        # DEMO_RUN model + loader; no UI
    features/    # one folder per console panel (act-rail, custody, tokens, rejections, log-tail)
    shared/ui/   # presentational, token-consuming, zero business logic
  ```
- Strict TypeScript as scaffolded (`ng new` strict). `any` is forbidden; unknown JSON is `unknown` until narrowed.

## The one data rule

The console has exactly **one input**: the captured `DEMO_RUN` JSON (schema owned by P4, emitted by the demo runs). Its TypeScript model lives in `core/` and is the single source of type truth — panels consume the model, never raw JSON. Parsing is fail-closed: a malformed capture renders an error state, never a half-lie of a demo run. No HTTP calls to Keycloak, the MCP server, or SPIRE — with **one amendment (D-017)**: when served by agent-web (same origin), the console may call **the agent's own `/api/me` and `/api/chat`** — the same session-cookie surface the browser already had. Those endpoints return answers and identity labels, never tokens; anywhere else the console is served, it must degrade to the offline capture (that fallback is part of the M11 exit and stays tested).

## Security posture (inherited from the stack)

- Never store, request, or display a complete token. Captures arrive with signatures redacted; the console renders **decoded claims**, and only those.
- No credentials of any kind in the repo, the bundle, or `localStorage`.
- The console must render the full demo **offline** (`ng build` output served statically, or `file://`). Anything reachable only online is a bug.

## Design system

- The visual source of truth is the **v2 "Plex" system** (D-037), drafted on the redesign canvas ("Identity Console Redesign"); the original mockup (`mockup/identity-demo-console.html`) is historical reference only.
- Design tokens are CSS custom properties in `src/styles/tokens.css`, two layers:
  - **primitive** (`--color-teal-500`, `--space-4`, `--font-mono`) — raw values, defined once;
  - **semantic** (`--surface-panel`, `--text-verdict-pass`, `--text-verdict-fail`, `--border-custody`) — what components actually use.
- Components consume **semantic tokens only**. A hex color, px spacing, or font name inside a component style is a review-blocking defect. New visual values enter through the token files or not at all.
- The system is **v2 "Plex"** (D-037): IBM Plex Sans/Mono over near-monochrome neutrals (`#f5f6f8`/`#ffffff`, hairline `#e4e7ec`, ink `#1a1d23`), a 3-level type ramp (mono strictly for identifiers/claims/log — never a sentence), 4-base spacing, radii 6/10, and a fixed **colour language** — human/OIDC `#35618e`, workload/SPIFFE `#1f7a70`, the bridge/`act` `#c2551f` (RFC 8693 hops ONLY), rejection `#b3362a`, verdict-green `#2e7d4f`. That colour language is semantic (it encodes which identity a value belongs to) — never repurpose those hues decoratively; red means denied, buttons and focus rings are ink. A theme change is a token swap, not component edits.

## Code rules (lint-enforced, not vibes)

Wired into the ESLint config at scaffold time (angular-eslint + `max-lines`, `max-lines-per-function`, `complexity`), so violations fail `scripts/check-console.sh` — same "executable check" discipline as the rest of the repo.

| Rule | Limit |
|---|---|
| Lines per file (any `.ts`) | ≤ 300; a file approaching it is a split waiting to happen |
| Component class | ≤ 200 lines; presentational components in `shared/ui` ≤ 100 |
| Function/method | ≤ 40 lines, cyclomatic complexity ≤ 10 |
| Template | inline only if ≤ 15 lines, else its own `.html`; nesting ≤ 4 levels |
| One per file | one component/directive/pipe/service per file, no exceptions |

- **Files**: kebab-case names as the CLI generates them at the pinned version — follow `ng generate` output, do not invent a different scheme. Component selector prefix `dc-` (demo console), set in `angular.json`.
- **Templates**: no function calls except signal reads and pure pipes; `@for` always with `track`; no logic beyond the native control flow — anything conditional-heavy moves into a `computed`.
- **State**: component state is signals; no side effects inside `computed`; `effect()` is a last resort with a comment saying why. Services hold shared state, components hold view state.
- **Styles**: component-scoped styles only, consuming semantic tokens; no `::ng-deep`, no global selectors outside `src/styles/`; no `!important`.
- **Imports**: no barrel files (`index.ts` re-exports invite cycles); import from the concrete file.
- **Accessibility is not optional**: semantic elements over styled `div`s, every interactive element keyboard-reachable, text contrast satisfied by the token palette (checked once, at the token layer — a benefit of tokens-only styling).
- **Formatting**: Prettier defaults as scaffolded; formatting is never discussed in review.

## Quality gates (executable, written before the implementation — house rule)

`scripts/check-console.sh` is the workstream's exit check and runs, in order: `npm ci`, lint, typecheck/build (`ng build`), unit tests, and the offline-render assertion (the built bundle renders a complete captured run without network). Every panel has at least one test rendering it from a fixture capture, including one **negative** fixture (rejection cards, malformed capture → error state) — negatives are first-class, same as the four M9 rejections.

## Git

- The console is its own workstream (`console/`); no edits outside it without asking.
- Commits follow `docs/CONVENTIONS.md` §Git; no co-author trailers.

/**
 * DEMO_RUN v1 — the console's ONE input (demo/demo-run.schema.json).
 * Parsing is fail-closed: a malformed capture throws and the app renders an
 * error state, never a half-rendered lie of a demo run.
 */
export interface DemoActors {
  readonly human: { readonly username: string; readonly sub: string };
  readonly agent: { readonly spiffe_id: string };
  readonly mcp_server: { readonly spiffe_id: string; readonly resource_id: string };
}

export interface DemoToken {
  readonly name: string;
  readonly description: string;
  readonly header: Readonly<Record<string, unknown>>;
  readonly claims: Readonly<Record<string, unknown>>;
  readonly signature: 'REDACTED';
}

export type StepKind = 'login' | 'consent' | 'exchange' | 'chat' | 'tool_call' | 'rejection';
export type StepVerdict = 'pass' | 'deny';

export interface DemoStep {
  readonly id: string;
  readonly kind: StepKind;
  readonly title: string;
  readonly verdict: StepVerdict;
  readonly prompt?: string;
  readonly answer?: string;
  readonly token_ref?: string;
  readonly detail?: string;
  readonly log_lines?: readonly string[];
}

export interface DemoRejection {
  readonly id: string;
  readonly title: string;
  readonly verdict: 'deny-as-designed' | 'FAILED-TO-DENY';
  readonly source: string;
}

export interface DemoRun {
  readonly version: 1;
  readonly captured_at: string;
  readonly trust_domain: string;
  readonly actors: DemoActors;
  readonly tokens: readonly DemoToken[];
  readonly steps: readonly DemoStep[];
  readonly rejections: readonly DemoRejection[];
  readonly chain_of_custody: { readonly verified: boolean; readonly notes: string; readonly source: string };
  readonly log_tail: readonly string[];
}

const JWT_SHAPE = /[\w-]{20,}\.[\w-]{20,}\.[\w-]{20,}/;

function require(cond: boolean, what: string): asserts cond {
  if (!cond) {
    throw new Error(`malformed DEMO_RUN capture: ${what}`);
  }
}

function validateIdentity(r: DemoRun): void {
  require(r.version === 1, 'unsupported version');
  require(r.trust_domain === 'spiffe://lab.internal', 'wrong trust domain');
  require(typeof r.actors?.human?.sub === 'string', 'actors.human missing');
  require(typeof r.actors?.agent?.spiffe_id === 'string', 'actors.agent missing');
  require(typeof r.actors?.mcp_server?.resource_id === 'string', 'actors.mcp_server missing');
}

function validateEvidence(r: DemoRun): void {
  require(Array.isArray(r.tokens) && r.tokens.length >= 2, 'tokens missing');
  for (const t of r.tokens) {
    require(t.signature === 'REDACTED', `token ${t?.name} signature not redacted`);
  }
  require(Array.isArray(r.steps) && r.steps.length >= 1, 'steps missing');
  require(Array.isArray(r.rejections) && r.rejections.length >= 5, 'rejections missing');
  require(typeof r.chain_of_custody?.verified === 'boolean', 'chain_of_custody missing');
  require(Array.isArray(r.log_tail), 'log_tail missing');
}

/** Fail-closed structural validation of an untrusted capture. */
export function parseDemoRun(raw: unknown): DemoRun {
  require(typeof raw === 'object' && raw !== null, 'not an object');
  const r = raw as DemoRun;
  validateIdentity(r);
  validateEvidence(r);
  require(!JWT_SHAPE.test(JSON.stringify(raw)), 'capture contains a token-shaped string');
  return r;
}

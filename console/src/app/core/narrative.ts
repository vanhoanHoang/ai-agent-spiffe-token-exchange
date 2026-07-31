/**
 * Presentation copy (from the approved mockup) joined to CAPTURED facts.
 * The rule: verdicts, identities, claims, and log lines come from the capture;
 * only the narration is authored here. The console can never show a pass or a
 * rejection the stack did not actually perform.
 */
import { DemoRun, DemoStep, DemoToken } from './demo-run';

export type IdentityRole = 'human' | 'workload' | 'bridge' | 'ink';

export interface Stage {
  readonly id: string;
  readonly num: string;
  readonly role: IdentityRole;
  readonly kindLabel: string;
  readonly title: string;
  readonly hint: string;
  readonly narration: string;
  readonly proves: string;
}

export interface CustodyHop {
  readonly role: string;
  readonly name: string;
  readonly detail: string;
  readonly badge?: string;
}

export interface RejectionCard {
  readonly id: string;
  readonly verdict: string;
  readonly failed: boolean;
  readonly story: string;
  readonly mechanism: string;
}

export const STAGES: readonly Stage[] = [
  {
    id: 'login', num: '01', role: 'human', kindLabel: 'OIDC', title: 'Human login',
    hint: 'alice signs in and consents',
    narration: 'Alice signs in to Keycloak and consents to the agent acting for her. She receives an ordinary OIDC access token that records who she is and what she consented to. It says nothing about the software acting for her.',
    proves: 'the human. This token alone cannot reach the MCP server: its audience is the agent client, not the resource.',
  },
  {
    id: 'svid', num: '02', role: 'workload', kindLabel: 'SPIFFE', title: 'Agent fetches SVIDs',
    hint: 'SPIRE hands the workload its identity',
    narration: 'SPIRE runs as an intermediate CA under the lab’s offline root (EJBCA), so every workload certificate chains back to real PKI. The agent asks for its own identity and receives two forms of the same SPIFFE ID: an X.509-SVID for mTLS, and a JWT-SVID it uses instead of a client secret. Attestation issues both; nothing is typed or configured.',
    proves: 'the workload. The agent holds no secret; if the process is not the attested agent, SPIRE hands it nothing.',
  },
  {
    id: 'exchange', num: '03', role: 'bridge', kindLabel: 'RFC 8693', title: 'Token exchange',
    hint: 'the only bridge',
    narration: 'The agent presents Alice’s token together with its JWT-SVID and asks Keycloak to exchange them. Keycloak returns one token that carries both identities: sub is still Alice, and a new act claim names the workload acting for her.',
    proves: 'the bridge. Two separate identity worlds, OIDC and SPIFFE, meet in exactly one place, and the result is auditable in a single token.',
  },
  {
    id: 'call', num: '04', role: 'ink', kindLabel: 'mTLS', title: 'mTLS MCP call',
    hint: 'server checks four things',
    narration: 'The agent calls the MCP server over mTLS with the exchanged token. The server checks the token’s audience, the peer certificate’s SPIFFE ID, the allowlist, and finally that act.sub equals the peer it is actually talking to.',
    proves: 'that the token cannot travel. It is bound to the workload it was issued to; a stolen copy is useless from any other peer.',
  },
  {
    id: 'chat', num: '05', role: 'ink', kindLabel: 'Agent', title: 'Agent does it end-to-end',
    hint: 'the same guarantees, from a chat',
    narration: 'Nothing above is a special demo path. When the model decides to call a tool, the identical exchange happens underneath. The model’s intent never becomes authority on its own.',
    proves: 'that enforcement lives in tokens, not in model behaviour. The agent may ask for anything; the server answers only what Alice’s consented scopes allow.',
  },
];

export function custodyHops(run: DemoRun): readonly CustodyHop[] {
  return [
    {
      role: 'Leaf · X.509-SVID', name: 'agent-client',
      detail: `URI SAN: ${run.actors.agent.spiffe_id} · rotated by SPIRE`,
    },
    {
      role: 'Issued by', name: 'SPIRE Intermediate CA',
      detail: 'issued offline by EJBCA',
      badge: 'Name Constraints (critical): URI host = lab.internal',
    },
    {
      role: 'Anchored at', name: 'Lab Root CA (EJBCA)',
      detail: 'offline root, the trust anchor',
    },
  ];
}

export interface CallCheck {
  readonly label: string;
  readonly detail: string;
}

export function callChecks(run: DemoRun): readonly CallCheck[] {
  const agent = run.actors.agent.spiffe_id;
  return [
    { label: 'Token audience is this server', detail: `aud = [${run.actors.mcp_server.resource_id}]` },
    { label: 'Peer presented an X.509-SVID over mTLS', detail: `peer = ${agent}` },
    { label: 'Peer is on the allowlist', detail: `allow ∋ ${agent}` },
    { label: 'act.sub equals the mTLS peer', detail: 'act.sub == peer → token is bound to this workload' },
  ];
}

const REJECTION_COPY: Readonly<Record<string, Omit<RejectionCard, 'id' | 'verdict' | 'failed'>>> = {
  'no-client-cert': {
    story: 'A caller opens a plain TLS connection with no client certificate.',
    mechanism: 'TLS handshake (mTLS required)',
  },
  'wrong-audience': {
    story: 'A valid Keycloak token minted for another service is replayed here.',
    mechanism: 'aud check (anti-passthrough)',
  },
  'svid-as-bearer': {
    story: 'The workload’s JWT-SVID is sent straight to the MCP server as a bearer token.',
    mechanism: 'issuer / JWKS',
  },
  'unlisted-workload': {
    story: 'A correctly exchanged token arrives from a workload that is not registered.',
    mechanism: 'workload allowlist',
  },
  'token-replay': {
    story: 'Another allowlisted workload replays a stolen token over its own mTLS connection.',
    mechanism: 'act.sub == mTLS peer',
  },
  'insufficient-scope': {
    story: 'The model tries to read the audit log, which is outside the consented scopes.',
    mechanism: 'token scopes (user ∩ agent)',
  },
};

export function rejectionCards(run: DemoRun): readonly RejectionCard[] {
  const cards: RejectionCard[] = run.rejections.map((r) => ({
    id: r.id,
    verdict: r.verdict === 'deny-as-designed' ? 'refused' : 'NOT REFUSED',
    failed: r.verdict !== 'deny-as-designed',
    ...(REJECTION_COPY[r.id] ?? { story: r.title, mechanism: r.source }),
  }));
  const refusal = run.steps.find((s) => s.id === 'chat-audit-refused');
  if (refusal) {
    cards.push({
      id: 'insufficient-scope',
      verdict: refusal.verdict === 'deny' ? '403' : 'NOT REFUSED',
      failed: refusal.verdict !== 'deny',
      ...REJECTION_COPY['insufficient-scope'],
    });
  }
  return cards;
}

export function tokenByRef(run: DemoRun, name: string): DemoToken | undefined {
  return run.tokens.find((t) => t.name === name);
}

export function stepById(run: DemoRun, id: string): DemoStep | undefined {
  return run.steps.find((s) => s.id === id);
}

import { DemoRun } from '../demo-run';

/** A minimal, valid DEMO_RUN capture for tests — same shape the stack emits. */
export function demoRunFixture(): DemoRun {
  return structuredClone(FIXTURE);
}

const FIXTURE: DemoRun = {
    version: 1,
    captured_at: '2026-07-31T00:00:00+00:00',
    trust_domain: 'spiffe://ai-agent.id.eviden.internal',
    actors: {
      human: { username: 'alice', sub: 'alice-sub-uuid' },
      agent: { spiffe_id: 'spiffe://ai-agent.id.eviden.internal/agent-client' },
      mcp_server: {
        spiffe_id: 'spiffe://ai-agent.id.eviden.internal/mcp-server',
        resource_id: 'https://mcp.ai-agent.id.eviden.internal:8443',
      },
    },
    tokens: [
      {
        name: 'subject_token',
        description: "alice's login token",
        header: { alg: 'RS256', typ: 'JWT' },
        claims: {
          sub: 'alice-sub-uuid',
          preferred_username: 'alice',
          aud: ['agent-client'],
          iss: 'http://keycloak:8080/realms/ai-agents',
          scope: 'openid profile',
        },
        signature: 'REDACTED',
      },
      {
        name: 'exchanged_token',
        description: 'delegation token',
        header: { alg: 'RS256', typ: 'JWT' },
        claims: {
          sub: 'alice-sub-uuid',
          act: { sub: 'spiffe://ai-agent.id.eviden.internal/agent-client' },
          aud: 'https://mcp.ai-agent.id.eviden.internal:8443',
          scope: 'openid profile',
        },
        signature: 'REDACTED',
      },
    ],
    steps: [
      { id: 'login', kind: 'login', title: 'alice logs in', verdict: 'pass', token_ref: 'subject_token' },
      { id: 'exchange', kind: 'exchange', title: 'exchange', verdict: 'pass', token_ref: 'exchanged_token' },
      {
        id: 'chat-whoami',
        kind: 'chat',
        title: 'whoami',
        verdict: 'pass',
        prompt: 'Who am I?',
        answer: 'You are alice; I act as the agent workload.',
        log_lines: ['tool=whoami sub=alice-sub-uuid act={sub=spiffe://ai-agent.id.eviden.internal/agent-client}'],
      },
      {
        id: 'chat-audit-refused',
        kind: 'chat',
        title: 'audit refused',
        verdict: 'deny',
        prompt: 'Read the audit log.',
        answer: 'The server refused: insufficient_scope.',
        log_lines: ['tool=read_audit_log DENIED sub=alice-sub-uuid'],
      },
    ],
    rejections: [
      { id: 'no-client-cert', title: 'no client cert', verdict: 'deny-as-designed', source: 'acceptance' },
      { id: 'wrong-audience', title: 'wrong aud', verdict: 'deny-as-designed', source: 'acceptance' },
      { id: 'svid-as-bearer', title: 'svid bearer', verdict: 'deny-as-designed', source: 'acceptance' },
      { id: 'unlisted-workload', title: 'unlisted', verdict: 'deny-as-designed', source: 'acceptance' },
      { id: 'token-replay', title: 'replay', verdict: 'deny-as-designed', source: 'acceptance' },
    ],
    chain_of_custody: { verified: true, notes: 'chains to the EJBCA root', source: 'acceptance' },
    log_tail: [
      'tool=whoami sub=alice-sub-uuid act={sub=spiffe://ai-agent.id.eviden.internal/agent-client}',
      'tool=read_audit_log DENIED sub=alice-sub-uuid',
      'tool=stack_status sub=alice-sub-uuid',
    ],
  };

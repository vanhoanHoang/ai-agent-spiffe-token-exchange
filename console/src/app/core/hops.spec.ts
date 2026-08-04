import { actChain, attributeHops, hopActor, hopCount, RawChainEvent } from './hops';

/** The stream a two-hop run produces: one svid+exchange pair per hop. */
const TWO_HOP: readonly RawChainEvent[] = [
  { step: 'svid', detail: 'agent-client JWT-SVID' },
  { step: 'exchange', detail: 'act.sub=agent-client aud=agent-pki' },
  { step: 'tool', detail: 'onboard_employee' },
  { step: 'svid', detail: 'agent-pki JWT-SVID' },
  { step: 'exchange', detail: 'act nests agent-pki over agent-client' },
  { step: 'tool', detail: 'issue_employee_cert' },
];

const ONE_HOP: readonly RawChainEvent[] = [
  { step: 'svid', detail: 'agent-client JWT-SVID' },
  { step: 'exchange', detail: 'act.sub=agent-client aud=mcp-server' },
  { step: 'tool', detail: 'read_audit_log' },
];

describe('hop attribution', () => {
  it('keeps a single-hop run entirely in hop 1', () => {
    expect(attributeHops(ONE_HOP).map((e) => e.hop)).toEqual([1, 1, 1]);
    expect(hopCount(attributeHops(ONE_HOP))).toBe(1);
  });

  it('opens a new hop at each svid, so the second exchange lands in hop 2', () => {
    expect(attributeHops(TWO_HOP).map((e) => e.hop)).toEqual([1, 1, 1, 2, 2, 2]);
    expect(hopCount(attributeHops(TWO_HOP))).toBe(2);
  });

  // Derivation is a fallback. The server is the authority on its own chain,
  // so once StepEvent carries a hop it must win outright.
  it('lets an explicit server hop override the derived one', () => {
    const withExplicit: readonly RawChainEvent[] = [
      { step: 'svid', detail: 'agent-client', hop: 1 },
      { step: 'tool', detail: 'onboard_employee', hop: 2 },
    ];
    expect(attributeHops(withExplicit).map((e) => e.hop)).toEqual([1, 2]);
  });

  it('never attributes an event to hop 0 when the stream opens mid-flight', () => {
    const partial: readonly RawChainEvent[] = [{ step: 'tool', detail: 'onboard_employee' }];
    expect(attributeHops(partial)[0].hop).toBe(1);
  });

  it('reports an empty stream as one hop rather than none', () => {
    expect(hopCount([])).toBe(1);
  });

  it('names the acting workload of each hop', () => {
    expect(hopActor(1)).toBe('agent-client');
    expect(hopActor(2)).toBe('agent-pki');
    expect(hopActor(3)).toBe('hop 3');
  });

  it('builds the act chain outermost last, the order the nested claim reads', () => {
    expect(actChain(attributeHops(TWO_HOP), 'alice')).toEqual([
      'alice',
      'agent-client',
      'agent-pki',
    ]);
    expect(actChain(attributeHops(ONE_HOP), 'alice')).toEqual(['alice', 'agent-client']);
  });
});

/**
 * Hop attribution for the live chain stream (M12 / D-032).
 *
 * The agent's SSE stream (D-018) is flat — `svid`, `exchange`, `tool` — and
 * carries no hop field. Rather than block the console on a server change, the
 * hop is DERIVED from the one invariant the emitter guarantees: every hop runs
 * exactly one exchange, and every exchange is preceded by that workload
 * fetching its own SVID (`TokenExchange.exchange` emits `svid` then `exchange`,
 * in that order, once per call). So an `svid` event OPENS a hop.
 *
 * Two-hop flow, as it arrives:
 *   svid(agent-client) exchange tool   -> hop 1
 *   svid(agent-pki)    exchange tool   -> hop 2
 *
 * Single-hop runs are unchanged: one `svid` means everything is hop 1.
 *
 * Derivation is a FALLBACK, never an override. When the server stamps an
 * explicit hop on the event, that value wins — see {@link RawChainEvent.hop}.
 * The console is presentation; the server is the authority on its own chain.
 */

/** One event as it arrives from the stream, before attribution. */
export interface RawChainEvent {
  readonly step: string;
  readonly detail: string;
  /** Set by the server once StepEvent carries a hop; wins over derivation. */
  readonly hop?: number;
}

/** One event, attributed to the hop it belongs to. */
export interface ChainEvent {
  readonly step: string;
  readonly detail: string;
  readonly hop: number;
}

/** Which workload acts in each hop, for labelling. Index 0 is hop 1. */
const HOP_ACTORS: readonly string[] = ['agent-client', 'agent-pki'];

/** The acting workload of a hop, or a generic label past the known chain. */
export function hopActor(hop: number): string {
  return HOP_ACTORS[hop - 1] ?? `hop ${hop}`;
}

/**
 * Attribute every event to its hop, in arrival order. Pure: the same input
 * always yields the same output, so the panels can recompute freely.
 */
export function attributeHops(raw: readonly RawChainEvent[]): readonly ChainEvent[] {
  let derived = 0;
  return raw.map((e) => {
    if (e.step === 'svid') {
      derived += 1;
    }
    return { step: e.step, detail: e.detail, hop: e.hop ?? Math.max(derived, 1) };
  });
}

/** How many hops this stream has reached so far (at least one). */
export function hopCount(events: readonly ChainEvent[]): number {
  return events.reduce((max, e) => Math.max(max, e.hop), 1);
}

/**
 * The delegation chain the events prove, outermost actor last — the same
 * order the nested `act` claim reads in (D-032): alice acting through
 * agent-client acting through agent-pki.
 */
export function actChain(events: readonly ChainEvent[], human: string): readonly string[] {
  const hops = hopCount(events);
  const chain = [human];
  for (let h = 1; h <= hops; h += 1) {
    chain.push(hopActor(h));
  }
  return chain;
}

/** The events of one hop, in arrival order. */
export interface HopGroup {
  readonly hop: number;
  readonly actor: string;
  readonly lines: readonly ChainEvent[];
}

/** Group the stream by hop, preserving arrival order within each group. */
export function groupByHop(events: readonly ChainEvent[]): readonly HopGroup[] {
  const groups: { hop: number; actor: string; lines: ChainEvent[] }[] = [];
  for (const e of events) {
    const last = groups[groups.length - 1];
    if (last === undefined || last.hop !== e.hop) {
      groups.push({ hop: e.hop, actor: hopActor(e.hop), lines: [e] });
    } else {
      last.lines.push(e);
    }
  }
  return groups;
}

/**
 * Which architecture-diagram stage an event belongs to. The same event name
 * means a different edge depending on its depth: hop 1's tool call reaches
 * agent-pki, hop 2's reaches cert-service.
 */
const HOP1_STAGES: Readonly<Record<string, string>> = {
  svid: 'svid',
  exchange: 'exchange',
  tool: 'call',
};

const HOP2_STAGES: Readonly<Record<string, string>> = {
  svid: 'svid2',
  exchange: 'exchange2',
  tool: 'issue',
};

export function stageIdFor(event: ChainEvent): string {
  const table = event.hop >= 2 ? HOP2_STAGES : HOP1_STAGES;
  return table[event.step] ?? 'chat';
}

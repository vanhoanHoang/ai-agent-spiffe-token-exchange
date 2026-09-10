import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

/**
 * Swimlane sequence diagram (v2/D-037): actors across the top, time flows
 * down, messages horizontal — packets still ride the lit edges via SMIL
 * animateMotion. Covers both delegation hops (M12/D-032).
 *
 * Two rules carry the second hop:
 *  - agent-pki and cert-service are drawn, each with the scope it may hold,
 *    so the non-overlap is visible on the picture itself;
 *  - agent-client → cert-service is DRAWN as refused, not omitted. An edge
 *    nobody can see proves nothing to an audience.
 *
 * Which edges light comes from the selected stage — packets only travel on
 * the part of the story being told. `hops` says how far the chain actually
 * went, so a single-hop run never lights second-hop scenery.
 */
const STAGE_EDGES: Readonly<Record<string, readonly string[]>> = {
  login: ['login'],
  svid: ['pki', 'svid'],
  exchange: ['svid', 'exch'],
  call: ['call'],
  chat: ['chat', 'exch', 'call'],
  hand: ['hand'],
  svid2: ['svid2'],
  exchange2: ['svid2', 'exch2'],
  issue: ['issue'],
  refused: ['forbidden'],
};

/**
 * With two hops the assistant's outbound call lands on agent-pki, not on the
 * MCP server — the same stage id means a different edge once the chain is
 * longer. Overrides only; anything absent falls through to STAGE_EDGES.
 */
const TWO_HOP_EDGES: Readonly<Record<string, readonly string[]>> = {
  call: ['hand'],
  chat: ['chat', 'exch', 'hand', 'exch2', 'issue'],
};

@Component({
  selector: 'dc-flow-diagram',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './flow-diagram.html',
  styleUrl: './flow-diagram.css',
})
export class FlowDiagram {
  readonly stage = input.required<string>();

  /** How many delegation hops this run reached. 1 = the original flow. */
  readonly hops = input<number>(1);

  /** The scope the assistant actually carries, as the run reports it. */
  readonly assistantScope = input<string>('onboard:initiate');

  private readonly twoHop = computed(() => this.hops() >= 2);

  protected readonly active = computed<readonly string[]>(() => {
    const stage = this.stage();
    const override = this.twoHop() ? TWO_HOP_EDGES[stage] : undefined;
    return override ?? STAGE_EDGES[stage] ?? [];
  });

  protected on(edge: string): boolean {
    return this.active().includes(edge);
  }

  /**
   * Workloads that exist but took no part in this run are dimmed rather than
   * hidden — the topology is a constant, the participation is not.
   */
  protected dim(group: string): boolean {
    return group === 'mcp' ? this.twoHop() : !this.twoHop();
  }
}

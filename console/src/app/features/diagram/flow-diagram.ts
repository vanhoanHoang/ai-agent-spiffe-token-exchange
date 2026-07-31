import { ChangeDetectionStrategy, Component, computed, input } from '@angular/core';

/**
 * The mockup's animated architecture diagram: six nodes, packets flowing
 * along the edges (SMIL animateMotion, exactly as the mockup does it). Which
 * edges are lit comes from the selected stage — the packets only travel on
 * the part of the story currently being told.
 */
const STAGE_EDGES: Readonly<Record<string, readonly string[]>> = {
  login: ['login'],
  svid: ['pki', 'svid'],
  exchange: ['svid', 'exch'],
  call: ['call'],
  chat: ['chat', 'exch', 'call'],
};

@Component({
  selector: 'dc-flow-diagram',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './flow-diagram.html',
  styleUrl: './flow-diagram.css',
})
export class FlowDiagram {
  readonly stage = input.required<string>();

  protected readonly active = computed<readonly string[]>(() => STAGE_EDGES[this.stage()] ?? []);

  protected on(edge: string): boolean {
    return this.active().includes(edge);
  }
}

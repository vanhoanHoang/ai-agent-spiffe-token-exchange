import {
  ChangeDetectionStrategy,
  Component,
  computed,
  effect,
  ElementRef,
  inject,
  input,
  output,
  signal,
  viewChild,
} from '@angular/core';

import {
  attributeHops,
  ChainEvent,
  groupByHop,
  hopCount,
  RawChainEvent,
  stageIdFor,
} from '../../core/hops';
import { LiveClient, LiveUser } from '../../core/live';

interface Turn {
  readonly q: string;
  readonly a: string;
  readonly error: boolean;
}

/** One event as the trace shows it: what happened, and where to inspect it. */
interface TraceLine {
  readonly stage: string;
  readonly label: string;
  readonly detail: string;
}

interface TraceGroup {
  readonly hop: number;
  readonly actor: string;
  readonly lines: readonly TraceLine[];
}

type Phase = 'idle' | 'flight' | 'done' | 'error';

/** What each event means, in the reader's language rather than the wire's. */
const STEP_LABEL: Readonly<Record<string, string>> = {
  svid: 'proved which workload it is',
  exchange: 'exchanged the token · RFC 8693',
  tool: 'called a tool over mTLS',
};

function toLine(e: ChainEvent): TraceLine {
  return {
    stage: stageIdFor(e),
    label: STEP_LABEL[e.step] ?? e.step,
    detail: e.detail,
  };
}

@Component({
  selector: 'dc-live-chat',
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: './live-chat.html',
  styleUrl: './live-chat.css',
})
export class LiveChat {
  readonly user = input.required<LiveUser>();
  /** A trace line was clicked — asks the page to open the matching stage. */
  readonly inspect = output<string>();
  /** How deep the chain went, so the page can follow it on the diagram. */
  readonly reached = output<string>();

  private readonly live = inject(LiveClient);

  protected readonly turns = signal<readonly Turn[]>([]);
  protected readonly draft = signal<string | null>(null);
  protected readonly pending = signal(false);
  protected readonly phase = signal<Phase>('idle');
  private readonly raw = signal<readonly RawChainEvent[]>([]);
  private readonly thread = viewChild<ElementRef<HTMLDivElement>>('thread');

  /** The stream, attributed to hops. Derived — see core/hops.ts for why. */
  private readonly events = computed(() => attributeHops(this.raw()));
  protected readonly hops = computed(() => hopCount(this.events()));
  protected readonly trace = computed<readonly TraceGroup[]>(() =>
    groupByHop(this.events()).map((g) => ({
      hop: g.hop,
      actor: g.actor,
      lines: g.lines.map(toLine),
    })),
  );

  /** Two hops means the assistant delegated rather than acted alone. */
  protected readonly delegated = computed(() => this.hops() >= 2);
  protected readonly hasAudit = computed(() => this.user().scopes.includes('mcp:audit'));

  constructor() {
    // Keep the thread pinned to the newest message as bubbles arrive.
    effect(() => {
      this.turns();
      this.draft();
      this.trace();
      const el = this.thread()?.nativeElement;
      if (el) {
        requestAnimationFrame(() => {
          el.scrollTop = el.scrollHeight;
        });
      }
    });
  }

  protected view(stageId: string): void {
    this.inspect.emit(stageId);
  }

  protected send(box: HTMLInputElement): void {
    const message = box.value.trim();
    if (message === '' || this.pending()) {
      return;
    }
    box.value = '';
    void this.run(message);
  }

  /** Each REAL completion from the server stream extends the trace. */
  private onEvent(step: string, detail: string): void {
    this.raw.update((r) => [...r, { step, detail }]);
    const lit = this.events().at(-1);
    if (lit !== undefined) {
      this.reached.emit(stageIdFor(lit));
    }
  }

  private async run(message: string): Promise<void> {
    this.pending.set(true);
    this.draft.set(message);
    this.phase.set('flight');
    this.raw.set([]);

    const res = await this.live.chatStream(message, (s, d) => this.onEvent(s, d));
    const error = res.answer === undefined;
    this.turns.update((t) => [...t, { q: message, a: res.answer ?? res.error ?? 'no response', error }]);
    this.draft.set(null);
    this.phase.set(error ? 'error' : 'done');
    this.pending.set(false);
  }
}
